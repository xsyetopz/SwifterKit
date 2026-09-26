#ifndef SwifterKitRuntimeMediaObjects_h
#define SwifterKitRuntimeMediaObjects_h

// Box, clock-device, and object-command plumbing shared by the audio and video runtimes.
// AudioDriverKit and VideoDriverKit declare parallel object classes, so the templates here take a
// family struct that names that family's classes, schema values, and the service ivars fields it
// owns as member pointers (see SwifterKitRuntimeAudioObjects.cpp and
// SwifterKitRuntimeVideoObjects.cpp). Like SwifterKitRuntimeMediaControls.h, this header includes
// neither framework.

#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSString.h>
#include <string.h>

#include "SwifterKitRuntimeMediaControls.h"

// Sends `change` to PerformDeviceConfigurationChange as `action`'s change info.
template<typename Device, typename Change>
kern_return_t
    SwifterKitRequestConfigurationChange(Device* device, uint64_t action, const Change& change) {
    OSData* info = OSData::withBytes(&change, sizeof(change));
    if (info == nullptr)
        return kIOReturnNoMemory;
    const kern_return_t result = device->RequestDeviceConfigurationChange(action, info);
    info->release();
    return result;
}

template<typename Change>
bool SwifterKitReadConfigurationChange(OSObject* info, Change* change) {
    const auto* data = OSDynamicCast(OSData, info);
    if (data == nullptr || data->getLength() != sizeof(*change))
        return false;
    memcpy(change, data->getBytesNoCopy(), sizeof(*change));
    return true;
}

// Copies a fixed-size request from `payload` when the length matches exactly.
template<typename Value>
bool SwifterKitReadExactPayload(const uint8_t* payload, uint32_t payloadLength, Value* value) {
    if (payload == nullptr || payloadLength != sizeof(*value))
        return false;
    memcpy(value, payload, sizeof(*value));
    return true;
}

inline kern_return_t SwifterKitBytesResponse(const void* bytes, size_t length, OSData** response) {
    OSData* data = OSData::withBytes(bytes, length);
    if (data == nullptr)
        return kIOReturnNoMemory;
    *response = data;
    return kIOReturnSuccess;
}

// What every SwifterKit box and clock-device subclass keeps: the retained service that reports
// host changes, and the object's index in the schema tables.
template<typename IVars>
bool SwifterKitAttachObjectState(IVars*& ivars, SwifterKitRuntimeService* service, uint32_t index) {
    ivars = IONewZero(IVars, 1);
    if (ivars == nullptr)
        return false;
    ivars->service = service;
    ivars->index = index;
    service->retain();
    return true;
}

// Names a box or clock device from its configuration's C string.
template<typename Object>
kern_return_t SwifterKitNameObject(Object* object, const char* name) {
    OSString* string = OSString::withCString(name);
    const kern_return_t result = string == nullptr ? kIOReturnNoMemory : object->SetName(string);
    OSSafeReleaseNULL(string);
    return result;
}

template<typename TransportType, typename Box, typename Configuration>
kern_return_t SwifterKitConfigureBox(Box* box, const Configuration* configuration) {
    kern_return_t result = SwifterKitNameObject(box, configuration->name);
    if (result == kIOReturnSuccess)
        result = box->SetTransportType(static_cast<TransportType>(configuration->transport));
    if (result == kIOReturnSuccess)
        result = box->SetHasAudio(configuration->hasAudio);
    if (result == kIOReturnSuccess)
        result = box->SetHasMIDI(configuration->hasMIDI);
    if (result == kIOReturnSuccess)
        result = box->SetHasVideo(configuration->hasVideo);
    if (result == kIOReturnSuccess)
        result = box->SetIsProtected(configuration->isProtected);
    if (result == kIOReturnSuccess)
        result = box->SetIsAcquired(configuration->isAcquired);
    return result;
}

