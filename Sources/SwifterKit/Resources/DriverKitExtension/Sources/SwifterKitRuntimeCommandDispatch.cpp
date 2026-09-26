#include "SwifterKitRuntimeCommandDispatch.h"

#include <DriverKit/IOLib.h>
#include <DriverKit/IOReturn.h>
#include <DriverKit/IOUserClient.h>
#include <DriverKit/OSData.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeUserClientHelpers.h"

// The command switch names every SwifterKitRuntimeOpcode and has no default, so -Wswitch
// rejects an opcode that no family handles. Each family helper compiles to kIOReturnUnsupported
// when its capability is off.
namespace {
    struct CommandContext {
        IOUserClient* client;
        SwifterKitRuntimeService* service;
        IOUserClientMethodArguments* arguments;
        uint64_t requestID;
        uint32_t opcode;
        const uint8_t* payload;
        uint32_t payloadLength;
    };

    kern_return_t RespondEmpty(const CommandContext& context) {
        return BuildResponse(
            context.arguments,
            SwifterKitRuntimeMessageKind::Response,
            context.requestID,
            nullptr,
            0);
    }

    // Answers a family call that may return data, taking ownership of `response`.
    kern_return_t RespondToCommand(
        const CommandContext& context,
        kern_return_t result,
        const OSData* response) {
        if (result != kIOReturnSuccess) {
            OSSafeReleaseNULL(response);
            return result;
        }
        if (response == nullptr) {
            return RespondEmpty(context);
        }
        return RespondWithData(result, response, context.arguments, context.requestID);
    }

    kern_return_t DispatchServiceCommand(const CommandContext& context) {
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        OSData* response = nullptr;
        const kern_return_t result = context.service->ServiceCommand(
            context.opcode,
            context.payload,
            context.payloadLength,
            &response);
        return RespondToCommand(context, result, response);
    }

