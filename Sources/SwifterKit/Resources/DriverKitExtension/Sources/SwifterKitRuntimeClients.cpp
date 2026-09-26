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

// Host exit and IOServiceClose reach the runtime client as Stop, which releases its wrapped
// memory and detaches it. This covers a client that DriverKit reports as crashed instead; the
// client's later Stop finds nothing left to release.
auto SwifterKitRuntimeService::ClientCrashed_Impl(IOService* client, uint64_t options)
    -> kern_return_t {
#if SWIFTERKIT_ENABLE_MEMORY
    ReleaseClientMemory(client);
#endif
    DetachEventClient(client);
    return ClientCrashed(client, options, SUPERDISPATCH);
}

// Resolves an IOConnectMapMemory64 memory type for the runtime user client, which only an
// entitled host can open. The type's kind selects the source and its identifier the object;
// kinds the extension was generated without, identifiers that name nothing, and any bit above
// the 32-bit type are refused with kIOReturnBadArgument. A ring or data queue answers
// kIOReturnNotReady while the fast path is not running, and memory another client wrapped
// answers kIOReturnNotPermitted to `client`.
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
