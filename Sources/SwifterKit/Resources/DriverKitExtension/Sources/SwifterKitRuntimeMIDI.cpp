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
    constexpr uint32_t kMIDIEventType = 0x0800;

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
        return service->EnqueueEvent(kMIDIEventType, &event, sizeof(event));
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartMIDI() {
    if (ivars == nullptr || ivars->midiDevice != nullptr) {
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
    if (result == kIOReturnSuccess) {
        result = AddObject(device.get());
    }
    if (result == kIOReturnSuccess) {
        device->retain();
        ivars->midiDevice = device.get();
        entity->retain();
        ivars->midiEntity = entity.get();
    }

    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitMIDISourceCount;
         ++index) {
        auto source = entity->GetSource(index);
        if (!source) {
            result = kIOReturnNotFound;
            break;
        }
        source->retain();
        ivars->midiSources[index] = source.get();
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
            ivars->midiDestinations[index] = destination.get();
        }
    }

    if (result != kIOReturnSuccess) {
        StopMIDI();
    }
    return result;
}

void SwifterKitRuntimeService::StopMIDI() {
    if (ivars == nullptr) {
        return;
    }
    for (uint32_t index = 0; index < 32; ++index) {
        if (ivars->midiDestinations[index] != nullptr) {
            (void)ivars->midiDestinations[index]->SetIOBlock(nullptr);
            OSSafeReleaseNULL(ivars->midiDestinations[index]);
        }
        if (ivars->midiSources[index] != nullptr) {
            OSSafeReleaseNULL(ivars->midiSources[index]);
        }
    }
    if (ivars->midiEntity != nullptr) {
        OSSafeReleaseNULL(ivars->midiEntity);
    }
    if (ivars->midiDevice != nullptr) {
        (void)RemoveObject(ivars->midiDevice);
        OSSafeReleaseNULL(ivars->midiDevice);
    }
}

kern_return_t SwifterKitRuntimeService::MIDICommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength) {
    if (ivars == nullptr || payload == nullptr
        || opcode != static_cast<uint32_t>(SwifterKitRuntimeOpcode::MIDISend)
        || payloadLength < sizeof(SwifterKitMIDIHeader)) {
        return kIOReturnBadArgument;
    }
    const auto* header = reinterpret_cast<const SwifterKitMIDIHeader*>(payload);
    const uint64_t expectedLength =
        sizeof(*header) + static_cast<uint64_t>(header->wordCount) * sizeof(IOUserMIDIUMPWord);
    if (header->wordCount == 0 || expectedLength != payloadLength
        || header->endpointIndex >= kSwifterKitMIDISourceCount
        || ivars->midiSources[header->endpointIndex] == nullptr) {
        return kIOReturnBadArgument;
    }
    const auto* words = reinterpret_cast<const IOUserMIDIUMPWord*>(payload + sizeof(*header));
    return ivars->midiSources[header->endpointIndex]->Send(words, header->wordCount);
}

kern_return_t SwifterKitRuntimeService::MIDIReceived(
    uint32_t destinationIndex,
    const uint32_t* words,
    uint32_t wordCount) {
    if (words == nullptr || wordCount == 0 || destinationIndex >= kSwifterKitMIDIDestinationCount
        || wordCount > (kSwifterKitRuntimeMaximumMessageSize - sizeof(uint32_t)
                        - sizeof(SwifterKitMIDIEventHeader))
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
        kMIDIEventType,
        event->getBytesNoCopy(),
        static_cast<uint32_t>(event->getLength()));
    event->release();
    return result;
}

kern_return_t SwifterKitRuntimeService::StartIO(OSArray* deviceList) {
    if (ivars == nullptr || ivars->midiDevice == nullptr) {
        return kIOReturnNotReady;
    }
    kern_return_t result = super::StartIO(deviceList);
    if (result != kIOReturnSuccess) {
        return result;
    }
    result = ivars->midiDevice->StartIO();
    if (result != kIOReturnSuccess) {
        (void)super::StopIO();
        return result;
    }
    result = QueueLifecycleEvent(this, MIDIEventKind::StartIO);
    if (result != kIOReturnSuccess) {
        (void)ivars->midiDevice->StopIO();
        (void)super::StopIO();
    }
    return result;
}

kern_return_t SwifterKitRuntimeService::StopIO() {
    kern_return_t deviceResult = kIOReturnNotReady;
    if (ivars != nullptr && ivars->midiDevice != nullptr) {
        deviceResult = ivars->midiDevice->StopIO();
    }
    const kern_return_t driverResult = super::StopIO();
    const kern_return_t eventResult = QueueLifecycleEvent(this, MIDIEventKind::StopIO);
    if (deviceResult != kIOReturnSuccess) {
        return deviceResult;
    }
    return driverResult != kIOReturnSuccess ? driverResult : eventResult;
}

#endif
