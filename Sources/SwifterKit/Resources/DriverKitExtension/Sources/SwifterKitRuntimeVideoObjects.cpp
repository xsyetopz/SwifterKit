#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeMediaObjects.h"
    #include "SwifterKitRuntimeSchema.h"
    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeVideoBox.h"
    #include "SwifterKitRuntimeVideoClockDevice.h"
    #include "SwifterKitRuntimeVideoDevice.h"
    #include "SwifterKitRuntimeVideoDeviceState.h"
    #include "SwifterKitRuntimeVideoProtocol.h"

namespace {
    using Opcode = SwifterKitRuntimeOpcode;

    bool Is(uint32_t opcode, Opcode expected) {
        return opcode == static_cast<uint32_t>(expected);
    }

    // Resolves a device, box, clock-device, or object-ID target. The driver is not an object.
    IOUserVideoObject* ResolveObject(
        SwifterKitRuntimeService* service,
        const SwifterKitRuntimeService_IVars* state,
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
        const SwifterKitRuntimeService_IVars* state,
        const SwifterKitVideoObjectTarget& target) {
        if (target.kind == kSwifterKitVideoTargetDevice && target.index == 0)
            return state->videoDevice;
        if (target.kind == kSwifterKitVideoTargetClock
            && target.index < kSwifterKitVideoObjectTableCount)
            return state->videoClockDevices[target.index];
        return nullptr;
    }

    // The VideoDriverKit classes, schema values, and service ivars the
    // SwifterKitRuntimeMediaObjects.h object templates operate on.
    struct VideoObjectFamily {
        using Driver = IOUserVideoDriver;
        using Object = IOUserVideoObject;
        using Box = IOUserVideoBox;
        using ClockDevice = IOUserVideoClockDevice;
        using RuntimeBox = SwifterKitRuntimeVideoBox;
        using RuntimeClockDevice = SwifterKitRuntimeVideoClockDevice;
        using TransportType = IOUserVideoTransportType;
        using Scope = IOUserVideoObjectPropertyScope;
        using Element = IOUserVideoObjectPropertyElement;
        using PropertySelector = IOUserVideoObjectPropertySelector;
        using ListHeader = SwifterKitVideoListHeader;
        using ElementNameHeader = SwifterKitVideoElementNameHeader;
        using BoxOwnership = SwifterKitVideoBoxOwnership;
        using BoxState = SwifterKitVideoBoxState;
        using ClockState = SwifterKitVideoClockState;
        using ClockTimestamp = SwifterKitVideoClockTimestamp;

