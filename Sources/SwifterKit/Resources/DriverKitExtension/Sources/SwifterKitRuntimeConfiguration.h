#ifndef SwifterKitRuntimeConfiguration_h
#define SwifterKitRuntimeConfiguration_h

#include <stdint.h>

static constexpr char kSwifterKitBundleIdentifier[] = "";

struct SwifterKitAudioFormatConfiguration {
    double sampleRate;
    uint32_t formatID;
    uint32_t formatFlags;
    uint32_t bytesPerPacket;
    uint32_t framesPerPacket;
    uint32_t bytesPerFrame;
    uint32_t channelsPerFrame;
    uint32_t bitsPerChannel;
};
struct SwifterKitAudioStreamConfiguration {
    uint32_t direction;
    const char* name;
    uint32_t formatStart;
    uint32_t formatCount;
    uint32_t initialFormatIndex;
    uint32_t ringBufferFrameCapacity;
};
static constexpr char kSwifterKitAudioDeviceUID[] = "";
static constexpr char kSwifterKitAudioModelUID[] = "";
static constexpr char kSwifterKitAudioManufacturerUID[] = "";
static constexpr char kSwifterKitAudioDeviceName[] = "";
static constexpr uint32_t kSwifterKitAudioTransport = 0;
static constexpr bool kSwifterKitAudioSupportsPrewarming = false;
static constexpr uint32_t kSwifterKitAudioZeroTimestampPeriod = 0;
static constexpr double kSwifterKitAudioSampleRates[] = {0};
static constexpr uint32_t kSwifterKitAudioSampleRateCount = 0;
static constexpr double kSwifterKitAudioInitialSampleRate = 0;
static constexpr SwifterKitAudioFormatConfiguration kSwifterKitAudioFormats[1] = {};
static constexpr SwifterKitAudioStreamConfiguration kSwifterKitAudioStreams[1] = {};
static constexpr uint32_t kSwifterKitAudioStreamCount = 0;

struct SwifterKitVideoFormatConfiguration {
    double frameRate;
    uint64_t frameTimeValue;
    uint32_t frameTimeScale;
    uint32_t codec;
    uint32_t codecFlags;
    uint32_t width;
    uint32_t height;
};
struct SwifterKitVideoStreamConfiguration {
    const char* identifier;
    uint32_t direction;
    uint32_t formatStart;
    uint32_t formatCount;
    uint32_t initialFormatIndex;
    uint32_t bufferCount;
    uint32_t dataBufferCapacity;
    uint32_t controlBufferCapacity;
};
static constexpr char kSwifterKitVideoDeviceUID[] = "";
static constexpr char kSwifterKitVideoModelUID[] = "";
static constexpr char kSwifterKitVideoManufacturerUID[] = "";
static constexpr char kSwifterKitVideoDeviceName[] = "";
static constexpr uint32_t kSwifterKitVideoTransport = 0;
static constexpr double kSwifterKitVideoSampleRates[] = {0};
static constexpr uint32_t kSwifterKitVideoSampleRateCount = 0;
static constexpr double kSwifterKitVideoInitialSampleRate = 0;
static constexpr SwifterKitVideoFormatConfiguration kSwifterKitVideoFormats[1] = {};
static constexpr SwifterKitVideoStreamConfiguration kSwifterKitVideoStreams[1] = {};
static constexpr uint32_t kSwifterKitVideoStreamCount = 0;

