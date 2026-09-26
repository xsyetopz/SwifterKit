#include "SwifterKitRuntimeService.h"

#include <DriverKit/IOLib.h>
#include <DriverKit/OSCollections.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeServiceState.h"
#include "SwifterKitRuntimeUserClient.h"

#if SWIFTERKIT_ENABLE_HID
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <HIDDriverKit/IOHIDDeviceKeys.h>
#endif

namespace {
#if SWIFTERKIT_ENABLE_USB
    [[maybe_unused]] kern_return_t OpenUSBProvider(
        SwifterKitRuntimeService* service,
        IOService* provider,
        const SwifterKitRuntimeService_IVars* state) {
        if (service == nullptr || state == nullptr) {
            return kIOReturnBadArgument;
        }
        return service->StartUSB(provider);
    }

    void CloseUSBProvider(
        SwifterKitRuntimeService* service,
        const SwifterKitRuntimeService_IVars* state) {
        if (service != nullptr && state != nullptr) {
            service->StopUSB();
        }
    }
#endif

#if SWIFTERKIT_ENABLE_PCI
    [[maybe_unused]] kern_return_t OpenPCIProvider(
        SwifterKitRuntimeService* service,
        const IOService* provider,
        SwifterKitRuntimeService_IVars* state) {
        if (service == nullptr || provider == nullptr || state == nullptr) {
            return kIOReturnBadArgument;
        }
        state->pciDevice = OSDynamicCast(IOPCIDevice, provider);
        if (state->pciDevice == nullptr) {
            return kIOReturnBadArgument;
        }
        state->pciDevice->retain();
        const kern_return_t result = state->pciDevice->Open(service, 0);
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(state->pciDevice);
        }
        return result;
    }

    void ClosePCIProvider(
        SwifterKitRuntimeService* service,
        SwifterKitRuntimeService_IVars* state) {
        if (service != nullptr && state != nullptr && state->pciDevice != nullptr) {
            state->pciDevice->Close(service, 0);
            OSSafeReleaseNULL(state->pciDevice);
        }
    }
#endif
}  // namespace

void SwifterKitRuntimeService::free() {
    if (ivars != nullptr) {
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
        StopSCSI();
        IOLockFreeZero(ivars->scsiLock);
        OSSafeReleaseNULL(ivars->scsiTargetQueue);
#endif
#if SWIFTERKIT_ENABLE_AUDIO
        StopAudio();
        IOLockFreeZero(ivars->audioLock);
        IOLockFreeZero(ivars->audioRequestLock);
#endif
#if SWIFTERKIT_ENABLE_VIDEO
        StopVideo();
        IOLockFreeZero(ivars->videoLock);
        IOLockFreeZero(ivars->videoRequestLock);
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
        StopNetwork();
        IOLockFreeZero(ivars->networkLock);
#endif
#if SWIFTERKIT_ENABLE_MIDI
        StopMIDI();
        IOLockFreeZero(ivars->midiLock);
#endif
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
        StopBlockStorage();
        IOLockFreeZero(ivars->blockStorageLock);
#endif
#if SWIFTERKIT_ENABLE_SERIAL
        StopSerial();
        IOLockFreeZero(ivars->serialLock);
#endif
#if SWIFTERKIT_ENABLE_MEMORY
        StopMemory();
        IOLockFreeZero(ivars->memoryLock);
#endif
#if SWIFTERKIT_ENABLE_INTERRUPTS
        StopInterrupts();
#endif
#if SWIFTERKIT_ENABLE_USB
        CloseUSBProvider(this, ivars);
        ReleaseUSBTransfers();
        IOLockFreeZero(ivars->usbLock);
#endif
#if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
#endif
#if SWIFTERKIT_ENABLE_HID
        StopHID();
        IORecursiveLockFreeZero(ivars->hidLock);
#endif
        StopPower();
        StopTimers();
        StopWatches();
        StopReporting();
        IOLockFreeZero(ivars->dispatchLock);
        OSSafeReleaseNULL(ivars->eventClient);
        OSSafeReleaseNULL(ivars->requiredEvents);
        OSSafeReleaseNULL(ivars->events);
        IOLockFreeZero(ivars->eventLock);
    }
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeService_IVars, 1);
    super::free();
}

