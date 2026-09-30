#include "SwifterKitRuntimeHIDDevice.h"

#if SWIFTERKIT_HID_DEVICE_FACTORY
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSCollections.h>

    #include "SwifterKitRuntimeHIDShared.h"
    #include "SwifterKitRuntimeService.h"

// A virtual HID device a HID device factory created. The factory root
// (SwifterKitRuntimeHIDFactory.cpp) reserves a slot and its configuration before IOService::Create.
// Create does not wait for Start, so handleStart claims the configuration from the root before
// IOUserHIDDevice reads the description and the report descriptor.
//
// Completion ownership: getReport returns success only after it records the request and queues
// a required event. From then on CompleteReport runs exactly once, when Swift answers through
// hidFactoryCompleteGetReport or, with kIOReturnAborted, when the device stops. An error return
// leaves completion to the caller.
struct SwifterKitRuntimeHIDDevice_IVars {
    // Set once in handleStart, before the family reads them, and constant afterwards.
    SwifterKitRuntimeService* root;
    OSData* configuration;
    SwifterKitHIDFactoryConfiguration parsed;
    uint32_t handle;
    // lock guards the fields below.
    IOLock* lock;
    bool stopped;
    uint32_t nextRequestID;
    uint64_t inputReportAttempts;
    uint64_t inputReportSuccesses;
    uint64_t inputReportFailures;
    SwifterKitHIDPendingReport requests[kSwifterKitHIDFactoryMaximumPendingReports];
};

namespace {
    struct __attribute__((packed)) FactoryGetReportRequest {
        SwifterKitHIDFactoryHandle device;
        SwifterKitHIDGetReportRequest request;
    };
    static_assert(
        sizeof(FactoryGetReportRequest)
        == sizeof(SwifterKitHIDFactoryHandle) + sizeof(SwifterKitHIDGetReportRequest));

    void ReleaseRequest(SwifterKitHIDPendingReport& request) {
        OSSafeReleaseNULL(request.action);
        OSSafeReleaseNULL(request.report);
    }
}  // namespace

bool SwifterKitRuntimeHIDDevice::init() {
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(SwifterKitRuntimeHIDDevice_IVars, 1);
    if (ivars == nullptr) {
        return false;
    }
    ivars->lock = IOLockAlloc();
    ivars->nextRequestID = 1;
    return ivars->lock != nullptr;
}

void SwifterKitRuntimeHIDDevice::free() {
    if (ivars != nullptr) {
        OSSafeReleaseNULL(ivars->configuration);
        OSSafeReleaseNULL(ivars->root);
        IOLockFreeZero(ivars->lock);
    }
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeHIDDevice_IVars, 1);
    super::free();
}

bool SwifterKitRuntimeHIDDevice::handleStart(IOService* provider) {
    auto* root = OSDynamicCast(SwifterKitRuntimeService, provider);
    if (ivars == nullptr || root == nullptr) {
        return false;
    }
    uint32_t handle = 0;
    OSData* configuration = nullptr;
    SwifterKitHIDFactoryConfiguration parsed = {};
    if (root->HIDFactoryAttachDevice(this, &handle, &configuration) != kIOReturnSuccess
        || configuration == nullptr
        || !SwifterKitHIDParseFactoryDevice(
            static_cast<const uint8_t*>(configuration->getBytesNoCopy()),
            static_cast<uint32_t>(configuration->getLength()),
            &parsed)) {
        OSSafeReleaseNULL(configuration);
        return false;
    }
    root->retain();
    ivars->root = root;
    ivars->configuration = configuration;
    ivars->parsed = parsed;
    ivars->handle = handle;
    if (!super::handleStart(provider)) {
        // Stop does not run after a failed Start, so the root hears of it here.
        root->HIDFactoryDeviceStopped(handle);
        return false;
    }
    return true;
}

auto SwifterKitRuntimeHIDDevice::Stop_Impl(IOService* provider) -> kern_return_t {
    if (ivars != nullptr && ivars->lock != nullptr) {
        IOLockLock(ivars->lock);
        ivars->stopped = true;
        IOLockUnlock(ivars->lock);
        AbortRequests();
        if (ivars->root != nullptr) {
            ivars->root->HIDFactoryDeviceStopped(ivars->handle);
        }
    }
    return Stop(provider, SUPERDISPATCH);
}

OSDictionary* SwifterKitRuntimeHIDDevice::newDeviceDescription() {
    if (ivars == nullptr || ivars->configuration == nullptr) {
        return nullptr;
    }
    const SwifterKitHIDFactoryConfiguration& parsed = ivars->parsed;
    return SwifterKitHIDNewDescription(
        parsed.device,
        parsed.transport,
        parsed.manufacturer,
        parsed.product,
        parsed.serialNumber);
}

