#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IODispatchQueue.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOTimerDispatchSource.h>
    #include <DriverKit/OSAction.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeMediaRequests.h"
    #include "SwifterKitRuntimeServiceState.h"
    #include "SwifterKitRuntimeVideoBox.h"
    #include "SwifterKitRuntimeVideoClockDevice.h"
    #include "SwifterKitRuntimeVideoProtocol.h"

// Video request contract, the same as the audio one:
// - HandleChangeAcquireBox and a clock device's HandleChangeSampleRate run on the driver work
//   queue. Both must return at once. Each records a pending request in a table of
//   kSwifterKitVideoPendingRequestCount entries, queues a required videoObject event, and
//   returns success. A full table fails the callback with kIOReturnNoResources.
// - A request ends exactly once, at the first of:
//   - Swift answers its ID through videoCompleteRequest.
//   - kVideoRequestTimeoutNanoseconds elapses, rejected with kIOReturnTimeout.
//   - The host detaches, or the video runtime stops, rejected with kIOReturnAborted.
// - HandleChangeAcquireBox sets the requested acquired state before it reports success.
//   Accepting the request keeps that state. Rejecting it restores the previous state and calls
//   SetAcquisitionFailure.
// - A clock device's HandleChangeSampleRate likewise sets the requested rate before it reports
//   success. IOUserVideoClockDevice.iig requires the value to be updated on success. Accepting
//   the request keeps that rate and reports it as a rate change. Rejecting it restores the
//   previous rate through a device configuration change, unless the rate changed again.
// - Without a registered host or a timeout timer, the callbacks apply the framework default at
//   once.
// - Each request retains its box or clock device, so an answer needs no videoLock. Answers run
//   on the work queue for timeouts, and on user-client threads for host answers. Holding
//   videoLock across VideoDriverKit calls on the work queue could deadlock with VideoCommand.
//   The table changes only under videoRequestLock, which is never held while it calls
//   VideoDriverKit.
namespace {
    constexpr uint64_t kVideoRequestTimeoutNanoseconds = 10'000'000'000ULL;
    constexpr uint64_t kVideoRequestLeewayNanoseconds = 100'000'000ULL;

    // The VideoDriverKit classes, schema values, and service ivars the
    // SwifterKitRuntimeMediaObjects.h request templates operate on.
    struct VideoRequestFamily {
        using RuntimeBox = SwifterKitRuntimeVideoBox;
        using RuntimeClockDevice = SwifterKitRuntimeVideoClockDevice;
        using PendingRequest = SwifterKitVideoPendingRequest;

        static constexpr uint32_t kBoxRequest = kSwifterKitVideoObjectEventBoxRequest;
        static constexpr uint32_t kClockRequest = kSwifterKitVideoObjectEventClockRequest;
        static constexpr uint32_t kPendingRequestCount = kSwifterKitVideoPendingRequestCount;
        static constexpr uint64_t kRequestTimeout = kVideoRequestTimeoutNanoseconds;
        static constexpr uint64_t kRequestLeeway = kVideoRequestLeewayNanoseconds;

        static constexpr auto kRequestLock = &SwifterKitRuntimeService_IVars::videoRequestLock;
        static constexpr auto kRequests = &SwifterKitRuntimeService_IVars::videoRequests;
        static constexpr auto kNextRequestID = &SwifterKitRuntimeService_IVars::nextVideoRequestID;
        static constexpr auto kRequestsStopped =
            &SwifterKitRuntimeService_IVars::videoRequestsStopped;
        static constexpr auto kRequestTimer = &SwifterKitRuntimeService_IVars::videoRequestTimer;
        static constexpr auto kRequestTimerAction =
            &SwifterKitRuntimeService_IVars::videoRequestTimerAction;
    };

