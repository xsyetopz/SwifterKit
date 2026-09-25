#ifndef SwifterKitRuntimeServiceState_h
#define SwifterKitRuntimeServiceState_h

#include <DriverKit/IOLib.h>
#include <DriverKit/IOTimerDispatchSource.h>
#include <DriverKit/OSAction.h>
#include <DriverKit/OSArray.h>

#include "SwifterKitRuntimeConfiguration.h"

#if SWIFTERKIT_ENABLE_SERIAL
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <SerialDriverKit/SerialPortInterface.h>
#endif

#if SWIFTERKIT_ENABLE_USB
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSAction.h>
    #include <USBDriverKit/IOUSBHostDevice.h>
    #include <USBDriverKit/IOUSBHostInterface.h>
    #include <USBDriverKit/IOUSBHostPipe.h>

    #include "SwifterKitRuntimeUSBProtocol.h"
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

class SwifterKitRuntimeUserClient;

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

#if SWIFTERKIT_ENABLE_USB
// One outstanding AsyncIO or IsochIO request. The slot owns the pipe, buffers, and action from
// submission until its completion event is queued; see SwifterKitRuntimeUSBPipes.cpp.
struct SwifterKitUSBPendingTransfer {
    uint32_t requestID = 0;
    uint8_t endpoint = 0;
    bool active = false;
    bool isochronous = false;
    bool completed = false;
    uint32_t length = 0;
    uint32_t frameCount = 0;
    int32_t status = 0;
    uint32_t bytesTransferred = 0;
    uint64_t timestamp = 0;
    uint64_t sequence = 0;
    OSAction* action = nullptr;
    IOUSBHostPipe* pipe = nullptr;
    IOBufferMemoryDescriptor* buffer = nullptr;
    IOMemoryMap* map = nullptr;
    IOBufferMemoryDescriptor* frames = nullptr;
    IOMemoryMap* frameMap = nullptr;
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

// Lossy events are notifications Swift may miss; required events carry
// DriverKit work that Swift must answer. See SwifterKitRuntimeEvents.cpp.
static constexpr uint32_t kSwifterKitMaximumQueuedLossyEvents = 64;
static constexpr uint32_t kSwifterKitMaximumQueuedRequiredEvents = 512;

struct SwifterKitRuntimeService_IVars {
    IOLock* eventLock = nullptr;
    OSArray* events = nullptr;
    OSArray* requiredEvents = nullptr;
    uint64_t lossyEventDrops = 0;
    // The registered host's user client (retained) and whether an enqueue must
    // notify it. Both change only under eventLock; see SwifterKitRuntimeEvents.cpp.
    SwifterKitRuntimeUserClient* eventClient = nullptr;
    bool eventNotificationArmed = false;
    // The unacknowledged SetPowerState request, guarded by eventLock, and its timeout timer,
    // used only on the default queue. See SwifterKitRuntimeServicePower.cpp.
    bool powerPending = false;
    bool powerStopped = false;
    uint32_t powerRequestID = 0;
    uint32_t nextPowerRequestID = 1;
    uint32_t powerFlags = 0;
    uint64_t powerDeadline = 0;
    IOTimerDispatchSource* powerTimer = nullptr;
    OSAction* powerTimerAction = nullptr;
#if SWIFTERKIT_ENABLE_HID
    uint64_t hidInputReportAttempts = 0;
    uint64_t hidInputReportSuccesses = 0;
    uint64_t hidInputReportFailures = 0;
#endif
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
    IOLock* usbLock = nullptr;
    IOUSBHostDevice* usbDevice = nullptr;
    IOUSBHostInterface* usbInterface = nullptr;
    uint32_t nextUSBRequestID = 1;
    uint64_t nextUSBCompletionSequence = 0;
    SwifterKitUSBPendingTransfer usbTransfers[kSwifterKitUSBMaximumPendingTransfers] = {};
#endif
#if SWIFTERKIT_ENABLE_PCI
    IOPCIDevice* pciDevice = nullptr;
    // Memory indices and sizes of BAR0...BAR5, read lazily from GetBARInfo to bound aperture
    // accesses. The expansion ROM has no reported size and is never cached.
    bool pciAperturesLoaded = false;
    uint8_t pciApertureCount = 0;
    uint8_t pciApertureIndices[6] = {};
    uint64_t pciApertureSizes[6] = {};
#endif
#if SWIFTERKIT_ENABLE_INTERRUPTS
    IOService* interruptProvider = nullptr;
    IODispatchQueue* interruptQueue = nullptr;
    IOInterruptDispatchSource* interruptSources[32] = {};
    OSAction* interruptActions[32] = {};
#endif
};

// Each tracked request table fills before the required queue does, so tracked
// requests alone cannot exhaust it; that takes a stalled Swift host plus
// untracked required notifications such as control changes.
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
static_assert(
    kSwifterKitMaximumQueuedRequiredEvents
    > sizeof(SwifterKitRuntimeService_IVars::scsiTasks) / sizeof(SwifterKitSCSIPendingTask));
#endif
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
static_assert(
    kSwifterKitMaximumQueuedRequiredEvents
    > sizeof(SwifterKitRuntimeService_IVars::blockStorageRequests)
          / sizeof(SwifterKitBlockStoragePendingRequest));
#endif
#if SWIFTERKIT_ENABLE_USB
static_assert(
    kSwifterKitMaximumQueuedRequiredEvents
    > sizeof(SwifterKitRuntimeService_IVars::usbTransfers) / sizeof(SwifterKitUSBPendingTransfer));
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
static_assert(
    kSwifterKitMaximumQueuedRequiredEvents
    > sizeof(SwifterKitRuntimeService_IVars::networkTransmits)
          / sizeof(SwifterKitNetworkPendingTransmit));
#endif

#endif