OSData* SwifterKitRuntimeHIDDevice::newReportDescriptor() {
    if (ivars == nullptr || ivars->configuration == nullptr) {
        return nullptr;
    }
    return OSData::withBytes(ivars->parsed.descriptor, ivars->parsed.device.descriptorLength);
}

kern_return_t SwifterKitRuntimeHIDDevice::SubmitInputReport(
    const SwifterKitHIDReportHeader* header,
    const uint8_t* bytes) {
    if (ivars == nullptr || ivars->lock == nullptr || ivars->configuration == nullptr) {
        return kIOReturnNotReady;
    }
    IOLockLock(ivars->lock);
    ivars->inputReportAttempts += 1;
    const bool stopped = ivars->stopped;
    IOLockUnlock(ivars->lock);

    kern_return_t result = kIOReturnNotReady;
    if (stopped) {
        result = kIOReturnNotReady;
    } else if (
        header == nullptr || bytes == nullptr || header->reportLength == 0
        || header->reportType != kIOHIDReportTypeInput || header->reserved != 0) {
        result = kIOReturnBadArgument;
    } else {
        IOBufferMemoryDescriptor* buffer = nullptr;
        result = SwifterKitHIDCreateReportBuffer(bytes, header->reportLength, &buffer);
        if (result == kIOReturnSuccess) {
            result = handleReport(
                header->timestamp,
                buffer,
                header->reportLength,
                kIOHIDReportTypeInput,
                header->options);
            buffer->release();
        }
    }

    IOLockLock(ivars->lock);
    if (result == kIOReturnSuccess) {
        ivars->inputReportSuccesses += 1;
    } else {
        ivars->inputReportFailures += 1;
    }
    IOLockUnlock(ivars->lock);
    return result;
}