#define SWIFTERKIT_ENABLE_HID 0
#define SWIFTERKIT_HID_DEVICE 0
#define SWIFTERKIT_HID_USB_DEVICE 0
#define SWIFTERKIT_HID_EVENT_SERVICE 0
#define SWIFTERKIT_HID_EVENT_DRIVER 0
#define SWIFTERKIT_ENABLE_NETWORKING 0
#define SWIFTERKIT_ENABLE_AUDIO 0
#define SWIFTERKIT_ENABLE_VIDEO 0
#define SWIFTERKIT_ENABLE_SCSI_CONTROLLER 0
#define SWIFTERKIT_ENABLE_SCSI_PERIPHERAL 0
#define SWIFTERKIT_SCSI_PERIPHERAL_TYPE 0
#define SWIFTERKIT_ENABLE_MIDI 0
#define SWIFTERKIT_ENABLE_BLOCK_STORAGE 0
#define SWIFTERKIT_ENABLE_SERIAL 0
// True when the serial service derives from IOUserUSBSerial on an IOUSBHostInterface.
#define SWIFTERKIT_USB_SERIAL 0
static constexpr bool kSwifterKitUSBSerialOverridesName = false;
static constexpr bool kSwifterKitUSBSerialDeliversReceivedPackets = false;
static constexpr bool kSwifterKitUSBSerialDeliversInterruptPackets = false;
#define SWIFTERKIT_ENABLE_USB 0
#define SWIFTERKIT_ENABLE_PCI 0
#define SWIFTERKIT_ENABLE_INTERRUPTS 0
#define SWIFTERKIT_ENABLE_MEMORY 0

// True when the USB provider is an IOUSBHostDevice rather than an IOUSBHostInterface.
static constexpr bool kSwifterKitUSBDeviceProvider = false;

static constexpr uint64_t kSwifterKitSCSIInitiatorIdentifier = 0;
static constexpr uint64_t kSwifterKitSCSIHighestTargetIdentifier = 0;
static constexpr uint64_t kSwifterKitSCSIHighestLogicalUnitNumber = 0;
static constexpr uint32_t kSwifterKitSCSIMaximumTaskCount = 0;
static constexpr uint64_t kSwifterKitSCSIMaximumTransferSize = 0;
static constexpr uint32_t kSwifterKitSCSIMinimumSegmentAlignment = 0;
static constexpr uint8_t kSwifterKitSCSIAddressBitCount = 0;
static constexpr uint16_t kSwifterKitSCSIDMASegmentType = 0;
static constexpr uint32_t kSwifterKitSCSISupportedFeatures = 0;
static constexpr bool kSwifterKitSCSIPerformsAutoSense = false;
static constexpr bool kSwifterKitSCSISupportsMultipathing = false;
static constexpr uint32_t kSwifterKitSCSITaskManagementResponse = 5;
static constexpr bool kSwifterKitSCSIProvidesTaskDataBuffers = false;
static constexpr bool kSwifterKitSCSIReportsConstraints = false;
static constexpr uint64_t kSwifterKitSCSIMaximumSegmentCountRead = 0;
static constexpr uint64_t kSwifterKitSCSIMaximumSegmentCountWrite = 0;
static constexpr uint64_t kSwifterKitSCSIMaximumSegmentByteCountRead = 0;
static constexpr uint64_t kSwifterKitSCSIMaximumSegmentByteCountWrite = 0;
static constexpr uint64_t kSwifterKitSCSIMinimumSegmentAlignmentByteCount = 0;
static constexpr uint64_t kSwifterKitSCSIMaximumSegmentAddressableBitCount = 0;
static constexpr uint64_t kSwifterKitSCSIMinimumHBADataAlignmentMask = 0;
static constexpr bool kSwifterKitSCSISupportsHierarchicalLogicalUnits = false;
static constexpr bool kSwifterKitSCSIPeripheralInitializationSucceeds = false;

