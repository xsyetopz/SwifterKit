#include "SwifterKitRuntimeVideoDevice.h"

#if SWIFTERKIT_ENABLE_VIDEO
    #include <DriverKit/IOBufferMemoryDescriptor.h>
    #include <DriverKit/IOLib.h>
    #include <DriverKit/IOMemoryMap.h>
    #include <DriverKit/OSArray.h>
    #include <DriverKit/OSData.h>
    #include <DriverKit/OSString.h>
    #include <VideoDriverKit/VideoDriverKit.h>

    #include "SwifterKitRuntimeProtocol.h"
    #include "SwifterKitRuntimeService.h"
    #include "SwifterKitRuntimeVideoDeviceState.h"
    #include "SwifterKitRuntimeVideoProtocol.h"

// Device, stream, buffer, control, and custom-property contract (opcodes 0x0C20-0x0C2D):
// - MemberCommand runs under videoLock, like every other device command, and validates each
//   payload length, reserved field, index, and selector before calling VideoDriverKit.
// - IOUserVideoBuffer.iig allows SetDataMemoryDescriptor and SetControlMemoryDescriptor only
//   during PerformDeviceConfigurationChange, so buffer capacities, queue sizes, buffer IDs, and
//   the stream buffer list change there too: RequestMemberChange records one pending change and
//   requests a configuration change, a second request while one is pending fails with
//   kIOReturnBusy, and ApplyMemberChange consumes it. IO is stopped while it runs.
// - bufferLock guards the maps, descriptors, capacities, buffer IDs, and the pending change.
//   Buffer reads, writes, and queue entries take it briefly; no VideoDriverKit call runs under it.
// - Swift names buffers by index. The runtime translates indexes to the current IOStreamBufferID
//   when it enqueues and back when it dequeues.
namespace {
    enum : uint32_t {
        kChangeCapacity = 1,
        kChangeQueueCount = 2,
        kChangeBufferID = 3,
        kChangeBufferAttached = 4,
    };

    template<typename Type>
    const Type* Payload(const uint8_t* payload, uint32_t payloadLength) {
        return payload != nullptr && payloadLength == sizeof(Type)
                   ? reinterpret_cast<const Type*>(payload)
                   : nullptr;
    }

    bool FindControl(uint32_t identifier, uint32_t* index) {
        for (uint32_t candidate = 0; candidate < kSwifterKitVideoControlCount; ++candidate)
            if (kSwifterKitVideoControls[candidate].identifier == identifier) {
                *index = candidate;
                return true;
            }
        return false;
    }

    bool FindProperty(uint32_t identifier, uint32_t* index) {
        for (uint32_t candidate = 0; candidate < kSwifterKitVideoCustomPropertyCount; ++candidate)
            if (kSwifterKitVideoCustomProperties[candidate].identifier == identifier) {
                *index = candidate;
                return true;
            }
        return false;
    }

    SwifterKitVideoStreamFormat WireFormat(const IOUserVideoStreamBasicDescription& format) {
        return {
            __builtin_bit_cast(uint64_t, format.mFrameRate),
            format.mFrameTimeValue,
            format.mFrameTimeScale,
            static_cast<uint32_t>(format.mVideoCodecType),
            format.mVideoCodecFlags,
            format.mWidth,
            format.mHeight,
            0};
    }

    uint64_t Length(const OSSharedPtr<IOMemoryDescriptor>& memory) {
        uint64_t length = 0;
        return memory && memory->GetLength(&length) == kIOReturnSuccess ? length : 0;
    }

    SwifterKitVideoQueueState WireQueue(
        const IOStreamBufferQueue* queue,
        const OSSharedPtr<IOMemoryDescriptor>& memory) {
        SwifterKitVideoQueueState state = {};
        if (queue != nullptr) {
            state.entryCount = queue->entryCount;
            state.headIndex = __atomic_load_n(&queue->headIndex, __ATOMIC_ACQUIRE);
            state.tailIndex = __atomic_load_n(&queue->tailIndex, __ATOMIC_ACQUIRE);
        }
        state.memoryLength = Length(memory);
        return state;
    }

    kern_return_t Respond(const void* bytes, uint32_t length, OSData** response) {
        OSData* data = OSData::withBytes(bytes, length);
        if (data == nullptr)
            return kIOReturnNoMemory;
        *response = data;
        return kIOReturnSuccess;
    }
}  // namespace

