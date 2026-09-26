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

// PerformDeviceConfigurationChange action for stream attachment, safety offsets, and clock
// latencies. IOUserVideoDriver.iig: "For changes to an IOUserVideoDevice's or
// IOUserVideoClockDevice's state that will affect IO or its structure, the client should trigger a
// request to the host using RequestDeviceConfigurationChange() ... It is only at this point that
// the device can make the state change." The change travels in the request's change info.
constexpr uint64_t kSwifterKitVideoStructureChangeAction = 0x53574B5653545255ULL;
constexpr uint32_t kSwifterKitVideoChangeStreamAttachment = 1;
// Safety offsets use the SetDeviceProperty selectors, latencies the SetClockProperty selectors.
constexpr uint32_t kSwifterKitVideoChangeInputSafetyOffset = 4;
constexpr uint32_t kSwifterKitVideoChangeOutputSafetyOffset = 5;
constexpr uint32_t kSwifterKitVideoChangeInputLatency = 6;
constexpr uint32_t kSwifterKitVideoChangeOutputLatency = 7;

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
    const SwifterKitVideoStructureChange change = {selector, index, value};
    OSData* info = OSData::withBytes(&change, sizeof(change));
    if (info == nullptr)
        return kIOReturnNoMemory;
    const kern_return_t result =
        device->RequestDeviceConfigurationChange(kSwifterKitVideoStructureChangeAction, info);
    info->release();
    return result;
}

inline bool SwifterKitReadVideoStructureChange(
    OSObject* info,
    SwifterKitVideoStructureChange* change) {
    auto* data = OSDynamicCast(OSData, info);
    if (data == nullptr || data->getLength() != sizeof(*change))
        return false;
    memcpy(change, data->getBytesNoCopy(), sizeof(*change));
    return true;
}
#endif
#endif
