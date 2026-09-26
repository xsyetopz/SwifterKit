#include <DriverKit/IOLib.h>
#include <DriverKit/OSCollections.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

#if SWIFTERKIT_HID_EVENT_SERVICE
    #include <HIDDriverKit/IOHIDDigitizerCollection.h>
    #include <HIDDriverKit/IOHIDDigitizerStructs.h>
    #include <HIDDriverKit/IOHIDElement.h>
#endif

// Swift's typed IOHIDEventService dispatches, LED control, and event-driver category switches.
// Every dispatch runs under hidLock so it cannot interleave with the superclass's own dispatches
// from handleReport.
#if SWIFTERKIT_HID_EVENT_SERVICE
namespace {
    // Swift sends zero to stamp an event with the current time.
    uint64_t Stamp(uint64_t timestamp) {
        return timestamp == 0 ? mach_absolute_time() : timestamp;
    }

    template<typename Payload>
    bool Read(const uint8_t* payload, uint32_t payloadLength, Payload* value) {
        if (payloadLength != sizeof(Payload)) {
            return false;
        }
        memcpy(value, payload, sizeof(Payload));
        return true;
    }

    IOHIDElement* FindElement(const OSArray* elements, uint32_t cookie) {
        if (elements == nullptr || cookie == 0) {
            return nullptr;
        }
        for (uint32_t index = 0; index < elements->getCount(); ++index) {
            auto* element = OSDynamicCast(IOHIDElement, elements->getObject(index));
            if (element != nullptr && element->getCookie() == cookie) {
                return element;
            }
        }
        return nullptr;
    }

    // One state bit of a dispatch payload's flags, as the 0 or 1 a digitizer field holds.
    uint32_t Bit(uint32_t flags, uint32_t mask) {
        return (flags & mask) != 0 ? 1U : 0U;
    }

    IOHIDDigitizerStylusData Stylus(const SwifterKitHIDStylusEvent& event) {
        IOHIDDigitizerStylusData data = {};
        data.identifier = event.identifier;
        data.x = event.x;
        data.y = event.y;
        data.tipPressure = event.tipPressure;
        data.barrelPressure = event.barrelPressure;
        data.tiltX = event.tiltX;
        data.tiltY = event.tiltY;
        data.twist = event.twist;
        data.pointerType = event.pointerType;
        data.effect = event.effect;
        data.uniqueID = event.uniqueID;
        data.inRange = Bit(event.flags, kSwifterKitHIDStylusInRange);
        data.tip = Bit(event.flags, kSwifterKitHIDStylusTip);
        data.barrelSwitch = Bit(event.flags, kSwifterKitHIDStylusBarrelSwitch);
        data.invert = Bit(event.flags, kSwifterKitHIDStylusInvert);
        data.eraser = Bit(event.flags, kSwifterKitHIDStylusEraser);
        data.tipChanged = Bit(event.flags, kSwifterKitHIDStylusTipChanged);
        data.positionChanged = Bit(event.flags, kSwifterKitHIDStylusPositionChanged);
        data.rangeChanged = Bit(event.flags, kSwifterKitHIDStylusRangeChanged);
        return data;
    }

    IOHIDDigitizerTouchData Touch(const SwifterKitHIDTouch& touch) {
        IOHIDDigitizerTouchData data = {};
        data.identifier = touch.identifier;
        data.x = touch.x;
        data.y = touch.y;
        data.inRange = Bit(touch.flags, kSwifterKitHIDTouchInRange);
        data.touch = Bit(touch.flags, kSwifterKitHIDTouchTouch);
        data.touchValid = Bit(touch.flags, kSwifterKitHIDTouchTouchValid);
        data.touchChanged = Bit(touch.flags, kSwifterKitHIDTouchTouchChanged);
        data.positionChanged = Bit(touch.flags, kSwifterKitHIDTouchPositionChanged);
        data.rangeChanged = Bit(touch.flags, kSwifterKitHIDTouchRangeChanged);
        return data;
    }

