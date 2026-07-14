#include "SwifterKitRuntimeUserClient.h"

#include <DriverKit/IOLib.h>
#include <DriverKit/IOReturn.h>
#include <DriverKit/IOUserClient.h>
#include <DriverKit/OSArray.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSString.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeUserClientHelpers.h"

namespace {
    auto HandleCommand(
        SwifterKitRuntimeService* service,
        IOUserClientMethodArguments* arguments,
        const SwifterKitRuntimeHeader* request,
        const uint8_t* payload) -> kern_return_t {
        if (request->payloadLength < sizeof(SwifterKitRuntimeCommandHeader)) {
            return kIOReturnBadArgument;
        }

        const auto* command = reinterpret_cast<const SwifterKitRuntimeCommandHeader*>(payload);
        if (command->reserved != 0
            || (command->requiredCapabilities & ~kSwifterKitRuntimeCapabilities) != 0) {
            return kIOReturnUnsupported;
        }

        const uint8_t* commandPayload = payload + sizeof(SwifterKitRuntimeCommandHeader);
        const uint32_t commandPayloadLength =
            request->payloadLength - sizeof(SwifterKitRuntimeCommandHeader);
        switch (static_cast<SwifterKitRuntimeOpcode>(command->opcode)) {
            case SwifterKitRuntimeOpcode::Ping:
                return BuildResponse(
                    arguments,
                    SwifterKitRuntimeMessageKind::Response,
                    request->requestID,
                    commandPayload,
                    commandPayloadLength);
            case SwifterKitRuntimeOpcode::PollEvent:
                return HandlePollEvent(
                    service,
                    arguments,
                    request->requestID,
                    commandPayloadLength);
            case SwifterKitRuntimeOpcode::InterruptSetEnabled:
            case SwifterKitRuntimeOpcode::InterruptGetType:
            case SwifterKitRuntimeOpcode::InterruptGetLast:
#if SWIFTERKIT_ENABLE_INTERRUPTS
                return HandleInterruptCommand(
                    service,
                    arguments,
                    request->requestID,
                    command->opcode,
                    commandPayload,
                    commandPayloadLength);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::USBControlTransfer:
#if SWIFTERKIT_ENABLE_USB
                return HandleUSBControlTransfer(
                    service,
                    arguments,
                    request->requestID,
                    commandPayload,
                    commandPayloadLength);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::USBPipeTransfer:
#if SWIFTERKIT_ENABLE_USB
                return HandleUSBPipeTransfer(
                    service,
                    arguments,
                    request->requestID,
                    commandPayload,
                    commandPayloadLength);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::USBClearStall:
#if SWIFTERKIT_ENABLE_USB
                if (service == nullptr || commandPayloadLength != 4 || commandPayload[1] > 1
                    || commandPayload[2] != 0 || commandPayload[3] != 0) {
                    return kIOReturnBadArgument;
                }
                {
                    const kern_return_t result =
                        service->USBClearStall(commandPayload[0], commandPayload[1] != 0);
                    if (result != kIOReturnSuccess) {
                        return result;
                    }
                }
                return BuildResponse(
                    arguments,
                    SwifterKitRuntimeMessageKind::Response,
                    request->requestID,
                    nullptr,
                    0);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::USBSelectAlternateSetting:
#if SWIFTERKIT_ENABLE_USB
                if (service == nullptr || commandPayloadLength != 4 || commandPayload[1] != 0
                    || commandPayload[2] != 0 || commandPayload[3] != 0) {
                    return kIOReturnBadArgument;
                }
                {
                    const kern_return_t result =
                        service->USBSelectAlternateSetting(commandPayload[0]);
                    if (result != kIOReturnSuccess) {
                        return result;
                    }
                }
                return BuildResponse(
                    arguments,
                    SwifterKitRuntimeMessageKind::Response,
                    request->requestID,
                    nullptr,
                    0);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::PCIRead:
            case SwifterKitRuntimeOpcode::PCIWrite:
            case SwifterKitRuntimeOpcode::PCIGetBARInfo:
            case SwifterKitRuntimeOpcode::PCIGetLocation:
            case SwifterKitRuntimeOpcode::PCIFindCapability:
#if SWIFTERKIT_ENABLE_PCI
                if (service == nullptr) {
                    return kIOReturnNotReady;
                }
                {
                    OSData* response = nullptr;
                    const kern_return_t result = service->PCICommand(
                        command->opcode,
                        commandPayload,
                        commandPayloadLength,
                        &response);
                    if (result != kIOReturnSuccess) {
                        OSSafeReleaseNULL(response);
                        return result;
                    }
                    if (response == nullptr) {
                        return BuildResponse(
                            arguments,
                            SwifterKitRuntimeMessageKind::Response,
                            request->requestID,
                            nullptr,
                            0);
                    }
                    return RespondWithData(result, response, arguments, request->requestID);
                }
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::MemoryAllocate:
            case SwifterKitRuntimeOpcode::MemoryRelease:
            case SwifterKitRuntimeOpcode::MemorySetLength:
            case SwifterKitRuntimeOpcode::MemoryRead:
            case SwifterKitRuntimeOpcode::MemoryWrite:
            case SwifterKitRuntimeOpcode::MemoryGetInfo:
            case SwifterKitRuntimeOpcode::MemoryPrepareDMA:
            case SwifterKitRuntimeOpcode::MemoryCompleteDMA:
#if SWIFTERKIT_ENABLE_MEMORY
                if (service == nullptr) {
                    return kIOReturnNotReady;
                }
                {
                    OSData* response = nullptr;
                    const kern_return_t result = service->MemoryCommand(
                        command->opcode,
                        commandPayload,
                        commandPayloadLength,
                        &response);
                    if (result != kIOReturnSuccess) {
                        OSSafeReleaseNULL(response);
                        return result;
                    }
                    if (response == nullptr) {
                        return BuildResponse(
                            arguments,
                            SwifterKitRuntimeMessageKind::Response,
                            request->requestID,
                            nullptr,
                            0);
                    }
                    return RespondWithData(result, response, arguments, request->requestID);
                }
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::NetworkReceive:
            case SwifterKitRuntimeOpcode::NetworkCompleteTransmit:
            case SwifterKitRuntimeOpcode::NetworkReportLink:
#if SWIFTERKIT_ENABLE_NETWORKING
                if (service == nullptr) {
                    return kIOReturnNotReady;
                }
                {
                    const kern_return_t result = service->NetworkCommand(
                        command->opcode,
                        commandPayload,
                        commandPayloadLength);
                    if (result != kIOReturnSuccess) {
                        return result;
                    }
                }
                return BuildResponse(
                    arguments,
                    SwifterKitRuntimeMessageKind::Response,
                    request->requestID,
                    nullptr,
                    0);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::AudioReadStream:
            case SwifterKitRuntimeOpcode::AudioWriteStream:
            case SwifterKitRuntimeOpcode::AudioGetIOState:
            case SwifterKitRuntimeOpcode::AudioUpdateTimestamp:
            case SwifterKitRuntimeOpcode::AudioRequestSampleRate:
            case SwifterKitRuntimeOpcode::AudioGetControl:
            case SwifterKitRuntimeOpcode::AudioSetControl:
            case SwifterKitRuntimeOpcode::AudioGetCustomProperty:
            case SwifterKitRuntimeOpcode::AudioSetCustomProperty:
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
#if SWIFTERKIT_ENABLE_AUDIO || SWIFTERKIT_ENABLE_VIDEO
                return HandleMediaCommand(
                    service,
                    arguments,
                    request->requestID,
                    command->opcode,
                    commandPayload,
                    commandPayloadLength);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::MIDISend:
#if SWIFTERKIT_ENABLE_MIDI
                if (service == nullptr) {
                    return kIOReturnNotReady;
                }
                {
                    const kern_return_t result =
                        service->MIDICommand(command->opcode, commandPayload, commandPayloadLength);
                    if (result != kIOReturnSuccess) {
                        return result;
                    }
                }
                return BuildResponse(
                    arguments,
                    SwifterKitRuntimeMessageKind::Response,
                    request->requestID,
                    nullptr,
                    0);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::SCSIPeripheralSendCDB:
            case SwifterKitRuntimeOpcode::SCSIPeripheralSuspendServices:
            case SwifterKitRuntimeOpcode::SCSIPeripheralResumeServices:
            case SwifterKitRuntimeOpcode::SCSIPeripheralReset:
            case SwifterKitRuntimeOpcode::SCSIPeripheralReportMediumBlockSize:
            case SwifterKitRuntimeOpcode::SCSICompleteParallelTask:
#if SWIFTERKIT_ENABLE_SCSI_CONTROLLER || SWIFTERKIT_ENABLE_SCSI_PERIPHERAL
                return HandleSCSICommand(
                    service,
                    arguments,
                    request->requestID,
                    command->opcode,
                    commandPayload,
                    commandPayloadLength);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::BlockStorageComplete:
            case SwifterKitRuntimeOpcode::BlockStorageCompleteIO:
#if SWIFTERKIT_ENABLE_BLOCK_STORAGE
                if (service == nullptr) {
                    return kIOReturnNotReady;
                }
                {
                    const kern_return_t result = service->BlockStorageCommand(
                        command->opcode,
                        commandPayload,
                        commandPayloadLength);
                    if (result != kIOReturnSuccess) {
                        return result;
                    }
                }
                return BuildResponse(
                    arguments,
                    SwifterKitRuntimeMessageKind::Response,
                    request->requestID,
                    nullptr,
                    0);
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::SerialEnqueueReceive:
            case SwifterKitRuntimeOpcode::SerialDequeueTransmit:
            case SwifterKitRuntimeOpcode::SerialSetModemStatus:
            case SwifterKitRuntimeOpcode::SerialReportReceiveErrors:
#if SWIFTERKIT_ENABLE_SERIAL
                if (service == nullptr) {
                    return kIOReturnNotReady;
                }
                {
                    OSData* response = nullptr;
                    const kern_return_t result = service->SerialCommand(
                        command->opcode,
                        commandPayload,
                        commandPayloadLength,
                        &response);
                    if (result != kIOReturnSuccess) {
                        OSSafeReleaseNULL(response);
                        return result;
                    }
                    if (response == nullptr) {
                        return BuildResponse(
                            arguments,
                            SwifterKitRuntimeMessageKind::Response,
                            request->requestID,
                            nullptr,
                            0);
                    }
                    return RespondWithData(result, response, arguments, request->requestID);
                }
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::HIDGetRuntimeStatistics:
#if SWIFTERKIT_ENABLE_HID
                if (service == nullptr || commandPayloadLength != 0) {
                    return kIOReturnBadArgument;
                }
                {
                    SwifterKitHIDRuntimeStatistics statistics = {};
                    const kern_return_t result = service->CopyHIDRuntimeStatistics(&statistics);
                    if (result != kIOReturnSuccess) {
                        return result;
                    }
                    return BuildResponse(
                        arguments,
                        SwifterKitRuntimeMessageKind::Response,
                        request->requestID,
                        &statistics,
                        sizeof(statistics));
                }
#else
                return kIOReturnUnsupported;
#endif
            case SwifterKitRuntimeOpcode::HIDSubmitInputReport:
#if SWIFTERKIT_ENABLE_HID
                if (commandPayloadLength < sizeof(SwifterKitHIDReportHeader)) {
                    return kIOReturnBadArgument;
                }
                {
                    const auto* report =
                        reinterpret_cast<const SwifterKitHIDReportHeader*>(commandPayload);
                    if (report->reportLength
                        != commandPayloadLength - sizeof(SwifterKitHIDReportHeader)) {
                        return kIOReturnBadArgument;
                    }
                    const uint8_t* reportBytes = commandPayload + sizeof(SwifterKitHIDReportHeader);
                    kern_return_t result = service->SubmitHIDInputReport(report, reportBytes);
                    if (result != kIOReturnSuccess) {
                        return result;
                    }
                }
                return BuildResponse(
                    arguments,
                    SwifterKitRuntimeMessageKind::Response,
                    request->requestID,
                    nullptr,
                    0);
#else
                return kIOReturnUnsupported;
#endif
        }
        return kIOReturnUnsupported;
    }
}  // namespace

