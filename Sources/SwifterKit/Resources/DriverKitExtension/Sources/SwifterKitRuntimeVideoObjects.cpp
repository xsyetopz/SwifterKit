#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeSchema.h"
    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeVideoBox.h"
    #include "SwifterKitRuntimeVideoClockDevice.h"
    #include "SwifterKitRuntimeVideoDevice.h"
    #include "SwifterKitRuntimeVideoDeviceState.h"
    #include "SwifterKitRuntimeVideoProtocol.h"

namespace {
    using Opcode = SwifterKitRuntimeOpcode;

    constexpr uint8_t kNoOwner = 0;

    bool Is(uint32_t opcode, Opcode expected) {
        return opcode == static_cast<uint32_t>(expected);
    }

    // Resolves a device, box, clock-device, or object-ID target; the driver is not an object.
    IOUserVideoObject* ResolveObject(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        const SwifterKitVideoObjectTarget& target,
        OSSharedPtr<IOUserVideoObject>& holder) {
        const bool indexed = target.index < kSwifterKitVideoObjectTableCount;
        switch (target.kind) {
            case kSwifterKitVideoTargetDevice:
                return target.index == 0 ? state->videoDevice : nullptr;
            case kSwifterKitVideoTargetBox:
                return indexed ? state->videoBoxes[target.index] : nullptr;
            case kSwifterKitVideoTargetClock:
                return indexed ? state->videoClockDevices[target.index] : nullptr;
            case kSwifterKitVideoTargetObject:
                holder = service->GetVideoObjectForObjectID(target.index);
                return holder.get();
            default:
                return nullptr;
        }
    }

    // The video device is an IOUserVideoClockDevice, so it answers clock-state reads too.
    IOUserVideoClockDevice* ResolveClock(
        SwifterKitRuntimeService_IVars* state,
        const SwifterKitVideoObjectTarget& target) {
        if (target.kind == kSwifterKitVideoTargetDevice && target.index == 0)
            return state->videoDevice;
        if (target.kind == kSwifterKitVideoTargetClock
            && target.index < kSwifterKitVideoObjectTableCount)
            return state->videoClockDevices[target.index];
        return nullptr;
    }

    // Copies a bounded, NUL-free name from a payload into an OSString.
    OSString* CopyName(const uint8_t* bytes, uint32_t length) {
        char name[kSwifterKitVideoNameMaximumLength + 1] = {};
        if (bytes == nullptr || length == 0 || length > kSwifterKitVideoNameMaximumLength
            || memchr(bytes, 0, length) != nullptr)
            return nullptr;
        memcpy(name, bytes, length);
        return OSString::withCString(name);
    }

    kern_return_t AppendName(OSData* data, const OSSharedPtr<OSString>& name, uint32_t* length) {
        *length = name ? static_cast<uint32_t>(name->getLength()) : 0;
        if (*length > kSwifterKitVideoNameMaximumLength)
            return kIOReturnNoSpace;
        return *length == 0 || data->appendBytes(name->getCStringNoCopy(), *length)
                   ? kIOReturnSuccess
                   : kIOReturnNoMemory;
    }

    kern_return_t BytesResponse(const void* bytes, size_t length, OSData** response) {
        *response = OSData::withBytes(bytes, length);
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }

    bool IsBool(uint64_t value) {
        return value <= 1;
    }

    bool IsValidRate(double rate) {
        return rate > 0.0 && rate <= __DBL_MAX__;
    }

