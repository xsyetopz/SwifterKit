#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeService.h"

#if SWIFTERKIT_ENABLE_MIDI

    #include <DriverKit/IOLib.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <MIDIDriverKit/IOUserMIDIDestination.h>
    #include <MIDIDriverKit/IOUserMIDIDevice.h>
    #include <MIDIDriverKit/IOUserMIDIEntity.h>
    #include <MIDIDriverKit/IOUserMIDISource.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeServiceState.h"

namespace {
    enum class MIDIEventKind : uint32_t {
        StartIO = 1,
        StopIO = 2,
        Received = 3,
    };

    OSString* MakeString(const char* value) {
        return value == nullptr ? nullptr : OSString::withCString(value);
    }

    kern_return_t QueueLifecycleEvent(SwifterKitRuntimeService* service, MIDIEventKind kind) {
        const SwifterKitMIDIEventHeader event = {
            .kind = static_cast<uint32_t>(kind),
            .endpointIndex = 0,
            .wordCount = 0,
            .reserved = 0,
        };
        return service->EnqueueEvent(kSwifterKitEventMIDI, &event, sizeof(event));
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartMIDI() {
    if (ivars == nullptr || ivars->midiLock == nullptr) {
        return kIOReturnNotReady;
    }
    IOLockLock(ivars->midiLock);
    const bool started = ivars->midiDevice != nullptr;
    IOLockUnlock(ivars->midiLock);
    if (started) {
        return kIOReturnNotReady;
    }

    OSString* driverName = MakeString(kSwifterKitMIDIDriverName);
    OSString* deviceIdentifier = MakeString(kSwifterKitMIDIDeviceIdentifier);
    OSString* modelIdentifier = MakeString(kSwifterKitMIDIModelIdentifier);
    OSString* manufacturerIdentifier = MakeString(kSwifterKitMIDIManufacturerIdentifier);
    OSString* entityName = MakeString(kSwifterKitMIDIEntityName);
    if (driverName == nullptr || deviceIdentifier == nullptr || modelIdentifier == nullptr
        || manufacturerIdentifier == nullptr || entityName == nullptr) {
        OSSafeReleaseNULL(driverName);
        OSSafeReleaseNULL(deviceIdentifier);
        OSSafeReleaseNULL(modelIdentifier);
        OSSafeReleaseNULL(manufacturerIdentifier);
        OSSafeReleaseNULL(entityName);
        return kIOReturnNoMemory;
    }

    kern_return_t result = SetName(driverName);
    auto device =
        IOUserMIDIDevice::Create(this, deviceIdentifier, modelIdentifier, manufacturerIdentifier);
    auto entity = IOUserMIDIEntity::Create(
        this,
        device.get(),
        entityName,
        static_cast<IOUserMIDIProtocolID>(kSwifterKitMIDIProtocol),
        kSwifterKitMIDISourceCount,
        kSwifterKitMIDIDestinationCount);
    OSSafeReleaseNULL(driverName);
    OSSafeReleaseNULL(deviceIdentifier);
    OSSafeReleaseNULL(modelIdentifier);
    OSSafeReleaseNULL(manufacturerIdentifier);
    OSSafeReleaseNULL(entityName);
    if (result != kIOReturnSuccess || !device || !entity) {
        return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
    }

    result = device->AddEntity(entity.get());
    bool added = false;
    if (result == kIOReturnSuccess) {
        result = AddObject(device.get());
        added = result == kIOReturnSuccess;
    }

    // Endpoints are gathered locally and published together under midiLock.
    IOUserMIDISource* sources[32] = {};
    IOUserMIDIDestination* destinations[32] = {};
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitMIDISourceCount;
         ++index) {
        auto source = entity->GetSource(index);
        if (!source) {
            result = kIOReturnNotFound;
            break;
        }
        source->retain();
        sources[index] = source.get();
    }

    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitMIDIDestinationCount;
         ++index) {
        auto destination = entity->GetDestination(index);
        if (!destination) {
            result = kIOReturnNotFound;
            break;
        }
        SwifterKitRuntimeService* service = this;
        const uint32_t endpointIndex = index;
        result = destination->SetIOBlock(
            ^kern_return_t(const IOUserMIDIUMPWord* words, size_t wordCount) {
              if (wordCount > UINT32_MAX) {
                  return kIOReturnNoSpace;
              }
              return service->MIDIReceived(endpointIndex, words, static_cast<uint32_t>(wordCount));
            });
        if (result == kIOReturnSuccess) {
            destination->retain();
            destinations[index] = destination.get();
        }
    }

    if (result == kIOReturnSuccess) {
        IOLockLock(ivars->midiLock);
        device->retain();
        ivars->midiDevice = device.get();
        entity->retain();
        ivars->midiEntity = entity.get();
        for (uint32_t index = 0; index < 32; ++index) {
            ivars->midiSources[index] = sources[index];
            ivars->midiDestinations[index] = destinations[index];
        }
        IOLockUnlock(ivars->midiLock);
        return kIOReturnSuccess;
    }

    for (uint32_t index = 0; index < 32; ++index) {
        if (destinations[index] != nullptr) {
            (void)destinations[index]->SetIOBlock(nullptr);
            OSSafeReleaseNULL(destinations[index]);
        }
        OSSafeReleaseNULL(sources[index]);
    }
    if (added) {
        (void)RemoveObject(device.get());
    }
    return result;
}

