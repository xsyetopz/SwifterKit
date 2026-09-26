#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeVideoDevice.h"

kern_return_t SwifterKitRuntimeService::StartVideo() {
    if (ivars == nullptr || ivars->videoLock == nullptr)
        return kIOReturnNotReady;
    IOLockLock(ivars->videoLock);
    const bool started = ivars->videoDevice != nullptr;
    IOLockUnlock(ivars->videoLock);
    if (started)
        return kIOReturnNotReady;
    OSString* deviceUID = OSString::withCString(kSwifterKitVideoDeviceUID);
    OSString* modelUID = OSString::withCString(kSwifterKitVideoModelUID);
    OSString* manufacturerUID = OSString::withCString(kSwifterKitVideoManufacturerUID);
    OSString* name = OSString::withCString(kSwifterKitVideoDeviceName);
    auto* device = OSTypeAlloc(SwifterKitRuntimeVideoDevice);
    kern_return_t result = deviceUID == nullptr || modelUID == nullptr || manufacturerUID == nullptr
                                   || name == nullptr || device == nullptr
                               ? kIOReturnNoMemory
                               : kIOReturnSuccess;
    if (result == kIOReturnSuccess)
        result = SetName(name);
    if (result == kIOReturnSuccess)
        result = SetTransportType(static_cast<IOUserVideoTransportType>(kSwifterKitVideoTransport));
    if (result == kIOReturnSuccess
        && !device->init(this, this, deviceUID, modelUID, manufacturerUID))
        result = kIOReturnNoMemory;
    if (result == kIOReturnSuccess)
        result = device->Configure();
    if (result == kIOReturnSuccess)
        result = AddObject(device);
    // VideoCommand reads videoDevice under videoLock, so it is published under the lock.
    if (result == kIOReturnSuccess) {
        IOLockLock(ivars->videoLock);
        ivars->videoDevice = device;
        IOLockUnlock(ivars->videoLock);
    } else
        OSSafeReleaseNULL(device);
    OSSafeReleaseNULL(name);
    OSSafeReleaseNULL(deviceUID);
    OSSafeReleaseNULL(modelUID);
    OSSafeReleaseNULL(manufacturerUID);
    if (result == kIOReturnSuccess)
        result = StartVideoObjects();
    return result;
}

void SwifterKitRuntimeService::StopVideo() {
    if (ivars == nullptr || ivars->videoLock == nullptr)
        return;
    // Boxes release the device before it leaves the driver.
    StopVideoObjects();
    IOLockLock(ivars->videoLock);
    SwifterKitRuntimeVideoDevice* device = ivars->videoDevice;
    ivars->videoDevice = nullptr;
    // Controls and custom properties leave their owners before the device leaves the driver.
    if (device != nullptr) {
        device->RemoveControlsAndProperties();
        (void)RemoveObject(device);
    }
    IOLockUnlock(ivars->videoLock);
    OSSafeReleaseNULL(device);
}