kern_return_t SwifterKitRuntimeHIDDevice::CopyStatistics(
    SwifterKitHIDRuntimeStatistics* statistics) {
    if (statistics == nullptr || ivars == nullptr || ivars->lock == nullptr) {
        return kIOReturnBadArgument;
    }
    IOLockLock(ivars->lock);
    *statistics = {
        .inputReportAttempts = ivars->inputReportAttempts,
        .inputReportSuccesses = ivars->inputReportSuccesses,
        .inputReportFailures = ivars->inputReportFailures,
    };
    IOLockUnlock(ivars->lock);
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeHIDDevice::setReport(
    IOMemoryDescriptor* report,
    IOHIDReportType reportType,
    IOOptionBits options,
    [[maybe_unused]] uint32_t completionTimeout,
    OSAction* action) {
    if (ivars == nullptr || ivars->root == nullptr) {
        return kIOReturnNotReady;
    }
    if (!SwifterKitHIDAcceptsHostReportType(
            ivars->parsed.device.acceptedHostReportTypes,
            reportType)) {
        return kIOReturnUnsupported;
    }
    if (report == nullptr) {
        return kIOReturnBadArgument;
    }
    uint64_t length64 = 0;
    kern_return_t result = report->GetLength(&length64);
    if (result != kIOReturnSuccess || length64 == 0
        || length64 > kSwifterKitHIDFactoryMaximumHostReport) {
        return kIOReturnBadArgument;
    }

    const SwifterKitHIDFactoryHandle device = {.handle = ivars->handle, .reserved = 0};
    const SwifterKitHIDReportHeader header = {
        .timestamp = 0,
        .reportType = static_cast<uint32_t>(reportType),
        .options = static_cast<uint32_t>(options),
        .reportLength = static_cast<uint32_t>(length64),
        .reserved = 0,
    };
    OSData* payload = OSData::withCapacity(sizeof(device) + sizeof(header) + header.reportLength);
    if (payload == nullptr || !payload->appendBytes(&device, sizeof(device))
        || !payload->appendBytes(&header, sizeof(header))) {
        OSSafeReleaseNULL(payload);
        return kIOReturnNoMemory;
    }
    result = SwifterKitHIDCopyDescriptorBytes(report, header.reportLength, payload);
    if (result == kIOReturnSuccess) {
        result = ivars->root->EnqueueEvent(
            kSwifterKitEventHIDFactoryReport,
            payload->getBytesNoCopy(),
            static_cast<uint32_t>(payload->getLength()));
    }
    payload->release();
    // Swift observes host reports and never answers them, so an accepted report completes here,
    // exactly once, as soon as it is queued.
    if (result == kIOReturnSuccess && action != nullptr) {
        CompleteReport(action, kIOReturnSuccess, header.reportLength);
    }
    return result;
}

kern_return_t SwifterKitRuntimeHIDDevice::getReport(
    IOMemoryDescriptor* report,
    IOHIDReportType reportType,
    IOOptionBits options,
    uint32_t completionTimeout,
    OSAction* action) {
    if (ivars == nullptr || ivars->root == nullptr || ivars->lock == nullptr) {
        return kIOReturnNotReady;
    }
    if (!SwifterKitHIDAnswersReportType(ivars->parsed.device.answeredReportTypes, reportType)) {
        return kIOReturnUnsupported;
    }
    if (report == nullptr || action == nullptr) {
        return kIOReturnBadArgument;
    }
    uint64_t length = 0;
    kern_return_t result = report->GetLength(&length);
    if (result != kIOReturnSuccess || length == 0
        || length > kSwifterKitHIDFactoryMaximumAnsweredReport) {
        return kIOReturnBadArgument;
    }

    FactoryGetReportRequest event = {
        .device = {.handle = ivars->handle, .reserved = 0},
        .request =
            {
                .requestID = 0,
                .reportType = static_cast<uint32_t>(reportType),
                .options = static_cast<uint32_t>(options),
                .capacity = static_cast<uint32_t>(length),
                .timeout = completionTimeout,
                .reserved = 0,
            },
    };
    IOLockLock(ivars->lock);
    for (auto& slot : ivars->requests) {
        if (ivars->stopped || slot.requestID != 0) {
            continue;
        }
        event.request.requestID = ivars->nextRequestID++;
        if (ivars->nextRequestID == 0) {
            ivars->nextRequestID = 1;
        }
        action->retain();
        report->retain();
        slot = {
            .requestID = event.request.requestID,
            .capacity = event.request.capacity,
            .action = action,
            .report = report,
        };
        break;
    }
    const bool stopped = ivars->stopped;
    IOLockUnlock(ivars->lock);
    if (event.request.requestID == 0) {
        return stopped ? kIOReturnNotReady : kIOReturnNoResources;
    }

    result = ivars->root->EnqueueRequiredEvent(
        kSwifterKitEventHIDFactoryGetReportRequest,
        &event,
        sizeof(event));
    if (result != kIOReturnSuccess) {
        SwifterKitHIDPendingReport taken[1] = {};
        IOLockLock(ivars->lock);
        const uint32_t count =
            SwifterKitHIDTakeRequests(ivars->requests, event.request.requestID, taken);
        IOLockUnlock(ivars->lock);
        if (count == 1) {
            ReleaseRequest(taken[0]);
        }
    }
    return result;
}

kern_return_t SwifterKitRuntimeHIDDevice::CompleteGetReport(
    const uint8_t* payload,
    uint32_t payloadLength) {
    if (ivars == nullptr || ivars->lock == nullptr || payload == nullptr
        || payloadLength < sizeof(SwifterKitHIDReportCompletion)) {
        return kIOReturnBadArgument;
    }
    SwifterKitHIDReportCompletion completion = {};
    memcpy(&completion, payload, sizeof(completion));
    if (completion.requestID == 0 || completion.reserved != 0
        || completion.length != payloadLength - sizeof(completion)
        || (completion.status != kIOReturnSuccess && completion.length != 0)) {
        return kIOReturnBadArgument;
    }
    SwifterKitHIDPendingReport taken[1] = {};
    IOLockLock(ivars->lock);
    for (const auto& slot : ivars->requests) {
        if (slot.requestID == completion.requestID && completion.length > slot.capacity) {
            IOLockUnlock(ivars->lock);
            return kIOReturnBadArgument;
        }
    }
    const uint32_t count = SwifterKitHIDTakeRequests(ivars->requests, completion.requestID, taken);
    IOLockUnlock(ivars->lock);
    if (count == 0) {
        return kIOReturnNotFound;
    }
    kern_return_t result = kIOReturnSuccess;
    IOReturn status = completion.status;
    uint32_t length = completion.length;
    if (status == kIOReturnSuccess && length != 0) {
        result =
            SwifterKitHIDCopyIntoDescriptor(taken[0].report, payload + sizeof(completion), length);
        if (result != kIOReturnSuccess) {
            status = result;
            length = 0;
        }
    }
    CompleteReport(taken[0].action, status, length);
    ReleaseRequest(taken[0]);
    return result;
}

void SwifterKitRuntimeHIDDevice::AbortRequests() {
    if (ivars == nullptr || ivars->lock == nullptr) {
        return;
    }
    SwifterKitHIDPendingReport taken[kSwifterKitHIDFactoryMaximumPendingReports] = {};
    IOLockLock(ivars->lock);
    const uint32_t count = SwifterKitHIDTakeRequests(ivars->requests, 0, taken);
    IOLockUnlock(ivars->lock);
    for (uint32_t index = 0; index < count; ++index) {
        CompleteReport(taken[index].action, kIOReturnAborted, 0);
        ReleaseRequest(taken[index]);
    }
}
#endif
