#include <DriverKit/IOLib.h>
#include <DriverKit/IOMemoryDescriptor.h>
#include <DriverKit/IOReporters.h>
#include <DriverKit/IOService.h>
#include <DriverKit/OSCollections.h>
#include <string.h>

#include "SwifterKitRuntimeConfiguration.h"
#include "SwifterKitRuntimeProtocol.h"
#include "SwifterKitRuntimeReportingProtocol.h"
#include "SwifterKitRuntimeService.h"
#include "SwifterKitRuntimeServiceState.h"

// IOReporting contract:
// - The generator validates the reporter tables in SwifterKitRuntimeConfiguration.h against the
//   limits in SwifterKitRuntimeReportingProtocol.h. StartReporting creates every reporter when
//   the service starts. It adds its channels and state IDs and publishes one legend through
//   SetLegend. IOReport clients therefore see the channels whether or not a host is connected.
// - ConfigureReport and UpdateReport hand the system's requests to configureAllReports and
//   updateAllReports. With no reporters they defer to IOService.
// - Swift updates and reads values by reporter index and channel ID. Each request is validated
//   here again:
//   - The reporter kind must match the operation.
//   - The channel and state must belong to the reporter.
//   - Unused values must be zero.
// - Reporters live until the service stops. They are not tied to a host connection. The
//   reporter array changes only under dispatchLock, and callers use a retained reference.

namespace {
    constexpr uint32_t kSimple = static_cast<uint32_t>(SwifterKitReporterKind::Simple);
    constexpr uint32_t kState = static_cast<uint32_t>(SwifterKitReporterKind::State);
    constexpr uint32_t kHistogram = static_cast<uint32_t>(SwifterKitReporterKind::Histogram);

    static_assert(kSwifterKitReporterCount <= kSwifterKitMaximumReporters);

    // Returns entry index of the run that starts at start, or nullptr outside the table. The
    // generator writes consistent runs. The check keeps a malformed table from reading past it.
    template<typename Entry, uint32_t Count>
    const Entry* RunEntry(const Entry (&table)[Count], uint32_t start, uint32_t index) {
        return start < Count && index < Count - start ? &table[start + index] : nullptr;
    }

    bool HasChannel(const SwifterKitReporterConfiguration& reporter, uint64_t channelID) {
        for (uint32_t index = 0; index < reporter.channelCount; index += 1) {
            const auto* channel = RunEntry(kSwifterKitReportChannels, reporter.channelStart, index);
            if (channel != nullptr && channel->identifier == channelID) {
                return true;
            }
        }
        return false;
    }

    bool HasState(const SwifterKitReporterConfiguration& reporter, uint64_t stateID) {
        for (uint32_t index = 0; index < reporter.stateCount; index += 1) {
            const uint64_t* state = RunEntry(kSwifterKitReportStates, reporter.stateStart, index);
            if (state != nullptr && *state == stateID) {
                return true;
            }
        }
        return false;
    }

    uint32_t BucketCount(const SwifterKitReporterConfiguration& reporter) {
        uint32_t count = 0;
        for (uint32_t index = 0; index < reporter.segmentCount; index += 1) {
            const auto* segment =
                RunEntry(kSwifterKitHistogramSegments, reporter.segmentStart, index);
            count += segment == nullptr ? 0 : segment->bucketCount;
        }
        return count;
    }