    kern_return_t ObjectInfo(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        const SwifterKitVideoObjectTarget& target,
        OSData** response) {
        OSSharedPtr<IOUserVideoObject> holder;
        SwifterKitVideoObjectInfoHeader header = {};
        OSSharedPtr<OSString> name;
        OSSharedPtr<OSString> uid;
        if (target.kind == kSwifterKitVideoTargetDriver) {
            if (target.index != 0)
                return kIOReturnBadArgument;
            header.classID = static_cast<uint32_t>(service->GetClassID());
            header.baseClassID = static_cast<uint32_t>(service->GetBaseClassID());
            header.transport = static_cast<uint32_t>(service->GetTransportType());
            name = service->GetName();
        } else {
            IOUserVideoObject* object = ResolveObject(service, state, target, holder);
            if (object == nullptr)
                return kIOReturnNotFound;
            header.objectID = object->GetObjectID();
            header.classID = static_cast<uint32_t>(object->GetClassID());
            header.baseClassID = static_cast<uint32_t>(object->GetBaseClassID());
            name = object->GetName();
            if (auto* clock = OSDynamicCast(IOUserVideoClockDevice, object)) {
                header.transport = static_cast<uint32_t>(clock->GetTransportType());
                uid = clock->GetUID();
            } else if (auto* box = OSDynamicCast(IOUserVideoBox, object)) {
                header.transport = static_cast<uint32_t>(box->GetTransportType());
                uid = box->GetUID();
            }
        }
        OSData* data = OSData::withCapacity(sizeof(header) + 2 * kSwifterKitVideoNameMaximumLength);
        if (data == nullptr)
            return kIOReturnNoMemory;
        kern_return_t result =
            data->appendBytes(&header, sizeof(header)) ? kIOReturnSuccess : kIOReturnNoMemory;
        uint32_t nameLength = 0;
        uint32_t uidLength = 0;
        if (result == kIOReturnSuccess)
            result = AppendName(data, name, &nameLength);
        if (result == kIOReturnSuccess)
            result = AppendName(data, uid, &uidLength);
        header.nameLength = nameLength;
        header.uidLength = uidLength;
        if (result != kIOReturnSuccess) {
            data->release();
            return result;
        }
        // Lengths are known only after appending; patch them into the copied header.
        auto* bytes = static_cast<uint8_t*>(const_cast<void*>(data->getBytesNoCopy()));
        memcpy(bytes, &header, sizeof(header));
        *response = data;
        return kIOReturnSuccess;
    }

    kern_return_t NameCommand(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        uint32_t opcode,
        const SwifterKitVideoObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        OSSharedPtr<IOUserVideoObject> holder;
        if (Is(opcode, Opcode::VideoSetObjectName) || Is(opcode, Opcode::VideoPropertiesChanged)) {
            SwifterKitVideoListHeader header = {};
            if (payloadLength < sizeof(header))
                return kIOReturnBadArgument;
            memcpy(&header, payload, sizeof(header));
            const uint8_t* body = payload + sizeof(header);
            const uint64_t bodyLength = payloadLength - sizeof(header);
            const bool isDriver = target.kind == kSwifterKitVideoTargetDriver && target.index == 0;
            if (header.reserved != 0)
                return kIOReturnBadArgument;
            if (Is(opcode, Opcode::VideoSetObjectName)) {
                if (bodyLength != header.count)
                    return kIOReturnBadArgument;
                OSString* name = CopyName(body, header.count);
                if (name == nullptr)
                    return kIOReturnBadArgument;
                IOUserVideoObject* object =
                    isDriver ? nullptr : ResolveObject(service, state, target, holder);
                const kern_return_t result = isDriver            ? service->SetName(name)
                                             : object != nullptr ? object->SetName(name)
                                                                 : kIOReturnNotFound;
                name->release();
                return result;
            }
            IOUserVideoObjectPropertySelector selectors[kSwifterKitVideoMaximumChangedProperties] =
                {};
            if (header.count == 0 || header.count > kSwifterKitVideoMaximumChangedProperties
                || bodyLength != header.count * 4ULL)
                return kIOReturnBadArgument;
            memcpy(selectors, body, header.count * 4ULL);
            for (uint32_t index = 0; index < header.count; ++index)
                if (selectors[index] == 0)
                    return kIOReturnBadArgument;
            IOUserVideoObject* object = ResolveObject(service, state, target, holder);
            return object == nullptr
                       ? kIOReturnNotFound
                       : service->PropertiesChanged(object->GetObjectID(), selectors, header.count);
        }
        SwifterKitVideoElementNameHeader header = {};
        if (payloadLength < sizeof(header))
            return kIOReturnBadArgument;
        memcpy(&header, payload, sizeof(header));
        const bool setting = Is(opcode, Opcode::VideoSetElementName);
        if (header.kind > kSwifterKitVideoElementNumber
            || (setting ? payloadLength != sizeof(header) + header.length
                        : payloadLength != sizeof(header) || header.length != 0))
            return kIOReturnBadArgument;
        IOUserVideoObject* object = ResolveObject(service, state, target, holder);
        if (object == nullptr)
            return kIOReturnNotFound;
        const auto scope = static_cast<IOUserVideoObjectPropertyScope>(header.scope);
        const IOUserVideoObjectPropertyElement element = header.element;
        if (setting) {
            OSString* name = CopyName(payload + sizeof(header), header.length);
            if (name == nullptr)
                return kIOReturnBadArgument;
            const kern_return_t result = header.kind == kSwifterKitVideoElementName
                                             ? object->SetElementName(element, scope, name)
                                         : header.kind == kSwifterKitVideoElementCategory
                                             ? object->SetElementCategoryName(element, scope, name)
                                             : object->SetElementNumberName(element, scope, name);
            name->release();
            return result;
        }
        const OSSharedPtr<OSString> name = header.kind == kSwifterKitVideoElementName
                                               ? object->GetElementName(element, scope)
                                           : header.kind == kSwifterKitVideoElementCategory
                                               ? object->GetElementCategoryName(element, scope)
                                               : object->GetElementNumberName(element, scope);
        if (!name || name->getLength() == 0)
            return kIOReturnSuccess;
        return name->getLength() > kSwifterKitVideoNameMaximumLength
                   ? kIOReturnNoSpace
                   : BytesResponse(name->getCStringNoCopy(), name->getLength(), response);
    }

