#include "SwifterKitRuntimeVideoBox.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeVideoProtocol.h"

struct SwifterKitRuntimeVideoBox_IVars {
    SwifterKitRuntimeService* service = nullptr;
    uint32_t index = 0;
};

bool SwifterKitRuntimeVideoBox::init(
    IOUserVideoDriver* driver,
    SwifterKitRuntimeService* service,
    uint32_t index,
    bool isAcquirable,
    OSString* uid) {
    if (driver == nullptr || service == nullptr || index >= kSwifterKitVideoObjectTableCount
        || !super::init(driver, isAcquirable, uid))
        return false;
    ivars = IONewZero(SwifterKitRuntimeVideoBox_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->service = service;
    ivars->index = index;
    service->retain();
    return true;
}

void SwifterKitRuntimeVideoBox::free() {
    if (ivars != nullptr)
        OSSafeReleaseNULL(ivars->service);
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeVideoBox_IVars, 1);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoBox::Configure(
    const SwifterKitVideoBoxConfiguration* configuration) {
    if (ivars == nullptr || configuration == nullptr)
        return kIOReturnBadArgument;
    OSString* name = OSString::withCString(configuration->name);
    kern_return_t result = name == nullptr ? kIOReturnNoMemory : SetName(name);
    OSSafeReleaseNULL(name);
    if (result == kIOReturnSuccess)
        result = SetTransportType(static_cast<IOUserVideoTransportType>(configuration->transport));
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

kern_return_t SwifterKitRuntimeVideoBox::HandleChangeAcquireBox(bool acquire) {
    if (ivars == nullptr || !IsAcquirable())
        return kIOReturnNotPermitted;
    // IOUserVideoBox follows IOUserAudioBox: a callback that reports success must already have
    // updated the value. The box takes the requested state before the request is queued, so a
    // fast answer from Swift cannot be overwritten; a rejection from videoCompleteRequest
    // restores the previous state. Without a host the framework default applies.
    const bool previous = IsAcquired();
    // Nothing changes, so there is nothing for Swift to accept or reject.
    if (previous == acquire)
        return kIOReturnSuccess;
    kern_return_t result = SetIsAcquired(acquire);
    if (result != kIOReturnSuccess)
        return result;
    result = ivars->service
                 ->BeginVideoRequest(this, kSwifterKitVideoEventBoxRequest, ivars->index, acquire);
    if (result == kIOReturnNotAttached)
        return super::HandleChangeAcquireBox(acquire);
    if (result != kIOReturnSuccess)
        (void)SetIsAcquired(previous);
    return result;
}
#endif
