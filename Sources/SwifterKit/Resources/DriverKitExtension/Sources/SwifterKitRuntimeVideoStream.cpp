#include "SwifterKitRuntimeVideoStream.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>

    #include "SwifterKitRuntimeService.h"

struct SwifterKitRuntimeVideoStream_IVars {
    SwifterKitRuntimeService* service;
    uint32_t streamIndex;
};

bool SwifterKitRuntimeVideoStream::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t streamIndex,
    OSString* identifier,
    IOUserVideoStreamDirection direction,
    OSArray* buffers) {
    if (service == nullptr || streamIndex >= kSwifterKitVideoStreamCount
        || !super::init(driver, identifier, direction, buffers))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoStream_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->service = service;
    ivars->streamIndex = streamIndex;
    service->retain();
    return true;
}

void SwifterKitRuntimeVideoStream::free() {
    if (ivars != nullptr)
        OSSafeReleaseNULL(ivars->service);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoStream_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoStream::StartIO(IOUserVideoStartStopFlags flags) {
    const kern_return_t result = super::StartIO(flags);
    if (result == kIOReturnSuccess)
        (void)ivars->service
            ->VideoStreamEvent(6, ivars->streamIndex, static_cast<uint64_t>(flags), false);
    return result;
}

kern_return_t SwifterKitRuntimeVideoStream::StopIO(IOUserVideoStartStopFlags flags) {
    (void)ivars->service
        ->VideoStreamEvent(7, ivars->streamIndex, static_cast<uint64_t>(flags), false);
    return super::StopIO(flags);
}

void SwifterKitRuntimeVideoStream::InputNotification() {
    (void)ivars->service->VideoStreamEvent(10, ivars->streamIndex, 0, false);
    super::InputNotification();
}

kern_return_t SwifterKitRuntimeVideoStream::HandleChangeCurrentStreamFormat(
    const IOUserVideoStreamBasicDescription* format) {
    if (format == nullptr || format->mReserved1 != 0 || format->mReserved2 != 0)
        return kIOReturnBadArgument;
    const auto& stream = kSwifterKitVideoStreams[ivars->streamIndex];
    bool supported = false;
    for (uint32_t index = 0; index < stream.formatCount; ++index) {
        const auto& candidate = kSwifterKitVideoFormats[stream.formatStart + index];
        supported =
            supported
            || (format->mFrameRate == candidate.frameRate
                && format->mFrameTimeValue == candidate.frameTimeValue
                && format->mFrameTimeScale == candidate.frameTimeScale
                && static_cast<uint32_t>(format->mVideoCodecType) == candidate.codec
                && format->mVideoCodecFlags == candidate.codecFlags
                && format->mWidth == candidate.width && format->mHeight == candidate.height);
    }
    if (!supported)
        return kIOReturnBadArgument;
    const kern_return_t event = ivars->service->VideoStreamFormatEvent(ivars->streamIndex, format);
    return event == kIOReturnSuccess ? super::HandleChangeCurrentStreamFormat(format) : event;
}

kern_return_t SwifterKitRuntimeVideoStream::HandleChangeStreamIsActive(bool isActive) {
    const kern_return_t event =
        ivars->service->VideoStreamEvent(9, ivars->streamIndex, isActive ? 1 : 0, true);
    return event == kIOReturnSuccess ? super::HandleChangeStreamIsActive(isActive) : event;
}
#endif