    kern_return_t ClockState(IOUserVideoClockDevice* clock, OSData** response) {
        if (clock == nullptr)
            return kIOReturnNotFound;
        uint8_t bytes[sizeof(SwifterKitVideoClockState) + kSwifterKitVideoMaximumSampleRates * 8] =
            {};
        double rates[kSwifterKitVideoMaximumSampleRates] = {};
        size_t count = clock->GetNumberAvailableSampleRates();
        count =
            count > kSwifterKitVideoMaximumSampleRates ? kSwifterKitVideoMaximumSampleRates : count;
        count = clock->GetAvailableSampleRates(rates, count);
        count =
            count > kSwifterKitVideoMaximumSampleRates ? kSwifterKitVideoMaximumSampleRates : count;
        SwifterKitVideoClockState state = {};
        uint64_t zeroSampleTime = 0;
        uint64_t zeroHostTime = 0;
        uint64_t inputSampleTime = 0;
        uint64_t outputSampleTime = 0;
        clock->GetCurrentZeroTimestamp(&zeroSampleTime, &zeroHostTime);
        clock->GetCurrentClientSampleTime(&inputSampleTime, &outputSampleTime);
        state.sampleRateBits = __builtin_bit_cast(uint64_t, clock->GetSampleRate());
        state.zeroSampleTime = zeroSampleTime;
        state.zeroHostTime = zeroHostTime;
        state.clientInputSampleTime = inputSampleTime;
        state.clientOutputSampleTime = outputSampleTime;
        state.objectID = clock->GetObjectID();
        state.clockDomain = clock->GetClockDomain();
        state.clockAlgorithm = static_cast<uint32_t>(clock->GetClockAlgorithm());
        state.transport = static_cast<uint32_t>(clock->GetTransportType());
        state.transportState = static_cast<uint32_t>(clock->GetDeviceTransportState());
        state.flags = (clock->GetClockIsStable() ? kSwifterKitVideoClockStateClockIsStable : 0)
                      | (clock->GetDeviceIsAlive() ? kSwifterKitVideoClockStateIsAlive : 0)
                      | (clock->GetDeviceIsRunning() ? kSwifterKitVideoClockStateIsRunning : 0)
                      | (clock->GetIsHidden() ? kSwifterKitVideoClockStateIsHidden : 0);
        state.inputLatency = clock->GetInputLatency();
        state.outputLatency = clock->GetOutputLatency();
        state.rateCount = static_cast<uint32_t>(count);
        memcpy(bytes, &state, sizeof(state));
        memcpy(bytes + sizeof(state), rates, count * sizeof(double));
        return BytesResponse(bytes, sizeof(state) + count * sizeof(double), response);
    }