kern_return_t SwifterKitRuntimeService::VideoControlEvent(uint32_t kind, uint64_t value) {
    const SwifterKitVideoEvent event = {kind, 0, value};
    return EnqueueEvent(kSwifterKitEventVideo, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::VideoControlValueEvent(
    uint32_t identifier,
    uint32_t kind,
    const uint32_t* values,
    uint32_t count) {
    if (identifier == 0 || kind < kSwifterKitVideoValueBoolean
        || kind > kSwifterKitVideoValueDirection || values == nullptr || count == 0
        || count > kSwifterKitVideoMaximumSelectorItems
        || (kind != kSwifterKitVideoValueSelector && count != 1))
        return kIOReturnBadArgument;
    uint8_t payload
        [sizeof(SwifterKitVideoControlEventHeader)
         + kSwifterKitVideoMaximumSelectorItems * sizeof(uint32_t)] = {};
    const SwifterKitVideoControlEventHeader header =
        {kSwifterKitVideoEventControlChanged, identifier, kind, count, 0};
    memcpy(payload, &header, sizeof(header));
    memcpy(payload + sizeof(header), values, count * sizeof(uint32_t));
    return EnqueueRequiredEvent(
        kSwifterKitEventVideo,
        payload,
        sizeof(header) + count * sizeof(uint32_t));
}

kern_return_t SwifterKitRuntimeService::VideoCustomPropertyEvent(
    uint32_t identifier,
    const uint8_t* qualifier,
    uint32_t qualifierLength,
    const uint8_t* value,
    uint32_t valueLength) {
    if (identifier == 0 || qualifier == nullptr || qualifierLength == 0
        || qualifierLength > kSwifterKitVideoNameMaximumLength || value == nullptr
        || valueLength > kSwifterKitVideoCustomPropertyValueMaximumLength)
        return kIOReturnBadArgument;
    uint8_t payload
        [sizeof(SwifterKitVideoCustomPropertyEventHeader) + kSwifterKitVideoNameMaximumLength
         + kSwifterKitVideoCustomPropertyValueMaximumLength] = {};
    const SwifterKitVideoCustomPropertyEventHeader header =
        {kSwifterKitVideoEventCustomPropertyChanged, identifier, qualifierLength, valueLength, 0};
    memcpy(payload, &header, sizeof(header));
    memcpy(payload + sizeof(header), qualifier, qualifierLength);
    memcpy(payload + sizeof(header) + qualifierLength, value, valueLength);
    return EnqueueRequiredEvent(
        kSwifterKitEventVideo,
        payload,
        sizeof(header) + qualifierLength + valueLength);
}

kern_return_t SwifterKitRuntimeService::VideoStreamEvent(
    uint32_t kind,
    uint32_t streamIndex,
    uint64_t value,
    bool required) {
    if ((kind != kSwifterKitVideoEventStreamStarted && kind != kSwifterKitVideoEventStreamStopped
         && kind != kSwifterKitVideoEventStreamActiveChanged
         && kind != kSwifterKitVideoEventStreamInputAvailable)
        || streamIndex >= kSwifterKitVideoStreamCount
        || (kind == kSwifterKitVideoEventStreamActiveChanged && value > 1)
        || (kind == kSwifterKitVideoEventStreamInputAvailable && value != 0))
        return kIOReturnBadArgument;
    const SwifterKitVideoEvent event = {kind, streamIndex, value};
    return required ? EnqueueRequiredEvent(kSwifterKitEventVideo, &event, sizeof(event))
                    : EnqueueEvent(kSwifterKitEventVideo, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::VideoStreamFormatEvent(
    uint32_t streamIndex,
    const IOUserVideoStreamBasicDescription* format) {
    if (streamIndex >= kSwifterKitVideoStreamCount || format == nullptr || format->mReserved1 != 0
        || format->mReserved2 != 0)
        return kIOReturnBadArgument;
    const SwifterKitVideoStreamFormatEvent event = {
        kSwifterKitVideoEventStreamFormatChanged,
        streamIndex,
        format->mFrameRate,
        format->mFrameTimeValue,
        format->mFrameTimeScale,
        static_cast<uint32_t>(format->mVideoCodecType),
        format->mVideoCodecFlags,
        format->mWidth,
        format->mHeight,
        0,
        0};
    return EnqueueRequiredEvent(kSwifterKitEventVideo, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::VideoCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->videoLock == nullptr || response == nullptr)
        return kIOReturnBadArgument;
    *response = nullptr;
    if (opcode >= static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoGetObjectInfo)
        && opcode <= static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoSetCustomPropertyOwner))
        return VideoObjectCommand(opcode, payload, payloadLength, response);
    IOLockLock(ivars->videoLock);
    SwifterKitRuntimeVideoDevice* device = ivars->videoDevice;
    kern_return_t result = device == nullptr ? kIOReturnNotReady : kIOReturnUnsupported;
    if (device != nullptr
        && opcode >= static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoGetDeviceState)
        && opcode <= static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoGetStreamMemoryObjectID)) {
        result = device->MemberCommand(opcode, payload, payloadLength, response);
    } else if (
        device != nullptr
        && (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoReadBuffer)
            || opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoWriteBuffer))) {
        if (payload == nullptr || payloadLength < sizeof(SwifterKitVideoTransferHeader))
            result = kIOReturnBadArgument;
        else {
            const auto* transfer = reinterpret_cast<const SwifterKitVideoTransferHeader*>(payload);
            const uint32_t expectedLength =
                opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoWriteBuffer)
                    ? sizeof(*transfer) + transfer->length
                    : sizeof(*transfer);
            if (transfer->reserved0 != 0 || transfer->reserved1 != 0 || transfer->reserved2 != 0
                || payloadLength != expectedLength)
                result = kIOReturnBadArgument;
            else if (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoReadBuffer))
                result = device->ReadBuffer(transfer, response);
            else
                result = device->WriteBuffer(transfer, payload + sizeof(*transfer));
        }
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoEnqueueOutput)) {
        result = payload != nullptr
                         && payloadLength == sizeof(uint32_t) + sizeof(SwifterKitVideoQueueEntry)
                     ? device->EnqueueOutput(
                           *reinterpret_cast<const uint32_t*>(payload),
                           reinterpret_cast<const SwifterKitVideoQueueEntry*>(
                               payload + sizeof(uint32_t)))
                     : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoDequeueInput)) {
        result = payload != nullptr && payloadLength == sizeof(uint32_t)
                     ? device->DequeueInput(*reinterpret_cast<const uint32_t*>(payload), response)
                     : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoNotifyOutput)) {
        result = payload != nullptr && payloadLength == sizeof(uint32_t)
                     ? device->NotifyOutput(*reinterpret_cast<const uint32_t*>(payload))
                     : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoUpdateTimestamp)) {
        result = payload != nullptr && payloadLength == sizeof(SwifterKitVideoTimestamp)
                     ? device->UpdateTimestamp(
                           reinterpret_cast<const SwifterKitVideoTimestamp*>(payload))
                     : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoRequestSampleRate)) {
        if (payload == nullptr || payloadLength != sizeof(uint64_t))
            result = kIOReturnBadArgument;
        else {
            uint64_t bits = 0;
            memcpy(&bits, payload, sizeof(bits));
            result = device->RequestSampleRate(__builtin_bit_cast(double, bits));
        }
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoGetControl)) {
        result = payload != nullptr && payloadLength == sizeof(SwifterKitVideoControlGet)
                     ? device->CopyControl(
                           reinterpret_cast<const SwifterKitVideoControlGet*>(payload),
                           response)
                     : kIOReturnBadArgument;
    } else if (
        device != nullptr
        && opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoSetControl)) {
        if (payload == nullptr || payloadLength < sizeof(SwifterKitVideoControlValueHeader))
            result = kIOReturnBadArgument;
        else {
            const auto* request =
                reinterpret_cast<const SwifterKitVideoControlValueHeader*>(payload);
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
        && (opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoGetCustomProperty)
            || opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoSetCustomProperty))) {
        if (payload == nullptr || payloadLength < sizeof(SwifterKitVideoCustomPropertyHeader))
            result = kIOReturnBadArgument;
        else {
            const auto* request =
                reinterpret_cast<const SwifterKitVideoCustomPropertyHeader*>(payload);
            const uint64_t expected = sizeof(*request)
                                      + static_cast<uint64_t>(request->qualifierLength)
                                      + request->valueLength;
            if (expected != payloadLength)
                result = kIOReturnBadArgument;
            else if (
                opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::VideoGetCustomProperty))
                result = device->CopyCustomProperty(request, payload + sizeof(*request), response);
            else
                result = device->SetCustomProperty(request, payload + sizeof(*request));
        }
    }
    IOLockUnlock(ivars->videoLock);
    return result;
}
#endif
