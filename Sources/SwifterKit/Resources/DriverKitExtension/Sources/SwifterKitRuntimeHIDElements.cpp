#include <DriverKit/IOLib.h>
#include <DriverKit/OSCollections.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeMappedMemory.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

#if SWIFTERKIT_HID_EVENT_SERVICE
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <HIDDriverKit/IOHIDElement.h>
    #include <HIDDriverKit/IOHIDInterface.h>
#endif

// Swift's view of the provider interface: the element tree, element values and commits, and
// interface reports. Element work runs under hidLock (see SwifterKitRuntimeHIDEvents.cpp).
// Interface report transfers call the kernel and take no lock.
#if SWIFTERKIT_HID_EVENT_SERVICE
namespace {
    // SwifterKitHIDElementWriteKind comes from RuntimeSchema+HID.swift.
    using ElementWriteKind = SwifterKitHIDElementWriteKind;

    // Report bytes that fit a command after its message, command, and request headers.
    constexpr uint32_t kMaximumReportLength =
        kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize
        - sizeof(SwifterKitRuntimeCommandHeader) - sizeof(SwifterKitHIDReportRequest);

    // Returns an element the array still owns. OSArray::getObject does not retain.
    DRIVERKIT_RETURNS_NOT_RETAINED IOHIDElement* FindElement(
        const OSArray* elements,
        uint32_t cookie) {
        if (elements == nullptr || cookie == 0) {
            return nullptr;
        }
        for (uint32_t index = 0; index < elements->getCount(); ++index) {
            auto* element = OSDynamicCast(IOHIDElement, elements->getObject(index));
            if (element != nullptr && element->getCookie() == cookie) {
                return element;
            }
        }
        return nullptr;
    }

    SwifterKitHIDElementDescriptor Describe(IOHIDElement* element) {
        IOHIDElement* parent = element->getParentElement();
        return {
            .cookie = element->getCookie(),
            .parentCookie = parent == nullptr ? 0U : parent->getCookie(),
            .type = static_cast<uint32_t>(element->getType()),
            .collectionType = static_cast<uint32_t>(element->getCollectionType()),
            .usagePage = element->getUsagePage(),
            .usage = element->getUsage(),
            .logicalMinimum = element->getLogicalMin(),
            .logicalMaximum = element->getLogicalMax(),
            .physicalMinimum = element->getPhysicalMin(),
            .physicalMaximum = element->getPhysicalMax(),
            .unit = element->getUnit(),
            .unitExponent = element->getUnitExponent(),
            .reportID = element->getReportID(),
            .reportSize = element->getReportSize(),
            .reportCount = element->getReportCount(),
            .flags = element->getFlags(),
            .value = element->getValue(0),
            .reserved = 0,
            .timestamp = element->getTimeStamp(),
        };
    }

    kern_return_t CopyElementPage(
        const OSArray* elements,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        SwifterKitHIDElementPageRequest request = {};
        if (payloadLength != sizeof(request)) {
            return kIOReturnBadArgument;
        }
        memcpy(&request, payload, sizeof(request));
        if (request.maximumCount == 0 || request.maximumCount > kSwifterKitHIDMaximumElementPage) {
            return kIOReturnBadArgument;
        }
        const uint32_t total = elements == nullptr ? 0 : elements->getCount();
        const uint32_t first = request.firstIndex < total ? request.firstIndex : total;
        const uint32_t remaining = total - first;
        const uint32_t count = remaining < request.maximumCount ? remaining : request.maximumCount;
        const SwifterKitHIDElementPage page = {.totalCount = total, .count = count};
        OSData* data = OSData::withCapacity(
            static_cast<uint32_t>(sizeof(page) + count * sizeof(SwifterKitHIDElementDescriptor)));
        if (data == nullptr || !data->appendBytes(&page, sizeof(page))) {
            OSSafeReleaseNULL(data);
            return kIOReturnNoMemory;
        }
        for (uint32_t index = first; index < first + count; ++index) {
            auto* element = OSDynamicCast(IOHIDElement, elements->getObject(index));
            const SwifterKitHIDElementDescriptor descriptor =
                element == nullptr ? SwifterKitHIDElementDescriptor {} : Describe(element);
            if (!data->appendBytes(&descriptor, sizeof(descriptor))) {
                data->release();
                return kIOReturnNoMemory;
            }
        }
        *response = data;
        return kIOReturnSuccess;
    }