static constexpr uint8_t kSwifterKitEthernetAddress[] = {0, 0, 0, 0, 0, 0};
static constexpr uint32_t kSwifterKitEthernetMTU = 0;
static constexpr uint32_t kSwifterKitEthernetMinimumMTU = 0;
static constexpr uint32_t kSwifterKitEthernetPacketBufferSize = 0;
static constexpr uint32_t kSwifterKitEthernetPacketCount = 0;
static constexpr uint32_t kSwifterKitEthernetRxPacketCount = 0;
static constexpr uint32_t kSwifterKitEthernetBufferCount = 0;
static constexpr uint32_t kSwifterKitEthernetMemorySegmentSize = 0;
static constexpr uint32_t kSwifterKitEthernetPoolFlags = 0;
static constexpr uint32_t kSwifterKitEthernetDMAAddressBits = 64;
static constexpr uint32_t kSwifterKitEthernetQueueCapacity = 0;
static constexpr uint32_t kSwifterKitEthernetHardwareAssists = 0;
static constexpr uint32_t kSwifterKitEthernetFeatureFlags = 0;
static constexpr uint32_t kSwifterKitEthernetTSOMSS4 = 0;
static constexpr uint32_t kSwifterKitEthernetTSOMSS6 = 0;
static constexpr bool kSwifterKitEthernetSoftwareVLAN = false;
static constexpr uint16_t kSwifterKitEthernetTxHeadroom = 0;
static constexpr uint16_t kSwifterKitEthernetTxTailroom = 0;
static constexpr uint16_t kSwifterKitEthernetTxDataOffset = 0;
static constexpr uint32_t kSwifterKitEthernetTxServiceClass = 0xFFFFFFFF;
static constexpr uint32_t kSwifterKitEthernetSubFamily = 0;
static constexpr char kSwifterKitEthernetBSDNamePrefix[] = "";
static constexpr int32_t kSwifterKitEthernetBSDUnitNumber = -1;
static constexpr bool kSwifterKitEthernetPacketTap = false;
static constexpr uint32_t kSwifterKitEthernetMedia[] = {0};
static constexpr uint32_t kSwifterKitEthernetMediaCount = 0;
static constexpr uint32_t kSwifterKitEthernetInitialMedia = 0;
static constexpr bool kSwifterKitEthernetWakeOnMagicPacket = false;
static constexpr bool kSwifterKitEthernetPolling = false;
static constexpr bool kSwifterKitEthernetPollingEnabled = false;
static constexpr uint64_t kSwifterKitEthernetPollDataRate = 0;
static constexpr uint64_t kSwifterKitEthernetPollInterval = 0;

static constexpr uint32_t kSwifterKitMIDIProtocol = 0;
static constexpr uint32_t kSwifterKitMIDISourceCount = 0;
static constexpr uint32_t kSwifterKitMIDIDestinationCount = 0;
static constexpr char kSwifterKitMIDIDriverName[] = "SwifterKit MIDI";
static constexpr char kSwifterKitMIDIDeviceIdentifier[] = "SwifterKit.Device";
static constexpr char kSwifterKitMIDIModelIdentifier[] = "SwifterKit.Model";
static constexpr char kSwifterKitMIDIManufacturerIdentifier[] = "SwifterKit";
static constexpr char kSwifterKitMIDIEntityName[] = "SwifterKit Entity";

static constexpr uint64_t kSwifterKitBlockCount = 0;
static constexpr uint32_t kSwifterKitBlockSize = 0;
static constexpr uint32_t kSwifterKitBlockMaximumIOSize = 0;
static constexpr uint32_t kSwifterKitBlockMaximumOutstandingIOCount = 0;
static constexpr uint32_t kSwifterKitBlockMaximumUnmapRegionCount = 0;
static constexpr uint32_t kSwifterKitBlockMinimumSegmentAlignment = 0;
static constexpr uint8_t kSwifterKitBlockAddressBitCount = 0;
static constexpr bool kSwifterKitBlockSupportsUnmap = false;
static constexpr bool kSwifterKitBlockSupportsFUA = false;
static constexpr bool kSwifterKitBlockIsEjectable = false;
static constexpr bool kSwifterKitBlockIsRemovable = false;
static constexpr bool kSwifterKitBlockIsWriteProtected = false;
static constexpr char kSwifterKitBlockVendor[] = "SwifterKit";
static constexpr char kSwifterKitBlockProduct[] = "Block Device";
static constexpr char kSwifterKitBlockRevision[] = "1.0";
static constexpr char kSwifterKitBlockAdditionalInfo[] = "";