    kern_return_t DispatchInterruptCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_INTERRUPTS
        return HandleInterruptCommand(
            context.service,
            context.arguments,
            context.requestID,
            context.opcode,
            context.payload,
            context.payloadLength);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchFastPathCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_FAST_PATH
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        OSData* response = nullptr;
        const kern_return_t result = context.service->FastPathCommand(
            context.opcode,
            context.payload,
            context.payloadLength,
            &response);
        return RespondToCommand(context, result, response);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchUSBControlTransfer([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_USB
        return HandleUSBControlTransfer(
            context.service,
            context.arguments,
            context.requestID,
            context.payload,
            context.payloadLength);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchUSBPipeTransfer([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_USB
        return HandleUSBPipeTransfer(
            context.service,
            context.arguments,
            context.requestID,
            context.payload,
            context.payloadLength);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchUSBClearStall([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_USB
        const uint8_t* payload = context.payload;
        if (context.service == nullptr || context.payloadLength != 4 || payload[1] > 1
            || payload[2] != 0 || payload[3] != 0) {
            return kIOReturnBadArgument;
        }
        const kern_return_t result = context.service->USBClearStall(payload[0], payload[1] != 0);
        if (result != kIOReturnSuccess) {
            return result;
        }
        return RespondEmpty(context);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchUSBSelectAlternateSetting(
        [[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_USB
        const uint8_t* payload = context.payload;
        if (context.service == nullptr || context.payloadLength != 4 || payload[1] != 0
            || payload[2] != 0 || payload[3] != 0) {
            return kIOReturnBadArgument;
        }
        const kern_return_t result = context.service->USBSelectAlternateSetting(payload[0]);
        if (result != kIOReturnSuccess) {
            return result;
        }
        return RespondEmpty(context);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchUSBCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_USB
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        OSData* response = nullptr;
        const kern_return_t result = context.service->USBCommand(
            context.opcode,
            context.payload,
            context.payloadLength,
            &response);
        return RespondToCommand(context, result, response);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchPCICommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_PCI
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        OSData* response = nullptr;
        const kern_return_t result = context.service->PCICommand(
            context.opcode,
            context.payload,
            context.payloadLength,
            &response);
        return RespondToCommand(context, result, response);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchMemoryCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_MEMORY
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        OSData* response = nullptr;
        // CreateMemoryDescriptorFromClient describes the calling task's memory, so the wrap runs
        // here, inside that client's ExternalMethod.
        const kern_return_t result =
            context.opcode == static_cast<uint32_t>(SwifterKitRuntimeOpcode::MemoryWrapClient)
                ? context.service->WrapClientMemory(
                      context.client,
                      context.payload,
                      context.payloadLength,
                      &response)
                : context.service->MemoryCommand(
                      context.client,
                      context.opcode,
                      context.payload,
                      context.payloadLength,
                      &response);
        return RespondToCommand(context, result, response);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchNetworkCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_NETWORKING
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        const kern_return_t result =
            context.service->NetworkCommand(context.opcode, context.payload, context.payloadLength);
        if (result != kIOReturnSuccess) {
            return result;
        }
        return RespondEmpty(context);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchMediaCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_AUDIO || SWIFTERKIT_ENABLE_VIDEO
        return HandleMediaCommand(
            context.service,
            context.arguments,
            context.requestID,
            context.opcode,
            context.payload,
            context.payloadLength);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchMIDICommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_MIDI
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        OSData* response = nullptr;
        const kern_return_t result = context.service->MIDICommand(
            context.opcode,
            context.payload,
            context.payloadLength,
            &response);
        return RespondToCommand(context, result, response);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchSCSICommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER || SWIFTERKIT_ENABLE_SCSI_PERIPHERAL
        return HandleSCSICommand(
            context.service,
            context.arguments,
            context.requestID,
            context.opcode,
            context.payload,
            context.payloadLength);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchBlockStorageCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        const kern_return_t result = context.service->BlockStorageCommand(
            context.opcode,
            context.payload,
            context.payloadLength);
        if (result != kIOReturnSuccess) {
            return result;
        }
        return RespondEmpty(context);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchSerialCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_SERIAL
        if (context.service == nullptr) {
            return kIOReturnNotReady;
        }
        OSData* response = nullptr;
        const kern_return_t result = context.service->SerialCommand(
            context.opcode,
            context.payload,
            context.payloadLength,
            &response);
        return RespondToCommand(context, result, response);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchHIDCommand([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_ENABLE_HID
        return HandleHIDCommand(
            context.service,
            context.arguments,
            context.requestID,
            context.opcode,
            context.payload,
            context.payloadLength);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchHIDRuntimeStatistics([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_HID_DEVICE
        if (context.service == nullptr || context.payloadLength != 0) {
            return kIOReturnBadArgument;
        }
        SwifterKitHIDRuntimeStatistics statistics = {};
        const kern_return_t result = context.service->CopyHIDRuntimeStatistics(&statistics);
        if (result != kIOReturnSuccess) {
            return result;
        }
        return BuildResponse(
            context.arguments,
            SwifterKitRuntimeMessageKind::Response,
            context.requestID,
            &statistics,
            sizeof(statistics));
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t DispatchHIDInputReport([[maybe_unused]] const CommandContext& context) {
#if SWIFTERKIT_HID_DEVICE
        if (context.service == nullptr
            || context.payloadLength < sizeof(SwifterKitHIDReportHeader)) {
            return kIOReturnBadArgument;
        }
        const auto* report = reinterpret_cast<const SwifterKitHIDReportHeader*>(context.payload);
        if (report->reportLength != context.payloadLength - sizeof(SwifterKitHIDReportHeader)) {
            return kIOReturnBadArgument;
        }
        const uint8_t* reportBytes = context.payload + sizeof(SwifterKitHIDReportHeader);
        const kern_return_t result = context.service->SubmitHIDInputReport(report, reportBytes);
        if (result != kIOReturnSuccess) {
            return result;
        }
        return RespondEmpty(context);
#else
        return kIOReturnUnsupported;
#endif
    }

    kern_return_t HandleCommand(
        IOUserClient* client,
        SwifterKitRuntimeService* service,
        IOUserClientMethodArguments* arguments,
        const SwifterKitRuntimeHeader* request,
        const uint8_t* payload) {
        if (request->payloadLength < sizeof(SwifterKitRuntimeCommandHeader)) {
            return kIOReturnBadArgument;
        }

        const auto* command = reinterpret_cast<const SwifterKitRuntimeCommandHeader*>(payload);
        if (command->reserved != 0
            || (command->requiredCapabilities & ~kSwifterKitRuntimeCapabilities) != 0) {
            return kIOReturnUnsupported;
        }

        const CommandContext context = {
            .client = client,
            .service = service,
            .arguments = arguments,
            .requestID = request->requestID,
            .opcode = command->opcode,
            .payload = payload + sizeof(SwifterKitRuntimeCommandHeader),
            .payloadLength = static_cast<uint32_t>(
                request->payloadLength - sizeof(SwifterKitRuntimeCommandHeader)),
        };
        switch (static_cast<SwifterKitRuntimeOpcode>(command->opcode)) {
            case SwifterKitRuntimeOpcode::Ping:
                return BuildResponse(
                    arguments,
                    SwifterKitRuntimeMessageKind::Response,
                    request->requestID,
                    context.payload,
                    context.payloadLength);
            case SwifterKitRuntimeOpcode::PollEvent:
                return HandlePollEvent(
                    service,
                    arguments,
                    request->requestID,
                    context.payloadLength);
            case SwifterKitRuntimeOpcode::ServiceSetProperties:
            case SwifterKitRuntimeOpcode::ServiceCopyProperties:
            case SwifterKitRuntimeOpcode::ServiceRemoveProperty:
            case SwifterKitRuntimeOpcode::ServiceSearchProperty:
            case SwifterKitRuntimeOpcode::ServiceCopyProviderProperties:
            case SwifterKitRuntimeOpcode::ServiceCopyName:
            case SwifterKitRuntimeOpcode::ServiceGetRegistryEntryID:
            case SwifterKitRuntimeOpcode::ServiceChangePowerState:
            case SwifterKitRuntimeOpcode::ServiceSetPowerOverride:
            case SwifterKitRuntimeOpcode::ServiceCreatePMAssertion:
            case SwifterKitRuntimeOpcode::ServiceReleasePMAssertion:
            case SwifterKitRuntimeOpcode::ServiceCompletePowerState:
            case SwifterKitRuntimeOpcode::ServiceAdjustBusy:
            case SwifterKitRuntimeOpcode::ServiceGetBusyState:
            case SwifterKitRuntimeOpcode::ServiceRequireMaxBusStall:
            case SwifterKitRuntimeOpcode::ServiceTerminate:
            case SwifterKitRuntimeOpcode::ServiceCopySystemStateItem:
            case SwifterKitRuntimeOpcode::ServiceCreateSystemStateItem:
            case SwifterKitRuntimeOpcode::ServiceSetSystemStateItem:
            case SwifterKitRuntimeOpcode::ServiceSendCoreAnalyticsEvent:
            case SwifterKitRuntimeOpcode::TimerStart:
            case SwifterKitRuntimeOpcode::TimerCancel:
            case SwifterKitRuntimeOpcode::WatchServices:
            case SwifterKitRuntimeOpcode::WatchSystemState:
            case SwifterKitRuntimeOpcode::WatchCancel:
            case SwifterKitRuntimeOpcode::ReporterUpdate:
            case SwifterKitRuntimeOpcode::ReporterRead:
                return DispatchServiceCommand(context);
            case SwifterKitRuntimeOpcode::FastPathRun:
            case SwifterKitRuntimeOpcode::FastPathStatus:
                return DispatchFastPathCommand(context);
            case SwifterKitRuntimeOpcode::InterruptSetEnabled:
            case SwifterKitRuntimeOpcode::InterruptGetType:
            case SwifterKitRuntimeOpcode::InterruptGetLast:
                return DispatchInterruptCommand(context);
            case SwifterKitRuntimeOpcode::USBControlTransfer:
                return DispatchUSBControlTransfer(context);
            case SwifterKitRuntimeOpcode::USBPipeTransfer:
                return DispatchUSBPipeTransfer(context);
            case SwifterKitRuntimeOpcode::USBClearStall:
                return DispatchUSBClearStall(context);
            case SwifterKitRuntimeOpcode::USBSelectAlternateSetting:
                return DispatchUSBSelectAlternateSetting(context);
            case SwifterKitRuntimeOpcode::USBDeviceSetConfiguration:
            case SwifterKitRuntimeOpcode::USBDeviceReset:
            case SwifterKitRuntimeOpcode::USBGetDeviceSpeed:
            case SwifterKitRuntimeOpcode::USBGetDeviceAddress:
            case SwifterKitRuntimeOpcode::USBGetPortStatus:
            case SwifterKitRuntimeOpcode::USBGetFrameNumber:
            case SwifterKitRuntimeOpcode::USBGetCurrentMicroframe:
            case SwifterKitRuntimeOpcode::USBGetReferenceMicroframe:
            case SwifterKitRuntimeOpcode::USBCopyDeviceDescriptor:
            case SwifterKitRuntimeOpcode::USBCopyConfigurationDescriptor:
            case SwifterKitRuntimeOpcode::USBCopyStringDescriptor:
            case SwifterKitRuntimeOpcode::USBCopyCapabilityDescriptors:
            case SwifterKitRuntimeOpcode::USBCopyDescriptor:
            case SwifterKitRuntimeOpcode::USBCopyInterfaces:
            case SwifterKitRuntimeOpcode::USBCopyInterfaceDescriptor:
            case SwifterKitRuntimeOpcode::USBSetIdlePolicy:
            case SwifterKitRuntimeOpcode::USBGetIdlePolicy:
            case SwifterKitRuntimeOpcode::USBAbortDeviceRequests:
            case SwifterKitRuntimeOpcode::USBPipeAsyncIO:
            case SwifterKitRuntimeOpcode::USBPipeAbort:
            case SwifterKitRuntimeOpcode::USBPipeSetIdlePolicy:
            case SwifterKitRuntimeOpcode::USBPipeGetIdlePolicy:
            case SwifterKitRuntimeOpcode::USBPipeGetDescriptors:
            case SwifterKitRuntimeOpcode::USBPipeGetSpeed:
            case SwifterKitRuntimeOpcode::USBPipeGetDeviceAddress:
            case SwifterKitRuntimeOpcode::USBPipeIsochIO:
            case SwifterKitRuntimeOpcode::USBAsyncDeviceRequest:
            case SwifterKitRuntimeOpcode::USBPipeCreateBundleRing:
            case SwifterKitRuntimeOpcode::USBPipeEnqueueBundled:
            case SwifterKitRuntimeOpcode::USBPipeReleaseBundleRing:
            case SwifterKitRuntimeOpcode::USBPipeAdjust:
                return DispatchUSBCommand(context);
            case SwifterKitRuntimeOpcode::PCIRead:
            case SwifterKitRuntimeOpcode::PCIWrite:
            case SwifterKitRuntimeOpcode::PCIGetBARInfo:
            case SwifterKitRuntimeOpcode::PCIGetLocation:
            case SwifterKitRuntimeOpcode::PCIFindCapability:
            case SwifterKitRuntimeOpcode::PCIReset:
            case SwifterKitRuntimeOpcode::PCISaveDeviceState:
            case SwifterKitRuntimeOpcode::PCIRestoreDeviceState:
            case SwifterKitRuntimeOpcode::PCIHasPowerManagement:
            case SwifterKitRuntimeOpcode::PCIEnablePowerManagement:
            case SwifterKitRuntimeOpcode::PCIGetLinkSpeed:
            case SwifterKitRuntimeOpcode::PCISetLinkSpeed:
            case SwifterKitRuntimeOpcode::PCISetASPMState:
            case SwifterKitRuntimeOpcode::PCISetProperties:
                return DispatchPCICommand(context);
            case SwifterKitRuntimeOpcode::MemoryAllocate:
            case SwifterKitRuntimeOpcode::MemoryRelease:
            case SwifterKitRuntimeOpcode::MemorySetLength:
            case SwifterKitRuntimeOpcode::MemoryRead:
            case SwifterKitRuntimeOpcode::MemoryWrite:
            case SwifterKitRuntimeOpcode::MemoryGetInfo:
            case SwifterKitRuntimeOpcode::MemoryPrepareDMA:
            case SwifterKitRuntimeOpcode::MemoryCompleteDMA:
            case SwifterKitRuntimeOpcode::MemorySubrange:
            case SwifterKitRuntimeOpcode::MemoryChain:
            case SwifterKitRuntimeOpcode::MemoryWrapClient:
                return DispatchMemoryCommand(context);
            case SwifterKitRuntimeOpcode::NetworkReceive:
            case SwifterKitRuntimeOpcode::NetworkCompleteTransmit:
            case SwifterKitRuntimeOpcode::NetworkReportLink:
            case SwifterKitRuntimeOpcode::NetworkReportLinkQuality:
            case SwifterKitRuntimeOpcode::NetworkReportDataBandwidths:
            case SwifterKitRuntimeOpcode::NetworkAddHardwareCounts:
            case SwifterKitRuntimeOpcode::NetworkReportNICProxyLimits:
            case SwifterKitRuntimeOpcode::NetworkSetPolling:
            case SwifterKitRuntimeOpcode::NetworkSetPollerParameters:
            case SwifterKitRuntimeOpcode::NetworkReceivePackets:
            case SwifterKitRuntimeOpcode::NetworkCompleteTransmits:
            case SwifterKitRuntimeOpcode::NetworkSetQueueEnabled:
            case SwifterKitRuntimeOpcode::NetworkPurgeTransmitQueue:
            case SwifterKitRuntimeOpcode::NetworkServiceTransmitQueue:
            case SwifterKitRuntimeOpcode::NetworkCompleteInterfaceCommand:
                return DispatchNetworkCommand(context);
            case SwifterKitRuntimeOpcode::AudioReadStream:
            case SwifterKitRuntimeOpcode::AudioWriteStream:
            case SwifterKitRuntimeOpcode::AudioGetIOState:
            case SwifterKitRuntimeOpcode::AudioUpdateTimestamp:
            case SwifterKitRuntimeOpcode::AudioRequestSampleRate:
            case SwifterKitRuntimeOpcode::AudioGetControl:
            case SwifterKitRuntimeOpcode::AudioSetControl:
            case SwifterKitRuntimeOpcode::AudioGetCustomProperty:
            case SwifterKitRuntimeOpcode::AudioSetCustomProperty:
            case SwifterKitRuntimeOpcode::AudioGetObjectInfo:
            case SwifterKitRuntimeOpcode::AudioSetObjectName:
            case SwifterKitRuntimeOpcode::AudioGetElementName:
            case SwifterKitRuntimeOpcode::AudioSetElementName:
            case SwifterKitRuntimeOpcode::AudioPropertiesChanged:
            case SwifterKitRuntimeOpcode::AudioGetBoxState:
            case SwifterKitRuntimeOpcode::AudioSetBoxProperty:
            case SwifterKitRuntimeOpcode::AudioSetBoxOwnership:
            case SwifterKitRuntimeOpcode::AudioGetClockDeviceState:
            case SwifterKitRuntimeOpcode::AudioSetClockDeviceProperty:
            case SwifterKitRuntimeOpcode::AudioSetClockSampleRates:
            case SwifterKitRuntimeOpcode::AudioUpdateClockTimestamp:
            case SwifterKitRuntimeOpcode::AudioRequestClockSampleRate:
            case SwifterKitRuntimeOpcode::AudioCompleteRequest:
            case SwifterKitRuntimeOpcode::AudioGetDeviceState:
            case SwifterKitRuntimeOpcode::AudioSetDeviceProperty:
            case SwifterKitRuntimeOpcode::AudioSetPreferredChannelLayout:
            case SwifterKitRuntimeOpcode::AudioGetStreamState:
            case SwifterKitRuntimeOpcode::AudioSetStreamProperty:
            case SwifterKitRuntimeOpcode::AudioGetControlInfo:
            case SwifterKitRuntimeOpcode::AudioSetControlProperty:
            case SwifterKitRuntimeOpcode::AudioRemoveSelectorItems:
            case SwifterKitRuntimeOpcode::AudioGetCustomPropertyInfo:
            case SwifterKitRuntimeOpcode::AudioSetMemberAttachment:
            case SwifterKitRuntimeOpcode::VideoReadBuffer:
            case SwifterKitRuntimeOpcode::VideoWriteBuffer:
            case SwifterKitRuntimeOpcode::VideoEnqueueOutput:
            case SwifterKitRuntimeOpcode::VideoDequeueInput:
            case SwifterKitRuntimeOpcode::VideoNotifyOutput:
            case SwifterKitRuntimeOpcode::VideoUpdateTimestamp:
            case SwifterKitRuntimeOpcode::VideoRequestSampleRate:
            case SwifterKitRuntimeOpcode::VideoGetControl:
            case SwifterKitRuntimeOpcode::VideoSetControl:
            case SwifterKitRuntimeOpcode::VideoGetCustomProperty:
            case SwifterKitRuntimeOpcode::VideoSetCustomProperty:
            case SwifterKitRuntimeOpcode::VideoGetObjectInfo:
            case SwifterKitRuntimeOpcode::VideoSetObjectName:
            case SwifterKitRuntimeOpcode::VideoGetElementName:
            case SwifterKitRuntimeOpcode::VideoSetElementName:
            case SwifterKitRuntimeOpcode::VideoPropertiesChanged:
            case SwifterKitRuntimeOpcode::VideoGetBoxState:
            case SwifterKitRuntimeOpcode::VideoSetBoxProperty:
            case SwifterKitRuntimeOpcode::VideoSetBoxOwnership:
            case SwifterKitRuntimeOpcode::VideoGetClockDeviceState:
            case SwifterKitRuntimeOpcode::VideoSetClockDeviceProperty:
            case SwifterKitRuntimeOpcode::VideoSetClockSampleRates:
            case SwifterKitRuntimeOpcode::VideoUpdateClockTimestamp:
            case SwifterKitRuntimeOpcode::VideoRequestClockSampleRate:
            case SwifterKitRuntimeOpcode::VideoCompleteRequest:
            case SwifterKitRuntimeOpcode::VideoNotifyBufferQueue:
            case SwifterKitRuntimeOpcode::VideoSetCustomPropertyOwner:
            case SwifterKitRuntimeOpcode::VideoGetDeviceState:
            case SwifterKitRuntimeOpcode::VideoSetDeviceProperty:
            case SwifterKitRuntimeOpcode::VideoSetPreferredChannelLayout:
            case SwifterKitRuntimeOpcode::VideoGetStreamState:
            case SwifterKitRuntimeOpcode::VideoSetStreamProperty:
            case SwifterKitRuntimeOpcode::VideoGetBufferInfo:
            case SwifterKitRuntimeOpcode::VideoSetBufferProperty:
            case SwifterKitRuntimeOpcode::VideoGetControlInfo:
            case SwifterKitRuntimeOpcode::VideoSetControlProperty:
            case SwifterKitRuntimeOpcode::VideoRemoveSelectorItems:
            case SwifterKitRuntimeOpcode::VideoGetCustomPropertyInfo:
            case SwifterKitRuntimeOpcode::VideoSetMemberAttachment:
            case SwifterKitRuntimeOpcode::VideoEnqueueOutputBuffer:
            case SwifterKitRuntimeOpcode::VideoGetStreamMemoryObjectID:
                return DispatchMediaCommand(context);
            case SwifterKitRuntimeOpcode::MIDISend:
            case SwifterKitRuntimeOpcode::MIDIGetObjectInfo:
            case SwifterKitRuntimeOpcode::MIDISetObjectName:
            case SwifterKitRuntimeOpcode::MIDIGetPropertyType:
            case SwifterKitRuntimeOpcode::MIDICopyProperty:
            case SwifterKitRuntimeOpcode::MIDISetProperty:
            case SwifterKitRuntimeOpcode::MIDIGetProperties:
            case SwifterKitRuntimeOpcode::MIDISetProperties:
            case SwifterKitRuntimeOpcode::MIDIGetDeviceState:
            case SwifterKitRuntimeOpcode::MIDIGetEntityMembers:
            case SwifterKitRuntimeOpcode::MIDISetMemberAttachment:
                return DispatchMIDICommand(context);
            case SwifterKitRuntimeOpcode::SCSIPeripheralSendCDB:
            case SwifterKitRuntimeOpcode::SCSIPeripheralSuspendServices:
            case SwifterKitRuntimeOpcode::SCSIPeripheralResumeServices:
            case SwifterKitRuntimeOpcode::SCSIPeripheralReset:
            case SwifterKitRuntimeOpcode::SCSIPeripheralReportMediumBlockSize:
            case SwifterKitRuntimeOpcode::SCSICompleteParallelTask:
            case SwifterKitRuntimeOpcode::SCSITargetPresent:
            case SwifterKitRuntimeOpcode::SCSICreateTarget:
            case SwifterKitRuntimeOpcode::SCSIDestroyTarget:
            case SwifterKitRuntimeOpcode::SCSISetControllerProperties:
            case SwifterKitRuntimeOpcode::SCSIRemoveControllerProperties:
            case SwifterKitRuntimeOpcode::SCSISetTargetProperties:
            case SwifterKitRuntimeOpcode::SCSIRemoveTargetProperties:
            case SwifterKitRuntimeOpcode::SCSIMediaParametersChanged:
            case SwifterKitRuntimeOpcode::SCSIReadTaskData:
            case SwifterKitRuntimeOpcode::SCSIWriteTaskData:
                return DispatchSCSICommand(context);
            case SwifterKitRuntimeOpcode::BlockStorageComplete:
            case SwifterKitRuntimeOpcode::BlockStorageCompleteIO:
                return DispatchBlockStorageCommand(context);
            case SwifterKitRuntimeOpcode::SerialEnqueueReceive:
            case SwifterKitRuntimeOpcode::SerialDequeueTransmit:
            case SwifterKitRuntimeOpcode::SerialSetModemStatus:
            case SwifterKitRuntimeOpcode::SerialReportReceiveErrors:
                return DispatchSerialCommand(context);
            case SwifterKitRuntimeOpcode::HIDCompleteGetReport:
            case SwifterKitRuntimeOpcode::HIDCopyElements:
            case SwifterKitRuntimeOpcode::HIDGetElementValue:
            case SwifterKitRuntimeOpcode::HIDSetElementValue:
            case SwifterKitRuntimeOpcode::HIDCommitElement:
            case SwifterKitRuntimeOpcode::HIDCommitElements:
            case SwifterKitRuntimeOpcode::HIDElementConformsTo:
            case SwifterKitRuntimeOpcode::HIDInterfaceGetReport:
            case SwifterKitRuntimeOpcode::HIDInterfaceSetReport:
            case SwifterKitRuntimeOpcode::HIDInterfaceProcessReport:
            case SwifterKitRuntimeOpcode::HIDDispatchKeyboard:
            case SwifterKitRuntimeOpcode::HIDDispatchRelativePointer:
            case SwifterKitRuntimeOpcode::HIDDispatchAbsolutePointer:
            case SwifterKitRuntimeOpcode::HIDDispatchScroll:
            case SwifterKitRuntimeOpcode::HIDDispatchDigitizerStylus:
            case SwifterKitRuntimeOpcode::HIDDispatchDigitizerTouches:
            case SwifterKitRuntimeOpcode::HIDDispatchDigitizerCollection:
            case SwifterKitRuntimeOpcode::HIDDispatchGameController:
            case SwifterKitRuntimeOpcode::HIDDispatchExtendedGameController:
            case SwifterKitRuntimeOpcode::HIDSetLED:
            case SwifterKitRuntimeOpcode::HIDSetLEDState:
            case SwifterKitRuntimeOpcode::HIDServiceConformsTo:
            case SwifterKitRuntimeOpcode::HIDSetEventDriverCategories:
            case SwifterKitRuntimeOpcode::HIDDeviceGetReport:
            case SwifterKitRuntimeOpcode::HIDDeviceSetProtocol:
            case SwifterKitRuntimeOpcode::HIDDeviceSetIdle:
            case SwifterKitRuntimeOpcode::HIDDeviceSetIdlePolicy:
            case SwifterKitRuntimeOpcode::HIDDeviceReset:
                return DispatchHIDCommand(context);
            case SwifterKitRuntimeOpcode::HIDGetRuntimeStatistics:
                return DispatchHIDRuntimeStatistics(context);
            case SwifterKitRuntimeOpcode::HIDSubmitInputReport:
                return DispatchHIDInputReport(context);
        }
        return kIOReturnUnsupported;
    }
}  // namespace

kern_return_t SwifterKitHandleMessage(
    IOUserClient* client,
    SwifterKitRuntimeService* service,
    IOUserClientMethodArguments* arguments,
    const SwifterKitRuntimeHeader* request,
    const uint8_t* payload) {
    // A handshake negotiates from its payload range, so only later messages must carry a
    // version this extension speaks.
    const auto kind = static_cast<SwifterKitRuntimeMessageKind>(request->kind);
    if (kind != SwifterKitRuntimeMessageKind::Handshake && !IsSupportedVersion(request->version)) {
        return kIOReturnBadArgument;
    }
    switch (kind) {
        case SwifterKitRuntimeMessageKind::Handshake:
            return HandleHandshake(arguments, request, payload);
        case SwifterKitRuntimeMessageKind::Command:
            return HandleCommand(client, service, arguments, request, payload);
        case SwifterKitRuntimeMessageKind::Response:
        case SwifterKitRuntimeMessageKind::Event:
        case SwifterKitRuntimeMessageKind::Error:
            return kIOReturnBadArgument;
    }
    return kIOReturnBadArgument;
}