template<typename Family, typename Clock, typename Configuration>
kern_return_t SwifterKitConfigureClockDevice(Clock* clock, const Configuration* configuration) {
    if (configuration->rateCount > Family::kMaximumSampleRates)
        return kIOReturnBadArgument;
    kern_return_t result = SwifterKitNameObject(clock, configuration->name);
    if (result == kIOReturnSuccess)
        result = clock->SetTransportType(
            static_cast<typename Family::TransportType>(configuration->transport));
    if (result == kIOReturnSuccess)
        result = clock->SetAvailableSampleRates(
            Family::kClockSampleRates + configuration->rateStart,
            configuration->rateCount);
    if (result == kIOReturnSuccess)
        result = clock->SetSampleRate(configuration->initialSampleRate);
    if (result == kIOReturnSuccess)
        result = clock->SetClockDomain(configuration->clockDomain);
    if (result == kIOReturnSuccess)
        result = clock->SetClockAlgorithm(
            static_cast<typename Family::ClockAlgorithm>(configuration->clockAlgorithm));
    if (result == kIOReturnSuccess)
        result = clock->SetClockIsStable(configuration->clockIsStable);
    if (result == kIOReturnSuccess)
        result = clock->SetIsHidden(configuration->isHidden);
    if (result == kIOReturnSuccess)
        result = clock->SetInputLatency(configuration->inputLatency);
    if (result == kIOReturnSuccess)
        result = clock->SetOutputLatency(configuration->outputLatency);
    return result;
}

template<typename Family, typename Clock>
bool SwifterKitIsAvailableSampleRate(Clock* clock, double sampleRate) {
    double rates[Family::kMaximumSampleRates] = {};
    const size_t count = clock->GetAvailableSampleRates(rates, Family::kMaximumSampleRates);
    for (size_t index = 0; index < count && index < Family::kMaximumSampleRates; ++index)
        if (rates[index] == sampleRate)
            return true;
    return false;
}

// Records `sampleRate` for PerformDeviceConfigurationChange and requests the change as `action`.
template<typename Clock>
kern_return_t SwifterKitRequestSampleRateChange(
    Clock* clock,
    uint64_t* pendingSampleRateBits,
    uint64_t action,
    double sampleRate) {
    __atomic_store_n(
        pendingSampleRateBits,
        __builtin_bit_cast(uint64_t, sampleRate),
        __ATOMIC_RELEASE);
    return clock->RequestDeviceConfigurationChange(action, nullptr);
}

// Applies the rate SwifterKitRequestSampleRateChange recorded and reports it through `report`.
template<typename Family, typename Clock, typename Report>
kern_return_t
    SwifterKitApplySampleRateChange(Clock* clock, uint64_t* pendingSampleRateBits, Report report) {
    const double sampleRate =
        __builtin_bit_cast(double, __atomic_exchange_n(pendingSampleRateBits, 0, __ATOMIC_ACQUIRE));
    kern_return_t result = SwifterKitIsAvailableSampleRate<Family>(clock, sampleRate)
                               ? clock->SetSampleRate(sampleRate)
                               : kIOReturnBadArgument;
    if (result == kIOReturnSuccess)
        result = report(__builtin_bit_cast(uint64_t, sampleRate));
    return result;
}

// Copies a bounded, NUL-free name from a payload into an OSString.
template<typename Family>
OSString* SwifterKitCopyObjectName(const uint8_t* bytes, uint32_t length) {
    char name[Family::kNameMaximumLength + 1] = {};
    if (bytes == nullptr || length == 0 || length > Family::kNameMaximumLength
        || memchr(bytes, 0, length) != nullptr)
        return nullptr;
    memcpy(name, bytes, length);
    return OSString::withCString(name);
}

template<typename Family>
kern_return_t
    SwifterKitAppendObjectName(OSData* data, const OSSharedPtr<OSString>& name, uint32_t* length) {
    *length = name ? static_cast<uint32_t>(name->getLength()) : 0;
    if (*length > Family::kNameMaximumLength)
        return kIOReturnNoSpace;
    return *length == 0 || data->appendBytes(name->getCStringNoCopy(), *length) ? kIOReturnSuccess
                                                                                : kIOReturnNoMemory;
}