    kern_return_t ReadValue(
        const OSArray* elements,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        SwifterKitHIDElementValueRequest request = {};
        if (payloadLength != sizeof(request)) {
            return kIOReturnBadArgument;
        }
        memcpy(&request, payload, sizeof(request));
        if (request.reserved != 0 || request.scaleType > kIOHIDValueScaleTypeExponent) {
            return kIOReturnBadArgument;
        }
        IOHIDElement* element = FindElement(elements, request.cookie);
        if (element == nullptr) {
            return kIOReturnNotFound;
        }
        const SwifterKitHIDElementValue value = {
            .value = element->getValue(request.options),
            .scaledValue = element->getScaledValue(request.scaleType),
            .scaledFixedValue = element->getScaledFixedValue(request.scaleType),
            .reserved = 0,
            .timestamp = element->getTimeStamp(),
        };
        *response = OSData::withBytes(&value, sizeof(value));
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }

    // The response is the bytes of IOHIDElement::getDataValue, or empty when it returns nullptr.
    // HIDDriverKit does not document getDataValue's ownership. The kernel's open-source
    // IOHIDElementPrivate::getDataValue returns its _dataValue ivar unretained and may replace it
    // on the next call, so the runtime copies the bytes at once and does not release the OSData.
    kern_return_t ReadDataValue(
        const OSArray* elements,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        SwifterKitHIDElementDataRequest request = {};
        if (payloadLength != sizeof(request)) {
            return kIOReturnBadArgument;
        }
        memcpy(&request, payload, sizeof(request));
        IOHIDElement* element = FindElement(elements, request.cookie);
        if (element == nullptr) {
            return kIOReturnNotFound;
        }
        const OSData* value = element->getDataValue(request.options);
        if (value == nullptr || value->getLength() == 0) {
            *response = OSData::withCapacity(0);
            return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
        if (value->getLength()
            > kSwifterKitRuntimeMaximumMessageSize - kSwifterKitRuntimeHeaderSize) {
            return kIOReturnNoSpace;
        }
        *response = OSData::withBytes(value->getBytesNoCopy(), value->getLength());
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }

    kern_return_t
        WriteValue(const OSArray* elements, const uint8_t* payload, uint32_t payloadLength) {
        SwifterKitHIDElementWrite write = {};
        if (payloadLength < sizeof(write)) {
            return kIOReturnBadArgument;
        }
        memcpy(&write, payload, sizeof(write));
        const bool isData = write.kind == static_cast<uint32_t>(ElementWriteKind::Data);
        if (write.kind > static_cast<uint32_t>(ElementWriteKind::Data)
            || write.length != payloadLength - sizeof(write)
            || (isData ? write.length == 0 || write.value != 0 : write.length != 0)) {
            return kIOReturnBadArgument;
        }
        IOHIDElement* element = FindElement(elements, write.cookie);
        if (element == nullptr) {
            return kIOReturnNotFound;
        }
        if (!isData) {
            element->setValue(write.value);
            return kIOReturnSuccess;
        }
        OSData* data = OSData::withBytes(payload + sizeof(write), write.length);
        if (data == nullptr) {
            return kIOReturnNoMemory;
        }
        element->setDataValue(data);
        data->release();
        return kIOReturnSuccess;
    }

    kern_return_t CommitElements(
        IOHIDInterface* interface,
        const OSArray* elements,
        const uint8_t* payload,
        uint32_t payloadLength) {
        SwifterKitHIDElementsCommit header = {};
        if (interface == nullptr) {
            return kIOReturnNotReady;
        }
        if (payloadLength < sizeof(header)) {
            return kIOReturnBadArgument;
        }
        memcpy(&header, payload, sizeof(header));
        if (header.direction > kIOHIDElementCommitDirectionOut || header.count == 0
            || header.count > kSwifterKitHIDMaximumCookies
            || payloadLength != sizeof(header) + header.count * sizeof(uint32_t)) {
            return kIOReturnBadArgument;
        }
        OSArray* batch = OSArray::withCapacity(header.count);
        if (batch == nullptr) {
            return kIOReturnNoMemory;
        }
        kern_return_t result = kIOReturnSuccess;
        for (uint32_t index = 0; index < header.count && result == kIOReturnSuccess; ++index) {
            uint32_t cookie = 0;
            memcpy(&cookie, payload + sizeof(header) + index * sizeof(cookie), sizeof(cookie));
            const IOHIDElement* element = FindElement(elements, cookie);
            if (element == nullptr) {
                result = kIOReturnNotFound;
            } else if (!batch->setObject(element)) {
                result = kIOReturnNoMemory;
            }
        }
        if (result == kIOReturnSuccess) {
            result = interface->commitElements(
                batch,
                static_cast<IOHIDElementCommitDirection>(header.direction));
        }
        batch->release();
        return result;
    }

    // Validates an interface report request whose bytes, if any, follow the header.
    bool ReadReportRequest(
        const uint8_t* payload,
        uint32_t payloadLength,
        bool carriesBytes,
        bool allowsTimestamp,
        SwifterKitHIDReportRequest* request) {
        if (payloadLength < sizeof(*request)) {
            return false;
        }
        memcpy(request, payload, sizeof(*request));
        const uint32_t bytes = payloadLength - sizeof(*request);
        return request->reportType <= kIOHIDReportTypeFeature && request->reportID <= 0xFF
               && request->reserved == 0 && request->timeout == 0
               && (allowsTimestamp || request->timestamp == 0) && request->length != 0
               && request->length <= kMaximumReportLength
               && bytes == (carriesBytes ? request->length : 0U);
    }

    kern_return_t CreateReportBuffer(
        uint64_t direction,
        const uint8_t* bytes,
        uint32_t length,
        IOBufferMemoryDescriptor** buffer) {
        kern_return_t result = IOBufferMemoryDescriptor::Create(direction, length, 0, buffer);
        if (result != kIOReturnSuccess || *buffer == nullptr) {
            return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
        }
        (void)(*buffer)->SetLength(length);
        uint64_t address = 0;
        uint64_t mappedLength = 0;
        result = (*buffer)->Map(0, 0, 0, 0, &address, &mappedLength);
        if (result == kIOReturnSuccess && (address == 0 || mappedLength < length)) {
            result = kIOReturnNoMemory;
        }
        if (result == kIOReturnSuccess && bytes != nullptr) {
            memcpy(SwifterKitMappedPointer<void>(address), bytes, length);
        }
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(*buffer);
        }
        return result;
    }

