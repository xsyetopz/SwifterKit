#include "SwifterKitRuntimeAudioStream.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <DriverKit/IOLib.h>

    #include "SwifterKitRuntimeService.h"

struct SwifterKitRuntimeAudioStream_IVars {
    SwifterKitRuntimeService* service;
    uint32_t streamIndex;
};

bool SwifterKitRuntimeAudioStream::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t streamIndex,
    IOUserAudioStreamDirection direction,
    IOMemoryDescriptor* memoryDescriptor) {
    if (service == nullptr || streamIndex >= kSwifterKitAudioStreamCount
        || !super::init(driver, direction, memoryDescriptor))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioStream_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->service = service;
    ivars->streamIndex = streamIndex;
    service->retain();
    return true;
}

void SwifterKitRuntimeAudioStream::free() {
    if (ivars != nullptr)
        OSSafeReleaseNULL(ivars->service);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioStream_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioStream::HandleChangeCurrentStreamFormat(
    const IOUserAudioStreamBasicDescription* format) {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    // IOUserAudioStream.iig: the base implementation applies the format with
    // SetCurrentStreamFormat. Report first and call super only if Swift can see the change.
    const kern_return_t event = ivars->service->AudioStreamFormatEvent(ivars->streamIndex, format);
    return event == kIOReturnSuccess ? super::HandleChangeCurrentStreamFormat(format) : event;
}

kern_return_t SwifterKitRuntimeAudioStream::HandleChangeStreamIsActive(bool isActive) {
    if (ivars == nullptr)
        return kIOReturnNotReady;
    const kern_return_t event =
        ivars->service->AudioStreamActiveEvent(ivars->streamIndex, isActive);
    return event == kIOReturnSuccess ? super::HandleChangeStreamIsActive(isActive) : event;
}
#endif