// Answers an object-info request for `object`, or for `driver` when `object` is null. The caller
// fills any family-only header fields first.
template<typename Family, typename Header>
kern_return_t SwifterKitObjectInfoResponse(
    typename Family::Driver* driver,
    typename Family::Object* object,
    Header header,
    OSData** response) {
    OSSharedPtr<OSString> name;
    OSSharedPtr<OSString> uid;
    if (object == nullptr) {
        header.classID = static_cast<uint32_t>(driver->GetClassID());
        header.baseClassID = static_cast<uint32_t>(driver->GetBaseClassID());
        header.transport = static_cast<uint32_t>(driver->GetTransportType());
        name = driver->GetName();
    } else {
        header.objectID = object->GetObjectID();
        header.classID = static_cast<uint32_t>(object->GetClassID());
        header.baseClassID = static_cast<uint32_t>(object->GetBaseClassID());
        name = object->GetName();
        if (auto* clock = SwifterKitDynamicCast<typename Family::ClockDevice>(object)) {
            header.transport = static_cast<uint32_t>(clock->GetTransportType());
            uid = clock->GetUID();
        } else if (auto* box = SwifterKitDynamicCast<typename Family::Box>(object)) {
            header.transport = static_cast<uint32_t>(box->GetTransportType());
            uid = box->GetUID();
        }
    }
    OSData* data = OSData::withCapacity(sizeof(header) + 2 * Family::kNameMaximumLength);
    if (data == nullptr)
        return kIOReturnNoMemory;
    kern_return_t result =
        data->appendBytes(&header, sizeof(header)) ? kIOReturnSuccess : kIOReturnNoMemory;
    uint32_t nameLength = 0;
    uint32_t uidLength = 0;
    if (result == kIOReturnSuccess)
        result = SwifterKitAppendObjectName<Family>(data, name, &nameLength);
    if (result == kIOReturnSuccess)
        result = SwifterKitAppendObjectName<Family>(data, uid, &uidLength);
    header.nameLength = nameLength;
    header.uidLength = uidLength;
    if (result != kIOReturnSuccess) {
        data->release();
        return result;
    }
    // Lengths are known only after appending; patch them into the copied header.
    auto* bytes = static_cast<uint8_t*>(const_cast<void*>(data->getBytesNoCopy()));
    memcpy(bytes, &header, sizeof(header));
    *response = data;
    return kIOReturnSuccess;
}

// Handles SetObjectName (`setName`) or PropertiesChanged. `resolve` returns the target object, or
// null when it does not exist; a driver target names the driver itself.
template<typename Family, typename Resolve>
kern_return_t SwifterKitChangeObject(
    typename Family::Driver* driver,
    bool setName,
    bool isDriver,
    const uint8_t* payload,
    uint32_t payloadLength,
    Resolve resolve) {
    typename Family::ListHeader header = {};
    if (payloadLength < sizeof(header))
        return kIOReturnBadArgument;
    memcpy(&header, payload, sizeof(header));
    const uint8_t* body = payload + sizeof(header);
    const uint64_t bodyLength = payloadLength - sizeof(header);
    if (header.reserved != 0)
        return kIOReturnBadArgument;
    if (setName) {
        if (bodyLength != header.count)
            return kIOReturnBadArgument;
        OSString* name = SwifterKitCopyObjectName<Family>(body, header.count);
        if (name == nullptr)
            return kIOReturnBadArgument;
        typename Family::Object* object = isDriver ? nullptr : resolve();
        const kern_return_t result = isDriver            ? driver->SetName(name)
                                     : object != nullptr ? object->SetName(name)
                                                         : kIOReturnNotFound;
        name->release();
        return result;
    }
    typename Family::PropertySelector selectors[Family::kMaximumChangedProperties] = {};
    if (header.count == 0 || header.count > Family::kMaximumChangedProperties
        || bodyLength != header.count * 4ULL)
        return kIOReturnBadArgument;
    memcpy(selectors, body, header.count * 4ULL);
    for (uint32_t index = 0; index < header.count; ++index)
        if (selectors[index] == 0)
            return kIOReturnBadArgument;
    typename Family::Object* object = resolve();
    return object == nullptr
               ? kIOReturnNotFound
               : driver->PropertiesChanged(object->GetObjectID(), selectors, header.count);
}