    kern_return_t SetBoxOwnership(
        SwifterKitRuntimeService_IVars* state,
        SwifterKitRuntimeVideoBox* box,
        const SwifterKitVideoObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength) {
        SwifterKitVideoBoxOwnership request = {};
        if (payloadLength != sizeof(request))
            return kIOReturnBadArgument;
        memcpy(&request, payload, sizeof(request));
        const bool device = request.member.kind == kSwifterKitVideoTargetDevice;
        if (request.owned > 1 || request.reserved != 0
            || (device ? request.member.index != 0
                       : request.member.kind != kSwifterKitVideoTargetClock
                             || request.member.index >= kSwifterKitVideoObjectTableCount))
            return kIOReturnBadArgument;
        IOUserVideoClockDevice* member =
            device ? static_cast<IOUserVideoClockDevice*>(state->videoDevice)
                   : state->videoClockDevices[request.member.index];
        if (box == nullptr || member == nullptr)
            return kIOReturnNotFound;
        uint8_t& owner =
            device ? state->videoDeviceOwner : state->videoClockOwners[request.member.index];
        const auto self = static_cast<uint8_t>(target.index + 1);
        if (request.owned == 1 ? owner != kNoOwner : owner != self)
            return owner == self ? kIOReturnSuccess : kIOReturnBusy;
        kern_return_t result = kIOReturnSuccess;
        if (device)
            result = request.owned == 1 ? box->AddDevice(state->videoDevice)
                                        : box->RemoveDevice(state->videoDevice);
        else
            result =
                request.owned == 1 ? box->AddClockDevice(member) : box->RemoveClockDevice(member);
        if (result == kIOReturnSuccess)
            owner = request.owned == 1 ? self : kNoOwner;
        return result;
    }

    kern_return_t
        SetBoxProperty(SwifterKitRuntimeVideoBox* box, uint32_t selector, uint64_t value) {
        const bool boolean = selector >= kSwifterKitVideoBoxPropertyHasAudio
                             && selector <= kSwifterKitVideoBoxPropertyIsProtected;
        if (selector < kSwifterKitVideoBoxPropertyTransport
            || selector > kSwifterKitVideoBoxPropertyAcquisitionFailure
            || (boolean && !IsBool(value)) || value > UINT32_MAX)
            return kIOReturnBadArgument;
        if (box == nullptr)
            return kIOReturnNotFound;
        const bool flag = value == 1;
        switch (selector) {
            case kSwifterKitVideoBoxPropertyTransport:
                return box->SetTransportType(static_cast<IOUserVideoTransportType>(value));
            case kSwifterKitVideoBoxPropertyHasAudio:
                return box->SetHasAudio(flag);
            case kSwifterKitVideoBoxPropertyHasMIDI:
                return box->SetHasMIDI(flag);
            case kSwifterKitVideoBoxPropertyHasVideo:
                return box->SetHasVideo(flag);
            case kSwifterKitVideoBoxPropertyIsAcquirable:
                return box->SetIsAcquirable(flag);
            case kSwifterKitVideoBoxPropertyIsAcquired:
                return box->SetIsAcquired(flag);
            case kSwifterKitVideoBoxPropertyIsProtected:
                return box->SetIsProtected(flag);
            default:
                return box->SetAcquisitionFailure(
                    static_cast<kern_return_t>(static_cast<uint32_t>(value)));
        }
    }

    kern_return_t SetClockProperty(
        SwifterKitRuntimeVideoClockDevice* clock,
        uint32_t selector,
        uint64_t value) {
        const bool boolean = selector == kSwifterKitVideoClockPropertyClockIsStable
                             || selector == kSwifterKitVideoClockPropertyIsAlive
                             || selector == kSwifterKitVideoClockPropertyIsHidden;
        if (selector < kSwifterKitVideoClockPropertyClockDomain
            || selector > kSwifterKitVideoClockPropertyTransport || value > UINT32_MAX
            || (boolean && !IsBool(value)))
            return kIOReturnBadArgument;
        if (clock == nullptr)
            return kIOReturnNotFound;
        const auto number = static_cast<uint32_t>(value);
        switch (selector) {
            case kSwifterKitVideoClockPropertyClockDomain:
                return clock->SetClockDomain(number);
            case kSwifterKitVideoClockPropertyClockAlgorithm:
                return clock->SetClockAlgorithm(static_cast<IOUserVideoClockAlgorithm>(number));
            case kSwifterKitVideoClockPropertyClockIsStable:
                return clock->SetClockIsStable(number == 1);
            case kSwifterKitVideoClockPropertyIsAlive:
                return clock->SetDeviceIsAlive(number == 1);
            case kSwifterKitVideoClockPropertyIsHidden:
                return clock->SetIsHidden(number == 1);
            case kSwifterKitVideoClockPropertyInputLatency:
            case kSwifterKitVideoClockPropertyOutputLatency:
                return SwifterKitRequestVideoStructureChange(clock, selector, 0, number);
            default:
                return clock->SetTransportType(static_cast<IOUserVideoTransportType>(number));
        }
    }

