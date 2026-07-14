#ifndef SwifterKitRuntimeVideoDeviceState_h
#define SwifterKitRuntimeVideoDeviceState_h

#include "SwifterKitRuntimeConfiguration.h"
#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOBufferMemoryDescriptor.h>
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
    IOBufferMemoryDescriptor* dataDescriptors[8][32] = {};
    IOBufferMemoryDescriptor* controlDescriptors[8][32] = {};
    IOMemoryMap* dataMaps[8][32] = {};
    IOMemoryMap* controlMaps[8][32] = {};
    uint64_t pendingSampleRateBits = 0;
};
#endif
#endif