// Handles GetElementName or SetElementName (`setting`) on the object `resolve` returns.
template<typename Family, typename Resolve>
kern_return_t SwifterKitElementNameCommand(
    bool setting,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response,
    Resolve resolve) {
    typename Family::ElementNameHeader header = {};
    if (payloadLength < sizeof(header))
        return kIOReturnBadArgument;
    memcpy(&header, payload, sizeof(header));
    if (header.kind > Family::kElementNumber
        || (setting ? payloadLength != sizeof(header) + header.length
                    : payloadLength != sizeof(header) || header.length != 0))
        return kIOReturnBadArgument;
    typename Family::Object* object = resolve();
    if (object == nullptr)
        return kIOReturnNotFound;
    const auto scope = static_cast<typename Family::Scope>(header.scope);
    const typename Family::Element element = header.element;
    if (setting) {
        OSString* name = SwifterKitCopyObjectName<Family>(payload + sizeof(header), header.length);
        if (name == nullptr)
            return kIOReturnBadArgument;
        const kern_return_t result = header.kind == Family::kElementName
                                         ? object->SetElementName(element, scope, name)
                                     : header.kind == Family::kElementCategory
                                         ? object->SetElementCategoryName(element, scope, name)
                                         : object->SetElementNumberName(element, scope, name);
        name->release();
        return result;
    }
    const OSSharedPtr<OSString> name =
        header.kind == Family::kElementName       ? object->GetElementName(element, scope)
        : header.kind == Family::kElementCategory ? object->GetElementCategoryName(element, scope)
                                                  : object->GetElementNumberName(element, scope);
    if (!name || name->getLength() == 0)
        return kIOReturnSuccess;
    return name->getLength() > Family::kNameMaximumLength
               ? kIOReturnNoSpace
               : SwifterKitBytesResponse(name->getCStringNoCopy(), name->getLength(), response);
}

// Answers a clock-state read. `finish(clock, state)` adds the family-only fields before the state
// is copied.
template<typename Family, typename Finish>
kern_return_t SwifterKitClockStateResponse(
    typename Family::ClockDevice* clock,
    OSData** response,
    Finish finish) {
    using ClockState = typename Family::ClockState;
    if (clock == nullptr)
        return kIOReturnNotFound;
    uint8_t bytes[sizeof(ClockState) + Family::kMaximumSampleRates * 8] = {};
    double rates[Family::kMaximumSampleRates] = {};
    size_t count = clock->GetNumberAvailableSampleRates();
    count = count > Family::kMaximumSampleRates ? Family::kMaximumSampleRates : count;
    count = clock->GetAvailableSampleRates(rates, count);
    count = count > Family::kMaximumSampleRates ? Family::kMaximumSampleRates : count;
    ClockState state = {};
    uint64_t zeroSampleTime = 0;
    uint64_t zeroHostTime = 0;
    uint64_t inputSampleTime = 0;
    uint64_t outputSampleTime = 0;
    clock->GetCurrentZeroTimestamp(&zeroSampleTime, &zeroHostTime);
    clock->GetCurrentClientSampleTime(&inputSampleTime, &outputSampleTime);
    state.sampleRateBits = __builtin_bit_cast(uint64_t, clock->GetSampleRate());
    state.zeroSampleTime = zeroSampleTime;
    state.zeroHostTime = zeroHostTime;
    state.clientInputSampleTime = inputSampleTime;
    state.clientOutputSampleTime = outputSampleTime;
    state.objectID = clock->GetObjectID();
    state.clockDomain = clock->GetClockDomain();
    state.clockAlgorithm = static_cast<uint32_t>(clock->GetClockAlgorithm());
    state.transport = static_cast<uint32_t>(clock->GetTransportType());
    state.transportState = static_cast<uint32_t>(clock->GetDeviceTransportState());
    state.flags = (clock->GetClockIsStable() ? Family::kClockStateClockIsStable : 0)
                  | (clock->GetDeviceIsAlive() ? Family::kClockStateIsAlive : 0)
                  | (clock->GetDeviceIsRunning() ? Family::kClockStateIsRunning : 0)
                  | (clock->GetIsHidden() ? Family::kClockStateIsHidden : 0);
    state.inputLatency = clock->GetInputLatency();
    state.outputLatency = clock->GetOutputLatency();
    state.rateCount = static_cast<uint32_t>(count);
    finish(clock, state);
    memcpy(bytes, &state, sizeof(state));
    memcpy(bytes + sizeof(state), rates, count * sizeof(double));
    return SwifterKitBytesResponse(bytes, sizeof(state) + count * sizeof(double), response);
}