    kern_return_t InterfaceReport(
        IOHIDInterface* interface,
        uint32_t opcode,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        const bool isSet =
            opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::HIDInterfaceSetReport);
        SwifterKitHIDReportRequest request = {};
        if (!ReadReportRequest(payload, payloadLength, isSet, false, &request)) {
            return kIOReturnBadArgument;
        }
        if (interface == nullptr) {
            return kIOReturnNotReady;
        }
        IOBufferMemoryDescriptor* buffer = nullptr;
        kern_return_t result = CreateReportBuffer(
            isSet ? kIOMemoryDirectionOut : kIOMemoryDirectionIn,
            isSet ? payload + sizeof(request) : nullptr,
            request.length,
            &buffer);
        if (result != kIOReturnSuccess) {
            return result;
        }
        const auto type = static_cast<IOHIDReportType>(request.reportType);
        if (isSet) {
            result = interface->SetReport(buffer, type, request.reportID, request.options);
        } else {
            result = interface->GetReport(buffer, type, request.reportID, request.options);
            uint64_t address = 0;
            uint64_t length = 0;
            if (result == kIOReturnSuccess) {
                result = buffer->Map(0, 0, 0, 0, &address, &length);
            }
            if (result == kIOReturnSuccess) {
                *response =
                    OSData::withBytes(SwifterKitMappedPointer<const void>(address), request.length);
                result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
            }
        }
        buffer->release();
        return result;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::HIDElementCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->hidLock == nullptr) {
        return kIOReturnNotReady;
    }
    IORecursiveLockLock(ivars->hidLock);
    IOHIDInterface* interface = ivars->hidInterface;
    if (interface != nullptr) {
        interface->retain();
    }
    IORecursiveLockUnlock(ivars->hidLock);

    const auto code = static_cast<SwifterKitRuntimeOpcode>(opcode);
    if (code == SwifterKitRuntimeOpcode::HIDInterfaceGetReport
        || code == SwifterKitRuntimeOpcode::HIDInterfaceSetReport) {
        const kern_return_t result =
            InterfaceReport(interface, opcode, payload, payloadLength, response);
        OSSafeReleaseNULL(interface);
        return result;
    }

    kern_return_t result = kIOReturnUnsupported;
    IORecursiveLockLock(ivars->hidLock);
    const OSArray* elements = getElements();
    switch (code) {
        case SwifterKitRuntimeOpcode::HIDCopyElements:
            result = CopyElementPage(elements, payload, payloadLength, response);
            break;
        case SwifterKitRuntimeOpcode::HIDGetElementValue:
            result = ReadValue(elements, payload, payloadLength, response);
            break;
        case SwifterKitRuntimeOpcode::HIDGetElementDataValue:
            result = ReadDataValue(elements, payload, payloadLength, response);
            break;
        case SwifterKitRuntimeOpcode::HIDSetElementValue:
            result = WriteValue(elements, payload, payloadLength);
            break;
        case SwifterKitRuntimeOpcode::HIDCommitElement: {
            SwifterKitHIDElementCommit commit = {};
            IOHIDElement* element = nullptr;
            if (payloadLength == sizeof(commit)) {
                memcpy(&commit, payload, sizeof(commit));
                element = FindElement(elements, commit.cookie);
            }
            result =
                payloadLength != sizeof(commit)
                        || commit.direction > kIOHIDElementCommitDirectionOut
                    ? kIOReturnBadArgument
                : element == nullptr
                    ? kIOReturnNotFound
                    : element->commit(static_cast<IOHIDElementCommitDirection>(commit.direction));
            break;
        }
        case SwifterKitRuntimeOpcode::HIDCommitElements:
            result = CommitElements(interface, elements, payload, payloadLength);
            break;
        case SwifterKitRuntimeOpcode::HIDElementConformsTo: {
            SwifterKitHIDUsageQuery query = {};
            IOHIDElement* element = nullptr;
            if (payloadLength == sizeof(query)) {
                memcpy(&query, payload, sizeof(query));
                element = FindElement(elements, query.cookie);
            }
            if (payloadLength != sizeof(query) || query.reserved != 0) {
                result = kIOReturnBadArgument;
            } else if (element == nullptr) {
                result = kIOReturnNotFound;
            } else {
                const uint32_t conforms = element->conformsTo(query.usagePage, query.usage) ? 1 : 0;
                *response = OSData::withBytes(&conforms, sizeof(conforms));
                result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDInterfaceProcessReport: {
            SwifterKitHIDReportRequest request = {};
            if (!ReadReportRequest(payload, payloadLength, true, true, &request)) {
                result = kIOReturnBadArgument;
            } else if (interface == nullptr) {
                result = kIOReturnNotReady;
            } else {
                // processReport takes a mutable pointer, so it parses a private copy.
                auto* bytes = static_cast<uint8_t*>(IOMalloc(request.length));
                if (bytes == nullptr) {
                    result = kIOReturnNoMemory;
                } else {
                    memcpy(bytes, payload + sizeof(request), request.length);
                    interface->processReport(
                        request.timestamp == 0 ? mach_absolute_time() : request.timestamp,
                        bytes,
                        request.length,
                        static_cast<IOHIDReportType>(request.reportType),
                        request.reportID);
                    IOFree(bytes, request.length);
                    result = kIOReturnSuccess;
                }
            }
            break;
        }
        default:
            break;
    }
    IORecursiveLockUnlock(ivars->hidLock);
    OSSafeReleaseNULL(interface);
    return result;
}
#endif
