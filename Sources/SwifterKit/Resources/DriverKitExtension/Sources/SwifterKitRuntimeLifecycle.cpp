#include <DriverKit/IOLib.h>
#include <DriverKit/OSArray.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

auto SwifterKitRuntimeService::init() -> bool {
    if (!super::init())
        return false;
    ivars = IONewZero(SwifterKitRuntimeService_IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->eventLock = IOLockAlloc();
    ivars->events = OSArray::withCapacity(64);
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
    ivars->scsiLock = IOLockAlloc();
#endif
#if SWIFTERKIT_ENABLE_AUDIO
    ivars->audioLock = IOLockAlloc();
#endif
#if SWIFTERKIT_ENABLE_VIDEO
    ivars->videoLock = IOLockAlloc();
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
    ivars->networkLock = IOLockAlloc();
#endif
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
    ivars->blockStorageLock = IOLockAlloc();
#endif
#if SWIFTERKIT_ENABLE_MEMORY
    ivars->memoryLock = IOLockAlloc();
#endif
#if SWIFTERKIT_ENABLE_SERIAL
    ivars->serialLock = IOLockAlloc();
#endif
    return ivars->eventLock != nullptr && ivars->events != nullptr
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
           && ivars->scsiLock != nullptr
#endif
#if SWIFTERKIT_ENABLE_AUDIO
           && ivars->audioLock != nullptr
#endif
#if SWIFTERKIT_ENABLE_VIDEO
           && ivars->videoLock != nullptr
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
           && ivars->networkLock != nullptr
#endif
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
           && ivars->blockStorageLock != nullptr
#endif
#if SWIFTERKIT_ENABLE_MEMORY
           && ivars->memoryLock != nullptr
#endif
#if SWIFTERKIT_ENABLE_SERIAL
           && ivars->serialLock != nullptr
#endif
        ;
}
