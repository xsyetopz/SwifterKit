#ifndef SwifterKitRuntimeAudioDeviceState_h
#define SwifterKitRuntimeAudioDeviceState_h

#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_AUDIO
    #include <AudioDriverKit/AudioDriverKit.h>
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>

class SwifterKitRuntimeService;

struct SwifterKitRuntimeAudioDevice_IVars {
    SwifterKitRuntimeService* service = nullptr;
    IOUserAudioStream* streams[8] = {};
    IOBufferMemoryDescriptor* descriptors[8] = {};
    IOMemoryMap* maps[8] = {};
    IOUserAudioControl* controls[64] = {};
    IOUserAudioCustomProperty* customProperties[32] = {};
    uint64_t sequence = 0;
    uint64_t sampleTime = 0;
    uint64_t hostTime = 0;
    uint32_t operation = UINT32_MAX;
    uint32_t frameCount = 0;
    uint64_t pendingSampleRateBits = 0;
};
#endif
#endif
