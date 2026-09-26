#include "SwifterKitRuntimeVideoBox.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeMediaObjects.h"
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
    return SwifterKitAttachObjectState(ivars, service, index);
}

void SwifterKitRuntimeVideoBox::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeVideoBox::Configure(
    const SwifterKitVideoBoxConfiguration* configuration) {
    if (ivars == nullptr || configuration == nullptr)
        return kIOReturnBadArgument;
    return SwifterKitConfigureBox<IOUserVideoTransportType>(this, configuration);
}

kern_return_t SwifterKitRuntimeVideoBox::HandleChangeAcquireBox(bool acquire) {
    if (ivars == nullptr || !IsAcquirable())
        return kIOReturnNotPermitted;
    // IOUserVideoBox.iig: a callback that reports success must already have updated the value. The
    // box takes the requested state before the request is queued, so a fast answer from Swift
    // cannot be overwritten; a rejection from videoCompleteRequest restores the previous state.
    // Without a host the framework default applies.
    const bool previous = IsAcquired();
    // Nothing changes, so there is nothing for Swift to accept or reject.
    if (previous == acquire)
        return kIOReturnSuccess;
    kern_return_t result = SetIsAcquired(acquire);
    if (result != kIOReturnSuccess)
        return result;
    result = ivars->service->BeginVideoRequest(
        this,
        kSwifterKitVideoObjectEventBoxRequest,
        ivars->index,
        acquire,
        0);
    if (result == kIOReturnNotAttached)
        return super::HandleChangeAcquireBox(acquire);
    if (result != kIOReturnSuccess)
        (void)SetIsAcquired(previous);
    return result;
}
#endif