static constexpr uint32_t kSwifterKitMaximumMemoryBuffers = 0;
static constexpr uint64_t kSwifterKitMaximumMemoryBufferSize = 0;
static constexpr uint64_t kSwifterKitMaximumMemoryTotalSize = 0;

static constexpr char kSwifterKitSerialBaseName[] = "SwifterKit";
static constexpr char kSwifterKitSerialSuffix[] = "Serial";
static constexpr bool kSwifterKitSerialInitialCTS = false;
static constexpr bool kSwifterKitSerialInitialDSR = false;
static constexpr bool kSwifterKitSerialInitialRI = false;
static constexpr bool kSwifterKitSerialInitialDCD = false;

static constexpr uint32_t kSwifterKitInterruptIndices[] = {0};
static constexpr uint32_t kSwifterKitInterruptSourceCount = 0;
static constexpr bool kSwifterKitPCIConfigureInterrupts = false;
static constexpr uint32_t kSwifterKitPCIInterruptType = 0;
static constexpr uint32_t kSwifterKitPCIInterruptRequiredVectors = 0;
static constexpr uint32_t kSwifterKitPCIInterruptRequestedVectors = 0;
struct SwifterKitReportChannelConfiguration {
    uint64_t identifier;
    const char* name;
};
struct SwifterKitHistogramSegmentConfiguration {
    uint32_t baseBucketWidth;
    uint32_t scale;
    uint32_t bucketCount;
};
struct SwifterKitReporterConfiguration {
    uint32_t kind;
    uint16_t categories;
    uint64_t unit;
    const char* group;
    const char* subgroup;
    uint32_t channelStart;
    uint32_t channelCount;
    uint32_t stateStart;
    uint32_t stateCount;
    uint32_t segmentStart;
    uint32_t segmentCount;
};
static constexpr SwifterKitReportChannelConfiguration kSwifterKitReportChannels[1] = {};
static constexpr uint64_t kSwifterKitReportStates[1] = {0};
static constexpr SwifterKitHistogramSegmentConfiguration kSwifterKitHistogramSegments[1] = {};
static constexpr SwifterKitReporterConfiguration kSwifterKitReporters[1] = {};
static constexpr uint32_t kSwifterKitReporterCount = 0;
static constexpr bool kSwifterKitReportLegendPublic = false;

static constexpr uint8_t kSwifterKitHIDReportDescriptor[] = {0};
static constexpr uint32_t kSwifterKitHIDReportDescriptorLength = 0;
static constexpr char kSwifterKitHIDTransport[] = "Virtual";
static constexpr uint32_t kSwifterKitHIDVendorID = 0;
static constexpr uint32_t kSwifterKitHIDProductID = 0;
static constexpr uint32_t kSwifterKitHIDVersionNumber = 1;
static constexpr uint32_t kSwifterKitHIDCountryCode = 0;
static constexpr uint32_t kSwifterKitHIDLocationID = 0;
static constexpr char kSwifterKitHIDManufacturer[] = "SwifterKit";
static constexpr char kSwifterKitHIDProduct[] = "SwifterKit Runtime";
static constexpr char kSwifterKitHIDSerialNumber[] = "SwifterKit";
static constexpr uint32_t kSwifterKitHIDPrimaryUsagePage = 0;
static constexpr uint32_t kSwifterKitHIDPrimaryUsage = 0;
static constexpr uint32_t kSwifterKitHIDAcceptedHostReportTypes = 3;
static constexpr uint32_t kSwifterKitHIDAnsweredReportTypes = 0;
static constexpr uint8_t kSwifterKitHIDDeviceProperties[] = {0};
static constexpr uint32_t kSwifterKitHIDDevicePropertiesLength = 0;
static constexpr bool kSwifterKitHIDDeliversDeviceInputReports = false;
static constexpr uint32_t kSwifterKitHIDEventDelivery = 0;
static constexpr uint32_t kSwifterKitHIDEventDriverCategories = 0;

#endif
