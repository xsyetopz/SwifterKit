#include "SwifterKitRuntimeMIDIDevice.h"

#if SWIFTERKIT_ENABLE_MIDI
    #include <DriverKit/OSArray.h>
    #include <MIDIDriverKit/MIDIDriverKit.h>

// IOUserMIDIDevice.iig: "The sorts of changes that must go through this mechanism are anything
// that affects either the structure of the device or IO. This includes, but is not limited to,
// changing the number of entities or adding/removing sources or destinations."
// The change info holds the member and its owner, so the change applies to the objects the
// command resolved. The action says whether the member is added or removed.
namespace {
    constexpr uint64_t kAttachMemberAction = 0x53574B4D49444141ULL;
    constexpr uint64_t kDetachMemberAction = 0x53574B4D49444444ULL;

    kern_return_t ApplyMemberChange(bool attached, const OSObject* changeInfo) {
        const auto* objects = OSDynamicCast(OSArray, changeInfo);
        if (objects == nullptr || objects->getCount() != 2) {
            return kIOReturnBadArgument;
        }
        const OSObject* member = objects->getObject(0);
        const OSObject* owner = objects->getObject(1);
        if (auto* entity = OSDynamicCast(IOUserMIDIEntity, member)) {
            auto* device = OSDynamicCast(IOUserMIDIDevice, owner);
            if (device == nullptr) {
                return kIOReturnBadArgument;
            }
            return attached ? device->AddEntity(entity) : device->RemoveEntity(entity);
        }
        auto* entityOwner = OSDynamicCast(IOUserMIDIEntity, owner);
        if (entityOwner == nullptr) {
            return kIOReturnBadArgument;
        }
        if (auto* source = OSDynamicCast(IOUserMIDISource, member)) {
            return attached ? entityOwner->AddSource(source) : entityOwner->RemoveSource(source);
        }
        if (auto* destination = OSDynamicCast(IOUserMIDIDestination, member)) {
            return attached ? entityOwner->AddDestination(destination)
                            : entityOwner->RemoveDestination(destination);
        }
        return kIOReturnBadArgument;
    }
}  // namespace

kern_return_t SwifterKitRuntimeMIDIDevice::RequestMemberChange(
    IOUserMIDIObject* member,
    IOUserMIDIObject* owner,
    bool attached) {
    if (member == nullptr || owner == nullptr) {
        return kIOReturnBadArgument;
    }
    const OSObject* objects[2] = {member, owner};
    OSArray* info = OSArray::withObjects(objects, 2, 2);
    if (info == nullptr) {
        return kIOReturnNoMemory;
    }
    const kern_return_t result = RequestDeviceConfigurationChange(
        attached ? kAttachMemberAction : kDetachMemberAction,
        info);
    info->release();
    return result;
}

kern_return_t SwifterKitRuntimeMIDIDevice::PerformDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    // IOUserMIDIDevice.iig: "Subclass and override this method to handle any custom
    // configuration change requests, then call super class to update state."
    if (changeAction == kAttachMemberAction || changeAction == kDetachMemberAction) {
        const kern_return_t result =
            ApplyMemberChange(changeAction == kAttachMemberAction, changeInfo);
        if (result != kIOReturnSuccess) {
            return result;
        }
    }
    return super::PerformDeviceConfigurationChange(changeAction, changeInfo);
}

kern_return_t SwifterKitRuntimeMIDIDevice::AbortDeviceConfigurationChange(
    uint64_t changeAction,
    OSObject* changeInfo) {
    // A member change keeps nothing outside its change info, so an aborted one leaves the
    // structure as it was.
    return super::AbortDeviceConfigurationChange(changeAction, changeInfo);
}

#endif
