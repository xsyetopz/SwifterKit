#ifndef SwifterKitRuntimeAudioDeviceState_h
#define SwifterKitRuntimeAudioDeviceState_h

#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSData.h>
    #include <string.h>

class SwifterKitRuntimeService;

// PerformDeviceConfigurationChange action for StreamProperty ring-buffer resizing.
constexpr uint64_t kSwifterKitAudioRingBufferChangeAction = 0x53574B52494E4742ULL;

// PerformDeviceConfigurationChange action for member changes that affect IO or the device's
// structure. IOUserAudioDriver.iig: "For changes to an IOUserAudioDevice's or
// IOUserAudioClockDevice's state that will affect IO or its structure, the client should trigger a
// request to the host using RequestDeviceConfigurationChange() ... It is only at this point that
// the device can make the state change." The change travels in the request's change info.
constexpr uint64_t kSwifterKitAudioMemberChangeAction = 0x53574B4D454D4252ULL;
constexpr uint32_t kSwifterKitAudioChangeStreamAttachment = 1;
constexpr uint32_t kSwifterKitAudioChangeInputSafetyOffset = 4;
constexpr uint32_t kSwifterKitAudioChangeOutputSafetyOffset = 5;
constexpr uint32_t kSwifterKitAudioChangeInputLatency = 6;
constexpr uint32_t kSwifterKitAudioChangeOutputLatency = 7;
constexpr uint32_t kSwifterKitAudioChangeZeroTimeStampPeriod = 9;

struct SwifterKitAudioMemberChange {
    uint32_t selector;
    uint32_t index;
    uint64_t value;
};

inline kern_return_t SwifterKitRequestAudioMemberChange(
    IOUserAudioClockDevice* device,
    uint32_t selector,
    uint32_t index,
    uint64_t value) {
    const SwifterKitAudioMemberChange change = {selector, index, value};
    OSData* info = OSData::withBytes(&change, sizeof(change));
    if (info == nullptr)
        return kIOReturnNoMemory;
    const kern_return_t result =
        device->RequestDeviceConfigurationChange(kSwifterKitAudioMemberChangeAction, info);
    info->release();
    return result;
}

inline bool SwifterKitReadAudioMemberChange(OSObject* info, SwifterKitAudioMemberChange* change) {
    auto* data = OSDynamicCast(OSData, info);
    if (data == nullptr || data->getLength() != sizeof(*change))
        return false;
    memcpy(change, data->getBytesNoCopy(), sizeof(*change));
    return true;
}

struct SwifterKitRuntimeAudioDevice_IVars {
    SwifterKitRuntimeService* service = nullptr;
    IOUserAudioStream* streams[8] = {};
    IOBufferMemoryDescriptor* descriptors[8] = {};
    IOMemoryMap* maps[8] = {};
    IOUserAudioControl* controls[64] = {};
    IOUserAudioCustomProperty* customProperties[32] = {};
    // Zero means attached to the device, as configured; see SwifterKitRuntimeAudioMembers.cpp.
    bool streamDetached[8] = {};
    bool controlDetached[64] = {};
    uint8_t propertyPlacement[32] = {};
    uint64_t sequence = 0;
    uint64_t sampleTime = 0;
    uint64_t hostTime = 0;
    uint32_t operation = UINT32_MAX;
    uint32_t frameCount = 0;
    uint64_t pendingSampleRateBits = 0;
    // A ring-buffer change waiting for PerformDeviceConfigurationChange: the stream index in the
    // high word and the frame capacity in the low word, or zero. ringLock guards maps and
    // descriptors while stream reads and writes copy bytes and while a change swaps them.
    uint64_t pendingRingBuffer = 0;
    IOLock* ringLock = nullptr;
};
#endif
#endif
