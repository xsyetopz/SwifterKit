#ifndef SwifterKitRuntimeConfiguration_h
#define SwifterKitRuntimeConfiguration_h

#include <stdint.h>

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
static constexpr char kSwifterKitBundleIdentifier[] = "";
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
#define SWIFTERKIT_ENABLE_NETWORKING 0
#define SWIFTERKIT_ENABLE_AUDIO 0
#define SWIFTERKIT_ENABLE_VIDEO 0
#define SWIFTERKIT_ENABLE_SCSI_CONTROLLER 0
#define SWIFTERKIT_ENABLE_SCSI_PERIPHERAL 0
#define SWIFTERKIT_SCSI_PERIPHERAL_TYPE 0
#define SWIFTERKIT_ENABLE_MIDI 0
#define SWIFTERKIT_ENABLE_BLOCK_STORAGE 0
#define SWIFTERKIT_ENABLE_SERIAL 0
#define SWIFTERKIT_ENABLE_USB 0
#define SWIFTERKIT_ENABLE_PCI 0
#define SWIFTERKIT_ENABLE_INTERRUPTS 0
#define SWIFTERKIT_ENABLE_MEMORY 0

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
static constexpr bool kSwifterKitSCSIPeripheralInitializationSucceeds = false;

static constexpr uint8_t kSwifterKitEthernetAddress[] = {0, 0, 0, 0, 0, 0};
static constexpr uint32_t kSwifterKitEthernetMTU = 0;
static constexpr uint32_t kSwifterKitEthernetPacketBufferSize = 0;
static constexpr uint32_t kSwifterKitEthernetPacketCount = 0;
static constexpr uint32_t kSwifterKitEthernetQueueCapacity = 0;
static constexpr uint32_t kSwifterKitEthernetHardwareAssists = 0;
static constexpr uint32_t kSwifterKitEthernetMedia[] = {0};
static constexpr uint32_t kSwifterKitEthernetMediaCount = 0;
static constexpr uint32_t kSwifterKitEthernetInitialMedia = 0;
static constexpr bool kSwifterKitEthernetWakeOnMagicPacket = false;

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
static constexpr uint32_t kSwifterKitHIDHostReportOutput = 1U << 0;
static constexpr uint32_t kSwifterKitHIDHostReportFeature = 1U << 1;
static constexpr uint32_t kSwifterKitHIDAcceptedHostReportTypes = 3;

#endif
