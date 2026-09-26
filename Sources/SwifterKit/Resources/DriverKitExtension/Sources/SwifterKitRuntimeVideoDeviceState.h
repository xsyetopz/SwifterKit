#ifndef SwifterKitRuntimeVideoDeviceState_h
#define SwifterKitRuntimeVideoDeviceState_h

#include "SwifterKitRuntimeConfiguration.h"
#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <VideoDriverKit/IOUserVideoBuffer.h>
    #include <VideoDriverKit/IOUserVideoControl.h>
    #include <VideoDriverKit/IOUserVideoCustomProperty.h>
    #include <VideoDriverKit/IOUserVideoStream.h>

class SwifterKitRuntimeService;

struct SwifterKitRuntimeVideoDevice_IVars {
    SwifterKitRuntimeService* service = nullptr;
    IOUserVideoStream* streams[8] = {};
    IOUserVideoBuffer* buffers[8][32] = {};
    IOUserVideoControl* controls[64] = {};
    IOUserVideoCustomProperty* customProperties[32] = {};
    // 0 detached, 1 device, 2 driver; see SwifterKitRuntimeVideoProtocol.h.
    uint8_t customPropertyOwners[32] = {};
    IOBufferMemoryDescriptor* dataDescriptors[8][32] = {};
    IOBufferMemoryDescriptor* controlDescriptors[8][32] = {};
    IOMemoryMap* dataMaps[8][32] = {};
    IOMemoryMap* controlMaps[8][32] = {};
    uint64_t pendingSampleRateBits = 0;
    // Live buffer sizing, identity, and attachment, which Swift can change after Configure.
    // bufferLock guards these, the maps, the descriptors, and the pending change; no
    // VideoDriverKit call runs under it.
    IOLock* bufferLock = nullptr;
    uint32_t dataCapacity[8] = {};
    uint32_t controlCapacity[8] = {};
    uint32_t bufferIDs[8][32] = {};
    bool bufferDetached[8][32] = {};
    bool streamDetached[8] = {};
    bool controlDetached[64] = {};
    // A stream or buffer change waiting for PerformDeviceConfigurationChange; kind zero is none.
    uint32_t pendingChangeKind = 0;
    uint32_t pendingChangeStream = 0;
    uint32_t pendingChangeBuffer = 0;
    uint64_t pendingChangeValue = 0;
};

// PerformDeviceConfigurationChange action for buffer, queue, and buffer-list changes.
constexpr uint64_t kSwifterKitVideoMemberChangeAction = 0x53574B564D454D42ULL;
#endif
#endif
