#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IODispatchQueue.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOTimerDispatchSource.h>
    #include <DriverKit/OSAction.h>

    #include "SwifterKitRuntimeAudioBox.h"
    #include "SwifterKitRuntimeAudioClockDevice.h"
    #include "SwifterKitRuntimeAudioProtocol.h"
    #include "SwifterKitRuntimeMediaRequests.h"
    #include "SwifterKitRuntimeServiceState.h"

// Audio request contract:
// - HandleChangeAcquireBox and a clock device's HandleChangeSampleRate run on the driver work
//   queue and must return at once. Each records a pending request in a table of
//   kSwifterKitAudioPendingRequestCount entries, queues a required audioObject event, and
//   returns success; a full table fails the callback with kIOReturnNoResources.
// - A request ends exactly once, at the first of: Swift answers its ID through
//   audioCompleteRequest; kAudioRequestTimeoutNanoseconds elapse (rejected with
//   kIOReturnTimeout); the host detaches or the audio runtime stops (rejected with
//   kIOReturnAborted).
// - HandleChangeAcquireBox sets the requested acquired state before it reports success, as
//   IOUserAudioBox requires. Accepting the request keeps that state; rejecting it restores the
//   previous state and calls SetAcquisitionFailure.
// - A clock device's HandleChangeSampleRate likewise sets the requested rate before it reports
//   success, because IOUserAudioClockDevice.iig requires the value to be updated on success.
//   Accepting the request keeps that rate and reports it as a rate change; rejecting it restores
//   the previous rate through a device configuration change, unless the rate changed again.
// - Without a registered host or a timeout timer, the callbacks apply the framework default at
//   once.
// - Each request retains its box or clock device, so an answer needs no audioLock: answers run
//   on the work queue (timeouts) and user-client threads, and holding audioLock across
//   AudioDriverKit calls on the work queue could deadlock with AudioCommand. The table changes
//   only under audioRequestLock, which is never held while calling AudioDriverKit.
namespace {
    constexpr uint64_t kAudioRequestTimeoutNanoseconds = 10'000'000'000ULL;
    constexpr uint64_t kAudioRequestLeewayNanoseconds = 100'000'000ULL;

    // The AudioDriverKit classes, schema values, and service ivars the
    // SwifterKitRuntimeMediaObjects.h request templates operate on.
    struct AudioRequestFamily {
        using RuntimeBox = SwifterKitRuntimeAudioBox;
        using RuntimeClockDevice = SwifterKitRuntimeAudioClockDevice;
        using PendingRequest = SwifterKitAudioPendingRequest;

        static constexpr uint32_t kBoxRequest = kSwifterKitAudioObjectEventBoxRequest;
        static constexpr uint32_t kClockRequest = kSwifterKitAudioObjectEventClockRequest;
        static constexpr uint32_t kPendingRequestCount = kSwifterKitAudioPendingRequestCount;
        static constexpr uint64_t kRequestTimeout = kAudioRequestTimeoutNanoseconds;
        static constexpr uint64_t kRequestLeeway = kAudioRequestLeewayNanoseconds;

        static constexpr auto kRequestLock = &SwifterKitRuntimeService_IVars::audioRequestLock;
        static constexpr auto kRequests = &SwifterKitRuntimeService_IVars::audioRequests;
        static constexpr auto kNextRequestID = &SwifterKitRuntimeService_IVars::nextAudioRequestID;
        static constexpr auto kRequestsStopped =
            &SwifterKitRuntimeService_IVars::audioRequestsStopped;
        static constexpr auto kRequestTimer = &SwifterKitRuntimeService_IVars::audioRequestTimer;
        static constexpr auto kRequestTimerAction =
            &SwifterKitRuntimeService_IVars::audioRequestTimerAction;
    };