    kern_return_t TopologyCommand(
        SwifterKitRuntimeService_IVars* state,
        uint32_t opcode,
        const SwifterKitVideoObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        const bool indexed = target.index < kSwifterKitVideoObjectTableCount;
        SwifterKitRuntimeVideoBox* box = target.kind == kSwifterKitVideoTargetBox && indexed
                                             ? state->videoBoxes[target.index]
                                             : nullptr;
        SwifterKitRuntimeVideoClockDevice* clockDevice =
            target.kind == kSwifterKitVideoTargetClock && indexed
                ? state->videoClockDevices[target.index]
                : nullptr;
        if (Is(opcode, Opcode::VideoGetBoxState)) {
            if (payloadLength != sizeof(target) || target.kind != kSwifterKitVideoTargetBox)
                return kIOReturnBadArgument;
            if (box == nullptr)
                return kIOReturnNotFound;
            const SwifterKitVideoBoxState boxState = {
                box->GetObjectID(),
                static_cast<uint32_t>(box->GetTransportType()),
                (box->HasAudio() ? kSwifterKitVideoBoxStateHasAudio : 0)
                    | (box->HasMIDI() ? kSwifterKitVideoBoxStateHasMIDI : 0)
                    | (box->HasVideo() ? kSwifterKitVideoBoxStateHasVideo : 0)
                    | (box->IsAcquirable() ? kSwifterKitVideoBoxStateIsAcquirable : 0)
                    | (box->IsAcquired() ? kSwifterKitVideoBoxStateIsAcquired : 0)
                    | (box->IsProtected() ? kSwifterKitVideoBoxStateIsProtected : 0),
                box->GetAcquisitionFailure()};
            return BytesResponse(&boxState, sizeof(boxState), response);
        }
        if (Is(opcode, Opcode::VideoSetBoxOwnership))
            return target.kind == kSwifterKitVideoTargetBox
                       ? SetBoxOwnership(state, box, target, payload, payloadLength)
                       : kIOReturnBadArgument;
        if (Is(opcode, Opcode::VideoGetClockDeviceState))
            return payloadLength == sizeof(target)
                       ? ClockState(ResolveClock(state, target), response)
                       : kIOReturnBadArgument;
        const bool boxOpcode = Is(opcode, Opcode::VideoSetBoxProperty);
        if (target.kind != (boxOpcode ? kSwifterKitVideoTargetBox : kSwifterKitVideoTargetClock))
            return kIOReturnBadArgument;
        if (Is(opcode, Opcode::VideoSetClockSampleRates)) {
            SwifterKitVideoListHeader header = {};
            if (payloadLength < sizeof(header))
                return kIOReturnBadArgument;
            memcpy(&header, payload, sizeof(header));
            double rates[kSwifterKitVideoMaximumSampleRates] = {};
            if (header.reserved != 0 || header.count == 0
                || header.count > kSwifterKitVideoMaximumSampleRates
                || payloadLength != sizeof(header) + header.count * sizeof(double))
                return kIOReturnBadArgument;
            memcpy(rates, payload + sizeof(header), header.count * sizeof(double));
            for (uint32_t index = 0; index < header.count; ++index) {
                if (!IsValidRate(rates[index]))
                    return kIOReturnBadArgument;
                for (uint32_t other = 0; other < index; ++other)
                    if (rates[other] == rates[index])
                        return kIOReturnBadArgument;
            }
            return clockDevice == nullptr
                       ? kIOReturnNotFound
                       : clockDevice->SetAvailableSampleRates(rates, header.count);
        }
        if (Is(opcode, Opcode::VideoUpdateClockTimestamp)) {
            SwifterKitVideoClockTimestamp timestamp = {};
            if (payloadLength != sizeof(timestamp))
                return kIOReturnBadArgument;
            if (clockDevice == nullptr)
                return kIOReturnNotFound;
            memcpy(&timestamp, payload, sizeof(timestamp));
            clockDevice->UpdateCurrentZeroTimestamp(timestamp.sampleTime, timestamp.hostTime);
            return kIOReturnSuccess;
        }
        SwifterKitVideoIndexedValue request = {};
        if (payloadLength != sizeof(request))
            return kIOReturnBadArgument;
        memcpy(&request, payload, sizeof(request));
        if (request.reserved != 0)
            return kIOReturnBadArgument;
        if (Is(opcode, Opcode::VideoRequestClockSampleRate)) {
            const double rate = __builtin_bit_cast(double, request.value);
            if (request.selector != 0 || !IsValidRate(rate))
                return kIOReturnBadArgument;
            return clockDevice == nullptr ? kIOReturnNotFound
                                          : clockDevice->RequestSampleRate(rate);
        }
        if (boxOpcode)
            return SetBoxProperty(box, request.selector, request.value);
        if (Is(opcode, Opcode::VideoSetClockDeviceProperty))
            return SetClockProperty(clockDevice, request.selector, request.value);
        return kIOReturnUnsupported;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartVideoObjects() {
    if (ivars == nullptr || ivars->videoLock == nullptr)
        return kIOReturnNotReady;
    // Without the timeout timer, box and clock requests take the framework default at once.
    (void)StartVideoRequests();
    kern_return_t result = kIOReturnSuccess;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitVideoClockDeviceCount;
         ++index) {
        const auto& config = kSwifterKitVideoClockDevices[index];
        OSString* deviceUID = OSString::withCString(config.deviceUID);
        OSString* modelUID = OSString::withCString(config.modelUID);
        OSString* manufacturerUID = OSString::withCString(config.manufacturerUID);
        auto* clock = OSTypeAlloc(SwifterKitRuntimeVideoClockDevice);
        result = deviceUID == nullptr || modelUID == nullptr || manufacturerUID == nullptr
                         || clock == nullptr
                     ? kIOReturnNoMemory
                     : kIOReturnSuccess;
        if (result == kIOReturnSuccess
            && !clock->init(this, this, index, deviceUID, modelUID, manufacturerUID))
            result = kIOReturnNoMemory;
        if (result == kIOReturnSuccess)
            result = clock->Configure(&config);
        if (result == kIOReturnSuccess)
            result = AddObject(clock);
        IOLockLock(ivars->videoLock);
        if (result == kIOReturnSuccess)
            ivars->videoClockDevices[index] = clock;
        IOLockUnlock(ivars->videoLock);
        if (result != kIOReturnSuccess)
            OSSafeReleaseNULL(clock);
        OSSafeReleaseNULL(deviceUID);
        OSSafeReleaseNULL(modelUID);
        OSSafeReleaseNULL(manufacturerUID);
    }
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitVideoBoxCount;
         ++index) {
        const auto& config = kSwifterKitVideoBoxes[index];
        OSString* uid = OSString::withCString(config.uid);
        auto* box = OSTypeAlloc(SwifterKitRuntimeVideoBox);
        result = uid == nullptr || box == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        if (result == kIOReturnSuccess && !box->init(this, this, index, config.isAcquirable, uid))
            result = kIOReturnNoMemory;
        if (result == kIOReturnSuccess)
            result = box->Configure(&config);
        IOLockLock(ivars->videoLock);
        if (result == kIOReturnSuccess && config.ownsDevice && ivars->videoDevice != nullptr) {
            result = box->AddDevice(ivars->videoDevice);
            if (result == kIOReturnSuccess)
                ivars->videoDeviceOwner = static_cast<uint8_t>(index + 1);
        }
        for (uint32_t clock = 0;
             result == kIOReturnSuccess && clock < kSwifterKitVideoObjectTableCount;
             ++clock) {
            if ((config.clockMask & (1U << clock)) == 0
                || ivars->videoClockDevices[clock] == nullptr)
                continue;
            result = box->AddClockDevice(ivars->videoClockDevices[clock]);
            if (result == kIOReturnSuccess)
                ivars->videoClockOwners[clock] = static_cast<uint8_t>(index + 1);
        }
        if (result == kIOReturnSuccess)
            ivars->videoBoxes[index] = box;
        IOLockUnlock(ivars->videoLock);
        if (result == kIOReturnSuccess)
            result = AddObject(box);
        else
            OSSafeReleaseNULL(box);
        OSSafeReleaseNULL(uid);
    }
    return result;
}

