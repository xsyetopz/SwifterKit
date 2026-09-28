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

// Host exit and IOServiceClose reach the runtime client as Stop. Stop releases the client's
// wrapped memory and detaches it. DriverKit calls this method instead when it reports the
// client as crashed. The client's later Stop then finds nothing left to release.
auto SwifterKitRuntimeService::ClientCrashed_Impl(IOService* client, uint64_t options)
    -> kern_return_t {
#if SWIFTERKIT_ENABLE_MEMORY
    ReleaseClientMemory(client);
#endif
    DetachEventClient(client);
    return ClientCrashed(client, options, SUPERDISPATCH);
}

// Resolves an IOConnectMapMemory64 memory type for the runtime user client. Only an entitled
// host can open this client. The type's kind selects the source, and its identifier selects
// the object. This method refuses with kIOReturnBadArgument when:
// - The extension was generated without the kind.
// - The identifier names nothing.
// - Any bit above the 32-bit type is set.
// A ring or data queue answers kIOReturnNotReady while the fast path is not running. Memory
// that another client wrapped answers kIOReturnNotPermitted to `client`.
auto SwifterKitRuntimeService::CopyClientMemory(
    [[maybe_unused]] IOService* client,
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
    // Unused when the extension was generated without memory, networking, and a fast path.
    [[maybe_unused]] const uint32_t identifier =
        static_cast<uint32_t>(type) & kSwifterKitClientMemoryIdentifierMask;
    // Each kind answers directly, so kinds whose family was not generated fall through to
    // kIOReturnBadArgument.
    const kern_return_t result = [&]() -> kern_return_t {
        if (kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::MemoryBuffer)) {
#if SWIFTERKIT_ENABLE_MEMORY
            if (identifier != 0) {
                return CopyMemoryForClient(client, identifier, memory);
            }
#endif
        } else if (kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::PacketPool)) {
#if SWIFTERKIT_ENABLE_NETWORKING
            return CopyPacketPoolMemory(identifier, memory);
#endif
        } else if (kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::Ring)) {
#if SWIFTERKIT_ENABLE_FAST_PATH
            return CopyFastPathRingMemory(identifier, memory);
#endif
        } else if (kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::DataQueue)) {
#if SWIFTERKIT_ENABLE_FAST_PATH
            return CopyFastPathDataQueueMemory(identifier, memory);
#endif
        }
        return kIOReturnBadArgument;
    }();
    // The network family owns packet buffers, so the host only reads them.
    const bool readOnly = kind == static_cast<uint32_t>(SwifterKitClientMemoryKind::PacketPool);
    if (result == kIOReturnSuccess && options != nullptr && readOnly) {
        *options |= kIOUserClientMemoryReadOnly;
    }
    return result;
}
