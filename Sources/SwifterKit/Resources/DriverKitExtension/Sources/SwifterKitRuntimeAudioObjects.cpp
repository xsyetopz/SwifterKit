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
    #include "SwifterKitRuntimeAudioDeviceState.h"
    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeMediaObjects.h"
    #include "SwifterKitRuntimeSchema.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    using Opcode = SwifterKitRuntimeOpcode;

    bool Is(uint32_t opcode, Opcode expected) {
        return opcode == static_cast<uint32_t>(expected);
    }

    // Resolves a device, box, clock-device, or object-ID target. The driver is not an object.
    IOUserAudioObject* ResolveObject(
        SwifterKitRuntimeService* service,
        const SwifterKitRuntimeService_IVars* state,
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
        const SwifterKitRuntimeService_IVars* state,
        const SwifterKitAudioObjectTarget& target) {
        if (target.kind == kSwifterKitAudioTargetDevice)
            return state->audioDevice;
        if (target.kind == kSwifterKitAudioTargetClock
            && target.index < kSwifterKitAudioObjectTableCount)
            return state->audioClockDevices[target.index];
        return nullptr;
    }

    // The AudioDriverKit classes, schema values, and service ivars the
    // SwifterKitRuntimeMediaObjects.h object templates operate on.
    struct AudioObjectFamily {
        using Driver = IOUserAudioDriver;
        using Object = IOUserAudioObject;
        using Box = IOUserAudioBox;
        using ClockDevice = IOUserAudioClockDevice;
        using RuntimeBox = SwifterKitRuntimeAudioBox;
        using RuntimeClockDevice = SwifterKitRuntimeAudioClockDevice;
        using TransportType = IOUserAudioTransportType;
        using Scope = IOUserAudioObjectPropertyScope;
        using Element = IOUserAudioObjectPropertyElement;
        using PropertySelector = IOUserAudioObjectPropertySelector;
        using ListHeader = SwifterKitAudioListHeader;
        using ElementNameHeader = SwifterKitAudioElementNameHeader;
        using BoxOwnership = SwifterKitAudioBoxOwnership;
        using BoxState = SwifterKitAudioBoxState;
        using ClockState = SwifterKitAudioClockState;
        using ClockTimestamp = SwifterKitAudioClockTimestamp;

        static constexpr uint32_t kNameMaximumLength = kSwifterKitAudioNameMaximumLength;
        static constexpr uint32_t kMaximumChangedProperties =
            kSwifterKitAudioMaximumChangedProperties;
        static constexpr uint32_t kMaximumSampleRates = kSwifterKitAudioMaximumSampleRates;
        static constexpr uint32_t kMaximumSettableSampleRates =
            kSwifterKitAudioMaximumSettableSampleRates;
        static constexpr uint32_t kObjectTableCount = kSwifterKitAudioObjectTableCount;
        static constexpr uint32_t kTargetDevice = kSwifterKitAudioTargetDevice;
        static constexpr uint32_t kTargetClock = kSwifterKitAudioTargetClock;
        static constexpr uint32_t kElementName = kSwifterKitAudioElementName;
        static constexpr uint32_t kElementCategory = kSwifterKitAudioElementCategory;
        static constexpr uint32_t kElementNumber = kSwifterKitAudioElementNumber;
        static constexpr uint32_t kClockStateClockIsStable =
            kSwifterKitAudioClockStateClockIsStable;
        static constexpr uint32_t kClockStateIsAlive = kSwifterKitAudioClockStateIsAlive;
        static constexpr uint32_t kClockStateIsRunning = kSwifterKitAudioClockStateIsRunning;
        static constexpr uint32_t kClockStateIsHidden = kSwifterKitAudioClockStateIsHidden;
        static constexpr uint32_t kBoxStateHasAudio = kSwifterKitAudioBoxStateHasAudio;
        static constexpr uint32_t kBoxStateHasMIDI = kSwifterKitAudioBoxStateHasMIDI;
        static constexpr uint32_t kBoxStateHasVideo = kSwifterKitAudioBoxStateHasVideo;
        static constexpr uint32_t kBoxStateIsAcquirable = kSwifterKitAudioBoxStateIsAcquirable;
        static constexpr uint32_t kBoxStateIsAcquired = kSwifterKitAudioBoxStateIsAcquired;
        static constexpr uint32_t kBoxStateIsProtected = kSwifterKitAudioBoxStateIsProtected;
        static constexpr uint32_t kBoxPropertyTransport = kSwifterKitAudioBoxPropertyTransport;
        static constexpr uint32_t kBoxPropertyHasAudio = kSwifterKitAudioBoxPropertyHasAudio;
        static constexpr uint32_t kBoxPropertyHasMIDI = kSwifterKitAudioBoxPropertyHasMIDI;
        static constexpr uint32_t kBoxPropertyHasVideo = kSwifterKitAudioBoxPropertyHasVideo;
        static constexpr uint32_t kBoxPropertyIsAcquirable =
            kSwifterKitAudioBoxPropertyIsAcquirable;
        static constexpr uint32_t kBoxPropertyIsAcquired = kSwifterKitAudioBoxPropertyIsAcquired;
        static constexpr uint32_t kBoxPropertyIsProtected = kSwifterKitAudioBoxPropertyIsProtected;
        static constexpr uint32_t kBoxPropertyAcquisitionFailure =
            kSwifterKitAudioBoxPropertyAcquisitionFailure;
        static constexpr uint32_t kClockDeviceCount = kSwifterKitAudioClockDeviceCount;
        static constexpr const auto* kClockDeviceConfigurations = kSwifterKitAudioClockDevices;
        static constexpr uint32_t kBoxCount = kSwifterKitAudioBoxCount;
        static constexpr const auto* kBoxConfigurations = kSwifterKitAudioBoxes;

        static constexpr auto kLock = &SwifterKitRuntimeService_IVars::audioLock;
        static constexpr auto kDevice = &SwifterKitRuntimeService_IVars::audioDevice;
        static constexpr auto kBoxes = &SwifterKitRuntimeService_IVars::audioBoxes;
        static constexpr auto kClockDevices = &SwifterKitRuntimeService_IVars::audioClockDevices;
        static constexpr auto kDeviceOwner = &SwifterKitRuntimeService_IVars::audioDeviceOwner;
        static constexpr auto kClockOwners = &SwifterKitRuntimeService_IVars::audioClockOwners;
    };

    bool IsBool(uint64_t value) {
        return value <= 1;
    }

    kern_return_t TopologyCommand(
        SwifterKitRuntimeService_IVars* state,
        uint32_t opcode,
        const SwifterKitAudioObjectTarget& target,
        const uint8_t* payload,
        uint32_t payloadLength,
        OSData** response);
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
        const auto resolve = [&] { return ResolveObject(service, state, target, holder); };
        if (Is(opcode, Opcode::AudioGetObjectInfo)) {
            if (payloadLength != sizeof(target))
                return kIOReturnBadArgument;
            IOUserAudioObject* object = isDriver ? nullptr : resolve();
            if (!isDriver && object == nullptr)
                return kIOReturnNotFound;
            SwifterKitAudioObjectInfoHeader header = {};
            if (object != nullptr)
                header.ownerObjectID = object->GetOwnerObjectID();
            return SwifterKitObjectInfoResponse<AudioObjectFamily>(
                service,
                object,
                header,
                response);
        }
        if (Is(opcode, Opcode::AudioSetObjectName) || Is(opcode, Opcode::AudioPropertiesChanged))
            return SwifterKitChangeObject<AudioObjectFamily>(
                service,
                Is(opcode, Opcode::AudioSetObjectName),
                isDriver,
                payload,
                payloadLength,
                resolve);
        if (Is(opcode, Opcode::AudioGetElementName) || Is(opcode, Opcode::AudioSetElementName))
            return SwifterKitElementNameCommand<AudioObjectFamily>(
                Is(opcode, Opcode::AudioSetElementName),
                payload,
                payloadLength,
                response,
                resolve);
        return TopologyCommand(state, opcode, target, payload, payloadLength, response);
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
        if (Is(opcode, Opcode::AudioGetBoxState))
            return payloadLength == sizeof(target)
                       ? SwifterKitBoxStateResponse<AudioObjectFamily>(box, response)
                       : kIOReturnBadArgument;
        if (Is(opcode, Opcode::AudioSetBoxOwnership))
            return SwifterKitSetBoxOwnership<AudioObjectFamily>(
                state,
                box,
                target.index,
                payload,
                payloadLength);
        if (Is(opcode, Opcode::AudioGetClockDeviceState)) {
            if (payloadLength != sizeof(target))
                return kIOReturnBadArgument;
            return SwifterKitClockStateResponse<AudioObjectFamily>(
                ResolveClock(state, target),
                response,
                [](IOUserAudioClockDevice* clock, SwifterKitAudioClockState& clockState) {
                    if (clock->GetSupportsPrewarming())
                        clockState.flags |= kSwifterKitAudioClockStateSupportsPrewarming;
                    clockState.zeroTimestampPeriod = clock->GetZeroTimestampPeriod();
                });
        }
        if (target.kind != kSwifterKitAudioTargetClock && !Is(opcode, Opcode::AudioSetBoxProperty))
            return kIOReturnBadArgument;
        if (Is(opcode, Opcode::AudioSetClockSampleRates))
            return SwifterKitSetClockSampleRates<AudioObjectFamily>(
                clockDevice,
                payload,
                payloadLength,
                [](double rate) {
                    return rate >= kSwifterKitAudioMinimumSampleRate
                           && rate <= kSwifterKitAudioMaximumSampleRate;
                });
        if (Is(opcode, Opcode::AudioUpdateClockTimestamp))
            return SwifterKitUpdateClockTimestamp<AudioObjectFamily>(
                clockDevice,
                payload,
                payloadLength);
        SwifterKitAudioIndexedValue request = {};
        if (!SwifterKitReadExactPayload(payload, payloadLength, &request) || request.reserved != 0)
            return kIOReturnBadArgument;
        if (Is(opcode, Opcode::AudioRequestClockSampleRate)) {
            if (request.selector != 0)
                return kIOReturnBadArgument;
            return clockDevice == nullptr
                       ? kIOReturnNotFound
                       : clockDevice->RequestSampleRate(__builtin_bit_cast(double, request.value));
        }
        if (Is(opcode, Opcode::AudioSetBoxProperty))
            return SwifterKitSetBoxProperty<AudioObjectFamily>(
                box,
                request.selector,
                request.value);
        if (Is(opcode, Opcode::AudioSetClockDeviceProperty))
            return SetClockProperty(clockDevice, request.selector, request.value);
        return kIOReturnUnsupported;
    }

    kern_return_t SetClockProperty(
        SwifterKitRuntimeAudioClockDevice* clock,
        uint32_t selector,
        uint64_t value) {
        const bool boolean = selector == kSwifterKitAudioClockPropertyClockIsStable
                             || selector == kSwifterKitAudioClockPropertyIsAlive
                             || selector == kSwifterKitAudioClockPropertyIsHidden
                             || selector == kSwifterKitAudioClockPropertyWantsControlsRestored;
        if (selector < kSwifterKitAudioClockPropertyClockDomain
            || selector > kSwifterKitAudioClockPropertyWantsControlsRestored || value > UINT32_MAX
            || (boolean && !IsBool(value))
            || (selector == kSwifterKitAudioClockPropertyZeroTimestampPeriod
                && (value < kSwifterKitAudioMinimumZeroTimestampPeriod
                    || value > kSwifterKitAudioMaximumFrameCount)))
            return kIOReturnBadArgument;
        if (clock == nullptr)
            return kIOReturnNotFound;
        const auto number = static_cast<uint32_t>(value);
        switch (selector) {
            case kSwifterKitAudioClockPropertyClockDomain:
                return clock->SetClockDomain(number);
            case kSwifterKitAudioClockPropertyClockAlgorithm:
                return clock->SetClockAlgorithm(static_cast<IOUserAudioClockAlgorithm>(number));
            case kSwifterKitAudioClockPropertyClockIsStable:
                return clock->SetClockIsStable(number == 1);
            case kSwifterKitAudioClockPropertyIsAlive:
                return clock->SetDeviceIsAlive(number == 1);
            case kSwifterKitAudioClockPropertyIsHidden:
                return clock->SetIsHidden(number == 1);
            case kSwifterKitAudioClockPropertyInputLatency:
            case kSwifterKitAudioClockPropertyOutputLatency:
            case kSwifterKitAudioClockPropertyZeroTimestampPeriod:
                return SwifterKitRequestAudioMemberChange(clock, selector, 0, number);
            case kSwifterKitAudioClockPropertyTransport:
                return clock->SetTransportType(static_cast<IOUserAudioTransportType>(number));
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
    // Without the timeout timer, box and clock requests take the framework default at once.
    (void)StartAudioRequests();
    kern_return_t result = SwifterKitStartClockDevices<AudioObjectFamily>(
        this,
        ivars,
        [this](
            SwifterKitRuntimeAudioClockDevice* clock,
            uint32_t index,
            const SwifterKitAudioClockConfiguration& config,
            OSString* deviceUID,
            OSString* modelUID,
            OSString* manufacturerUID) {
            return clock->init(
                this,
                this,
                index,
                config.supportsPrewarming,
                deviceUID,
                modelUID,
                manufacturerUID,
                config.zeroTimestampPeriod);
        });
    if (result == kIOReturnSuccess)
        result = SwifterKitStartBoxes<AudioObjectFamily>(this, ivars);
    return result;
}

void SwifterKitRuntimeService::StopAudioObjects() {
    if (ivars == nullptr || ivars->audioLock == nullptr)
        return;
    StopAudioRequests();
    SwifterKitStopBoxesAndClockDevices<AudioObjectFamily>(this, ivars);
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
        SwifterKitAudioRequestAnswer answer = {};
        const kern_return_t result = SwifterKitReadRequestAnswer(payload, payloadLength, &answer);
        return result == kIOReturnSuccess
                   ? CompleteAudioRequest(answer.requestID, answer.accepted == 1, answer.failure)
                   : result;
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
