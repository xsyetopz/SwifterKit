#ifndef SwifterKitRuntimeServiceState_h
#define SwifterKitRuntimeServiceState_h

#include <DriverKit/IOLib.h>
#include <DriverKit/OSArray.h>

#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_SERIAL
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <SerialDriverKit/SerialPortInterface.h>
#endif

#if SWIFTERKIT_ENABLE_USB
    #include <USBDriverKit/IOUSBHostInterface.h>
#endif

#if SWIFTERKIT_ENABLE_PCI
    #include <PCIDriverKit/IOPCIDevice.h>
#endif

#if SWIFTERKIT_ENABLE_MEMORY
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IODMACommand.h>
    #include <DriverKit/IOMemoryMap.h>
#endif

#if SWIFTERKIT_ENABLE_INTERRUPTS
    #include <DriverKit/IODispatchQueue.h>
    #include <DriverKit/IOInterruptDispatchSource.h>
    #include <DriverKit/OSAction.h>
#endif

#if SWIFTERKIT_ENABLE_NETWORKING
    #include <DriverKit/IODispatchQueue.h>
    #include <DriverKit/OSAction.h>
    #include <NetworkingDriverKit/NetworkingDriverKit.h>
#endif

#if SWIFTERKIT_ENABLE_AUDIO
class SwifterKitRuntimeAudioDevice;
#endif
#if SWIFTERKIT_ENABLE_VIDEO
class SwifterKitRuntimeVideoDevice;
#endif

#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
    #include <DriverKit/OSAction.h>
#endif

#if SWIFTERKIT_ENABLE_MIDI
class IOUserMIDIDevice;
class IOUserMIDIEntity;
class IOUserMIDISource;
class IOUserMIDIDestination;
#endif

#if SWIFTERKIT_ENABLE_NETWORKING
struct SwifterKitNetworkPendingTransmit {
    uint32_t requestID = 0;
    IOUserNetworkPacket* packet = nullptr;
};
#endif

#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
struct SwifterKitBlockStoragePendingRequest {
    uint32_t requestID = 0;
    uint64_t maximumByteCount = 0;
    bool isIO = false;
    bool active = false;
};
#endif

#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
struct SwifterKitSCSIPendingTask {
    uint32_t requestID = 0;
    uint64_t targetIdentifier = 0;
    uint64_t controllerTaskIdentifier = 0;
    uint64_t requestedTransferCount = 0;
    uint32_t featureRequestCount = 0;
    OSAction* completion = nullptr;
};
#endif

#if SWIFTERKIT_ENABLE_MEMORY
struct SwifterKitMemoryEntry {
    uint64_t handle = 0;
    uint64_t capacity = 0;
    uint64_t length = 0;
    uint32_t direction = 0;
    uint32_t alignment = 0;
    IOBufferMemoryDescriptor* descriptor = nullptr;
    IOMemoryMap* map = nullptr;
    IODMACommand* dmaCommand = nullptr;
};
#endif

struct SwifterKitRuntimeService_IVars {
    IOLock* eventLock = nullptr;
    OSArray* events = nullptr;
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
    IOLock* scsiLock = nullptr;
    uint32_t nextSCSIRequestID = 1;
    uint32_t nextSCSITaskMapID = 1;
    SwifterKitSCSIPendingTask scsiTasks[256] = {};
#endif
#if SWIFTERKIT_ENABLE_AUDIO
    IOLock* audioLock = nullptr;
    SwifterKitRuntimeAudioDevice* audioDevice = nullptr;
#endif
#if SWIFTERKIT_ENABLE_VIDEO
    IOLock* videoLock = nullptr;
    SwifterKitRuntimeVideoDevice* videoDevice = nullptr;
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
    IOLock* networkLock = nullptr;
    IODispatchQueue* networkQueue = nullptr;
    IOUserNetworkPacketBufferPool* networkPool = nullptr;
    IOUserNetworkTxSubmissionQueue* networkTxSubmission = nullptr;
    IOUserNetworkTxCompletionQueue* networkTxCompletion = nullptr;
    IOUserNetworkRxSubmissionQueue* networkRxSubmission = nullptr;
    IOUserNetworkRxCompletionQueue* networkRxCompletion = nullptr;
    OSAction* networkTxAction = nullptr;
    uint32_t nextNetworkRequestID = 1;
    bool networkEnabled = false;
    bool networkStopping = false;
    uint8_t networkAddress[6] = {};
    SwifterKitNetworkPendingTransmit networkTransmits[64] = {};
#endif
#if SWIFTERKIT_ENABLE_MIDI
    IOUserMIDIDevice* midiDevice = nullptr;
    IOUserMIDIEntity* midiEntity = nullptr;
    IOUserMIDISource* midiSources[32] = {};
    IOUserMIDIDestination* midiDestinations[32] = {};
#endif
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
    IOLock* blockStorageLock = nullptr;
    SwifterKitBlockStoragePendingRequest blockStorageRequests[64] = {};
#endif
#if SWIFTERKIT_ENABLE_MEMORY
    IOLock* memoryLock = nullptr;
    IOService* memoryProvider = nullptr;
    uint64_t nextMemoryHandle = 1;
    uint64_t allocatedMemory = 0;
    SwifterKitMemoryEntry memoryEntries[64] = {};
#endif
#if SWIFTERKIT_ENABLE_SERIAL
    IOLock* serialLock = nullptr;
    IOBufferMemoryDescriptor* serialArenaDescriptor = nullptr;
    IOMemoryDescriptor* serialReceiveDescriptor = nullptr;
    IOMemoryDescriptor* serialTransmitDescriptor = nullptr;
    IOMemoryMap* serialArenaMap = nullptr;
    IOMemoryMap* serialReceiveMap = nullptr;
    IOMemoryMap* serialTransmitMap = nullptr;
    driverkit::serial::SerialPortInterface* serialInterface = nullptr;
    bool serialConnected = false;
    bool serialCTS = false;
    bool serialDSR = false;
    bool serialRI = false;
    bool serialDCD = false;
#endif
#if SWIFTERKIT_ENABLE_USB
    IOUSBHostInterface* usbInterface = nullptr;
#endif
#if SWIFTERKIT_ENABLE_PCI
    IOPCIDevice* pciDevice = nullptr;
#endif
#if SWIFTERKIT_ENABLE_INTERRUPTS
    IOService* interruptProvider = nullptr;
    IODispatchQueue* interruptQueue = nullptr;
    IOInterruptDispatchSource* interruptSources[32] = {};
    OSAction* interruptActions[32] = {};
#endif
};

#endif
