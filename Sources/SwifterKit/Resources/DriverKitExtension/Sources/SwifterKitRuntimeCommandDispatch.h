#ifndef SwifterKitRuntimeCommandDispatch_h
#define SwifterKitRuntimeCommandDispatch_h

#include <DriverKit/IOUserClient.h>

#include "SwifterKitRuntimeProtocol.h"

class SwifterKitRuntimeService;

// Answers a transact message whose selector, length, and magic the user client already checked:
// a handshake, or a command routed to its opcode family.
kern_return_t SwifterKitHandleMessage(
    SwifterKitRuntimeService* service,
    IOUserClientMethodArguments* arguments,
    const SwifterKitRuntimeHeader* request,
    const uint8_t* payload);

#endif