struct SwifterKitRuntimeUserClient_IVars {
    SwifterKitRuntimeService* service = nullptr;
};

auto SwifterKitRuntimeUserClient::init() -> bool {
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(SwifterKitRuntimeUserClient_IVars, 1);
    return ivars != nullptr;
}

void SwifterKitRuntimeUserClient::free() {
    if (ivars != nullptr) {
        OSSafeReleaseNULL(ivars->service);
    }
    IOSafeDeleteNULL(ivars, SwifterKitRuntimeUserClient_IVars, 1);
    super::free();
}

auto SwifterKitRuntimeUserClient::Start_Impl(IOService* provider) -> kern_return_t {
    if (ivars == nullptr || provider == nullptr) {
        return kIOReturnBadArgument;
    }

    const kern_return_t startResult = Start(provider, SUPERDISPATCH);
    if (startResult != kIOReturnSuccess) {
        return startResult;
    }
#if SWIFTERKIT_ENABLE_AUDIO
    OSDictionary* entitlements = nullptr;
    const kern_return_t entitlementResult = CopyClientEntitlements(&entitlements);
    OSArray* access =
        entitlementResult == kIOReturnSuccess && entitlements != nullptr
            ? OSDynamicCast(
                  OSArray,
                  entitlements->getObject("com.apple.developer.driverkit.userclient-access"))
            : nullptr;
    bool authorized = false;
    if (access != nullptr)
        for (uint32_t index = 0; index < access->getCount(); ++index) {
            const OSString* identifier = OSDynamicCast(OSString, access->getObject(index));
            if (identifier != nullptr && identifier->isEqualTo(kSwifterKitBundleIdentifier)) {
                authorized = true;
                break;
            }
        }
    OSSafeReleaseNULL(entitlements);
    if (!authorized) {
        Stop(provider, SUPERDISPATCH);
        return kIOReturnNotPermitted;
    }
#endif
    ivars->service = OSDynamicCast(SwifterKitRuntimeService, provider);
    if (ivars->service == nullptr) {
        Stop(provider, SUPERDISPATCH);
        return kIOReturnBadArgument;
    }
    ivars->service->retain();
    return kIOReturnSuccess;
}

