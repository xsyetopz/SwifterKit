#ifndef SwifterKitRuntimeDispatchSources_h
#define SwifterKitRuntimeDispatchSources_h

#include <DriverKit/IODispatchSource.h>
#include <DriverKit/OSAction.h>
#include <string.h>

// Helpers for the dispatch sources that the runtime creates for Swift's timers and watches.

// A dispatch source may start disabled, so every source is enabled once its handler is set and
// its slot is reserved.
inline kern_return_t SwifterKitEnableSource(IODispatchSource* source) {
    return source->SetEnableWithCompletion(true, nullptr);
}

// Cancels and releases a source and its action. A handler already running keeps its own
// references; later firings are dropped because the slot no longer holds their identifier.
// The helper consumes the caller's references; os_consumed tells the static analyzer so, which
// otherwise reports every caller's reference as leaked.
inline void SwifterKitReleaseSource(
    IODispatchSource* __attribute__((os_consumed)) source,
    OSAction* __attribute__((os_consumed)) action) {
    if (source != nullptr) {
        (void)source->Cancel(nullptr);
    }
    if (action != nullptr) {
        (void)action->Cancel(nullptr);
    }
    OSSafeReleaseNULL(source);
    OSSafeReleaseNULL(action);
}

// Stores an identifier in an action created with a sizeof(uint32_t) reference.
inline void SwifterKitSetActionIdentifier(OSAction* action, uint32_t identifier) {
    memcpy(action->GetReference(), &identifier, sizeof(identifier));
}

inline uint32_t SwifterKitActionIdentifier(OSAction* action) {
    uint32_t identifier = 0;
    if (action != nullptr && action->GetReference() != nullptr) {
        memcpy(&identifier, action->GetReference(), sizeof(identifier));
    }
    return identifier;
}

// Reads a SwifterKitDispatchIdentifier payload; returns 0 when it is malformed.
inline uint32_t SwifterKitReadIdentifier(const uint8_t* payload, uint32_t payloadLength) {
    uint32_t words[2] = {};
    if (payload == nullptr || payloadLength != sizeof(words)) {
        return 0;
    }
    memcpy(words, payload, sizeof(words));
    return words[1] == 0 ? words[0] : 0;
}

#endif