kern_return_t SwifterKitRuntimeVideoDevice::MemberCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || response == nullptr)
        return kIOReturnBadArgument;
    switch (static_cast<SwifterKitRuntimeOpcode>(opcode)) {
        case SwifterKitRuntimeOpcode::VideoGetDeviceState:
            return payloadLength == 0 ? CopyDeviceState(response) : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::VideoSetDeviceProperty:
            return SetDeviceProperty(Payload<SwifterKitVideoMemberValue>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::VideoSetPreferredChannelLayout: {
            if (payload == nullptr || payloadLength < sizeof(SwifterKitVideoChannelLayoutHeader))
                return kIOReturnBadArgument;
            const auto* header =
                reinterpret_cast<const SwifterKitVideoChannelLayoutHeader*>(payload);
            if (header->isInput > 1 || header->count == 0
                || header->count > kSwifterKitVideoMaximumChannelLabels
                || payloadLength != sizeof(*header) + header->count * sizeof(uint32_t))
                return kIOReturnBadArgument;
            IOUserVideoChannelLabel labels[kSwifterKitVideoMaximumChannelLabels] = {};
            for (uint32_t index = 0; index < header->count; ++index) {
                uint32_t label = 0;
                memcpy(&label, payload + sizeof(*header) + index * sizeof(label), sizeof(label));
                labels[index] = static_cast<IOUserVideoChannelLabel>(label);
            }
            return header->isInput != 0 ? SetPreferredInputChannelLayout(labels, header->count)
                                        : SetPreferredOutputChannelLayout(labels, header->count);
        }
        case SwifterKitRuntimeOpcode::VideoGetStreamState:
            return CopyStreamState(
                Payload<SwifterKitVideoMemberRequest>(payload, payloadLength),
                response);
        case SwifterKitRuntimeOpcode::VideoSetStreamProperty:
            return SetStreamProperty(
                Payload<SwifterKitVideoMemberProperty>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::VideoGetBufferInfo:
            return CopyBufferInfo(
                Payload<SwifterKitVideoMemberRequest>(payload, payloadLength),
                response);
        case SwifterKitRuntimeOpcode::VideoSetBufferProperty:
            return SetBufferProperty(
                Payload<SwifterKitVideoBufferProperty>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::VideoGetControlInfo:
            return CopyControlInfo(
                Payload<SwifterKitVideoMemberRequest>(payload, payloadLength),
                response);
        case SwifterKitRuntimeOpcode::VideoSetControlProperty:
            return SetControlProperty(
                Payload<SwifterKitVideoMemberProperty>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::VideoRemoveSelectorItems: {
            if (payload == nullptr || payloadLength < sizeof(SwifterKitVideoSelectorRemoval))
                return kIOReturnBadArgument;
            const auto* header = reinterpret_cast<const SwifterKitVideoSelectorRemoval*>(payload);
            if (header->count == 0 || header->count > kSwifterKitVideoMaximumSelectorItems
                || payloadLength != sizeof(*header) + header->count * sizeof(uint32_t))
                return kIOReturnBadArgument;
            return RemoveSelectorItems(header, payload + sizeof(*header));
        }
        case SwifterKitRuntimeOpcode::VideoGetCustomPropertyInfo:
            return CopyCustomPropertyInfo(
                Payload<SwifterKitVideoMemberRequest>(payload, payloadLength),
                response);
        case SwifterKitRuntimeOpcode::VideoSetMemberAttachment:
            return SetMemberAttachment(
                Payload<SwifterKitVideoMemberAttachment>(payload, payloadLength));
        case SwifterKitRuntimeOpcode::VideoEnqueueOutputBuffer:
            return payload != nullptr
                           && payloadLength == sizeof(uint32_t) + sizeof(SwifterKitVideoQueueEntry)
                       ? EnqueueOutputBuffer(
                             *reinterpret_cast<const uint32_t*>(payload),
                             reinterpret_cast<const SwifterKitVideoQueueEntry*>(
                                 payload + sizeof(uint32_t)))
                       : kIOReturnBadArgument;
        case SwifterKitRuntimeOpcode::VideoGetStreamMemoryObjectID: {
            const auto* request = Payload<SwifterKitVideoMemberRequest>(payload, payloadLength);
            if (request == nullptr || request->identifier >= kSwifterKitVideoStreamCount)
                return kIOReturnBadArgument;
            if (ivars->streams[request->identifier] == nullptr)
                return kIOReturnNotReady;
            const uint32_t wire[2] = {
                ivars->streams[request->identifier]->GetMemoryObjectID(request->argument),
                0};
            return Respond(wire, sizeof(wire), response);
        }
        default:
            return kIOReturnUnsupported;
    }
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyDeviceState(OSData** response) {
    SwifterKitVideoDeviceState state = {};
    state.objectID = GetObjectID();
    state.canBeDefaultInput = CanBeDefaultInputDevice() != 0 ? 1 : 0;
    state.canBeDefaultOutput = CanBeDefaultOutputDevice() != 0 ? 1 : 0;
    state.canBeDefaultSystemOutput = CanBeDefaultSystemOutputDevice() != 0 ? 1 : 0;
    state.inputSafetyOffset = GetInputSafetyOffset();
    state.outputSafetyOffset = GetOutputSafetyOffset();
    uint32_t left = 0;
    uint32_t right = 0;
    uint64_t times[4] = {};
    GetPreferredChannelsForStereo(&left, &right);
    GetCurrentClientIOTime(true, &times[0], &times[1]);
    GetCurrentClientIOTime(false, &times[2], &times[3]);
    state.preferredLeft = left;
    state.preferredRight = right;
    state.inputSampleTime = times[0];
    state.inputHostTime = times[1];
    state.outputSampleTime = times[2];
    state.outputHostTime = times[3];
    return Respond(&state, sizeof(state), response);
}

kern_return_t SwifterKitRuntimeVideoDevice::SetDeviceProperty(
    const SwifterKitVideoMemberValue* request) {
    if (request == nullptr || request->reserved != 0)
        return kIOReturnBadArgument;
    const uint64_t value = request->value;
    const bool isFlag =
        request->selector >= kSwifterKitVideoDevicePropertyCanBeDefaultInput
        && request->selector <= kSwifterKitVideoDevicePropertyCanBeDefaultSystemOutput;
    if ((isFlag && value > 1)
        || (!isFlag && request->selector != kSwifterKitVideoDevicePropertyPreferredStereoChannels
            && value > UINT32_MAX))
        return kIOReturnBadArgument;
    const auto low = static_cast<uint32_t>(value);
    const auto high = static_cast<uint32_t>(value >> 32);
    switch (request->selector) {
        case kSwifterKitVideoDevicePropertyCanBeDefaultInput:
            return SetCanBeDefaultInputDevice(value != 0);
        case kSwifterKitVideoDevicePropertyCanBeDefaultOutput:
            return SetCanBeDefaultOutputDevice(value != 0);
        case kSwifterKitVideoDevicePropertyCanBeDefaultSystemOutput:
            return SetCanBeDefaultSystemOutputDevice(value != 0);
        case kSwifterKitVideoDevicePropertyInputSafetyOffset:
        case kSwifterKitVideoDevicePropertyOutputSafetyOffset:
            return SwifterKitRequestVideoStructureChange(this, request->selector, 0, low);
        case kSwifterKitVideoDevicePropertyPreferredStereoChannels:
            if (low == 0 || high == 0 || low == high)
                return kIOReturnBadArgument;
            return SetPreferredChannelsForStereo(low, high);
        default:
            return kIOReturnBadArgument;
    }
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyStreamState(
    const SwifterKitVideoMemberRequest* request,
    OSData** response) {
    if (request == nullptr || request->argument != 0
        || request->identifier >= kSwifterKitVideoStreamCount)
        return kIOReturnBadArgument;
    const uint32_t index = request->identifier;
    auto* stream = ivars->streams[index];
    if (stream == nullptr)
        return kIOReturnNotReady;
    constexpr uint32_t kFormats = kSwifterKitVideoMaximumStreamFormats;
    IOUserVideoStreamBasicDescription formats[kFormats] = {};
    const size_t available = stream->GetNumberAvailableStreamFormats();
    const auto formatCount = static_cast<uint32_t>(
        stream->GetAvailableStreamFormats(formats, available < kFormats ? available : kFormats));
    uint32_t bufferIDs[kSwifterKitVideoMaximumBuffers] = {};
    uint32_t bufferCount = 0;
    OSSharedPtr<OSArray> list = stream->GetBufferList();
    for (uint32_t item = 0;
         list && item < list->getCount() && bufferCount < kSwifterKitVideoMaximumBuffers;
         ++item)
        if (auto* buffer = OSDynamicCast(IOUserVideoBuffer, list->getObject(item)))
            bufferIDs[bufferCount++] = buffer->getBufferID();
    SwifterKitVideoStreamState state = {};
    state.objectID = stream->GetObjectID();
    state.direction = static_cast<uint32_t>(stream->GetStreamDirection());
    state.terminalType = static_cast<uint32_t>(stream->GetTerminalType());
    state.startingChannel = stream->GetStartingChannel();
    state.isActive = stream->GetStreamIsActive() ? 1 : 0;
    state.isAttached = ivars->streamDetached[index] ? 0 : 1;
    state.formatCount = formatCount > kFormats ? kFormats : formatCount;
    const uint32_t listed = stream->GetBufferCount();
    state.bufferCount = listed < bufferCount ? listed : bufferCount;
    IOLockLock(ivars->bufferLock);
    state.dataCapacity = ivars->dataCapacity[index];
    state.controlCapacity = ivars->controlCapacity[index];
    IOLockUnlock(ivars->bufferLock);
    state.inputQueue = WireQueue(stream->GetInputQueue(), stream->GetInputQueueMemoryDescriptor());
    state.outputQueue =
        WireQueue(stream->GetOutputQueue(), stream->GetOutputQueueMemoryDescriptor());
    SwifterKitVideoStreamFormat wire[kFormats + 1] = {WireFormat(stream->GetCurrentStreamFormat())};
    for (uint32_t format = 0; format < state.formatCount; ++format)
        wire[format + 1] = WireFormat(formats[format]);
    const uint32_t formatBytes = (state.formatCount + 1) * sizeof(wire[0]);
    const uint32_t idBytes = state.bufferCount * sizeof(uint32_t);
    OSData* data = OSData::withCapacity(sizeof(state) + formatBytes + idBytes);
    if (data == nullptr)
        return kIOReturnNoMemory;
    if (!data->appendBytes(&state, sizeof(state)) || !data->appendBytes(wire, formatBytes)
        || (idBytes > 0 && !data->appendBytes(bufferIDs, idBytes))) {
        data->release();
        return kIOReturnNoMemory;
    }
    *response = data;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeVideoDevice::SetStreamProperty(
    const SwifterKitVideoMemberProperty* request) {
    if (request == nullptr || request->identifier >= kSwifterKitVideoStreamCount)
        return kIOReturnBadArgument;
    const uint32_t index = request->identifier;
    auto* stream = ivars->streams[index];
    if (stream == nullptr)
        return kIOReturnNotReady;
    const uint64_t value = request->value;
    const auto word = static_cast<uint32_t>(value);
    if ((request->selector != kSwifterKitVideoStreamPropertyBufferCapacity && value > UINT32_MAX)
        || (request->selector == kSwifterKitVideoStreamPropertyIsActive && value > 1))
        return kIOReturnBadArgument;
    switch (request->selector) {
        case kSwifterKitVideoStreamPropertyIsActive:
            return stream->SetStreamIsActive(word != 0);
        case kSwifterKitVideoStreamPropertyStartingChannel:
            return word == 0 ? kIOReturnBadArgument : stream->SetStartingChannel(word);
        case kSwifterKitVideoStreamPropertyTerminalType:
            return stream->SetTerminalType(static_cast<IOUserVideoStreamTerminalType>(word));
        case kSwifterKitVideoStreamPropertyCurrentFormat: {
            IOUserVideoStreamBasicDescription formats[kSwifterKitVideoMaximumStreamFormats] = {};
            const size_t count =
                stream->GetAvailableStreamFormats(formats, kSwifterKitVideoMaximumStreamFormats);
            return word < count ? stream->SetCurrentStreamFormat(&formats[word])
                                : kIOReturnBadArgument;
        }
        case kSwifterKitVideoStreamPropertyBufferCapacity: {
            const auto data = static_cast<uint32_t>(value);
            const auto control = static_cast<uint32_t>(value >> 32);
            if (data == 0 || data > kSwifterKitVideoMaximumDataCapacity || control == 0
                || control > kSwifterKitVideoMaximumControlCapacity)
                return kIOReturnBadArgument;
            return RequestMemberChange(kChangeCapacity, index, 0, value);
        }
        case kSwifterKitVideoStreamPropertyQueueEntryCount:
            return word == 0 || word > kSwifterKitVideoMaximumQueueEntries
                       ? kIOReturnBadArgument
                       : RequestMemberChange(kChangeQueueCount, index, 0, word);
        default:
            return kIOReturnBadArgument;
    }
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyBufferInfo(
    const SwifterKitVideoMemberRequest* request,
    OSData** response) {
    if (request == nullptr || request->identifier >= kSwifterKitVideoStreamCount
        || request->argument >= kSwifterKitVideoStreams[request->identifier].bufferCount)
        return kIOReturnBadArgument;
    auto* stream = ivars->streams[request->identifier];
    IOUserVideoBuffer* configured = ivars->buffers[request->identifier][request->argument];
    if (stream == nullptr || configured == nullptr)
        return kIOReturnNotReady;
    // GetBufferWithID finds the buffer only while it is in the stream's buffer list.
    OSSharedPtr<IOUserVideoBuffer> listed = stream->GetBufferWithID(configured->getBufferID());
    IOUserVideoBuffer* buffer = listed ? listed.get() : configured;
    SwifterKitVideoBufferInfo info = {};
    info.objectID = buffer->GetObjectID();
    info.classID = static_cast<uint32_t>(buffer->GetClassID());
    info.baseClassID = static_cast<uint32_t>(buffer->GetBaseClassID());
    info.bufferID = buffer->getBufferID();
    info.isAttached = listed ? 1 : 0;
    info.dataMemoryObjectID = stream->_GetOutputDataMemoryObjectID(info.objectID);
    info.controlMemoryObjectID = stream->_GetOutputControlMemoryObjectID(info.objectID);
    info.dataLength = Length(buffer->GetDataMemoryDescriptor());
    info.controlLength = Length(buffer->GetControlMemoryDescriptor());
    info.outputDataLength = Length(stream->GetOutputDataMemoryDescriptor(info.dataMemoryObjectID));
    info.outputControlLength =
        Length(stream->GetOutputControlMemoryDescriptor(info.controlMemoryObjectID));
    return Respond(&info, sizeof(info), response);
}

kern_return_t SwifterKitRuntimeVideoDevice::SetBufferProperty(
    const SwifterKitVideoBufferProperty* request) {
    if (request == nullptr || request->reserved != 0
        || request->streamIndex >= kSwifterKitVideoStreamCount
        || request->bufferIndex >= kSwifterKitVideoStreams[request->streamIndex].bufferCount)
        return kIOReturnBadArgument;
    if (ivars->buffers[request->streamIndex][request->bufferIndex] == nullptr)
        return kIOReturnNotReady;
    const uint64_t value = request->value;
    if (request->selector == kSwifterKitVideoBufferPropertyBufferID) {
        if (value >= UINT32_MAX)
            return kIOReturnBadArgument;
        return RequestMemberChange(
            kChangeBufferID,
            request->streamIndex,
            request->bufferIndex,
            value);
    }
    if (request->selector == kSwifterKitVideoBufferPropertyIsAttached && value <= 1)
        return RequestMemberChange(
            kChangeBufferAttached,
            request->streamIndex,
            request->bufferIndex,
            value);
    return kIOReturnBadArgument;
}

kern_return_t SwifterKitRuntimeVideoDevice::RequestMemberChange(
    uint32_t kind,
    uint32_t stream,
    uint32_t buffer,
    uint64_t value) {
    IOLockLock(ivars->bufferLock);
    const bool busy = ivars->pendingChangeKind != 0;
    if (!busy) {
        ivars->pendingChangeKind = kind;
        ivars->pendingChangeStream = stream;
        ivars->pendingChangeBuffer = buffer;
        ivars->pendingChangeValue = value;
    }
    IOLockUnlock(ivars->bufferLock);
    if (busy)
        return kIOReturnBusy;
    const kern_return_t result =
        RequestDeviceConfigurationChange(kSwifterKitVideoMemberChangeAction, nullptr);
    if (result != kIOReturnSuccess) {
        IOLockLock(ivars->bufferLock);
        ivars->pendingChangeKind = 0;
        IOLockUnlock(ivars->bufferLock);
    }
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::ApplyMemberChange() {
    IOLockLock(ivars->bufferLock);
    const uint32_t kind = ivars->pendingChangeKind;
    const uint32_t stream = ivars->pendingChangeStream;
    const uint32_t buffer = ivars->pendingChangeBuffer;
    const uint64_t value = ivars->pendingChangeValue;
    ivars->pendingChangeKind = 0;
    IOLockUnlock(ivars->bufferLock);
    if (stream >= kSwifterKitVideoStreamCount || ivars->streams[stream] == nullptr)
        return kIOReturnBadArgument;
    const uint32_t bufferCount = kSwifterKitVideoStreams[stream].bufferCount;
    switch (kind) {
        case kChangeCapacity:
            return ApplyBufferCapacity(stream, value);
        case kChangeQueueCount: {
            // A failed create restores the previous queue length instead of leaving none.
            auto* target = ivars->streams[stream];
            const IOStreamBufferQueue* previous = target->GetOutputQueue();
            const uint32_t previousCount = previous != nullptr ? previous->entryCount : 0;
            kern_return_t result = target->destroyQueues();
            if (result == kIOReturnSuccess) {
                result = target->createQueues(static_cast<uint32_t>(value), 0);
                if (result != kIOReturnSuccess && previousCount != 0)
                    (void)target->createQueues(previousCount, 0);
            }
            return result;
        }
        case kChangeBufferID: {
            if (buffer >= bufferCount || ivars->buffers[stream][buffer] == nullptr)
                return kIOReturnBadArgument;
            const auto newID = static_cast<IOStreamBufferID>(value);
            IOLockLock(ivars->bufferLock);
            bool unique = true;
            for (uint32_t other = 0; other < bufferCount; ++other)
                unique = unique && (other == buffer || ivars->bufferIDs[stream][other] != newID);
            IOLockUnlock(ivars->bufferLock);
            if (!unique)
                return kIOReturnBadArgument;
            ivars->buffers[stream][buffer]->setBufferID(newID);
            IOLockLock(ivars->bufferLock);
            ivars->bufferIDs[stream][buffer] = newID;
            IOLockUnlock(ivars->bufferLock);
            return kIOReturnSuccess;
        }
        case kChangeBufferAttached:
            return buffer < bufferCount ? ApplyBufferList(stream, buffer, value != 0)
                                        : kIOReturnBadArgument;
        default:
            return kIOReturnBadArgument;
    }
}

kern_return_t SwifterKitRuntimeVideoDevice::ApplyBufferCapacity(uint32_t stream, uint64_t value) {
    const uint32_t bufferCount = kSwifterKitVideoStreams[stream].bufferCount;
    const uint32_t sizes[2] = {static_cast<uint32_t>(value), static_cast<uint32_t>(value >> 32)};
    IOBufferMemoryDescriptor* descriptors[2][kSwifterKitVideoMaximumBuffers] = {};
    IOMemoryMap* maps[2][kSwifterKitVideoMaximumBuffers] = {};
    kern_return_t result = kIOReturnSuccess;
    for (uint32_t buffer = 0; result == kIOReturnSuccess && buffer < bufferCount; ++buffer)
        for (uint32_t plane = 0; result == kIOReturnSuccess && plane < 2; ++plane) {
            result = IOBufferMemoryDescriptor::Create(
                kIOMemoryDirectionInOut,
                sizes[plane],
                0,
                &descriptors[plane][buffer]);
            if (result == kIOReturnSuccess)
                result = descriptors[plane][buffer]
                             ->CreateMapping(0, 0, 0, sizes[plane], 0, &maps[plane][buffer]);
        }
    uint32_t touched = 0;
    for (uint32_t buffer = 0; result == kIOReturnSuccess && buffer < bufferCount; ++buffer) {
        IOUserVideoBuffer* target = ivars->buffers[stream][buffer];
        result = target == nullptr ? kIOReturnNotReady
                                   : target->SetDataMemoryDescriptor(descriptors[0][buffer]);
        touched = buffer + 1;
        if (result == kIOReturnSuccess)
            result = target->SetControlMemoryDescriptor(descriptors[1][buffer]);
    }
    if (result != kIOReturnSuccess) {
        // Roll every buffer set so far, including a half-set one, back to the descriptors the
        // ivars still hold; only this configuration change replaces them.
        for (uint32_t buffer = 0; buffer < touched; ++buffer) {
            IOUserVideoBuffer* target = ivars->buffers[stream][buffer];
            if (target == nullptr)
                continue;
            if (ivars->dataDescriptors[stream][buffer] != nullptr)
                (void)target->SetDataMemoryDescriptor(ivars->dataDescriptors[stream][buffer]);
            if (ivars->controlDescriptors[stream][buffer] != nullptr)
                (void)target->SetControlMemoryDescriptor(ivars->controlDescriptors[stream][buffer]);
        }
    }
    if (result == kIOReturnSuccess) {
        // Swap under the lock; the previous objects are released after it.
        IOLockLock(ivars->bufferLock);
        for (uint32_t buffer = 0; buffer < bufferCount; ++buffer) {
            auto* oldData = ivars->dataDescriptors[stream][buffer];
            auto* oldControl = ivars->controlDescriptors[stream][buffer];
            auto* oldDataMap = ivars->dataMaps[stream][buffer];
            auto* oldControlMap = ivars->controlMaps[stream][buffer];
            ivars->dataDescriptors[stream][buffer] = descriptors[0][buffer];
            ivars->controlDescriptors[stream][buffer] = descriptors[1][buffer];
            ivars->dataMaps[stream][buffer] = maps[0][buffer];
            ivars->controlMaps[stream][buffer] = maps[1][buffer];
            descriptors[0][buffer] = oldData;
            descriptors[1][buffer] = oldControl;
            maps[0][buffer] = oldDataMap;
            maps[1][buffer] = oldControlMap;
        }
        ivars->dataCapacity[stream] = sizes[0];
        ivars->controlCapacity[stream] = sizes[1];
        IOLockUnlock(ivars->bufferLock);
    }
    for (uint32_t plane = 0; plane < 2; ++plane)
        for (uint32_t buffer = 0; buffer < bufferCount; ++buffer) {
            OSSafeReleaseNULL(maps[plane][buffer]);
            OSSafeReleaseNULL(descriptors[plane][buffer]);
        }
    return result;
}

kern_return_t
    SwifterKitRuntimeVideoDevice::ApplyBufferList(uint32_t stream, uint32_t buffer, bool attach) {
    if (ivars->bufferDetached[stream][buffer] != attach)
        return kIOReturnSuccess;
    auto* target = ivars->streams[stream];
    kern_return_t result = kIOReturnSuccess;
    if (attach) {
        result = target->addBuffer(ivars->buffers[stream][buffer]);
    } else {
        // IOUserVideoStream removes buffers only all at once; the others are added back. Both
        // lists are built before anything is removed, and a failed re-add restores the
        // previous list.
        const uint32_t bufferCount = kSwifterKitVideoStreams[stream].bufferCount;
        OSArray* remaining = OSArray::withCapacity(bufferCount);
        OSArray* previous = OSArray::withCapacity(bufferCount);
        result = remaining == nullptr || previous == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        for (uint32_t other = 0; result == kIOReturnSuccess && other < bufferCount; ++other) {
            if (ivars->bufferDetached[stream][other])
                continue;
            if (!previous->setObject(ivars->buffers[stream][other])
                || (other != buffer && !remaining->setObject(ivars->buffers[stream][other])))
                result = kIOReturnNoMemory;
        }
        if (result == kIOReturnSuccess)
            result = target->removeAllBuffers();
        if (result == kIOReturnSuccess && remaining->getCount() > 0) {
            result = target->addBuffers(remaining);
            if (result != kIOReturnSuccess) {
                (void)target->removeAllBuffers();
                (void)target->addBuffers(previous);
            }
        }
        OSSafeReleaseNULL(remaining);
        OSSafeReleaseNULL(previous);
    }
    if (result == kIOReturnSuccess) {
        IOLockLock(ivars->bufferLock);
        ivars->bufferDetached[stream][buffer] = !attach;
        IOLockUnlock(ivars->bufferLock);
    }
    return result;
}

kern_return_t SwifterKitRuntimeVideoDevice::EnqueueOutputBuffer(
    uint32_t streamIndex,
    const SwifterKitVideoQueueEntry* entry) {
    IOStreamBufferQueueEntry native = {};
    const kern_return_t result = NativeEntry(streamIndex, entry, &native);
    if (result != kIOReturnSuccess)
        return result;
    OSSharedPtr<IOUserVideoBuffer> buffer =
        ivars->streams[streamIndex]->GetBufferWithID(native.bufferID);
    return buffer ? ivars->streams[streamIndex]->enqueueOutputBuffer(
                        buffer.get(),
                        native.dataOffset,
                        native.dataLength,
                        native.controlOffset,
                        native.controlLength)
                  : kIOReturnNotFound;
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyControlInfo(
    const SwifterKitVideoMemberRequest* request,
    OSData** response) {
    uint32_t index = 0;
    if (request == nullptr || request->argument != 0)
        return kIOReturnBadArgument;
    if (!FindControl(request->identifier, &index) || ivars->controls[index] == nullptr)
        return kIOReturnNotFound;
    auto* control = ivars->controls[index];
    SwifterKitVideoControlInfo info = {};
    info.objectID = control->GetObjectID();
    info.kind = kSwifterKitVideoControls[index].kind;
    info.scope = static_cast<uint32_t>(control->GetControlScope());
    info.element = static_cast<uint32_t>(control->GetControlElement());
    info.isSettable = control->GetIsSettable() ? 1 : 0;
    info.isAttached = ivars->controlDetached[index] ? 0 : 1;
    info.owningDeviceID = control->GetOwningDeviceID();
    if (auto* slider = OSDynamicCast(IOUserVideoSliderControl, control)) {
        const IOUserVideoSliderRange range = slider->GetRange();
        info.sliderMinimum = range.m_min;
        info.sliderMaximum = range.m_max;
    }
    if (auto* pan = OSDynamicCast(IOUserVideoStereoPanControl, control)) {
        IOUserVideoObjectPropertyElement left = 0;
        IOUserVideoObjectPropertyElement right = 0;
        pan->GetPanningChannels(&left, &right);
        info.panLeft = left;
        info.panRight = right;
    }
    IOUserVideoSelectorValueDescription items[kSwifterKitVideoMaximumSelectorItems] = {};
    if (auto* selector = OSDynamicCast(IOUserVideoSelectorControl, control)) {
        const size_t count = selector->GetControlValuesCount();
        info.itemCount = static_cast<uint32_t>(selector->GetControlValueDescriptions(
            items,
            count < kSwifterKitVideoMaximumSelectorItems ? count
                                                         : kSwifterKitVideoMaximumSelectorItems));
    }
    OSData* data = OSData::withCapacity(
        sizeof(info) + info.itemCount * (8 + kSwifterKitVideoNameMaximumLength));
    bool appended = data != nullptr && data->appendBytes(&info, sizeof(info));
    for (uint32_t item = 0; appended && item < info.itemCount; ++item) {
        const char* name = items[item].m_name ? items[item].m_name->getCStringNoCopy() : "";
        const size_t length = strnlen(name, kSwifterKitVideoNameMaximumLength + 1);
        const uint32_t header[2] = {items[item].m_value, static_cast<uint32_t>(length)};
        appended = length <= kSwifterKitVideoNameMaximumLength
                   && data->appendBytes(header, sizeof(header)) && data->appendBytes(name, length);
    }
    if (!appended) {
        OSSafeReleaseNULL(data);
        return kIOReturnNoMemory;
    }
    *response = data;
    return kIOReturnSuccess;
}

kern_return_t SwifterKitRuntimeVideoDevice::SetControlProperty(
    const SwifterKitVideoMemberProperty* request) {
    uint32_t index = 0;
    if (request == nullptr)
        return kIOReturnBadArgument;
    if (!FindControl(request->identifier, &index) || ivars->controls[index] == nullptr)
        return kIOReturnNotFound;
    const auto low = static_cast<uint32_t>(request->value);
    const auto high = static_cast<uint32_t>(request->value >> 32);
    auto* control = ivars->controls[index];
    if (request->selector == kSwifterKitVideoControlPropertySliderRange) {
        auto* slider = OSDynamicCast(IOUserVideoSliderControl, control);
        if (slider == nullptr || low > high)
            return kIOReturnBadArgument;
        return slider->SetRange(IOUserVideoSliderRange {low, high});
    }
    if (request->selector == kSwifterKitVideoControlPropertyPanningChannels) {
        auto* pan = OSDynamicCast(IOUserVideoStereoPanControl, control);
        if (pan == nullptr || low == high)
            return kIOReturnBadArgument;
        return pan->SetPanningChannels(low, high);
    }
    return kIOReturnBadArgument;
}

kern_return_t SwifterKitRuntimeVideoDevice::RemoveSelectorItems(
    const SwifterKitVideoSelectorRemoval* request,
    const uint8_t* values) {
    uint32_t index = 0;
    if (!FindControl(request->identifier, &index) || ivars->controls[index] == nullptr)
        return kIOReturnNotFound;
    auto* selector = OSDynamicCast(IOUserVideoSelectorControl, ivars->controls[index]);
    if (selector == nullptr)
        return kIOReturnBadArgument;
    IOUserVideoSelectorValueDescription items[kSwifterKitVideoMaximumSelectorItems] = {};
    const size_t available =
        selector->GetControlValueDescriptions(items, kSwifterKitVideoMaximumSelectorItems);
    IOUserVideoSelectorValueDescription removed[kSwifterKitVideoMaximumSelectorItems] = {};
    for (uint32_t value = 0; value < request->count; ++value) {
        uint32_t wanted = 0;
        memcpy(&wanted, values + value * sizeof(wanted), sizeof(wanted));
        size_t match = available;
        for (size_t item = 0; item < available; ++item)
            if (items[item].m_value == wanted)
                match = item;
        if (match == available)
            return kIOReturnNotFound;
        removed[value] = items[match];
    }
    return selector->RemoveControlValueDescriptions(removed, request->count);
}

kern_return_t SwifterKitRuntimeVideoDevice::CopyCustomPropertyInfo(
    const SwifterKitVideoMemberRequest* request,
    OSData** response) {
    uint32_t index = 0;
    if (request == nullptr || request->argument != 0)
        return kIOReturnBadArgument;
    if (!FindProperty(request->identifier, &index) || ivars->customProperties[index] == nullptr)
        return kIOReturnNotFound;
    auto* property = ivars->customProperties[index];
    const IOUserVideoCustomPropertyInfo info = property->GetCustomPropertyInfo();
    const SwifterKitVideoCustomPropertyInfo wire = {
        property->GetObjectID(),
        static_cast<uint32_t>(info.mSelector),
        static_cast<uint32_t>(info.mPropertyDataType),
        static_cast<uint32_t>(info.mQualifierDataType),
        ivars->customPropertyOwners[index],
        0};
    return Respond(&wire, sizeof(wire), response);
}

kern_return_t SwifterKitRuntimeVideoDevice::SetMemberAttachment(
    const SwifterKitVideoMemberAttachment* request) {
    if (request == nullptr || request->reserved != 0 || request->attached > 1)
        return kIOReturnBadArgument;
    const bool attach = request->attached != 0;
    uint32_t index = request->identifier;
    if (request->kind == kSwifterKitVideoMemberStream) {
        if (index >= kSwifterKitVideoStreamCount)
            return kIOReturnBadArgument;
        if (ivars->streams[index] == nullptr)
            return kIOReturnNotReady;
        if (ivars->streamDetached[index] != attach)
            return kIOReturnSuccess;
        return SwifterKitRequestVideoStructureChange(
            this,
            kSwifterKitVideoChangeStreamAttachment,
            index,
            attach ? 1 : 0);
    }
    if (request->kind != kSwifterKitVideoMemberControl)
        return kIOReturnBadArgument;
    if (!FindControl(request->identifier, &index) || ivars->controls[index] == nullptr)
        return kIOReturnNotFound;
    if (ivars->controlDetached[index] != attach)
        return kIOReturnSuccess;
    if (attach)
        ivars->controls[index]->_SetOwningDeviceID(GetObjectID());
    const kern_return_t result =
        attach ? AddControl(ivars->controls[index]) : RemoveControl(ivars->controls[index]);
    if (result == kIOReturnSuccess)
        ivars->controlDetached[index] = !attach;
    return result;
}
#endif
