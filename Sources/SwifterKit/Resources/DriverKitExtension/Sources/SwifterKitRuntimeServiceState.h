#ifndef SwifterKitRuntimeServiceState_h
#define SwifterKitRuntimeServiceState_h

#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOTimerDispatchSource.h>
#include <DriverKit/OSAction.h>
#include <DriverKit/OSArray.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeDispatchProtocol.h"
#include "SwifterKitRuntimeReportingProtocol.h"

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

#if SWIFTERKIT_ENABLE_HID
    #include "SwifterKitRuntimeHIDProtocol.h"
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
    #include <NetworkingDriverKit/IOUserNetworkPacketPoller.h>
    #include <NetworkingDriverKit/NetworkingDriverKit.h>
#endif

class IODispatchSource;
class IOHIDInterface;
class IOMemoryDescriptor;
class IOReporter;
class IOService;
class SwifterKitRuntimeUserClient;

// A timer Swift started; see SwifterKitRuntimeTimers.cpp. A zero timerID marks a free slot.
struct SwifterKitTimerSlot {
    uint32_t timerID = 0;
    uint64_t interval = 0;
    uint64_t leeway = 0;
    uint64_t deadline = 0;
    uint64_t fireCount = 0;
    IOTimerDispatchSource* source = nullptr;
    OSAction* action = nullptr;
};

// A service-matching or system-state watch; see SwifterKitRuntimeServiceWatches.cpp. A zero
// watchID marks a free slot. stateService and items are set only for system-state watches.
struct SwifterKitServiceWatch {
    uint32_t watchID = 0;
    uint64_t sequence = 0;
    IODispatchSource* source = nullptr;
    OSAction* action = nullptr;
    IOService* stateService = nullptr;
    OSArray* items = nullptr;
};

#if SWIFTERKIT_ENABLE_AUDIO
class SwifterKitRuntimeAudioDevice;
class SwifterKitRuntimeAudioBox;
class SwifterKitRuntimeAudioClockDevice;

// A box-acquisition or clock sample-rate change waiting for Swift; request ID zero is free.
// The request holds a reference on its box or clock device until it ends.
struct SwifterKitAudioPendingRequest {
    OSObject* object;
    uint32_t requestID;
    uint32_t kind;
    uint32_t index;
    uint64_t value;
    // The value a rejection restores: the previous sample rate for a clock request.
    uint64_t previous;
    uint64_t deadline;
};
#endif
#if SWIFTERKIT_ENABLE_VIDEO
class SwifterKitRuntimeVideoDevice;
class SwifterKitRuntimeVideoBox;
class SwifterKitRuntimeVideoClockDevice;

// A box-acquisition or clock sample-rate change waiting for Swift; request ID zero is free.
// The request holds a reference on its box or clock device until it ends.
struct SwifterKitVideoPendingRequest {
    OSObject* object;
    uint32_t requestID;
    uint32_t kind;
    uint32_t index;
    uint64_t value;
    // The value a rejection restores: the previous sample rate for a clock request.
    uint64_t previous;
    uint64_t deadline;
};
#endif

#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOMemoryMap.h>
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

// DLT_EN10MB with a 14-byte Ethernet header. The BPF_MODE_* tap directions come from
// RuntimeSchema+Networking.swift.
static constexpr uint32_t kSwifterKitEthernetDataLinkType = 1;
static constexpr uint32_t kSwifterKitEthernetHeaderLength = 14;
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
    // Set only with kSwifterKitSCSIProvidesTaskDataBuffers; owned by the slot and released when
    // the task completes. Read and written under scsiLock.
    IOBufferMemoryDescriptor* dataBuffer = nullptr;
    IOMemoryMap* dataMap = nullptr;
};
#endif