auto SwifterKitRuntimeUserClient::Stop_Impl(IOService* provider) -> kern_return_t {
    if (ivars != nullptr) {
        OSSafeReleaseNULL(ivars->service);
    }
    return Stop(provider, SUPERDISPATCH);
}

auto SwifterKitRuntimeUserClient::ExternalMethod(
    uint64_t selector,
    IOUserClientMethodArguments* arguments,
    const IOUserClientMethodDispatch*,
    OSObject*,
    void*) -> kern_return_t {
    if (selector != kTransactSelector || arguments == nullptr
        || arguments->structureInput == nullptr || arguments->scalarInputCount != 0
        || arguments->scalarOutputCount != 0) {
        return kIOReturnBadArgument;
    }

    const size_t inputLength = arguments->structureInput->getLength();
    if (inputLength < sizeof(SwifterKitRuntimeHeader)
        || inputLength > kSwifterKitRuntimeMaximumMessageSize) {
        return kIOReturnBadArgument;
    }

    const auto* bytes = static_cast<const uint8_t*>(arguments->structureInput->getBytesNoCopy());
    const auto* request = reinterpret_cast<const SwifterKitRuntimeHeader*>(bytes);
    if (request == nullptr || request->magic != kSwifterKitRuntimeMagic
        || request->version != kSwifterKitRuntimeVersion
        || request->payloadLength != inputLength - sizeof(SwifterKitRuntimeHeader)) {
        return kIOReturnBadArgument;
    }

    const auto kind = static_cast<SwifterKitRuntimeMessageKind>(request->kind);
    const uint8_t* payload = bytes + sizeof(SwifterKitRuntimeHeader);
    switch (kind) {
        case SwifterKitRuntimeMessageKind::Handshake:
            return HandleHandshake(arguments, request);
        case SwifterKitRuntimeMessageKind::Command:
            return HandleCommand(
                ivars == nullptr ? nullptr : ivars->service,
                arguments,
                request,
                payload);
        case SwifterKitRuntimeMessageKind::Response:
        case SwifterKitRuntimeMessageKind::Event:
        case SwifterKitRuntimeMessageKind::Error:
            return kIOReturnBadArgument;
    }
    return kIOReturnBadArgument;
}