    bool TakeRequest(
        SwifterKitRuntimeService_IVars* state,
        uint32_t requestID,
        SwifterKitVideoPendingRequest* request) {
        return SwifterKitTakeRequest<VideoRequestFamily>(state, requestID, request);
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartDevice(
    IOUserVideoObjectID objectID,
    IOUserVideoStartStopFlags flags) {
    const kern_return_t result = super::StartDevice(objectID, flags);
    if (result == kIOReturnSuccess)
        (void)VideoObjectEvent(
            kSwifterKitVideoObjectEventDeviceStarted,
            objectID,
            static_cast<uint64_t>(flags));
    return result;
}

kern_return_t SwifterKitRuntimeService::StopDevice(
    IOUserVideoObjectID objectID,
    IOUserVideoStartStopFlags flags) {
    (void)VideoObjectEvent(
        kSwifterKitVideoObjectEventDeviceStopped,
        objectID,
        static_cast<uint64_t>(flags));
    return super::StopDevice(objectID, flags);
}

kern_return_t
    SwifterKitRuntimeService::VideoObjectEvent(uint32_t kind, uint32_t index, uint64_t value) {
    const SwifterKitVideoObjectEvent event = {kind, index, 0, 0, value};
    return EnqueueEvent(kSwifterKitEventVideoObject, &event, sizeof(event));
}

kern_return_t SwifterKitRuntimeService::StartVideoRequests() {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return kIOReturnNotReady;
    // The timer shares the driver work queue with the callbacks that create requests.
    const OSSharedPtr<IODispatchQueue> queue = GetWorkQueue();
    return SwifterKitStartRequests<VideoRequestFamily>(
        ivars,
        queue.get(),
        [this](OSAction** action) { return CreateActionVideoRequestTimerOccurred(0, action); });
}

void SwifterKitRuntimeService::StopVideoRequests() {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return;
    SwifterKitStopRequests<VideoRequestFamily>(ivars, [this] {
        RejectVideoRequests(kIOReturnAborted);
    });
}

kern_return_t SwifterKitRuntimeService::BeginVideoRequest(
    OSObject* object,
    uint32_t kind,
    uint32_t index,
    uint64_t value,
    uint64_t previous) {
    if (ivars == nullptr || ivars->eventLock == nullptr || ivars->videoRequestLock == nullptr
        || object == nullptr)
        return kIOReturnNotReady;
    uint32_t requestID = 0;
    kern_return_t result = SwifterKitBeginRequest<VideoRequestFamily>(
        ivars,
        object,
        kind,
        index,
        value,
        previous,
        &requestID);
    const SwifterKitVideoObjectEvent event = {kind, index, requestID, 0, value};
    if (result == kIOReturnSuccess)
        result = EnqueueRequiredEvent(kSwifterKitEventVideoObject, &event, sizeof(event));
    if (result != kIOReturnSuccess && requestID != 0)
        (void)TakeRequest(ivars, requestID, nullptr);
    return result;
}

kern_return_t SwifterKitRuntimeService::CompleteVideoRequest(
    uint32_t requestID,
    bool accept,
    int32_t failure) {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return kIOReturnNotReady;
    SwifterKitVideoPendingRequest request = {};
    if (!TakeRequest(ivars, requestID, &request))
        return kIOReturnNotFound;
    const kern_return_t result = ApplyVideoRequest(
        request.object,
        request.kind,
        request.value,
        request.previous,
        accept,
        failure);
    OSSafeReleaseNULL(request.object);
    return result;
}

kern_return_t SwifterKitRuntimeService::ApplyVideoRequest(
    OSObject* object,
    uint32_t kind,
    uint64_t value,
    uint64_t previous,
    bool accept,
    int32_t failure) {
    return SwifterKitApplyRequest<VideoRequestFamily>(
        object,
        kind,
        value,
        previous,
        accept,
        failure);
}

void SwifterKitRuntimeService::RejectVideoRequests(int32_t failure) {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return;
    SwifterKitRejectRequests<VideoRequestFamily>(ivars, failure);
}

void SwifterKitRuntimeService::VideoRequestTimerOccurred_Impl(OSAction*, uint64_t) {
    if (ivars == nullptr || ivars->videoRequestLock == nullptr)
        return;
    // A deadline that cannot be re-armed must not strand its request, so every request then
    // ends with kIOReturnTimeout.
    SwifterKitExpireRequests<VideoRequestFamily>(ivars, [this] {
        RejectVideoRequests(kIOReturnTimeout);
    });
}
#endif
