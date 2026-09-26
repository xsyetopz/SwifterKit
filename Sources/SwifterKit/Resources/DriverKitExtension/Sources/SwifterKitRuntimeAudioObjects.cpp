#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioBox.h"
    #include "SwifterKitRuntimeAudioClockDevice.h"
    #include "SwifterKitRuntimeAudioDevice.h"
    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeSchema.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    using Opcode = SwifterKitRuntimeOpcode;

    constexpr uint8_t kNoOwner = 0;

    bool Is(uint32_t opcode, Opcode expected) {
        return opcode == static_cast<uint32_t>(expected);
    }

    // Resolves a device, box, clock-device, or object-ID target; the driver is not an object.
    IOUserAudioObject* ResolveObject(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        const SwifterKitAudioObjectTarget& target,
        OSSharedPtr<IOUserAudioObject>& holder) {
        const bool indexed = target.index < kSwifterKitAudioObjectTableCount;
        switch (target.kind) {
            case kSwifterKitAudioTargetDevice:
                return state->audioDevice;
            case kSwifterKitAudioTargetBox:
                return indexed ? state->audioBoxes[target.index] : nullptr;
            case kSwifterKitAudioTargetClock:
                return indexed ? state->audioClockDevices[target.index] : nullptr;
            case kSwifterKitAudioTargetObject:
                holder = service->GetAudioObjectForObjectID(target.index);
                return holder.get();
            default:
                return nullptr;
        }
    }

    IOUserAudioClockDevice* ResolveClock(
        SwifterKitRuntimeService_IVars* state,
        const SwifterKitAudioObjectTarget& target) {
        if (target.kind == kSwifterKitAudioTargetDevice)
            return state->audioDevice;
        if (target.kind == kSwifterKitAudioTargetClock
            && target.index < kSwifterKitAudioObjectTableCount)
            return state->audioClockDevices[target.index];
        return nullptr;
    }

    // Copies a bounded, NUL-free name from a payload into an OSString.
    OSString* CopyName(const uint8_t* bytes, uint32_t length) {
        char name[256] = {};
        if (bytes == nullptr || length == 0 || length > 255 || memchr(bytes, 0, length) != nullptr)
            return nullptr;
        memcpy(name, bytes, length);
        return OSString::withCString(name);
    }

    kern_return_t AppendName(OSData* data, const OSSharedPtr<OSString>& name, uint32_t* length) {
        *length = name ? static_cast<uint32_t>(name->getLength()) : 0;
        if (*length > 255)
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

    kern_return_t ElementNameCommand(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        uint32_t opcode,
        const SwifterKitAudioObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response);
    kern_return_t TopologyCommand(
        SwifterKitRuntimeService_IVars* state,
        uint32_t opcode,
        const SwifterKitAudioObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response);
    kern_return_t SetBoxProperty(SwifterKitRuntimeAudioBox* box, uint32_t selector, uint64_t value);
    kern_return_t SetClockProperty(
        SwifterKitRuntimeAudioClockDevice* clock,
        uint32_t selector,
        uint64_t value);

    kern_return_t ObjectCommand(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        uint32_t opcode,
        const SwifterKitAudioObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        OSSharedPtr<IOUserAudioObject> holder;
        const bool isDriver = target.kind == kSwifterKitAudioTargetDriver && target.index == 0;
        if (Is(opcode, Opcode::AudioGetObjectInfo)) {
            if (payloadLength != sizeof(target))
                return kIOReturnBadArgument;
            SwifterKitAudioObjectInfoHeader header = {};
            OSSharedPtr<OSString> name;
            OSSharedPtr<OSString> uid;
            if (isDriver) {
                header.classID = static_cast<uint32_t>(service->GetClassID());
                header.baseClassID = static_cast<uint32_t>(service->GetBaseClassID());
                header.transport = static_cast<uint32_t>(service->GetTransportType());
                name = service->GetName();
            } else {
                IOUserAudioObject* object = ResolveObject(service, state, target, holder);
                if (object == nullptr)
                    return kIOReturnNotFound;
                header.objectID = object->GetObjectID();
                header.ownerObjectID = object->GetOwnerObjectID();
                header.classID = static_cast<uint32_t>(object->GetClassID());
                header.baseClassID = static_cast<uint32_t>(object->GetBaseClassID());
                name = object->GetName();
                if (auto* clock = OSDynamicCast(IOUserAudioClockDevice, object)) {
                    header.transport = static_cast<uint32_t>(clock->GetTransportType());
                    uid = clock->GetUID();
                } else if (auto* box = OSDynamicCast(IOUserAudioBox, object)) {
                    header.transport = static_cast<uint32_t>(box->GetTransportType());
                    uid = box->GetUID();
                }
            }
            OSData* data = OSData::withCapacity(sizeof(header) + 510);
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
        if (Is(opcode, Opcode::AudioSetObjectName) || Is(opcode, Opcode::AudioPropertiesChanged)) {
            if (payloadLength < sizeof(SwifterKitAudioListHeader))
                return kIOReturnBadArgument;
            SwifterKitAudioListHeader header = {};
            memcpy(&header, payload, sizeof(header));
            const uint8_t* body = payload + sizeof(header);
            const uint64_t bodyLength = payloadLength - sizeof(header);
            if (header.reserved != 0)
                return kIOReturnBadArgument;
            if (Is(opcode, Opcode::AudioSetObjectName)) {
                if (bodyLength != header.count)
                    return kIOReturnBadArgument;
                OSString* name = CopyName(body, header.count);
                if (name == nullptr)
                    return kIOReturnBadArgument;
                IOUserAudioObject* object =
                    isDriver ? nullptr : ResolveObject(service, state, target, holder);
                const kern_return_t result = isDriver            ? service->SetName(name)
                                             : object != nullptr ? object->SetName(name)
                                                                 : kIOReturnNotFound;
                name->release();
                return result;
            }
            IOUserAudioObjectPropertySelector selectors[32] = {};
            if (header.count == 0 || header.count > 32 || bodyLength != header.count * 4ULL)
                return kIOReturnBadArgument;
            memcpy(selectors, body, header.count * 4ULL);
            for (uint32_t index = 0; index < header.count; ++index)
                if (selectors[index] == 0)
                    return kIOReturnBadArgument;
            IOUserAudioObject* object = ResolveObject(service, state, target, holder);
            return object == nullptr
                       ? kIOReturnNotFound
                       : service->PropertiesChanged(object->GetObjectID(), selectors, header.count);
        }
        if (Is(opcode, Opcode::AudioGetElementName) || Is(opcode, Opcode::AudioSetElementName))
            return ElementNameCommand(
                service,
                state,
                opcode,
                target,
                payload,
                payloadLength,
                response);
        return TopologyCommand(state, opcode, target, payload, payloadLength, response);
    }

    kern_return_t ElementNameCommand(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state,
        uint32_t opcode,
        const SwifterKitAudioObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        if (payloadLength < sizeof(SwifterKitAudioElementNameHeader))
            return kIOReturnBadArgument;
        SwifterKitAudioElementNameHeader header = {};
        memcpy(&header, payload, sizeof(header));
        const bool setting = Is(opcode, Opcode::AudioSetElementName);
        if (header.kind > 2
            || (setting ? payloadLength != sizeof(header) + header.length
                        : payloadLength != sizeof(header) || header.length != 0))
            return kIOReturnBadArgument;
        OSSharedPtr<IOUserAudioObject> holder;
        IOUserAudioObject* object = ResolveObject(service, state, target, holder);
        if (object == nullptr)
            return kIOReturnNotFound;
        const auto scope = static_cast<IOUserAudioObjectPropertyScope>(header.scope);
        const IOUserAudioObjectPropertyElement element = header.element;
        if (setting) {
            OSString* name = CopyName(payload + sizeof(header), header.length);
            if (name == nullptr)
                return kIOReturnBadArgument;
            const kern_return_t result =
                header.kind == 0   ? object->SetElementName(element, scope, name)
                : header.kind == 1 ? object->SetElementCategoryName(element, scope, name)
                                   : object->SetElementNumberName(element, scope, name);
            name->release();
            return result;
        }
        const OSSharedPtr<OSString> name = header.kind == 0 ? object->GetElementName(element, scope)
                                           : header.kind == 1
                                               ? object->GetElementCategoryName(element, scope)
                                               : object->GetElementNumberName(element, scope);
        if (!name || name->getLength() == 0)
            return kIOReturnSuccess;
        return name->getLength() > 255
                   ? kIOReturnNoSpace
                   : BytesResponse(name->getCStringNoCopy(), name->getLength(), response);
    }

    kern_return_t TopologyCommand(
        SwifterKitRuntimeService_IVars* state,
        uint32_t opcode,
        const SwifterKitAudioObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response) {
        const bool indexed = target.index < kSwifterKitAudioObjectTableCount;
        SwifterKitRuntimeAudioBox* box = target.kind == kSwifterKitAudioTargetBox && indexed
                                             ? state->audioBoxes[target.index]
                                             : nullptr;
        SwifterKitRuntimeAudioClockDevice* clockDevice =
            target.kind == kSwifterKitAudioTargetClock && indexed
                ? state->audioClockDevices[target.index]
                : nullptr;
        if (Is(opcode, Opcode::AudioGetBoxState)) {
            if (payloadLength != sizeof(target))
                return kIOReturnBadArgument;
            if (box == nullptr)
                return kIOReturnNotFound;
            const SwifterKitAudioBoxState boxState = {
                box->GetObjectID(),
                static_cast<uint32_t>(box->GetTransportType()),
                (box->HasAudio() ? 0x1U : 0) | (box->HasMIDI() ? 0x2U : 0)
                    | (box->HasVideo() ? 0x4U : 0) | (box->IsAcquirable() ? 0x8U : 0)
                    | (box->IsAcquired() ? 0x10U : 0) | (box->IsProtected() ? 0x20U : 0),
                box->GetAcquisitionFailure()};
            return BytesResponse(&boxState, sizeof(boxState), response);
        }
        if (Is(opcode, Opcode::AudioSetBoxOwnership)) {
            SwifterKitAudioBoxOwnership request = {};
            if (payloadLength != sizeof(request))
                return kIOReturnBadArgument;
            memcpy(&request, payload, sizeof(request));
            const bool device = request.member.kind == kSwifterKitAudioTargetDevice;
            if (request.owned > 1 || request.reserved != 0
                || (device ? request.member.index != 0
                           : request.member.kind != kSwifterKitAudioTargetClock
                                 || request.member.index >= kSwifterKitAudioObjectTableCount))
                return kIOReturnBadArgument;
            IOUserAudioClockDevice* member =
                device ? static_cast<IOUserAudioClockDevice*>(state->audioDevice)
                       : state->audioClockDevices[request.member.index];
            if (box == nullptr || member == nullptr)
                return kIOReturnNotFound;
            uint8_t& owner =
                device ? state->audioDeviceOwner : state->audioClockOwners[request.member.index];
            const auto self = static_cast<uint8_t>(target.index + 1);
            if (request.owned == 1 ? owner != kNoOwner : owner != self)
                return owner == self ? kIOReturnSuccess : kIOReturnBusy;
            kern_return_t result = kIOReturnSuccess;
            if (device)
                result = request.owned == 1 ? box->AddDevice(state->audioDevice)
                                            : box->RemoveDevice(state->audioDevice);
            else
                result = request.owned == 1 ? box->AddClockDevice(member)
                                            : box->RemoveClockDevice(member);
            if (result == kIOReturnSuccess)
                owner = request.owned == 1 ? self : kNoOwner;
            return result;
        }
        if (Is(opcode, Opcode::AudioGetClockDeviceState)) {
            if (payloadLength != sizeof(target))
                return kIOReturnBadArgument;
            IOUserAudioClockDevice* clock = ResolveClock(state, target);
            if (clock == nullptr)
                return kIOReturnNotFound;
            uint8_t
                bytes[sizeof(SwifterKitAudioClockState) + kSwifterKitAudioMaximumSampleRates * 8] =
                    {};
            double rates[kSwifterKitAudioMaximumSampleRates] = {};
            size_t count = clock->GetNumberAvailableSampleRates();
            count = count > kSwifterKitAudioMaximumSampleRates ? kSwifterKitAudioMaximumSampleRates
                                                               : count;
            count = clock->GetAvailableSampleRates(rates, count);
            count = count > kSwifterKitAudioMaximumSampleRates ? kSwifterKitAudioMaximumSampleRates
                                                               : count;
            SwifterKitAudioClockState clockState = {};
            uint64_t zeroSampleTime = 0;
            uint64_t zeroHostTime = 0;
            uint64_t inputSampleTime = 0;
            uint64_t outputSampleTime = 0;
            clock->GetCurrentZeroTimestamp(&zeroSampleTime, &zeroHostTime);
            clock->GetCurrentClientSampleTime(&inputSampleTime, &outputSampleTime);
            clockState.sampleRateBits = __builtin_bit_cast(uint64_t, clock->GetSampleRate());
            clockState.zeroSampleTime = zeroSampleTime;
            clockState.zeroHostTime = zeroHostTime;
            clockState.clientInputSampleTime = inputSampleTime;
            clockState.clientOutputSampleTime = outputSampleTime;
            clockState.objectID = clock->GetObjectID();
            clockState.clockDomain = clock->GetClockDomain();
            clockState.clockAlgorithm = static_cast<uint32_t>(clock->GetClockAlgorithm());
            clockState.transport = static_cast<uint32_t>(clock->GetTransportType());
            clockState.transportState = static_cast<uint32_t>(clock->GetDeviceTransportState());
            clockState.flags =
                (clock->GetClockIsStable() ? 0x1U : 0) | (clock->GetDeviceIsAlive() ? 0x2U : 0)
                | (clock->GetDeviceIsRunning() ? 0x4U : 0) | (clock->GetIsHidden() ? 0x8U : 0)
                | (clock->GetSupportsPrewarming() ? 0x10U : 0);
            clockState.inputLatency = clock->GetInputLatency();
            clockState.outputLatency = clock->GetOutputLatency();
            clockState.zeroTimestampPeriod = clock->GetZeroTimestampPeriod();
            clockState.rateCount = static_cast<uint32_t>(count);
            memcpy(bytes, &clockState, sizeof(clockState));
            memcpy(bytes + sizeof(clockState), rates, count * sizeof(double));
            return BytesResponse(bytes, sizeof(clockState) + count * sizeof(double), response);
        }
        if (target.kind != kSwifterKitAudioTargetClock && !Is(opcode, Opcode::AudioSetBoxProperty))
            return kIOReturnBadArgument;
        if (Is(opcode, Opcode::AudioSetClockSampleRates)) {
            SwifterKitAudioListHeader header = {};
            if (payloadLength < sizeof(header))
                return kIOReturnBadArgument;
            memcpy(&header, payload, sizeof(header));
            double rates[16] = {};
            if (header.reserved != 0 || header.count == 0 || header.count > 16
                || payloadLength != sizeof(header) + header.count * sizeof(double))
                return kIOReturnBadArgument;
            memcpy(rates, payload + sizeof(header), header.count * sizeof(double));
            for (uint32_t index = 0; index < header.count; ++index) {
                if (!(rates[index] >= 8000.0 && rates[index] <= 768000.0))
                    return kIOReturnBadArgument;
                for (uint32_t other = 0; other < index; ++other)
                    if (rates[other] == rates[index])
                        return kIOReturnBadArgument;
            }
            return clockDevice == nullptr
                       ? kIOReturnNotFound
                       : clockDevice->SetAvailableSampleRates(rates, header.count);
        }
        if (Is(opcode, Opcode::AudioUpdateClockTimestamp)) {
            SwifterKitAudioClockTimestamp timestamp = {};
            if (payloadLength != sizeof(timestamp))
                return kIOReturnBadArgument;
            if (clockDevice == nullptr)
                return kIOReturnNotFound;
            memcpy(&timestamp, payload, sizeof(timestamp));
            clockDevice->UpdateCurrentZeroTimestamp(timestamp.sampleTime, timestamp.hostTime);
            return kIOReturnSuccess;
        }
        SwifterKitAudioIndexedValue request = {};
        if (payloadLength != sizeof(request))
            return kIOReturnBadArgument;
        memcpy(&request, payload, sizeof(request));
        if (request.reserved != 0)
            return kIOReturnBadArgument;
        if (Is(opcode, Opcode::AudioRequestClockSampleRate)) {
            if (request.selector != 0)
                return kIOReturnBadArgument;
            return clockDevice == nullptr
                       ? kIOReturnNotFound
                       : clockDevice->RequestSampleRate(__builtin_bit_cast(double, request.value));
        }
        if (Is(opcode, Opcode::AudioSetBoxProperty))
            return SetBoxProperty(box, request.selector, request.value);
        if (Is(opcode, Opcode::AudioSetClockDeviceProperty))
            return SetClockProperty(clockDevice, request.selector, request.value);
        return kIOReturnUnsupported;
    }

    kern_return_t
        SetBoxProperty(SwifterKitRuntimeAudioBox* box, uint32_t selector, uint64_t value) {
        if (selector == 0 || selector > 8 || (selector >= 2 && selector <= 7 && !IsBool(value))
            || value > UINT32_MAX)
            return kIOReturnBadArgument;
        if (box == nullptr)
            return kIOReturnNotFound;
        const bool flag = value == 1;
        switch (selector) {
            case 1:
                return box->SetTransportType(static_cast<IOUserAudioTransportType>(value));
            case 2:
                return box->SetHasAudio(flag);
            case 3:
                return box->SetHasMIDI(flag);
            case 4:
                return box->SetHasVideo(flag);
            case 5:
                return box->SetIsAcquirable(flag);
            case 6:
                return box->SetIsAcquired(flag);
            case 7:
                return box->SetIsProtected(flag);
            default:
                return box->SetAcquisitionFailure(
                    static_cast<kern_return_t>(static_cast<uint32_t>(value)));
        }
    }

    kern_return_t SetClockProperty(
        SwifterKitRuntimeAudioClockDevice* clock,
        uint32_t selector,
        uint64_t value) {
        const bool boolean = selector == 3 || selector == 4 || selector == 5 || selector == 10;
        if (selector == 0 || selector > 10 || value > UINT32_MAX || (boolean && !IsBool(value))
            || (selector == 9 && (value < 16 || value > 1048576)))
            return kIOReturnBadArgument;
        if (clock == nullptr)
            return kIOReturnNotFound;
        const auto number = static_cast<uint32_t>(value);
        switch (selector) {
            case 1:
                return clock->SetClockDomain(number);
            case 2:
                return clock->SetClockAlgorithm(static_cast<IOUserAudioClockAlgorithm>(number));
            case 3:
                return clock->SetClockIsStable(number == 1);
            case 4:
                return clock->SetDeviceIsAlive(number == 1);
            case 5:
                return clock->SetIsHidden(number == 1);
            case 6:
                return clock->SetInputLatency(number);
            case 7:
                return clock->SetOutputLatency(number);
            case 8:
                return clock->SetTransportType(static_cast<IOUserAudioTransportType>(number));
            case 9:
                return clock->SetZeroTimeStampPeriod(number);
            default:
    #if defined(__DRIVERKIT_25_5) && __DRIVERKIT_VERSION_MAX_ALLOWED >= __DRIVERKIT_25_5
                clock->SetWantsControlsRestored(number == 1);
                return kIOReturnSuccess;
    #else
                return kIOReturnUnsupported;
    #endif
        }
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartAudioObjects() {
    if (ivars == nullptr || ivars->audioLock == nullptr)
        return kIOReturnNotReady;
    kern_return_t result = StartAudioRequests();
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitAudioClockDeviceCount;
         ++index) {
        const auto& config = kSwifterKitAudioClockDevices[index];
        OSString* deviceUID = OSString::withCString(config.deviceUID);
        OSString* modelUID = OSString::withCString(config.modelUID);
        OSString* manufacturerUID = OSString::withCString(config.manufacturerUID);
        auto* clock = OSTypeAlloc(SwifterKitRuntimeAudioClockDevice);
        result = deviceUID == nullptr || modelUID == nullptr || manufacturerUID == nullptr
                         || clock == nullptr
                     ? kIOReturnNoMemory
                     : kIOReturnSuccess;
        if (result == kIOReturnSuccess
            && !clock->init(
                this,
                this,
                index,
                config.supportsPrewarming,
                deviceUID,
                modelUID,
                manufacturerUID,
                config.zeroTimestampPeriod))
            result = kIOReturnNoMemory;
        if (result == kIOReturnSuccess)
            result = clock->Configure(&config);
        if (result == kIOReturnSuccess)
            result = AddObject(clock);
        IOLockLock(ivars->audioLock);
        if (result == kIOReturnSuccess)
            ivars->audioClockDevices[index] = clock;
        IOLockUnlock(ivars->audioLock);
        if (result != kIOReturnSuccess)
            OSSafeReleaseNULL(clock);
        OSSafeReleaseNULL(deviceUID);
        OSSafeReleaseNULL(modelUID);
        OSSafeReleaseNULL(manufacturerUID);
    }
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitAudioBoxCount;
         ++index) {
        const auto& config = kSwifterKitAudioBoxes[index];
        OSString* uid = OSString::withCString(config.uid);
        auto* box = OSTypeAlloc(SwifterKitRuntimeAudioBox);
        result = uid == nullptr || box == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        if (result == kIOReturnSuccess && !box->init(this, this, index, config.isAcquirable, uid))
            result = kIOReturnNoMemory;
        if (result == kIOReturnSuccess)
            result = box->Configure(&config);
        IOLockLock(ivars->audioLock);
        if (result == kIOReturnSuccess && config.ownsDevice && ivars->audioDevice != nullptr) {
            result = box->AddDevice(ivars->audioDevice);
            if (result == kIOReturnSuccess)
                ivars->audioDeviceOwner = static_cast<uint8_t>(index + 1);
        }
        for (uint32_t clock = 0;
             result == kIOReturnSuccess && clock < kSwifterKitAudioObjectTableCount;
             ++clock) {
            if ((config.clockMask & (1U << clock)) == 0
                || ivars->audioClockDevices[clock] == nullptr)
                continue;
            result = box->AddClockDevice(ivars->audioClockDevices[clock]);
            if (result == kIOReturnSuccess)
                ivars->audioClockOwners[clock] = static_cast<uint8_t>(index + 1);
        }
        if (result == kIOReturnSuccess)
            ivars->audioBoxes[index] = box;
        IOLockUnlock(ivars->audioLock);
        if (result == kIOReturnSuccess)
            result = AddObject(box);
        else
            OSSafeReleaseNULL(box);
        OSSafeReleaseNULL(uid);
    }
    return result;
}

void SwifterKitRuntimeService::StopAudioObjects() {
    if (ivars == nullptr || ivars->audioLock == nullptr)
        return;
    StopAudioRequests();
    IOLockLock(ivars->audioLock);
    for (uint32_t index = 0; index < kSwifterKitAudioObjectTableCount; ++index) {
        SwifterKitRuntimeAudioBox* box = ivars->audioBoxes[index];
        ivars->audioBoxes[index] = nullptr;
        if (box == nullptr)
            continue;
        const auto owner = static_cast<uint8_t>(index + 1);
        if (ivars->audioDeviceOwner == owner && ivars->audioDevice != nullptr)
            (void)box->RemoveDevice(ivars->audioDevice);
        if (ivars->audioDeviceOwner == owner)
            ivars->audioDeviceOwner = kNoOwner;
        for (uint32_t clock = 0; clock < kSwifterKitAudioObjectTableCount; ++clock) {
            if (ivars->audioClockOwners[clock] != owner)
                continue;
            if (ivars->audioClockDevices[clock] != nullptr)
                (void)box->RemoveClockDevice(ivars->audioClockDevices[clock]);
            ivars->audioClockOwners[clock] = kNoOwner;
        }
        (void)RemoveObject(box);
        OSSafeReleaseNULL(box);
    }
    for (uint32_t index = 0; index < kSwifterKitAudioObjectTableCount; ++index) {
        SwifterKitRuntimeAudioClockDevice* clock = ivars->audioClockDevices[index];
        ivars->audioClockDevices[index] = nullptr;
        if (clock != nullptr)
            (void)RemoveObject(clock);
        OSSafeReleaseNULL(clock);
    }
    IOLockUnlock(ivars->audioLock);
}

kern_return_t SwifterKitRuntimeService::AudioObjectCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->audioLock == nullptr || response == nullptr)
        return kIOReturnBadArgument;
    *response = nullptr;
    if (Is(opcode, Opcode::AudioCompleteRequest)) {
        if (payload == nullptr || payloadLength != sizeof(SwifterKitAudioRequestAnswer))
            return kIOReturnBadArgument;
        SwifterKitAudioRequestAnswer answer = {};
        memcpy(&answer, payload, sizeof(answer));
        if (answer.requestID == 0 || answer.accepted > 1 || answer.reserved != 0
            || (answer.accepted == 1 && answer.failure != 0))
            return kIOReturnBadArgument;
        return CompleteAudioRequest(answer.requestID, answer.accepted == 1, answer.failure);
    }
    if (payload == nullptr || payloadLength < sizeof(SwifterKitAudioObjectTarget))
        return kIOReturnBadArgument;
    SwifterKitAudioObjectTarget target = {};
    memcpy(&target, payload, sizeof(target));
    IOLockLock(ivars->audioLock);
    const kern_return_t result =
        ObjectCommand(this, ivars, opcode, target, payload, payloadLength, response);
    IOLockUnlock(ivars->audioLock);
    return result;
}

#endif