void SwifterKitRuntimeService::StopVideoObjects() {
    if (ivars == nullptr || ivars->videoLock == nullptr)
        return;
    StopVideoRequests();
    IOLockLock(ivars->videoLock);
    for (uint32_t index = 0; index < kSwifterKitVideoObjectTableCount; ++index) {
        SwifterKitRuntimeVideoBox* box = ivars->videoBoxes[index];
        ivars->videoBoxes[index] = nullptr;
        if (box == nullptr)
            continue;
        const auto owner = static_cast<uint8_t>(index + 1);
        if (ivars->videoDeviceOwner == owner && ivars->videoDevice != nullptr)
            (void)box->RemoveDevice(ivars->videoDevice);
        if (ivars->videoDeviceOwner == owner)
            ivars->videoDeviceOwner = kNoOwner;
        for (uint32_t clock = 0; clock < kSwifterKitVideoObjectTableCount; ++clock) {
            if (ivars->videoClockOwners[clock] != owner)
                continue;
            if (ivars->videoClockDevices[clock] != nullptr)
                (void)box->RemoveClockDevice(ivars->videoClockDevices[clock]);
            ivars->videoClockOwners[clock] = kNoOwner;
        }
        (void)RemoveObject(box);
        OSSafeReleaseNULL(box);
    }
    for (uint32_t index = 0; index < kSwifterKitVideoObjectTableCount; ++index) {
        SwifterKitRuntimeVideoClockDevice* clock = ivars->videoClockDevices[index];
        ivars->videoClockDevices[index] = nullptr;
        if (clock != nullptr)
            (void)RemoveObject(clock);
        OSSafeReleaseNULL(clock);
    }
    IOLockUnlock(ivars->videoLock);
}