    IOReporter* CreateReporter(IOService* service, const SwifterKitReporterConfiguration& config) {
        const auto* first = RunEntry(kSwifterKitReportChannels, config.channelStart, 0);
        if (first == nullptr || config.channelCount == 0
            || config.segmentCount > kSwifterKitMaximumHistogramSegments) {
            return nullptr;
        }
        if (config.kind == kHistogram) {
            IOHistogramSegmentConfig segments[kSwifterKitMaximumHistogramSegments] = {};
            for (uint32_t index = 0; index < config.segmentCount; index += 1) {
                const auto* segment =
                    RunEntry(kSwifterKitHistogramSegments, config.segmentStart, index);
                if (segment == nullptr) {
                    return nullptr;
                }
                segments[index] = {
                    .base_bucket_width = segment->baseBucketWidth,
                    .scale_flag = segment->scale,
                    .segment_idx = index,
                    .segment_bucket_count = segment->bucketCount,
                };
            }
            return IOHistogramReporter::with(
                service,
                config.categories,
                first->identifier,
                first->name,
                config.unit,
                static_cast<int>(config.segmentCount),
                segments);
        }

        IOReporter* reporter = nullptr;
        IOStateReporter* stateReporter = nullptr;
        if (config.kind == kState) {
            stateReporter = IOStateReporter::with(
                service,
                config.categories,
                static_cast<int>(config.stateCount),
                config.unit);
            reporter = stateReporter;
        } else {
            reporter = IOSimpleReporter::with(service, config.categories, config.unit);
        }
        bool valid = reporter != nullptr;
        for (uint32_t index = 0; valid && index < config.channelCount; index += 1) {
            const auto* channel = RunEntry(kSwifterKitReportChannels, config.channelStart, index);
            valid = channel != nullptr
                    && reporter->addChannel(channel->identifier, channel->name) == kIOReturnSuccess;
            for (uint32_t state = 0; valid && stateReporter != nullptr && state < config.stateCount;
                 state += 1) {
                const uint64_t* stateID =
                    RunEntry(kSwifterKitReportStates, config.stateStart, state);
                valid = stateID != nullptr
                        && stateReporter->setStateID(
                               channel->identifier,
                               static_cast<int>(state),
                               *stateID)
                               == kIOReturnSuccess;
            }
        }
        if (!valid) {
            OSSafeReleaseNULL(reporter);
        }
        return reporter;
    }

    // Returns a retained reporter for index, or nullptr when reporting has not started.
    IOReporter* CopyReporter(const SwifterKitRuntimeService_IVars* state, uint32_t index) {
        IOLockLock(state->dispatchLock);
        IOReporter* reporter = state->reporters[index];
        if (reporter != nullptr) {
            reporter->retain();
        }
        IOLockUnlock(state->dispatchLock);
        return reporter;
    }

    OSArray* CopyReporterSet(const SwifterKitRuntimeService_IVars* state) {
        if (state == nullptr || state->dispatchLock == nullptr) {
            return nullptr;
        }
        IOLockLock(state->dispatchLock);
        OSArray* reporters = state->reporterSet;
        if (reporters != nullptr) {
            reporters->retain();
        }
        IOLockUnlock(state->dispatchLock);
        return reporters;
    }

    kern_return_t Update(
        IOReporter* reporter,
        const SwifterKitReporterConfiguration& config,
        const SwifterKitReporterUpdate& update) {
        const int64_t* values = update.values;
        const auto state = static_cast<uint64_t>(values[0]);
        switch (static_cast<SwifterKitReporterOperation>(update.operation)) {
            case SwifterKitReporterOperation::SetValue:
            case SwifterKitReporterOperation::IncrementValue: {
                if (config.kind != kSimple || values[1] != 0 || values[2] != 0 || values[3] != 0
                    || values[4] != 0) {
                    return kIOReturnBadArgument;
                }
                auto* simple = static_cast<IOSimpleReporter*>(reporter);
                return update.operation
                               == static_cast<uint32_t>(SwifterKitReporterOperation::SetValue)
                           ? simple->setValue(update.channelID, values[0])
                           : simple->incrementValue(update.channelID, values[0]);
            }
            case SwifterKitReporterOperation::SetState:
                if (config.kind != kState || !HasState(config, state) || values[1] != 0
                    || values[2] != 0 || values[3] != 0 || values[4] != 0) {
                    return kIOReturnBadArgument;
                }
                return static_cast<IOStateReporter*>(reporter)->setChannelState(
                    update.channelID,
                    state);
            case SwifterKitReporterOperation::OverrideState:
            case SwifterKitReporterOperation::IncrementState: {
                if (config.kind != kState || !HasState(config, state) || values[1] < 0
                    || values[2] < 0 || values[3] < 0 || values[4] != 0) {
                    return kIOReturnBadArgument;
                }
                auto* states = static_cast<IOStateReporter*>(reporter);
                const auto time = static_cast<uint64_t>(values[1]);
                const auto transitions = static_cast<uint64_t>(values[2]);
                const auto last = static_cast<uint64_t>(values[3]);
                return update.operation
                               == static_cast<uint32_t>(SwifterKitReporterOperation::OverrideState)
                           ? states->overrideChannelState(
                                 update.channelID,
                                 state,
                                 time,
                                 transitions,
                                 last)
                           : states->incrementChannelState(
                                 update.channelID,
                                 state,
                                 time,
                                 transitions,
                                 last);
            }
            case SwifterKitReporterOperation::TallyValue:
                if (config.kind != kHistogram || values[1] != 0 || values[2] != 0 || values[3] != 0
                    || values[4] != 0) {
                    return kIOReturnBadArgument;
                }
                return static_cast<IOHistogramReporter*>(reporter)->tallyValue(values[0]) < 0
                           ? kIOReturnError
                           : kIOReturnSuccess;
            case SwifterKitReporterOperation::OverrideBucket:
                if (config.kind != kHistogram || values[0] < 0
                    || static_cast<uint64_t>(values[0]) >= BucketCount(config) || values[1] < 0
                    || values[2] > values[3]) {
                    return kIOReturnBadArgument;
                }
                return static_cast<IOHistogramReporter*>(reporter)->overrideBucketValues(
                    static_cast<unsigned int>(values[0]),
                    static_cast<uint64_t>(values[1]),
                    values[2],
                    values[3],
                    values[4]);
        }
        return kIOReturnBadArgument;
    }