        static constexpr uint32_t kNameMaximumLength = kSwifterKitVideoNameMaximumLength;
        static constexpr uint32_t kMaximumChangedProperties =
            kSwifterKitVideoMaximumChangedProperties;
        static constexpr uint32_t kMaximumSampleRates = kSwifterKitVideoMaximumSampleRates;
        static constexpr uint32_t kMaximumSettableSampleRates = kSwifterKitVideoMaximumSampleRates;
        static constexpr uint32_t kObjectTableCount = kSwifterKitVideoObjectTableCount;
        static constexpr uint32_t kTargetDevice = kSwifterKitVideoTargetDevice;
        static constexpr uint32_t kTargetClock = kSwifterKitVideoTargetClock;
        static constexpr uint32_t kElementName = kSwifterKitVideoElementName;
        static constexpr uint32_t kElementCategory = kSwifterKitVideoElementCategory;
        static constexpr uint32_t kElementNumber = kSwifterKitVideoElementNumber;
        static constexpr uint32_t kClockStateClockIsStable =
            kSwifterKitVideoClockStateClockIsStable;
        static constexpr uint32_t kClockStateIsAlive = kSwifterKitVideoClockStateIsAlive;
        static constexpr uint32_t kClockStateIsRunning = kSwifterKitVideoClockStateIsRunning;
        static constexpr uint32_t kClockStateIsHidden = kSwifterKitVideoClockStateIsHidden;
        static constexpr uint32_t kBoxStateHasAudio = kSwifterKitVideoBoxStateHasAudio;
        static constexpr uint32_t kBoxStateHasMIDI = kSwifterKitVideoBoxStateHasMIDI;
        static constexpr uint32_t kBoxStateHasVideo = kSwifterKitVideoBoxStateHasVideo;
        static constexpr uint32_t kBoxStateIsAcquirable = kSwifterKitVideoBoxStateIsAcquirable;
        static constexpr uint32_t kBoxStateIsAcquired = kSwifterKitVideoBoxStateIsAcquired;
        static constexpr uint32_t kBoxStateIsProtected = kSwifterKitVideoBoxStateIsProtected;
        static constexpr uint32_t kBoxPropertyTransport = kSwifterKitVideoBoxPropertyTransport;
        static constexpr uint32_t kBoxPropertyHasAudio = kSwifterKitVideoBoxPropertyHasAudio;
        static constexpr uint32_t kBoxPropertyHasMIDI = kSwifterKitVideoBoxPropertyHasMIDI;
        static constexpr uint32_t kBoxPropertyHasVideo = kSwifterKitVideoBoxPropertyHasVideo;
        static constexpr uint32_t kBoxPropertyIsAcquirable =
            kSwifterKitVideoBoxPropertyIsAcquirable;
        static constexpr uint32_t kBoxPropertyIsAcquired = kSwifterKitVideoBoxPropertyIsAcquired;
        static constexpr uint32_t kBoxPropertyIsProtected = kSwifterKitVideoBoxPropertyIsProtected;
        static constexpr uint32_t kBoxPropertyAcquisitionFailure =
            kSwifterKitVideoBoxPropertyAcquisitionFailure;
        static constexpr uint32_t kClockDeviceCount = kSwifterKitVideoClockDeviceCount;
        static constexpr const auto* kClockDeviceConfigurations = kSwifterKitVideoClockDevices;
        static constexpr uint32_t kBoxCount = kSwifterKitVideoBoxCount;
        static constexpr const auto* kBoxConfigurations = kSwifterKitVideoBoxes;

        static constexpr auto kLock = &SwifterKitRuntimeService_IVars::videoLock;
        static constexpr auto kDevice = &SwifterKitRuntimeService_IVars::videoDevice;
        static constexpr auto kBoxes = &SwifterKitRuntimeService_IVars::videoBoxes;
        static constexpr auto kClockDevices = &SwifterKitRuntimeService_IVars::videoClockDevices;
        static constexpr auto kDeviceOwner = &SwifterKitRuntimeService_IVars::videoDeviceOwner;
        static constexpr auto kClockOwners = &SwifterKitRuntimeService_IVars::videoClockOwners;
    };

    bool IsBool(uint64_t value) {
        return value <= 1;
    }

    bool IsValidRate(double rate) {
        return rate > 0.0 && rate <= __DBL_MAX__;
    }