#if SWIFTERKIT_ENABLE_USB
// One outstanding AsyncIO or IsochIO request. The slot owns the pipe, buffers, and action from
// submission until its completion event is queued; see SwifterKitRuntimeUSBPipes.cpp.
struct SwifterKitUSBPendingTransfer {
    uint32_t requestID = 0;
    // The endpoint address, or bmRequestType for an asynchronous control request.
    uint8_t endpoint = 0;
    bool active = false;
    bool isochronous = false;
    bool deviceRequest = false;
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

// One descriptor-ring entry of a bundled-I/O pipe; see SwifterKitRuntimeUSBBundled.cpp.
enum class SwifterKitUSBBundleEntryState : uint8_t {
    Idle,
    InFlight,
    Completed
};

struct SwifterKitUSBBundleEntry {
    SwifterKitUSBBundleEntryState state = SwifterKitUSBBundleEntryState::Idle;
    int32_t status = 0;
    uint32_t bytesTransferred = 0;
    uint64_t sequence = 0;
    IOBufferMemoryDescriptor* buffer = nullptr;
    IOMemoryMap* map = nullptr;
};

struct SwifterKitUSBBundleRing {
    bool reserved = false;
    bool ready = false;
    uint8_t endpoint = 0;
    uint32_t generation = 0;
    uint32_t entryCount = 0;
    uint32_t bufferLength = 0;
    IOUSBHostPipe* pipe = nullptr;
    OSAction* action = nullptr;
    SwifterKitUSBBundleEntry entries[kSwifterKitUSBMaximumBundleRingEntries] = {};
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

#if SWIFTERKIT_ENABLE_HID
// A host get-report request Swift answers; see SwifterKitRuntimeHIDRequests.cpp. A zero
// requestID marks a free slot.
struct SwifterKitHIDPendingReport {
    uint32_t requestID = 0;
    uint32_t capacity = 0;
    OSAction* action = nullptr;
    IOMemoryDescriptor* report = nullptr;
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
    // Swift's timers and watches. Slots and identifiers change only under dispatchLock.
    IOLock* dispatchLock = nullptr;
    uint32_t nextTimerID = 1;
    uint32_t nextWatchID = 1;
    SwifterKitTimerSlot timers[kSwifterKitMaximumTimers] = {};
    SwifterKitServiceWatch watches[kSwifterKitMaximumServiceWatches] = {};
    // The configured reporters, created in StartReporting and released in StopReporting; the
    // array holds the same reporters for configureAllReports. Both change under dispatchLock.
    OSArray* reporterSet = nullptr;
    IOReporter* reporters[kSwifterKitMaximumReporters] = {};
#if SWIFTERKIT_ENABLE_HID
    uint64_t hidInputReportAttempts = 0;
    uint64_t hidInputReportSuccesses = 0;
    uint64_t hidInputReportFailures = 0;
    // Serializes element access and event dispatch between the service queue and Swift's
    // commands, and guards the pending get-report table. Recursive because handleReport runs
    // inside processReport.
    IORecursiveLock* hidLock = nullptr;
    IOHIDInterface* hidInterface = nullptr;
    uint32_t hidEventDriverHandling = 0;
    uint32_t nextHIDRequestID = 1;
    SwifterKitHIDPendingReport hidRequests[kSwifterKitHIDMaximumPendingReports] = {};
#endif
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER
    IOLock* scsiLock = nullptr;
    // Runs UserCreateTargetForID away from the user client's queue; see SCSIControlCommand.
    IODispatchQueue* scsiTargetQueue = nullptr;
    uint32_t nextSCSIRequestID = 1;
    uint32_t nextSCSITaskMapID = 1;
    SwifterKitSCSIPendingTask scsiTasks[256] = {};
#endif
#if SWIFTERKIT_ENABLE_AUDIO
    IOLock* audioLock = nullptr;
    SwifterKitRuntimeAudioDevice* audioDevice = nullptr;
    // Boxes and clock devices by configuration index, and the box (index + 1) that owns the
    // device or each clock device; zero means unowned. All guarded by audioLock.
    SwifterKitRuntimeAudioBox* audioBoxes[kSwifterKitAudioObjectTableCount] = {};
    SwifterKitRuntimeAudioClockDevice* audioClockDevices[kSwifterKitAudioObjectTableCount] = {};
    uint8_t audioDeviceOwner = 0;
    uint8_t audioClockOwners[kSwifterKitAudioObjectTableCount] = {};
    // Requests Swift must answer, guarded by audioRequestLock.
    IOLock* audioRequestLock = nullptr;
    SwifterKitAudioPendingRequest audioRequests[kSwifterKitAudioPendingRequestCount] = {};
    uint32_t nextAudioRequestID = 1;
    bool audioRequestsStopped = true;
    IOTimerDispatchSource* audioRequestTimer = nullptr;
    OSAction* audioRequestTimerAction = nullptr;
#endif
#if SWIFTERKIT_ENABLE_VIDEO
    IOLock* videoLock = nullptr;
    SwifterKitRuntimeVideoDevice* videoDevice = nullptr;
    // Boxes and clock devices by configuration index, and the box (index + 1) that owns the
    // device or each clock device; zero means unowned. All guarded by videoLock.
    SwifterKitRuntimeVideoBox* videoBoxes[kSwifterKitVideoObjectTableCount] = {};
    SwifterKitRuntimeVideoClockDevice* videoClockDevices[kSwifterKitVideoObjectTableCount] = {};
    uint8_t videoDeviceOwner = 0;
    uint8_t videoClockOwners[kSwifterKitVideoObjectTableCount] = {};
    // Requests Swift must answer, guarded by videoRequestLock.
    IOLock* videoRequestLock = nullptr;
    SwifterKitVideoPendingRequest videoRequests[kSwifterKitVideoPendingRequestCount] = {};
    uint32_t nextVideoRequestID = 1;
    bool videoRequestsStopped = true;
    IOTimerDispatchSource* videoRequestTimer = nullptr;
    OSAction* videoRequestTimerAction = nullptr;
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
    IOLock* networkLock = nullptr;
    IODispatchQueue* networkQueue = nullptr;
    IOUserNetworkPacketBufferPool* networkPool = nullptr;
    IOUserNetworkPacketBufferPool* networkRxPool = nullptr;
    IOUserNetworkPacketPoller* networkPoller = nullptr;
    uint32_t networkTapMode = 0;
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
    // The one private interface command waiting for Swift; changes only under networkLock.
    uint32_t networkCommandID = 0;
    uint32_t nextNetworkCommandID = 1;
    int32_t networkCommandStatus = 0;
    bool networkCommandAnswered = false;
#endif
#if SWIFTERKIT_ENABLE_MIDI
    // Guards the pointers below: StartMIDI and StopMIDI publish and clear them on the service
    // queue while MIDI commands read them on the user-client queue. The destination I/O blocks
    // never take it.
    IOLock* midiLock = nullptr;
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
    uint32_t nextUSBBundleGeneration = 1;
    SwifterKitUSBBundleRing usbBundleRings[kSwifterKitUSBMaximumBundleRings] = {};
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
#if SWIFTERKIT_ENABLE_HID
static_assert(kSwifterKitMaximumQueuedRequiredEvents > kSwifterKitHIDMaximumPendingReports);
#endif
#if SWIFTERKIT_ENABLE_USB
// Pending transfers and every bundle-ring entry each hold at most one undelivered completion.
static_assert(
    kSwifterKitMaximumQueuedRequiredEvents
    > sizeof(SwifterKitRuntimeService_IVars::usbTransfers) / sizeof(SwifterKitUSBPendingTransfer)
          + size_t {kSwifterKitUSBMaximumBundleRings} * kSwifterKitUSBMaximumBundleRingEntries);
#endif
#if SWIFTERKIT_ENABLE_NETWORKING
static_assert(
    kSwifterKitMaximumQueuedRequiredEvents
    > sizeof(SwifterKitRuntimeService_IVars::networkTransmits)
          / sizeof(SwifterKitNetworkPendingTransmit));
#endif

#endif