// A box owner slot's value when no box owns the device or clock device; otherwise it is the owning
// box's index plus one.
inline constexpr uint8_t kSwifterKitMediaNoOwner = 0;

// Adds the device or a clock device to `box`, or removes it, and records which box owns it. A
// member belongs to at most one box; `boxIndex` is the box's schema index.
template<typename Family, typename State>
kern_return_t SwifterKitSetBoxOwnership(
    State* state,
    typename Family::RuntimeBox* box,
    uint32_t boxIndex,
    const uint8_t* payload,
    uint32_t payloadLength) {
    typename Family::BoxOwnership request = {};
    if (!SwifterKitReadExactPayload(payload, payloadLength, &request))
        return kIOReturnBadArgument;
    const bool device = request.member.kind == Family::kTargetDevice;
    if (request.owned > 1 || request.reserved != 0
        || (device ? request.member.index != 0
                   : request.member.kind != Family::kTargetClock
                         || request.member.index >= Family::kObjectTableCount))
        return kIOReturnBadArgument;
    auto* runtimeDevice = state->*Family::kDevice;
    typename Family::ClockDevice* member =
        device ? static_cast<typename Family::ClockDevice*>(runtimeDevice)
               : (state->*Family::kClockDevices)[request.member.index];
    if (box == nullptr || member == nullptr)
        return kIOReturnNotFound;
    uint8_t& owner = device ? state->*Family::kDeviceOwner
                            : (state->*Family::kClockOwners)[request.member.index];
    const auto self = static_cast<uint8_t>(boxIndex + 1);
    if (request.owned == 1 ? owner != kSwifterKitMediaNoOwner : owner != self)
        return owner == self ? kIOReturnSuccess : kIOReturnBusy;
    kern_return_t result = kIOReturnSuccess;
    if (device)
        result =
            request.owned == 1 ? box->AddDevice(runtimeDevice) : box->RemoveDevice(runtimeDevice);
    else
        result = request.owned == 1 ? box->AddClockDevice(member) : box->RemoveClockDevice(member);
    if (result == kIOReturnSuccess)
        owner = request.owned == 1 ? self : kSwifterKitMediaNoOwner;
    return result;
}

template<typename Family>
kern_return_t
    SwifterKitSetBoxProperty(typename Family::RuntimeBox* box, uint32_t selector, uint64_t value) {
    const bool boolean =
        selector >= Family::kBoxPropertyHasAudio && selector <= Family::kBoxPropertyIsProtected;
    if (selector < Family::kBoxPropertyTransport
        || selector > Family::kBoxPropertyAcquisitionFailure || (boolean && value > 1)
        || value > UINT32_MAX)
        return kIOReturnBadArgument;
    if (box == nullptr)
        return kIOReturnNotFound;
    const bool flag = value == 1;
    switch (selector) {
        case Family::kBoxPropertyTransport:
            return box->SetTransportType(static_cast<typename Family::TransportType>(value));
        case Family::kBoxPropertyHasAudio:
            return box->SetHasAudio(flag);
        case Family::kBoxPropertyHasMIDI:
            return box->SetHasMIDI(flag);
        case Family::kBoxPropertyHasVideo:
            return box->SetHasVideo(flag);
        case Family::kBoxPropertyIsAcquirable:
            return box->SetIsAcquirable(flag);
        case Family::kBoxPropertyIsAcquired:
            return box->SetIsAcquired(flag);
        case Family::kBoxPropertyIsProtected:
            return box->SetIsProtected(flag);
        default:
            return box->SetAcquisitionFailure(
                static_cast<kern_return_t>(static_cast<uint32_t>(value)));
    }
}