    kern_return_t RespondWithFlag(bool value, OSData** response) {
        const uint32_t flag = value ? 1 : 0;
        *response = OSData::withBytes(&flag, sizeof(flag));
        return *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::HIDDispatchCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->hidLock == nullptr) {
        return kIOReturnNotReady;
    }
    const auto code = static_cast<SwifterKitRuntimeOpcode>(opcode);
    // SetLEDState dispatches through SetLEDState_Impl, which forwards the change and locks.
    if (code == SwifterKitRuntimeOpcode::HIDSetLEDState) {
        SwifterKitHIDLEDState state = {};
        if (!Read(payload, payloadLength, &state) || state.on > 1 || state.reserved != 0) {
            return kIOReturnBadArgument;
        }
        return SetLEDState(state.usagePage, state.usage, state.on != 0);
    }

    kern_return_t result = kIOReturnBadArgument;
    IORecursiveLockLock(ivars->hidLock);
    switch (code) {
        case SwifterKitRuntimeOpcode::HIDDispatchKeyboard: {
            SwifterKitHIDKeyboardEvent event = {};
            if (Read(payload, payloadLength, &event) && event.flags <= 1 && event.reserved == 0) {
                result = dispatchKeyboardEvent(
                    Stamp(event.timestamp),
                    event.usagePage,
                    event.usage,
                    event.value,
                    event.options,
                    event.flags != 0);
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDDispatchRelativePointer:
        case SwifterKitRuntimeOpcode::HIDDispatchAbsolutePointer: {
            SwifterKitHIDPointerEvent event = {};
            if (Read(payload, payloadLength, &event) && event.flags <= 1 && event.z == 0) {
                result = code == SwifterKitRuntimeOpcode::HIDDispatchRelativePointer
                             ? dispatchRelativePointerEvent(
                                   Stamp(event.timestamp),
                                   event.x,
                                   event.y,
                                   event.buttons,
                                   event.options,
                                   event.flags != 0)
                             : dispatchAbsolutePointerEvent(
                                   Stamp(event.timestamp),
                                   event.x,
                                   event.y,
                                   event.buttons,
                                   event.options,
                                   event.flags != 0);
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDDispatchScroll: {
            SwifterKitHIDPointerEvent event = {};
            if (Read(payload, payloadLength, &event) && event.flags <= 1 && event.buttons == 0) {
                result = dispatchRelativeScrollWheelEvent(
                    Stamp(event.timestamp),
                    event.x,
                    event.y,
                    event.z,
                    event.options,
                    event.flags != 0);
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDDispatchDigitizerStylus: {
            SwifterKitHIDStylusEvent event = {};
            if (Read(payload, payloadLength, &event)
                && (event.flags & ~kSwifterKitHIDStylusFlagsAll) == 0 && event.reserved == 0) {
                IOHIDDigitizerStylusData stylus = Stylus(event);
                result = dispatchDigitizerStylusEvent(Stamp(event.timestamp), &stylus);
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDDispatchDigitizerTouches: {
            SwifterKitHIDTouchesHeader header = {};
            if (payloadLength < sizeof(header)) {
                break;
            }
            memcpy(&header, payload, sizeof(header));
            if (header.reserved != 0 || header.count == 0
                || header.count > kSwifterKitHIDMaximumTouches
                || payloadLength != sizeof(header) + header.count * sizeof(SwifterKitHIDTouch)) {
                break;
            }
            IOHIDDigitizerTouchData touches[kSwifterKitHIDMaximumTouches] = {};
            bool valid = true;
            for (uint32_t index = 0; index < header.count; ++index) {
                SwifterKitHIDTouch touch = {};
                memcpy(
                    &touch,
                    payload + sizeof(header) + index * sizeof(SwifterKitHIDTouch),
                    sizeof(touch));
                valid = valid && (touch.flags & ~kSwifterKitHIDTouchFlagsAll) == 0;
                touches[index] = Touch(touch);
            }
            if (valid) {
                result =
                    dispatchDigitizerTouchEvent(Stamp(header.timestamp), touches, header.count);
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDDispatchDigitizerCollection:
            result = DispatchHIDDigitizerCollection(payload, payloadLength);
            break;
        case SwifterKitRuntimeOpcode::HIDDispatchGameController: {
            SwifterKitHIDGameControllerEvent event = {};
            if (Read(payload, payloadLength, &event)
                && (event.flags & ~kSwifterKitHIDGameControllerFlagsAll) == 0) {
                const int32_t* v = event.values;
                result = dispatchStandardGameControllerEvent(
                    Stamp(event.timestamp),
                    v[0],
                    v[1],
                    v[2],
                    v[3],
                    v[4],
                    v[5],
                    v[6],
                    v[7],
                    v[8],
                    v[9],
                    v[10],
                    v[11],
                    v[12],
                    v[13],
                    v[14],
                    v[15],
                    (event.flags & kSwifterKitHIDGameControllerThumbstickButtonLeft) != 0,
                    (event.flags & kSwifterKitHIDGameControllerThumbstickButtonRight) != 0,
                    event.options);
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDDispatchExtendedGameController: {
            SwifterKitHIDExtendedGameControllerEvent event = {};
            if (!Read(payload, payloadLength, &event)
                || (event.standard.flags & ~kSwifterKitHIDGameControllerFlagsAll) != 0) {
                break;
            }
            if (__builtin_available(driverkit 23.0, *)) {
                const int32_t* v = event.standard.values;
                const int32_t* b = event.buttons;
                result = dispatchExtendedGameControllerEventWithOptionalButtons(
                    Stamp(event.standard.timestamp),
                    v[0],
                    v[1],
                    v[2],
                    v[3],
                    v[4],
                    v[5],
                    v[6],
                    v[7],
                    v[8],
                    v[9],
                    v[10],
                    v[11],
                    v[12],
                    v[13],
                    v[14],
                    v[15],
                    (event.standard.flags & kSwifterKitHIDGameControllerThumbstickButtonLeft) != 0,
                    (event.standard.flags & kSwifterKitHIDGameControllerThumbstickButtonRight) != 0,
                    b[0],
                    b[1],
                    b[2],
                    b[3],
                    b[4],
                    b[5],
                    event.standard.options);
            } else {
                result = kIOReturnUnsupported;
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDSetLED: {
            SwifterKitHIDLEDState state = {};
            if (Read(payload, payloadLength, &state)
                && state.usagePage == kSwifterKitHIDLEDUsagePage && state.on <= 1
                && state.reserved == 0) {
                SetLED(state.usage, state.on != 0);
                result = kIOReturnSuccess;
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDServiceConformsTo: {
            SwifterKitHIDUsageQuery query = {};
            if (Read(payload, payloadLength, &query) && query.cookie == 0 && query.reserved == 0) {
                result = RespondWithFlag(conformsTo(query.usagePage, query.usage), response);
            }
            break;
        }
        case SwifterKitRuntimeOpcode::HIDSetEventDriverCategories: {
    #if SWIFTERKIT_HID_EVENT_DRIVER
            SwifterKitHIDDeviceSetting setting = {};
            if (Read(payload, payloadLength, &setting) && setting.kind == 0
                && (setting.value & ~kSwifterKitHIDEventDriverCategoriesAll) == 0) {
                ivars->hidEventDriverHandling = setting.value;
                result = kIOReturnSuccess;
            }
    #else
            result = kIOReturnUnsupported;
    #endif
            break;
        }
        default:
            result = kIOReturnUnsupported;
            break;
    }
    IORecursiveLockUnlock(ivars->hidLock);
    return result;
}

// Materializes one transducer as an IOHIDDigitizerCollection over the named elements and
// dispatches the collection's state as a stylus (stylus and puck) or touch (finger and hand).
kern_return_t SwifterKitRuntimeService::DispatchHIDDigitizerCollection(
    const uint8_t* payload,
    uint32_t payloadLength) {
    SwifterKitHIDCollectionEvent event = {};
    if (payloadLength < sizeof(event)) {
        return kIOReturnBadArgument;
    }
    memcpy(&event, payload, sizeof(event));
    if (event.type > kIOHIDDigitizerCollectionTypeHand
        || (event.flags & ~kSwifterKitHIDCollectionFlagsAll) != 0
        || event.elementCount > kSwifterKitHIDMaximumCollectionElements
        || payloadLength != sizeof(event) + event.elementCount * sizeof(uint32_t)) {
        return kIOReturnBadArgument;
    }
    const OSArray* elements = getElements();
    IOHIDElement* parent = FindElement(elements, event.parentCookie);
    if (event.parentCookie != 0 && parent == nullptr) {
        return kIOReturnNotFound;
    }
    IOHIDDigitizerCollection* collection = IOHIDDigitizerCollection::withType(
        static_cast<IOHIDDigitizerCollectionType>(event.type),
        parent);
    if (collection == nullptr) {
        return kIOReturnNoMemory;
    }
    for (uint32_t index = 0; index < event.elementCount; ++index) {
        uint32_t cookie = 0;
        memcpy(&cookie, payload + sizeof(event) + index * sizeof(cookie), sizeof(cookie));
        IOHIDElement* element = FindElement(elements, cookie);
        if (element == nullptr) {
            collection->release();
            return kIOReturnNotFound;
        }
        collection->addElement(element);
    }
    collection->setTouch((event.flags & kSwifterKitHIDCollectionTouch) != 0);
    collection->setInRange((event.flags & kSwifterKitHIDCollectionInRange) != 0);
    collection->setX(event.x);
    collection->setY(event.y);
    collection->setZ(event.z);

    const uint32_t changes = event.flags >> kSwifterKitHIDCollectionChangeShift;
    kern_return_t result = kIOReturnSuccess;
    const IOHIDDigitizerCollectionType type = collection->getType();
    if (type == kIOHIDDigitizerCollectionTypeStylus || type == kIOHIDDigitizerCollectionTypePuck) {
        IOHIDDigitizerStylusData stylus = {};
        stylus.identifier = event.identifier;
        stylus.x = collection->getX();
        stylus.y = collection->getY();
        stylus.tipPressure = collection->getZ();
        stylus.inRange = collection->getInRange() ? 1 : 0;
        stylus.tip = collection->getTouch() ? 1 : 0;
        stylus.tipChanged = Bit(changes, kSwifterKitHIDCollectionChangeTouch);
        stylus.positionChanged = Bit(changes, kSwifterKitHIDCollectionChangePosition);
        stylus.rangeChanged = Bit(changes, kSwifterKitHIDCollectionChangeRange);
        result = dispatchDigitizerStylusEvent(Stamp(event.timestamp), &stylus);
    } else {
        IOHIDDigitizerTouchData touch = {};
        touch.identifier = event.identifier;
        touch.x = collection->getX();
        touch.y = collection->getY();
        touch.inRange = collection->getInRange() ? 1 : 0;
        touch.touch = collection->getTouch() ? 1 : 0;
        touch.touchValid = 1;
        touch.touchChanged = Bit(changes, kSwifterKitHIDCollectionChangeTouch);
        touch.positionChanged = Bit(changes, kSwifterKitHIDCollectionChangePosition);
        touch.rangeChanged = Bit(changes, kSwifterKitHIDCollectionChangeRange);
        result = dispatchDigitizerTouchEvent(Stamp(event.timestamp), &touch, 1);
    }
    collection->release();
    return result;
}
#endif
