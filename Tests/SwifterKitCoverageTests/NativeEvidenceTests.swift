import Foundation
import Testing

@testable import SwifterKitCoverage

struct NativeEvidenceTests {
  @Test
  func attributesActionImplementationsToTheMemberTheirTypeNames() {
    let iig = """
      class SwifterKitRuntimeService : public IOService
      {
      public:
          virtual kern_return_t Start(IOService * provider) override;
          virtual void USBPipeIOComplete(
              OSAction * action,
              IOReturn status) TYPE(IOUSBHostPipe::CompleteAsyncIO);
      };
      """
    let actions = NativeEvidence.actions(inIIG: iig)
    let uses: Set = [
      use(
        "IOService",
        "USBPipeIOComplete",
        nil,
        kind: .override,
        in: "SwifterKitRuntimeService::USBPipeIOComplete_Impl"
      ),
      use("IOService", "Start", nil, kind: .override, in: "SwifterKitRuntimeService::Start_Impl"),
    ]
    let resolved = NativeEvidence.resolvingActions(uses, actions)
    #expect(
      Set(resolved.map { "\($0.className)::\($0.method) \($0.function)" }) == [
        "IOUSBHostPipe::CompleteAsyncIO SwifterKitRuntimeService::USBPipeIOComplete_Impl",
        "IOService::Start SwifterKitRuntimeService::Start_Impl",
      ]
    )
  }
}
