#include <DriverKit/IOReturn.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeUserClient.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKitTypes.h>
#endif
#if SWIFTERKIT_ENABLE_VIDEO
    #include <VideoDriverKit/VideoDriverKitTypes.h>
#endif

auto SwifterKitRuntimeService::NewUserClient_Impl(uint32_t type, IOUserClient** userClient)
    -> kern_return_t {
#if SWIFTERKIT_ENABLE_AUDIO
    if (type == kIOUserAudioDriverUserClientType) {
        return NewUserClient(type, userClient, SUPERDISPATCH);
    }
#endif
#if SWIFTERKIT_ENABLE_VIDEO
    if (type == kIOUserVideoDriverUserClientType) {
        return NewUserClient(type, userClient, SUPERDISPATCH);
    }
#endif
#if SWIFTERKIT_ENABLE_MIDI
    if (type == kIOUserMIDIDriverUserClientType) {
        return NewUserClient(type, userClient, SUPERDISPATCH);
    }
#endif
    if (type != 0 || userClient == nullptr) {
        return kIOReturnBadArgument;
    }

    IOService* client = nullptr;
    const kern_return_t result = Create(this, "UserClientProperties", &client);
    if (result != kIOReturnSuccess) {
        return result;
    }

    *userClient = OSDynamicCast(SwifterKitRuntimeUserClient, client);
    if (*userClient == nullptr) {
        client->release();
        return kIOReturnError;
    }
    return kIOReturnSuccess;
}
