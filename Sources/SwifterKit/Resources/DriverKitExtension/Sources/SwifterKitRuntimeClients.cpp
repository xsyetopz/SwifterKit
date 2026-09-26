#include <DriverKit/IOMemoryDescriptor.h>
#include <DriverKit/IOReturn.h>
#include <DriverKit/IOUserClient.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeSchema.h"
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

// Host exit and IOServiceClose reach the runtime client as Stop, which detaches
// it. This covers a registered client that DriverKit reports as crashed instead.
auto SwifterKitRuntimeService::ClientCrashed_Impl(IOService* client, uint64_t options)
    -> kern_return_t {
    DetachEventClient(client);
    return ClientCrashed(client, options, SUPERDISPATCH);
}

// Resolves an IOConnectMapMemory64 memory type for the runtime user client, which only an
// entitled host can open. The type's kind selects the source and its identifier the object;
// kinds the extension was generated without, identifiers that name nothing, and any bit above
// the 32-bit type are refused with kIOReturnBadArgument. Rings and data queues have reserved
// kinds and answer kIOReturnUnsupported.
auto SwifterKitRuntimeService::CopyClientMemory(
    uint64_t type,
    uint64_t* options,
    IOMemoryDescriptor** memory) -> kern_return_t {
    if (memory == nullptr) {
        return kIOReturnBadArgument;
    }
    *memory = nullptr;
    if (type > UINT32_MAX) {
        return kIOReturnBadArgument;
    }
    const uint32_t kind = static_cast<uint32_t>(type) >> kSwifterKitClientMemoryKindShift;
    // Unused when the extension was generated without memory and networking.
    [[maybe_unused]] const uint32_t identifier =
        static_cast<uint32_t>(type) & kSwifterKitClientMemoryIdentifierMask;
    kern_return_t result = kIOReturnBadArgument;
    bool readOnly = false;
    if (kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::MemoryBuffer)) {
#if SWIFTERKIT_ENABLE_MEMORY
        if (identifier != 0) {
            result = CopyMemoryForClient(identifier, memory);
        }
#endif
    } else if (kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::PacketPool)) {
        // The network family owns packet buffers, so the host only reads them.
        readOnly = true;
#if SWIFTERKIT_ENABLE_NETWORKING
        result = CopyPacketPoolMemory(identifier, memory);
#endif
    } else if (
        kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::Ring)
        || kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::DataQueue)) {
        result = kIOReturnUnsupported;
    }
    if (result == kIOReturnSuccess && options != nullptr && readOnly) {
        *options |= kIOUserClientMemoryReadOnly;
    }
    return result;
}