kern_return_t SwifterKitRuntimeService::VideoObjectCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->videoLock == nullptr || response == nullptr)
        return kIOReturnBadArgument;
    *response = nullptr;
    if (payload == nullptr)
        return kIOReturnBadArgument;
    if (Is(opcode, Opcode::VideoCompleteRequest)) {
        if (payloadLength != sizeof(SwifterKitVideoRequestAnswer))
            return kIOReturnBadArgument;
        SwifterKitVideoRequestAnswer answer = {};
        memcpy(&answer, payload, sizeof(answer));
        if (answer.requestID == 0 || answer.accepted > 1 || answer.reserved != 0
            || (answer.accepted == 1 && answer.failure != 0))
            return kIOReturnBadArgument;
        return CompleteVideoRequest(answer.requestID, answer.accepted == 1, answer.failure);
    }
    if (Is(opcode, Opcode::VideoNotifyBufferQueue)
        || Is(opcode, Opcode::VideoSetCustomPropertyOwner)) {
        if (payloadLength != 16)
            return kIOReturnBadArgument;
        uint32_t words[2] = {};
        uint64_t value = 0;
        memcpy(words, payload, sizeof(words));
        memcpy(&value, payload + sizeof(words), sizeof(value));
        IOLockLock(ivars->videoLock);
        SwifterKitRuntimeVideoDevice* device = ivars->videoDevice;
        kern_return_t result = kIOReturnNotReady;
        if (device != nullptr)
            result = Is(opcode, Opcode::VideoNotifyBufferQueue)
                         ? device->NotifyBufferQueue(words[0], words[1], value)
                         : (value != 0 ? kIOReturnBadArgument
                                       : device->SetCustomPropertyOwner(words[0], words[1]));
        IOLockUnlock(ivars->videoLock);
        return result;
    }
    if (payloadLength < sizeof(SwifterKitVideoObjectTarget))
        return kIOReturnBadArgument;
    SwifterKitVideoObjectTarget target = {};
    memcpy(&target, payload, sizeof(target));
    IOLockLock(ivars->videoLock);
    kern_return_t result = kIOReturnUnsupported;
    if (Is(opcode, Opcode::VideoGetObjectInfo))
        result = payloadLength == sizeof(target) ? ObjectInfo(this, ivars, target, response)
                                                 : kIOReturnBadArgument;
    else if (
        Is(opcode, Opcode::VideoSetObjectName) || Is(opcode, Opcode::VideoPropertiesChanged)
        || Is(opcode, Opcode::VideoGetElementName) || Is(opcode, Opcode::VideoSetElementName))
        result = NameCommand(this, ivars, opcode, target, payload, payloadLength, response);
    else
        result = TopologyCommand(ivars, opcode, target, payload, payloadLength, response);
    IOLockUnlock(ivars->videoLock);
    return result;
}

#endif