    kern_return_t ObjectInfo(
        SwifterKitRuntimeService* service,
        const SwifterKitRuntimeService_IVars* state,
        const SwifterKitVideoObjectTarget& target,
        OSData** response) {
        IOUserVideoObject* object = nullptr;
        OSSharedPtr<IOUserVideoObject> holder;
        if (target.kind == kSwifterKitVideoTargetDriver) {
            if (target.index != 0)
                return kIOReturnBadArgument;
        } else {
            object = ResolveObject(service, state, target, holder);
            if (object == nullptr)
                return kIOReturnNotFound;
        }
        return SwifterKitObjectInfoResponse<VideoObjectFamily>(
            service,
            object,
            SwifterKitVideoObjectInfoHeader {},
            response);
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
        const auto resolve = [&] { return ResolveObject(service, state, target, holder); };
        if (Is(opcode, Opcode::VideoSetObjectName) || Is(opcode, Opcode::VideoPropertiesChanged))
            return SwifterKitChangeObject<VideoObjectFamily>(
                service,
                Is(opcode, Opcode::VideoSetObjectName),
                target.kind == kSwifterKitVideoTargetDriver && target.index == 0,
                payload,
                payloadLength,
                resolve);
        return SwifterKitElementNameCommand<VideoObjectFamily>(
            Is(opcode, Opcode::VideoSetElementName),
            payload,
            payloadLength,
            response,
            resolve);
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
        if (Is(opcode, Opcode::VideoGetBoxState))
            return payloadLength == sizeof(target) && target.kind == kSwifterKitVideoTargetBox
                       ? SwifterKitBoxStateResponse<VideoObjectFamily>(box, response)
                       : kIOReturnBadArgument;
        if (Is(opcode, Opcode::VideoSetBoxOwnership))
            return target.kind == kSwifterKitVideoTargetBox
                       ? SwifterKitSetBoxOwnership<VideoObjectFamily>(
                             state,
                             box,
                             target.index,
                             payload,
                             payloadLength)
                       : kIOReturnBadArgument;
        if (Is(opcode, Opcode::VideoGetClockDeviceState))
            return payloadLength == sizeof(target)
                       ? SwifterKitClockStateResponse<VideoObjectFamily>(
                             ResolveClock(state, target),
                             response,
                             [](IOUserVideoClockDevice*, SwifterKitVideoClockState&) {})
                       : kIOReturnBadArgument;
        const bool boxOpcode = Is(opcode, Opcode::VideoSetBoxProperty);
        if (target.kind != (boxOpcode ? kSwifterKitVideoTargetBox : kSwifterKitVideoTargetClock))
            return kIOReturnBadArgument;
        if (Is(opcode, Opcode::VideoSetClockSampleRates))
            return SwifterKitSetClockSampleRates<VideoObjectFamily>(
                clockDevice,
                payload,
                payloadLength,
                IsValidRate);
        if (Is(opcode, Opcode::VideoUpdateClockTimestamp))
            return SwifterKitUpdateClockTimestamp<VideoObjectFamily>(
                clockDevice,
                payload,
                payloadLength);
        SwifterKitVideoIndexedValue request = {};
        if (!SwifterKitReadExactPayload(payload, payloadLength, &request) || request.reserved != 0)
            return kIOReturnBadArgument;
        if (Is(opcode, Opcode::VideoRequestClockSampleRate)) {
            const auto rate = __builtin_bit_cast(double, request.value);
            if (request.selector != 0 || !IsValidRate(rate))
                return kIOReturnBadArgument;
            return clockDevice == nullptr ? kIOReturnNotFound
                                          : clockDevice->RequestSampleRate(rate);
        }
        if (boxOpcode)
            return SwifterKitSetBoxProperty<VideoObjectFamily>(
                box,
                request.selector,
                request.value);
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
    kern_return_t result = SwifterKitStartClockDevices<VideoObjectFamily>(
        this,
        ivars,
        [this](
            SwifterKitRuntimeVideoClockDevice* clock,
            uint32_t index,
            const SwifterKitVideoClockConfiguration&,
            OSString* deviceUID,
            OSString* modelUID,
            OSString* manufacturerUID) {
            return clock->init(this, this, index, deviceUID, modelUID, manufacturerUID);
        });
    if (result == kIOReturnSuccess)
        result = SwifterKitStartBoxes<VideoObjectFamily>(this, ivars);
    return result;
}

void SwifterKitRuntimeService::StopVideoObjects() {
    if (ivars == nullptr || ivars->videoLock == nullptr)
        return;
    StopVideoRequests();
    SwifterKitStopBoxesAndClockDevices<VideoObjectFamily>(this, ivars);
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
        SwifterKitVideoRequestAnswer answer = {};
        const kern_return_t result = SwifterKitReadRequestAnswer(payload, payloadLength, &answer);
        return result == kIOReturnSuccess
                   ? CompleteVideoRequest(answer.requestID, answer.accepted == 1, answer.failure)
                   : result;
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
