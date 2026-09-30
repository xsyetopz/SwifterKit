// Generated from Sources/SwifterKit/DriverKit/Runtime/RuntimeSchema+HID.swift.
// Do not edit.
// Regenerate: SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter RuntimeSchemaTests

#ifndef SwifterKitRuntimeHIDSchema_h
#define SwifterKitRuntimeHIDSchema_h

#include <stdint.h>

static constexpr uint32_t kSwifterKitHIDMaximumPendingReports = 16;
static constexpr uint32_t kSwifterKitHIDMaximumFactoryDevices = 32;
static constexpr uint32_t kSwifterKitHIDFactoryDeviceHeaderSize = 64;
static constexpr uint32_t kSwifterKitHIDFactoryHandleSize = 8;
static constexpr uint32_t kSwifterKitHIDMaximumElementPage = 512;
static constexpr uint32_t kSwifterKitHIDMaximumCookies = 1024;
static constexpr uint32_t kSwifterKitHIDMaximumCollectionElements = 64;
static constexpr uint32_t kSwifterKitHIDMaximumTouches = 64;
static constexpr uint32_t kSwifterKitHIDMaximumEventValues = 256;
static constexpr uint32_t kSwifterKitHIDLEDUsagePage = 0x08;

enum class SwifterKitHIDElementWriteKind : uint32_t {
    Value = 0,
    Data = 1,
};

static constexpr uint32_t kSwifterKitHIDHostReportOutput = 0x1;
static constexpr uint32_t kSwifterKitHIDHostReportFeature = 0x2;
static constexpr uint32_t kSwifterKitHIDHostReportTypesAll = 0x3;
static constexpr uint32_t kSwifterKitHIDGetReportInput = 0x1;
static constexpr uint32_t kSwifterKitHIDGetReportOutput = 0x2;
static constexpr uint32_t kSwifterKitHIDGetReportFeature = 0x4;
static constexpr uint32_t kSwifterKitHIDGetReportTypesAll = 0x7;
static constexpr uint32_t kSwifterKitHIDDeliverReports = 0x1;
static constexpr uint32_t kSwifterKitHIDDeliverElementValues = 0x2;
static constexpr uint32_t kSwifterKitHIDDeliverAll = 0x3;

static constexpr uint32_t kSwifterKitHIDEventDriverCategoryKeyboard = 0x1;
static constexpr uint32_t kSwifterKitHIDEventDriverCategoryPointer = 0x2;
static constexpr uint32_t kSwifterKitHIDEventDriverCategoryScroll = 0x4;
static constexpr uint32_t kSwifterKitHIDEventDriverCategoryLED = 0x8;
static constexpr uint32_t kSwifterKitHIDEventDriverCategoryDigitizer = 0x10;
static constexpr uint32_t kSwifterKitHIDEventDriverCategoryProximity = 0x20;
static constexpr uint32_t kSwifterKitHIDEventDriverCategoryGameController = 0x40;
static constexpr uint32_t kSwifterKitHIDEventDriverCategoryRemaining = 0x80;
static constexpr uint32_t kSwifterKitHIDEventDriverCategoriesAll = 0xFF;

static constexpr uint32_t kSwifterKitHIDStylusInRange = 0x1;
static constexpr uint32_t kSwifterKitHIDStylusTip = 0x2;
static constexpr uint32_t kSwifterKitHIDStylusBarrelSwitch = 0x4;
static constexpr uint32_t kSwifterKitHIDStylusInvert = 0x8;
static constexpr uint32_t kSwifterKitHIDStylusEraser = 0x10;
static constexpr uint32_t kSwifterKitHIDStylusTipChanged = 0x20;
static constexpr uint32_t kSwifterKitHIDStylusPositionChanged = 0x40;
static constexpr uint32_t kSwifterKitHIDStylusRangeChanged = 0x80;
static constexpr uint32_t kSwifterKitHIDStylusFlagsAll = 0xFF;
static constexpr uint32_t kSwifterKitHIDTouchInRange = 0x1;
static constexpr uint32_t kSwifterKitHIDTouchTouch = 0x2;
static constexpr uint32_t kSwifterKitHIDTouchTouchValid = 0x4;
static constexpr uint32_t kSwifterKitHIDTouchTouchChanged = 0x8;
static constexpr uint32_t kSwifterKitHIDTouchPositionChanged = 0x10;
static constexpr uint32_t kSwifterKitHIDTouchRangeChanged = 0x20;
static constexpr uint32_t kSwifterKitHIDTouchFlagsAll = 0x3F;
static constexpr uint32_t kSwifterKitHIDCollectionTouch = 0x1;
static constexpr uint32_t kSwifterKitHIDCollectionInRange = 0x2;
static constexpr uint32_t kSwifterKitHIDCollectionStateFlagsAll = 0x3;
static constexpr uint32_t kSwifterKitHIDCollectionChangeTouch = 0x1;
static constexpr uint32_t kSwifterKitHIDCollectionChangePosition = 0x2;
static constexpr uint32_t kSwifterKitHIDCollectionChangeRange = 0x4;
static constexpr uint32_t kSwifterKitHIDCollectionChangesAll = 0x7;
static constexpr uint32_t kSwifterKitHIDCollectionChangeShift = 2;
static constexpr uint32_t kSwifterKitHIDCollectionFlagsAll = 0x1F;
static constexpr uint32_t kSwifterKitHIDGameControllerThumbstickButtonLeft = 0x1;
static constexpr uint32_t kSwifterKitHIDGameControllerThumbstickButtonRight = 0x2;
static constexpr uint32_t kSwifterKitHIDGameControllerFlagsAll = 0x3;

#endif