#if !SWIFTERKIT_ENABLE_HID
auto SwifterKitRuntimeService::Start_Impl(IOService* provider) -> kern_return_t {
    kern_return_t result = Start(provider, SUPERDISPATCH);
    if (result != kIOReturnSuccess) {
        return result;
    }

    // Reporters publish their legend first; if a later step fails, free() releases them.
    result = StartReporting();
    if (result != kIOReturnSuccess) {
        StopReporting();
        Stop(provider, SUPERDISPATCH);
        return result;
    }

    #if SWIFTERKIT_ENABLE_MIDI
    result = StartMIDI();
    if (result != kIOReturnSuccess) {
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_SERIAL
    result = StartSerial();
    if (result != kIOReturnSuccess) {
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_USB
    result = OpenUSBProvider(this, provider, ivars);
    if (result != kIOReturnSuccess) {
        #if SWIFTERKIT_ENABLE_MIDI
        StopMIDI();
        #endif
        #if SWIFTERKIT_ENABLE_SERIAL
        StopSerial();
        #endif
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_PCI
    result = OpenPCIProvider(this, provider, ivars);
    if (result != kIOReturnSuccess) {
        #if SWIFTERKIT_ENABLE_USB
        CloseUSBProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_MIDI
        StopMIDI();
        #endif
        #if SWIFTERKIT_ENABLE_SERIAL
        StopSerial();
        #endif
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_MEMORY
    result = StartMemory(provider);
    if (result != kIOReturnSuccess) {
        #if SWIFTERKIT_ENABLE_USB
        CloseUSBProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_MIDI
        StopMIDI();
        #endif
        #if SWIFTERKIT_ENABLE_SERIAL
        StopSerial();
        #endif
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_INTERRUPTS
    result = StartInterrupts(provider);
    if (result != kIOReturnSuccess) {
        #if SWIFTERKIT_ENABLE_MEMORY
        StopMemory();
        #endif
        #if SWIFTERKIT_ENABLE_USB
        CloseUSBProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_MIDI
        StopMIDI();
        #endif
        #if SWIFTERKIT_ENABLE_SERIAL
        StopSerial();
        #endif
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_VIDEO
    result = StartVideo();
    if (result != kIOReturnSuccess) {
        StopVideo();
        #if SWIFTERKIT_ENABLE_INTERRUPTS
        StopInterrupts();
        #endif
        #if SWIFTERKIT_ENABLE_MEMORY
        StopMemory();
        #endif
        #if SWIFTERKIT_ENABLE_USB
        CloseUSBProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
        #endif
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_AUDIO
    result = StartAudio();
    if (result != kIOReturnSuccess) {
        StopAudio();
        #if SWIFTERKIT_ENABLE_INTERRUPTS
        StopInterrupts();
        #endif
        #if SWIFTERKIT_ENABLE_MEMORY
        StopMemory();
        #endif
        #if SWIFTERKIT_ENABLE_USB
        CloseUSBProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_MIDI
        StopMIDI();
        #endif
        #if SWIFTERKIT_ENABLE_SERIAL
        StopSerial();
        #endif
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_NETWORKING
    result = StartNetwork();
    if (result != kIOReturnSuccess) {
        StopNetwork();
        #if SWIFTERKIT_ENABLE_AUDIO
        StopAudio();
        #endif
        #if SWIFTERKIT_ENABLE_INTERRUPTS
        StopInterrupts();
        #endif
        #if SWIFTERKIT_ENABLE_MEMORY
        StopMemory();
        #endif
        #if SWIFTERKIT_ENABLE_USB
        CloseUSBProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
        #endif
        #if SWIFTERKIT_ENABLE_MIDI
        StopMIDI();
        #endif
        #if SWIFTERKIT_ENABLE_SERIAL
        StopSerial();
        #endif
        Stop(provider, SUPERDISPATCH);
        return result;
    }
    #endif

    #if SWIFTERKIT_ENABLE_BLOCK_STORAGE
    result = RegisterDext();
    #else
    result = RegisterService();
    #endif
    if (result != kIOReturnSuccess) {
    #if SWIFTERKIT_ENABLE_NETWORKING
        StopNetwork();
    #endif
    #if SWIFTERKIT_ENABLE_AUDIO
        StopAudio();
    #endif
    #if SWIFTERKIT_ENABLE_VIDEO
        StopVideo();
    #endif
    #if SWIFTERKIT_ENABLE_INTERRUPTS
        StopInterrupts();
    #endif
    #if SWIFTERKIT_ENABLE_MEMORY
        StopMemory();
    #endif
    #if SWIFTERKIT_ENABLE_USB
        CloseUSBProvider(this, ivars);
    #endif
    #if SWIFTERKIT_ENABLE_PCI
        ClosePCIProvider(this, ivars);
    #endif
    #if SWIFTERKIT_ENABLE_MIDI
        StopMIDI();
    #endif
    #if SWIFTERKIT_ENABLE_SERIAL
        StopSerial();
    #endif
        Stop(provider, SUPERDISPATCH);
    }
    return result;
}
#endif

auto SwifterKitRuntimeService::Stop_Impl(IOService* provider) -> kern_return_t {
    DetachEventClient(nullptr);
#if SWIFTERKIT_ENABLE_HID
    StopHID();
#endif
    StopPower();
    StopTimers();
    StopWatches();
    StopReporting();
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
    StopSCSI();
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
    StopNetwork();
#endif
#if SWIFTERKIT_ENABLE_AUDIO
    StopAudio();
#endif
#if SWIFTERKIT_ENABLE_VIDEO
    StopVideo();
#endif
#if SWIFTERKIT_ENABLE_MIDI
    StopMIDI();
#endif
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
    StopBlockStorage();
#endif
#if SWIFTERKIT_ENABLE_SERIAL
    StopSerial();
#endif
#if SWIFTERKIT_ENABLE_MEMORY
    StopMemory();
#endif
#if SWIFTERKIT_ENABLE_INTERRUPTS
    StopInterrupts();
#endif
#if SWIFTERKIT_ENABLE_USB
    CloseUSBProvider(this, ivars);
#endif
#if SWIFTERKIT_ENABLE_PCI
    ClosePCIProvider(this, ivars);
#endif
    return Stop(provider, SUPERDISPATCH);
}