    bool TakeRequest(
        SwifterKitRuntimeService_IVars* state,
        uint32_t requestID,
        SwifterKitAudioPendingRequest* request) {
        return SwifterKitTakeRequest<AudioRequestFamily>(state, requestID, request);
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartDevice(
    IOUserAudioObjectID objectID,
    IOUserAudioStartStopFlags flags) {
    const kern_return_t result = super::StartDevice(objectID, flags);
    if (result == kIOReturnSuccess)
        (void)AudioObjectEvent(
            kSwifterKitAudioObjectEventDeviceStarted,
            objectID,
            static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeService::StopDevice(
    IOUserAudioObjectID objectID,
    IOUserAudioStartStopFlags flags) {
    (void)AudioObjectEvent(
        kSwifterKitAudioObjectEventDeviceStopped,
        objectID,
        static_cast<uint64_t>(flags));
    return super::StopDevice(objectID, flags);
}

kern_return_t
    SwifterKitRuntimeService::AudioObjectEvent(uint32_t kind, uint32_t index, uint64_t value) {
    const SwifterKitAudioObjectEvent event = {kind, index, 0, 0, value};
    return EnqueueEvent(kSwifterKitEventAudioObject, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::StartAudioRequests() {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return kIOReturnNotReady;
    // The timer shares the driver work queue with the callbacks that create requests.
    const OSSharedPtr<IODispatchQueue> queue = GetWorkQueue();
    return SwifterKitStartRequests<AudioRequestFamily>(
        ivars,
        queue.get(),
        [this](OSAction** action) { return CreateActionAudioRequestTimerOccurred(0, action); });
}

void SwifterKitRuntimeService::StopAudioRequests() {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return;
    SwifterKitStopRequests<AudioRequestFamily>(ivars, [this] {
        RejectAudioRequests(kIOReturnAborted);
    });
}

kern_return_t SwifterKitRuntimeService::BeginAudioRequest(
    OSObject* object,
    uint32_t kind,
    uint32_t index,
    uint64_t value,
    uint64_t previous) {
    if (ivars == nullptr || ivars->eventLock == nullptr || ivars->audioRequestLock == nullptr
        || object == nullptr)
        return kIOReturnNotReady;
    uint32_t requestID = 0;
    kern_return_t result = SwifterKitBeginRequest<AudioRequestFamily>(
        ivars,
        object,
        kind,
        index,
        value,
        previous,
        &requestID);
    const SwifterKitAudioObjectEvent event = {kind, index, requestID, 0, value};
    if (result == kIOReturnSuccess)
        result = EnqueueRequiredEvent(kSwifterKitEventAudioObject, &event, sizeof(event));
    if (result != kIOReturnSuccess && requestID != 0)
        (void)TakeRequest(ivars, requestID, nullptr);
    return result;
}

kern_return_t SwifterKitRuntimeService::CompleteAudioRequest(
    uint32_t requestID,
    bool accept,
    int32_t failure) {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return kIOReturnNotReady;
    SwifterKitAudioPendingRequest request = {};
    if (!TakeRequest(ivars, requestID, &request))
        return kIOReturnNotFound;
    const kern_return_t result = ApplyAudioRequest(
        request.object,
        request.kind,
        request.value,
        request.previous,
        accept,
        failure);
    OSSafeReleaseNULL(request.object);
    return result;
}

kern_return_t SwifterKitRuntimeService::ApplyAudioRequest(
    OSObject* object,
    uint32_t kind,
    uint64_t value,
    uint64_t previous,
    bool accept,
    int32_t failure) {
    return SwifterKitApplyRequest<AudioRequestFamily>(
        object,
        kind,
        value,
        previous,
        accept,
        failure);
}

void SwifterKitRuntimeService::RejectAudioRequests(int32_t failure) {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return;
    SwifterKitRejectRequests<AudioRequestFamily>(ivars, failure);
}

void SwifterKitRuntimeService::AudioRequestTimerOccurred_Impl(OSAction*, uint64_t) {
    if (ivars == nullptr || ivars->audioRequestLock == nullptr)
        return;
    // A deadline that cannot be re-armed must not strand its request, so every request then
    // ends with kIOReturnTimeout.
    SwifterKitExpireRequests<AudioRequestFamily>(ivars, [this] {
        RejectAudioRequests(kIOReturnTimeout);
    });
}
#endif
