#ifndef SwifterKitRuntimeAudioDeviceState_h
#define SwifterKitRuntimeAudioDeviceState_h

#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>

class SwifterKitRuntimeService;

// PerformDeviceConfigurationChange action for StreamProperty ring-buffer resizing.
constexpr uint64_t kSwifterKitAudioRingBufferChangeAction = 0x53574B52494E4742ULL;

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
