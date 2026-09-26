#include "SwifterKitRuntimeUserClient.h"

#include <DriverKit/IOLib.h>
#include <DriverKit/IOMemoryDescriptor.h>
#include <DriverKit/IOReturn.h>
#include <DriverKit/IOUserClient.h>
#include <DriverKit/OSAction.h>
#include <DriverKit/OSArray.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSString.h>

#include "SwifterKitRuntimeCommandDispatch.h"
#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"

struct SwifterKitRuntimeUserClient_IVars {
    SwifterKitRuntimeService* service = nullptr;
    // The host's event-notification completion, retained. actionLock guards it
    // because the service sends notifications from its own queues.
    IOLock* actionLock = nullptr;
    OSAction* eventAction = nullptr;
};

namespace {
    // Swaps the retained notification action and releases the previous one.
    void ReplaceEventAction(SwifterKitRuntimeUserClient_IVars* state, OSAction* action) {
        if (action != nullptr) {
            action->retain();
        }
        IOLockLock(state->actionLock);
        const OSAction* previous = state->eventAction;
        state->eventAction = action;
        IOLockUnlock(state->actionLock);
        OSSafeReleaseNULL(previous);
    }

    // Registers the caller's completion as the service's event notification.
    // ExternalMethod and Stop share this client's default queue, so a
    // registration cannot race Stop's detach.
    kern_return_t RegisterEventNotification(
        SwifterKitRuntimeUserClient* client,
        SwifterKitRuntimeUserClient_IVars* state,
        const IOUserClientMethodArguments* arguments) {
        if (state == nullptr || state->service == nullptr || state->actionLock == nullptr) {
            return kIOReturnNotReady;
        }
        if (arguments->completion == nullptr || arguments->scalarInputCount != 0
            || arguments->structureInput != nullptr
            || arguments->structureInputDescriptor != nullptr || arguments->scalarOutputCount != 0
            || arguments->structureOutputDescriptor != nullptr) {
            return kIOReturnBadArgument;
        }
        ReplaceEventAction(state, arguments->completion);
        const kern_return_t result = state->service->AttachEventClient(client);
        if (result != kIOReturnSuccess) {
            ReplaceEventAction(state, nullptr);
        }
        return result;
    }
}  // namespace

auto SwifterKitRuntimeUserClient::init() -> bool {
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(SwifterKitRuntimeUserClient_IVars, 1);
    if (ivars == nullptr) {
        return false;
    }
    ivars->actionLock = IOLockAlloc();
    return ivars->actionLock != nullptr;
}

void SwifterKitRuntimeUserClient::free() {
    if (ivars != nullptr) {
        OSSafeReleaseNULL(ivars->eventAction);
        IOLockFreeZero(ivars->actionLock);
        OSSafeReleaseNULL(ivars->service);
    }
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeUserClient_IVars, 1);
    super::free();
}

void SwifterKitRuntimeUserClient::NotifyEventsPending() {
    if (ivars == nullptr || ivars->actionLock == nullptr) {
        return;
    }
    IOLockLock(ivars->actionLock);
    OSAction* action = ivars->eventAction;
    if (action != nullptr) {
        action->retain();
    }
    IOLockUnlock(ivars->actionLock);
    if (action == nullptr) {
        return;
    }
    const IOUserClientAsyncArgumentsArray noArguments = {};
    AsyncCompletion(action, kIOReturnSuccess, noArguments, 0);
    action->release();
}