template<typename Family>
kern_return_t SwifterKitBoxStateResponse(typename Family::RuntimeBox* box, OSData** response) {
    if (box == nullptr)
        return kIOReturnNotFound;
    const typename Family::BoxState boxState = {
        box->GetObjectID(),
        static_cast<uint32_t>(box->GetTransportType()),
        (box->HasAudio() ? Family::kBoxStateHasAudio : 0)
            | (box->HasMIDI() ? Family::kBoxStateHasMIDI : 0)
            | (box->HasVideo() ? Family::kBoxStateHasVideo : 0)
            | (box->IsAcquirable() ? Family::kBoxStateIsAcquirable : 0)
            | (box->IsAcquired() ? Family::kBoxStateIsAcquired : 0)
            | (box->IsProtected() ? Family::kBoxStateIsProtected : 0),
        box->GetAcquisitionFailure()};
    return SwifterKitBytesResponse(&boxState, sizeof(boxState), response);
}

// Replaces a clock device's available rates; `isValid` bounds each rate.
template<typename Family, typename IsValid>
kern_return_t SwifterKitSetClockSampleRates(
    typename Family::RuntimeClockDevice* clock,
    const uint8_t* payload,
    uint32_t payloadLength,
    IsValid isValid) {
    typename Family::ListHeader header = {};
    if (payloadLength < sizeof(header))
        return kIOReturnBadArgument;
    memcpy(&header, payload, sizeof(header));
    double rates[Family::kMaximumSettableSampleRates] = {};
    if (header.reserved != 0 || header.count == 0
        || header.count > Family::kMaximumSettableSampleRates
        || payloadLength != sizeof(header) + header.count * sizeof(double))
        return kIOReturnBadArgument;
    memcpy(rates, payload + sizeof(header), header.count * sizeof(double));
    for (uint32_t index = 0; index < header.count; ++index) {
        if (!isValid(rates[index]))
            return kIOReturnBadArgument;
        for (uint32_t other = 0; other < index; ++other)
            if (rates[other] == rates[index])
                return kIOReturnBadArgument;
    }
    return clock == nullptr ? kIOReturnNotFound
                            : clock->SetAvailableSampleRates(rates, header.count);
}

template<typename Family>
kern_return_t SwifterKitUpdateClockTimestamp(
    typename Family::RuntimeClockDevice* clock,
    const uint8_t* payload,
    uint32_t payloadLength) {
    typename Family::ClockTimestamp timestamp = {};
    if (payloadLength != sizeof(timestamp))
        return kIOReturnBadArgument;
    if (clock == nullptr)
        return kIOReturnNotFound;
    memcpy(&timestamp, payload, sizeof(timestamp));
    clock->UpdateCurrentZeroTimestamp(timestamp.sampleTime, timestamp.hostTime);
    return kIOReturnSuccess;
}

// Validates a Swift answer to a pending host request.
template<typename Answer>
kern_return_t
    SwifterKitReadRequestAnswer(const uint8_t* payload, uint32_t payloadLength, Answer* answer) {
    if (!SwifterKitReadExactPayload(payload, payloadLength, answer))
        return kIOReturnBadArgument;
    return answer->requestID == 0 || answer->accepted > 1 || answer->reserved != 0
                   || (answer->accepted == 1 && answer->failure != 0)
               ? kIOReturnBadArgument
               : kIOReturnSuccess;
}

// Creates, configures, and publishes each schema clock device. `init` runs the family's init.
template<typename Family, typename Service, typename State, typename Init>
kern_return_t SwifterKitStartClockDevices(Service* service, State* state, Init init) {
    kern_return_t result = kIOReturnSuccess;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < Family::kClockDeviceCount;
         ++index) {
        const auto& config = Family::kClockDeviceConfigurations[index];
        OSString* deviceUID = OSString::withCString(config.deviceUID);
        OSString* modelUID = OSString::withCString(config.modelUID);
        OSString* manufacturerUID = OSString::withCString(config.manufacturerUID);
        auto* clock = SwifterKitAllocate<typename Family::RuntimeClockDevice>();
        result = deviceUID == nullptr || modelUID == nullptr || manufacturerUID == nullptr
                         || clock == nullptr
                     ? kIOReturnNoMemory
                     : kIOReturnSuccess;
        if (result == kIOReturnSuccess
            && !init(clock, index, config, deviceUID, modelUID, manufacturerUID))
            result = kIOReturnNoMemory;
        if (result == kIOReturnSuccess)
            result = clock->Configure(&config);
        if (result == kIOReturnSuccess)
            result = service->AddObject(clock);
        IOLockLock(state->*Family::kLock);
        if (result == kIOReturnSuccess)
            (state->*Family::kClockDevices)[index] = clock;
        IOLockUnlock(state->*Family::kLock);
        if (result != kIOReturnSuccess)
            OSSafeReleaseNULL(clock);
        OSSafeReleaseNULL(deviceUID);
        OSSafeReleaseNULL(modelUID);
        OSSafeReleaseNULL(manufacturerUID);
    }
    return result;
}