void SwifterKitRuntimeService::StopMIDI() {
    if (ivars == nullptr || ivars->midiLock == nullptr) {
        return;
    }
    IOUserMIDISource* sources[32] = {};
    IOUserMIDIDestination* destinations[32] = {};
    IOLockLock(ivars->midiLock);
    IOUserMIDIDevice* device = ivars->midiDevice;
    IOUserMIDIEntity* entity = ivars->midiEntity;
    ivars->midiDevice = nullptr;
    ivars->midiEntity = nullptr;
    for (uint32_t index = 0; index < 32; ++index) {
        sources[index] = ivars->midiSources[index];
        destinations[index] = ivars->midiDestinations[index];
        ivars->midiSources[index] = nullptr;
        ivars->midiDestinations[index] = nullptr;
    }
    IOLockUnlock(ivars->midiLock);

    for (uint32_t index = 0; index < 32; ++index) {
        if (destinations[index] != nullptr) {
            (void)destinations[index]->SetIOBlock(nullptr);
            OSSafeReleaseNULL(destinations[index]);
        }
        OSSafeReleaseNULL(sources[index]);
    }
    OSSafeReleaseNULL(entity);
    if (device != nullptr) {
        (void)RemoveObject(device);
        OSSafeReleaseNULL(device);
    }
}

kern_return_t SwifterKitRuntimeService::MIDICommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->midiLock == nullptr || response == nullptr) {
        return kIOReturnBadArgument;
    }
    *response = nullptr;
    if (opcode != static_cast<uint32_t>(SwifterKitRuntimeOpcode::MIDISend)) {
        return MIDIObjectCommand(opcode, payload, payloadLength, response);
    }
    if (payload == nullptr || payloadLength < sizeof(SwifterKitMIDIHeader)) {
        return kIOReturnBadArgument;
    }
    const auto* header = reinterpret_cast<const SwifterKitMIDIHeader*>(payload);
    const uint64_t expectedLength =
        sizeof(*header) + static_cast<uint64_t>(header->wordCount) * sizeof(IOUserMIDIUMPWord);
    if (header->wordCount == 0 || expectedLength != payloadLength
        || header->endpointIndex >= kSwifterKitMIDISourceCount) {
        return kIOReturnBadArgument;
    }
    IOLockLock(ivars->midiLock);
    IOUserMIDISource* source = ivars->midiSources[header->endpointIndex];
    if (source != nullptr) {
        source->retain();
    }
    IOLockUnlock(ivars->midiLock);
    if (source == nullptr) {
        return kIOReturnBadArgument;
    }
    const auto* words = reinterpret_cast<const IOUserMIDIUMPWord*>(payload + sizeof(*header));
    const kern_return_t result = source->Send(words, header->wordCount);
    source->release();
    return result;
}

kern_return_t SwifterKitRuntimeService::MIDIReceived(
    uint32_t destinationIndex,
    const uint32_t* words,
    uint32_t wordCount) {
    if (words == nullptr || wordCount == 0 || destinationIndex >= kSwifterKitMIDIDestinationCount
        || wordCount > (kSwifterKitMaximumEventPayloadLength - sizeof(SwifterKitMIDIEventHeader))
                           / sizeof(uint32_t)) {
        return kIOReturnBadArgument;
    }
    const SwifterKitMIDIEventHeader header = {
        .kind = static_cast<uint32_t>(MIDIEventKind::Received),
        .endpointIndex = destinationIndex,
        .wordCount = wordCount,
        .reserved = 0,
    };
    OSData* event = OSData::withCapacity(sizeof(header) + wordCount * sizeof(uint32_t));
    if (event == nullptr || !event->appendBytes(&header, sizeof(header))
        || !event->appendBytes(words, wordCount * sizeof(uint32_t))) {
        OSSafeReleaseNULL(event);
        return kIOReturnNoMemory;
    }
    const kern_return_t result = EnqueueEvent(
        kSwifterKitEventMIDI,
        event->getBytesNoCopy(),
        static_cast<uint32_t>(event->getLength()));
    event->release();
    return result;
}

IOUserMIDIDevice* SwifterKitRuntimeService::CopyMIDIDevice() {
    if (ivars == nullptr || ivars->midiLock == nullptr) {
        return nullptr;
    }
    IOLockLock(ivars->midiLock);
    IOUserMIDIDevice* device = ivars->midiDevice;
    if (device != nullptr) {
        device->retain();
    }
    IOLockUnlock(ivars->midiLock);
    return device;
}

kern_return_t SwifterKitRuntimeService::StartIO(OSArray* deviceList) {
    IOUserMIDIDevice* device = CopyMIDIDevice();
    if (device == nullptr) {
        return kIOReturnNotReady;
    }
    kern_return_t result = super::StartIO(deviceList);
    if (result == kIOReturnSuccess) {
        result = device->StartIO();
        if (result != kIOReturnSuccess) {
            (void)super::StopIO();
        }
    }
    if (result == kIOReturnSuccess) {
        result = QueueLifecycleEvent(this, MIDIEventKind::StartIO);
        if (result != kIOReturnSuccess) {
            (void)device->StopIO();
            (void)super::StopIO();
        }
    }
    device->release();
    return result;
}

kern_return_t SwifterKitRuntimeService::StopIO() {
    kern_return_t deviceResult = kIOReturnNotReady;
    IOUserMIDIDevice* device = CopyMIDIDevice();
    if (device != nullptr) {
        deviceResult = device->StopIO();
        device->release();
    }
    const kern_return_t driverResult = super::StopIO();
    const kern_return_t eventResult = QueueLifecycleEvent(this, MIDIEventKind::StopIO);
    if (deviceResult != kIOReturnSuccess) {
        return deviceResult;
    }
    return driverResult != kIOReturnSuccess ? driverResult : eventResult;
}

#endif
