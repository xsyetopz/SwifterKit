#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioDevice.h"
    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

kern_return_t SwifterKitRuntimeService::StartAudio() {
    if (ivars == nullptr || ivars->audioDevice != nullptr)
        return kIOReturnNotReady;
    OSString* deviceUID = OSString::withCString(kSwifterKitAudioDeviceUID);
    OSString* modelUID = OSString::withCString(kSwifterKitAudioModelUID);
    OSString* manufacturerUID = OSString::withCString(kSwifterKitAudioManufacturerUID);
    auto* device = OSTypeAlloc(SwifterKitRuntimeAudioDevice);
    kern_return_t result = deviceUID == nullptr || modelUID == nullptr || manufacturerUID == nullptr
                                   || device == nullptr
                               ? kIOReturnNoMemory
                               : kIOReturnSuccess;
    if (result == kIOReturnSuccess
        && !device->init(
            this,
            this,
            kSwifterKitAudioSupportsPrewarming,
            deviceUID,
            modelUID,
            manufacturerUID,
            kSwifterKitAudioZeroTimestampPeriod))
        result = kIOReturnNoMemory;
    if (result == kIOReturnSuccess)
        result = device->Configure();
    if (result == kIOReturnSuccess)
        result = AddObject(device);
    if (result == kIOReturnSuccess)
        ivars->audioDevice = device;
    else
        OSSafeReleaseNULL(device);
    OSSafeReleaseNULL(deviceUID);
    OSSafeReleaseNULL(modelUID);
    OSSafeReleaseNULL(manufacturerUID);
    return result;
}

void SwifterKitRuntimeService::StopAudio() {
    if (ivars == nullptr || ivars->audioLock == nullptr)
        return;
    IOLockLock(ivars->audioLock);
    SwifterKitRuntimeAudioDevice* device = ivars->audioDevice;
    ivars->audioDevice = nullptr;
    if (device != nullptr)
        (void)RemoveObject(device);
    IOLockUnlock(ivars->audioLock);
    OSSafeReleaseNULL(device);
}

kern_return_t SwifterKitRuntimeService::AudioControlEvent(uint32_t kind, uint64_t value) {
    const SwifterKitAudioEvent event = {kind, 0, value};
    return EnqueueEvent(0x0A00, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::AudioControlValueEvent(
    uint32_t identifier,
    uint32_t kind,
    const uint32_t* values,
    uint32_t count) {
    if (identifier == 0 || kind < 1 || kind > 6 || values == nullptr || count == 0 || count > 32
        || (kind != 4 && count != 1))
        return kIOReturnBadArgument;
    uint8_t payload[sizeof(SwifterKitAudioControlEventHeader) + 32 * sizeof(uint32_t)] = {};
    const SwifterKitAudioControlEventHeader header = {4, identifier, kind, count, 0};
    memcpy(payload, &header, sizeof(header));
    memcpy(payload + sizeof(header), values, count * sizeof(uint32_t));
    return EnqueueRequiredEvent(0x0A00, payload, sizeof(header) + count * sizeof(uint32_t));
}

kern_return_t SwifterKitRuntimeService::AudioCustomPropertyEvent(
    uint32_t identifier,
    const uint8_t* qualifier,
    uint32_t qualifierLength,
    const uint8_t* value,
    uint32_t valueLength) {
    if (identifier == 0 || qualifier == nullptr || qualifierLength == 0 || qualifierLength > 255
        || value == nullptr || valueLength > 4096)
        return kIOReturnBadArgument;
    uint8_t payload[sizeof(SwifterKitAudioCustomPropertyEventHeader) + 255 + 4096] = {};
    const SwifterKitAudioCustomPropertyEventHeader header =
        {5, identifier, qualifierLength, valueLength, 0};
    memcpy(payload, &header, sizeof(header));
    memcpy(payload + sizeof(header), qualifier, qualifierLength);
    memcpy(payload + sizeof(header) + qualifierLength, value, valueLength);
    return EnqueueRequiredEvent(0x0A00, payload, sizeof(header) + qualifierLength + valueLength);
}

kern_return_t SwifterKitRuntimeService::AudioCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->audioLock == nullptr || response == nullptr)
        return kIOReturnBadArgument;
    *response = nullptr;
    IOLockLock(ivars->audioLock);
    SwifterKitRuntimeAudioDevice* device = ivars->audioDevice;
    kern_return_t result = device == nullptr ? kIOReturnNotReady : kIOReturnUnsupported;
    if (device != nullptr
        && (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioReadStream)
            || opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioWriteStream))) {
        if (payload == nullptr || payloadLength < sizeof(SwifterKitAudioTransferHeader))
            result = kIOReturnBadArgument;
        else {
            const auto* transfer = reinterpret_cast<const SwifterKitAudioTransferHeader*>(payload);
            const uint32_t expectedLength =
                opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioWriteStream)
                    ? sizeof(*transfer) + transfer->length
                    : sizeof(*transfer);
            if (transfer->reserved0 != 0 || transfer->reserved1 != 0
                || payloadLength != expectedLength)
                result = kIOReturnBadArgument;
            else if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioReadStream))
                result = device->ReadStream(transfer, response);
            else
                result = device->WriteStream(transfer, payload + sizeof(*transfer));
        }
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetIOState)) {
        result = payloadLength == 0 ? device->CopyIOState(response) : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioUpdateTimestamp)) {
        result = payload != nullptr && payloadLength == sizeof(SwifterKitAudioTimestamp)
                     ? device->UpdateTimestamp(
                           reinterpret_cast<const SwifterKitAudioTimestamp*>(payload))
                     : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioRequestSampleRate)) {
        if (payload == nullptr || payloadLength != sizeof(uint64_t))
            result = kIOReturnBadArgument;
        else {
            uint64_t bits = 0;
            memcpy(&bits, payload, sizeof(bits));
            result = device->RequestSampleRate(__builtin_bit_cast(double, bits));
        }
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetControl)) {
        result = payload != nullptr && payloadLength == sizeof(SwifterKitAudioControlGet)
                     ? device->CopyControl(
                           reinterpret_cast<const SwifterKitAudioControlGet*>(payload),
                           response)
                     : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioSetControl)) {
        if (payload == nullptr || payloadLength < sizeof(SwifterKitAudioControlValueHeader))
            result = kIOReturnBadArgument;
        else {
            const auto* request =
                reinterpret_cast<const SwifterKitAudioControlValueHeader*>(payload);
            const uint64_t expected =
                sizeof(*request) + static_cast<uint64_t>(request->valueCount) * sizeof(uint32_t);
            result = expected == payloadLength
                         ? device->SetControl(
                               request,
                               reinterpret_cast<const uint32_t*>(payload + sizeof(*request)))
                         : kIOReturnBadArgument;
        }
    } else if (
        device != nullptr
        && (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetCustomProperty)
            || opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioSetCustomProperty))) {
        if (payload == nullptr || payloadLength < sizeof(SwifterKitAudioCustomPropertyHeader))
            result = kIOReturnBadArgument;
        else {
            const auto* request =
                reinterpret_cast<const SwifterKitAudioCustomPropertyHeader*>(payload);
            const uint64_t expected = sizeof(*request)
                                      + static_cast<uint64_t>(request->qualifierLength)
                                      + request->valueLength;
            if (expected != payloadLength)
                result = kIOReturnBadArgument;
            else if (
                opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::AudioGetCustomProperty))
                result = device->CopyCustomProperty(request, payload + sizeof(*request), response);
            else
                result = device->SetCustomProperty(request, payload + sizeof(*request));
        }
    }
    IOLockUnlock(ivars->audioLock);
    return result;
}
#endif