// Creates each schema box, gives it the members it owns, and publishes it.
template<typename Family, typename Service, typename State>
kern_return_t SwifterKitStartBoxes(Service* service, State* state) {
    kern_return_t result = kIOReturnSuccess;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < Family::kBoxCount; ++index) {
        const auto& config = Family::kBoxConfigurations[index];
        OSString* uid = OSString::withCString(config.uid);
        auto* box = SwifterKitAllocate<typename Family::RuntimeBox>();
        result = uid == nullptr || box == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        if (result == kIOReturnSuccess
            && !box->init(service, service, index, config.isAcquirable, uid))
            result = kIOReturnNoMemory;
        if (result == kIOReturnSuccess)
            result = box->Configure(&config);
        IOLockLock(state->*Family::kLock);
        auto* device = state->*Family::kDevice;
        if (result == kIOReturnSuccess && config.ownsDevice && device != nullptr) {
            result = box->AddDevice(device);
            if (result == kIOReturnSuccess)
                state->*Family::kDeviceOwner = static_cast<uint8_t>(index + 1);
        }
        const auto& clocks = state->*Family::kClockDevices;
        for (uint32_t clock = 0; result == kIOReturnSuccess && clock < Family::kObjectTableCount;
             ++clock) {
            if ((config.clockMask & (1U << clock)) == 0 || clocks[clock] == nullptr)
                continue;
            result = box->AddClockDevice(clocks[clock]);
            if (result == kIOReturnSuccess)
                (state->*Family::kClockOwners)[clock] = static_cast<uint8_t>(index + 1);
        }
        if (result == kIOReturnSuccess)
            (state->*Family::kBoxes)[index] = box;
        IOLockUnlock(state->*Family::kLock);
        if (result == kIOReturnSuccess)
            result = service->AddObject(box);
        else
            OSSafeReleaseNULL(box);
        OSSafeReleaseNULL(uid);
    }
    return result;
}

// Takes every box and clock device out of the driver; boxes first release the members they own.
template<typename Family, typename Service, typename State>
void SwifterKitStopBoxesAndClockDevices(Service* service, State* state) {
    IOLockLock(state->*Family::kLock);
    auto* device = state->*Family::kDevice;
    auto& boxes = state->*Family::kBoxes;
    auto& clocks = state->*Family::kClockDevices;
    auto& clockOwners = state->*Family::kClockOwners;
    uint8_t& deviceOwner = state->*Family::kDeviceOwner;
    for (uint32_t index = 0; index < Family::kObjectTableCount; ++index) {
        typename Family::RuntimeBox* box = boxes[index];
        boxes[index] = nullptr;
        if (box == nullptr)
            continue;
        const auto owner = static_cast<uint8_t>(index + 1);
        if (deviceOwner == owner && device != nullptr)
            (void)box->RemoveDevice(device);
        if (deviceOwner == owner)
            deviceOwner = kSwifterKitMediaNoOwner;
        for (uint32_t clock = 0; clock < Family::kObjectTableCount; ++clock) {
            if (clockOwners[clock] != owner)
                continue;
            if (clocks[clock] != nullptr)
                (void)box->RemoveClockDevice(clocks[clock]);
            clockOwners[clock] = kSwifterKitMediaNoOwner;
        }
        (void)service->RemoveObject(box);
        OSSafeReleaseNULL(box);
    }
    for (uint32_t index = 0; index < Family::kObjectTableCount; ++index) {
        typename Family::RuntimeClockDevice* clock = clocks[index];
        clocks[index] = nullptr;
        if (clock != nullptr)
            (void)service->RemoveObject(clock);
        OSSafeReleaseNULL(clock);
    }
    IOLockUnlock(state->*Family::kLock);
}

#endif