    kern_return_t Read(
        IOReporter* reporter,
        const SwifterKitReporterConfiguration& config,
        const SwifterKitReporterRead& read,
        SwifterKitReporterReading* reading) {
        if (read.reserved != 0) {
            return kIOReturnBadArgument;
        }
        if (config.kind == kSimple && read.stateID == 0) {
            reading->values[0] = static_cast<IOSimpleReporter*>(reporter)->getValue(read.channelID);
            return kIOReturnSuccess;
        }
        if (config.kind != kState || !HasState(config, read.stateID)) {
            return kIOReturnBadArgument;
        }
        auto* states = static_cast<IOStateReporter*>(reporter);
        reading->values[0] =
            static_cast<int64_t>(states->getStateInTransitions(read.channelID, read.stateID));
        reading->values[1] =
            static_cast<int64_t>(states->getStateResidencyTime(read.channelID, read.stateID));
        reading->values[2] =
            static_cast<int64_t>(states->getStateLastTransitionTime(read.channelID, read.stateID));
        return kIOReturnSuccess;
    }
}  // namespace

kern_return_t SwifterKitRuntimeService::StartReporting() {
    if (ivars == nullptr || ivars->dispatchLock == nullptr) {
        return kIOReturnNotReady;
    }
    if (kSwifterKitReporterCount == 0) {
        return kIOReturnSuccess;
    }
    OSArray* reporters = OSArray::withCapacity(kSwifterKitReporterCount);
    IOReportLegend* legend = IOReportLegend::with(nullptr);
    kern_return_t result =
        reporters == nullptr || legend == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
    for (uint32_t index = 0; result == kIOReturnSuccess && index < kSwifterKitReporterCount;
         index += 1) {
        const SwifterKitReporterConfiguration& config = kSwifterKitReporters[index];
        IOReporter* reporter = CreateReporter(this, config);
        result = reporter == nullptr || !reporters->setObject(reporter) ? kIOReturnNoMemory
                                                                        : kIOReturnSuccess;
        if (result == kIOReturnSuccess) {
            result = legend->addReporterLegend(reporter, config.group, config.subgroup);
        }
        if (result == kIOReturnSuccess) {
            IOLockLock(ivars->dispatchLock);
            ivars->reporters[index] = reporter;
            IOLockUnlock(ivars->dispatchLock);
        } else {
            OSSafeReleaseNULL(reporter);
        }
    }
    if (result == kIOReturnSuccess) {
        result = SetLegend(legend->getLegend(), kSwifterKitReportLegendPublic);
    }
    OSSafeReleaseNULL(legend);
    if (result == kIOReturnSuccess) {
        IOLockLock(ivars->dispatchLock);
        ivars->reporterSet = reporters;
        IOLockUnlock(ivars->dispatchLock);
    } else {
        OSSafeReleaseNULL(reporters);
    }
    return result;
}

