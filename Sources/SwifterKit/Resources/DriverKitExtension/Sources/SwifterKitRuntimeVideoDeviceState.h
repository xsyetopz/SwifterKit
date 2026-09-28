#ifndef SwifterKitRuntimeVideoDeviceState_h
#define SwifterKitRuntimeVideoDeviceState_h

#include "SwifterKitRuntimeConfiguration.h"
#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <VideoDriverKit/IOUserVideoBuffer.h>
    #include <VideoDriverKit/IOUserVideoClockDevice.h>
    #include <VideoDriverKit/IOUserVideoControl.h>
    #include <VideoDriverKit/IOUserVideoCustomProperty.h>
    #include <VideoDriverKit/IOUserVideoStream.h>
    #include <string.h>

    #include "SwifterKitRuntimeMediaObjects.h"
    #include "SwifterKitRuntimeSchema.h"

class SwifterKitRuntimeService;

struct SwifterKitRuntimeVideoDevice_IVars {
    SwifterKitRuntimeService* service = nullptr;
    IOUserVideoStream* streams[kSwifterKitVideoMaximumStreams] = {};
    IOUserVideoBuffer* buffers[kSwifterKitVideoMaximumStreams][kSwifterKitVideoMaximumBuffers] = {};
    IOUserVideoControl* controls[kSwifterKitVideoMaximumControls] = {};
    IOUserVideoCustomProperty* customProperties[kSwifterKitVideoMaximumCustomProperties] = {};
    // A kSwifterKitVideoOwner value.
    uint8_t customPropertyOwners[kSwifterKitVideoMaximumCustomProperties] = {};
    IOBufferMemoryDescriptor* dataDescriptors[kSwifterKitVideoMaximumStreams]
                                             [kSwifterKitVideoMaximumBuffers] = {};
    IOBufferMemoryDescriptor* controlDescriptors[kSwifterKitVideoMaximumStreams]
                                                [kSwifterKitVideoMaximumBuffers] = {};
    IOMemoryMap* dataMaps[kSwifterKitVideoMaximumStreams][kSwifterKitVideoMaximumBuffers] = {};
    IOMemoryMap* controlMaps[kSwifterKitVideoMaximumStreams][kSwifterKitVideoMaximumBuffers] = {};
    uint64_t pendingSampleRateBits = 0;
    // Live buffer sizing, identity, and attachment, which Swift can change after Configure.
    // bufferLock guards these, the maps, the descriptors, and the pending change. No
    // VideoDriverKit call runs under it.
    IOLock* bufferLock = nullptr;
    uint32_t dataCapacity[kSwifterKitVideoMaximumStreams] = {};
    uint32_t controlCapacity[kSwifterKitVideoMaximumStreams] = {};
    uint32_t bufferIDs[kSwifterKitVideoMaximumStreams][kSwifterKitVideoMaximumBuffers] = {};
    bool bufferDetached[kSwifterKitVideoMaximumStreams][kSwifterKitVideoMaximumBuffers] = {};
    bool streamDetached[kSwifterKitVideoMaximumStreams] = {};
    bool controlDetached[kSwifterKitVideoMaximumControls] = {};
    // A stream or buffer change waiting for PerformDeviceConfigurationChange. Kind zero is none.
    uint32_t pendingChangeKind = 0;
    uint32_t pendingChangeStream = 0;
    uint32_t pendingChangeBuffer = 0;
    uint64_t pendingChangeValue = 0;
};

// PerformDeviceConfigurationChange action for buffer, queue, and buffer-list changes.
constexpr uint64_t kSwifterKitVideoMemberChangeAction = 0x53574B564D454D42ULL;

// PerformDeviceConfigurationChange action for stream attachment, safety offsets, and clock
// latencies. IOUserVideoDriver.iig: "For changes to an IOUserVideoDevice's or
// IOUserVideoClockDevice's state that will affect IO or its structure, the client should trigger a
// request to the host using RequestDeviceConfigurationChange() ... It is only at this point that
// the device can make the state change." The change travels in the request's change info.
constexpr uint64_t kSwifterKitVideoStructureChangeAction = 0x53574B5653545255ULL;
constexpr uint32_t kSwifterKitVideoChangeStreamAttachment = kSwifterKitVideoMemberStream;
// Safety offsets use the SetDeviceProperty selectors, latencies the SetClockProperty selectors.
constexpr uint32_t kSwifterKitVideoChangeInputSafetyOffset =
    kSwifterKitVideoDevicePropertyInputSafetyOffset;
constexpr uint32_t kSwifterKitVideoChangeOutputSafetyOffset =
    kSwifterKitVideoDevicePropertyOutputSafetyOffset;
constexpr uint32_t kSwifterKitVideoChangeInputLatency = kSwifterKitVideoClockPropertyInputLatency;
constexpr uint32_t kSwifterKitVideoChangeOutputLatency = kSwifterKitVideoClockPropertyOutputLatency;

struct SwifterKitVideoStructureChange {
    uint32_t selector;
    uint32_t index;
    uint64_t value;
};

inline kern_return_t SwifterKitRequestVideoStructureChange(
    IOUserVideoClockDevice* device,
    uint32_t selector,
    uint32_t index,
    uint64_t value) {
    return SwifterKitRequestConfigurationChange(
        device,
        kSwifterKitVideoStructureChangeAction,
        SwifterKitVideoStructureChange {selector, index, value});
}

inline bool SwifterKitReadVideoStructureChange(
    OSObject* info,
    SwifterKitVideoStructureChange* change) {
    return SwifterKitReadConfigurationChange(info, change);
}
#endif
#endif
