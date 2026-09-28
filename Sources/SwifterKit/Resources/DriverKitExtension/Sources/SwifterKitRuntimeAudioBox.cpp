#include "SwifterKitRuntimeAudioBox.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSString.h>

    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeMediaObjects.h"
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
    return SwifterKitAttachObjectState(ivars, service, index);
}

void SwifterKitRuntimeAudioBox::free() {
    SwifterKitDetachCallbackState(ivars);
    super::free();
}

kern_return_t SwifterKitRuntimeAudioBox::Configure(
    const SwifterKitAudioBoxConfiguration* configuration) {
    if (ivars == nullptr || configuration == nullptr)
        return kIOReturnBadArgument;
    return SwifterKitConfigureBox<IOUserAudioTransportType>(this, configuration);
}

kern_return_t SwifterKitRuntimeAudioBox::HandleChangeAcquireBox(bool acquire) {
    if (ivars == nullptr || !IsAcquirable())
        return kIOReturnNotPermitted;
    // IOUserAudioBox.iig: a callback that reports success must already have updated the value.
    // The box takes the requested state before it queues the request. A fast answer from Swift
    // cannot overwrite it. A rejection from audioCompleteRequest restores the previous state.
    // Without a host, the framework default applies.
    const bool previous = IsAcquired();
    // Nothing changes, so there is nothing for Swift to accept or reject.
    if (previous == acquire)
        return kIOReturnSuccess;
    kern_return_t result = SetIsAcquired(acquire);
    if (result != kIOReturnSuccess)
        return result;
    result = ivars->service->BeginAudioRequest(
        this,
        kSwifterKitAudioObjectEventBoxRequest,
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