void SwifterKitRuntimeService::StopReporting() {
    if (ivars == nullptr || ivars->dispatchLock == nullptr) {
        return;
    }
    const IOReporter* reporters[kSwifterKitMaximumReporters] = {};
    IOLockLock(ivars->dispatchLock);
    const OSArray* reporterSet = ivars->reporterSet;
    ivars->reporterSet = nullptr;
    for (uint32_t index = 0; index < kSwifterKitMaximumReporters; index += 1) {
        reporters[index] = ivars->reporters[index];
        ivars->reporters[index] = nullptr;
    }
    IOLockUnlock(ivars->dispatchLock);
    for (const auto* reporter : reporters) {
        OSSafeReleaseNULL(reporter);
    }
    OSSafeReleaseNULL(reporterSet);
}

IOReturn SwifterKitRuntimeService::ConfigureReport_Impl(
    OSData* channels,
    uint32_t action,
    uint32_t* outCount) {
    OSArray* reporters = CopyReporterSet(ivars);
    if (reporters == nullptr) {
        return ConfigureReport(channels, action, outCount, SUPERDISPATCH);
    }
    const IOReturn result = IOReporter::configureAllReports(reporters, channels, action, outCount);
    reporters->release();
    return result;
}

IOReturn SwifterKitRuntimeService::UpdateReport_Impl(
    OSData* channels,
    uint32_t action,
    uint32_t* outElementCount,
    uint64_t offset,
    uint64_t capacity,
    IOMemoryDescriptor* buffer) {
    OSArray* reporters = CopyReporterSet(ivars);
    if (reporters == nullptr) {
        return UpdateReport(
            channels,
            action,
            outElementCount,
            offset,
            capacity,
            buffer,
            SUPERDISPATCH);
    }
    const IOReturn result = IOReporter::updateAllReports(
        reporters,
        channels,
        action,
        outElementCount,
        offset,
        capacity,
        buffer);
    reporters->release();
    return result;
}

kern_return_t SwifterKitRuntimeService::ReporterCommand(
    uint32_t opcode,
    const uint8_t* payload,
    uint32_t payloadLength,
    OSData** response) {
    if (ivars == nullptr || ivars->dispatchLock == nullptr) {
        return kIOReturnNotReady;
    }
    const bool isUpdate =
        static_cast<SwifterKitRuntimeOpcode>(opcode) == SwifterKitRuntimeOpcode::ReporterUpdate;
    SwifterKitReporterUpdate update = {};
    SwifterKitReporterRead read = {};
    const uint32_t expected = isUpdate ? sizeof(update) : sizeof(read);
    if (payload == nullptr || payloadLength != expected) {
        return kIOReturnBadArgument;
    }
    memcpy(isUpdate ? static_cast<void*>(&update) : static_cast<void*>(&read), payload, expected);
    const uint32_t index = isUpdate ? update.reporterIndex : read.reporterIndex;
    const uint64_t channelID = isUpdate ? update.channelID : read.channelID;
    if (index >= kSwifterKitReporterCount || !HasChannel(kSwifterKitReporters[index], channelID)) {
        return kIOReturnBadArgument;
    }
    IOReporter* reporter = CopyReporter(ivars, index);
    if (reporter == nullptr) {
        return kIOReturnNotReady;
    }
    kern_return_t result = kIOReturnSuccess;
    if (isUpdate) {
        result = Update(reporter, kSwifterKitReporters[index], update);
    } else {
        SwifterKitReporterReading reading = {};
        result = Read(reporter, kSwifterKitReporters[index], read, &reading);
        if (result == kIOReturnSuccess) {
            *response = OSData::withBytes(&reading, sizeof(reading));
            result = *response == nullptr ? kIOReturnNoMemory : kIOReturnSuccess;
        }
    }
    reporter->release();
    return result;
}
