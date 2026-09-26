#include "SwifterKitRuntimeAudioBox.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeService.h"

struct SwifterKitRuntimeAudioBox_IVars {
    SwifterKitRuntimeService* service = nullptr;
    uint32_t index = 0;
};

bool SwifterKitRuntimeAudioBox::init(
    IOUserAudioDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t index,
    bool isAcquirable,
    OSString* uid) {
    if (driver == nullptr || service == nullptr || index >= kSwifterKitAudioObjectTableCount
        || !super::init(driver, isAcquirable, uid))
        return false;
    ivars = IONewZero(SwifterKitRuntimeAudioBox_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->service = service;
    ivars->index = index;
    service->retain();
    return true;
}

void SwifterKitRuntimeAudioBox::free() {
    if (ivars != nullptr)
        OSSafeReleaseNULL(ivars->service);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeAudioBox_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioBox::Configure(
    const SwifterKitAudioBoxConfiguration* configuration) {
    if (ivars == nullptr || configuration == nullptr)
        return kIOReturnBadArgument;
    OSString* name = OSString::withCString(configuration->name);
    kern_return_t result = name == nullptr ? kIOReturnNoMemory : SetName(name);
    OSSafeReleaseNULL(name);
    if (result == kIOReturnSuccess)
        result = SetTransportType(static_cast<IOUserAudioTransportType>(configuration->transport));
    if (result == kIOReturnSuccess)
        result = SetHasAudio(configuration->hasAudio);
    if (result == kIOReturnSuccess)
        result = SetHasMIDI(configuration->hasMIDI);
    if (result == kIOReturnSuccess)
        result = SetHasVideo(configuration->hasVideo);
    if (result == kIOReturnSuccess)
        result = SetIsProtected(configuration->isProtected);
    if (result == kIOReturnSuccess)
        result = SetIsAcquired(configuration->isAcquired);
    return result;
}

kern_return_t SwifterKitRuntimeAudioBox::HandleChangeAcquireBox(bool acquire) {
    if (ivars == nullptr || !IsAcquirable())
        return kIOReturnNotPermitted;
    // IOUserAudioBox.iig: a callback that reports success must already have updated the value.
    // The box takes the requested state before the request is queued, so a fast answer from
    // Swift cannot be overwritten; a rejection from audioCompleteRequest restores the previous
    // state. Without a host the framework default applies.
    const bool previous = IsAcquired();
    kern_return_t result = SetIsAcquired(acquire);
    if (result != kIOReturnSuccess)
        return result;
    result = ivars->service
                 ->BeginAudioRequest(this, kSwifterKitAudioEventBoxRequest, ivars->index, acquire);
    if (result == kIOReturnNotAttached)
        return super::HandleChangeAcquireBox(acquire);
    if (result != kIOReturnSuccess)
        (void)SetIsAcquired(previous);
    return result;
}
#endif