auto SwifterKitRuntimeUserClient::Start_Impl(IOService* provider) -> kern_return_t {
    if (ivars == nullptr || provider == nullptr) {
        return kIOReturnBadArgument;
    }

    const kern_return_t startResult = Start(provider, SUPERDISPATCH);
    if (startResult != kIOReturnSuccess) {
        return startResult;
    }
    // Every generated runtime requires the client to list this extension in
    // com.apple.developer.driverkit.userclient-access. An empty identifier never matches.
    OSDictionary* entitlements = nullptr;
    const kern_return_t entitlementResult = CopyClientEntitlements(&entitlements);
    const OSArray* access =
        entitlementResult == kIOReturnSuccess && entitlements != nullptr
            ? OSDynamicCast(
                  OSArray,
                  entitlements->getObject("com.apple.developer.driverkit.userclient-access"))
            : nullptr;
    bool authorized = false;
    if (access != nullptr)
        for (uint32_t index = 0; index < access->getCount(); ++index) {
            const OSString* identifier = OSDynamicCast(OSString, access->getObject(index));
            if (identifier != nullptr && identifier->getLength() != 0
                && identifier->isEqualTo(kSwifterKitBundleIdentifier)) {
                authorized = true;
                break;
            }
        }
    OSSafeReleaseNULL(entitlements);
    if (!authorized) {
        Stop(provider, SUPERDISPATCH);
        return kIOReturnNotPermitted;
    }
    ivars->service = OSDynamicCast(SwifterKitRuntimeService, provider);
    if (ivars->service == nullptr) {
        Stop(provider, SUPERDISPATCH);
        return kIOReturnBadArgument;
    }
    ivars->service->retain();
    return kIOReturnSuccess;
}

auto SwifterKitRuntimeUserClient::Stop_Impl(IOService* provider) -> kern_return_t {
    if (ivars != nullptr) {
        // Detaching answers the requests this host can no longer complete.
        if (ivars->service != nullptr) {
            ivars->service->DetachEventClient(this);
        }
        if (ivars->actionLock != nullptr) {
            ReplaceEventAction(ivars, nullptr);
        }
        OSSafeReleaseNULL(ivars->service);
    }
    return Stop(provider, SUPERDISPATCH);
}

auto SwifterKitRuntimeUserClient::ExternalMethod(
    uint64_t selector,
    IOUserClientMethodArguments* arguments,
    const IOUserClientMethodDispatch*,
    OSObject*,
    void*) -> kern_return_t {
    if (selector == kSwifterKitSelectorEventNotification && arguments != nullptr) {
        return RegisterEventNotification(this, ivars, arguments);
    }
    if (selector != kSwifterKitSelectorTransact || arguments == nullptr
        || arguments->structureInput == nullptr || arguments->scalarInputCount != 0
        || arguments->scalarOutputCount != 0) {
        return kIOReturnBadArgument;
    }

    const size_t inputLength = arguments->structureInput->getLength();
    if (inputLength < sizeof(SwifterKitRuntimeHeader)
        || inputLength > kSwifterKitRuntimeMaximumMessageSize) {
        return kIOReturnBadArgument;
    }

    const auto* bytes = static_cast<const uint8_t*>(arguments->structureInput->getBytesNoCopy());
    const auto* request = reinterpret_cast<const SwifterKitRuntimeHeader*>(bytes);
    if (request == nullptr || request->magic != kSwifterKitRuntimeMagic
        || request->payloadLength != inputLength - sizeof(SwifterKitRuntimeHeader)) {
        return kIOReturnBadArgument;
    }

    return SwifterKitHandleMessage(
        this,
        ivars == nullptr ? nullptr : ivars->service,
        arguments,
        request,
        bytes + sizeof(SwifterKitRuntimeHeader));
}

// IOConnectMapMemory64 reaches only a client Start admitted, so only an entitled host maps
// runtime memory. The service resolves the type; after Stop detaches it nothing maps. Like
// ExternalMethod and Stop, this runs on the client's default queue.
auto SwifterKitRuntimeUserClient::CopyClientMemoryForType_Impl(
    uint64_t type,
    uint64_t* options,
    IOMemoryDescriptor** memory) -> kern_return_t {
    if (ivars == nullptr || ivars->service == nullptr) {
        return kIOReturnNotReady;
    }
    return ivars->service->CopyClientMemory(type, options, memory);
}
