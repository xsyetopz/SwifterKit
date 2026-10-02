import Foundation
import Testing

@testable import SwifterKitCoverage

/// Reads `header` as the ExampleKit framework of one SDK.
func surface(_ version: String, _ header: String) -> SDKSurface {
  SDKSurface(
    version: version,
    classes: IIGParser.parse(header).map {
      SDKSurface.DeclaredClass(framework: "ExampleKit", declaration: $0)
    }
  )
}

func use(
  _ className: String,
  _ method: String,
  _ parameters: [String]?,
  kind: NativeUse.Kind = .call,
  in function: String = "Runtime::Start"
) -> NativeUse {
  NativeUse(
    className: className,
    method: method,
    parameters: parameters,
    kind: kind,
    file: "Runtime.cpp",
    function: function
  )
}

/// The status of every member, keyed `Class::signature`.
func statuses(_ coverage: Coverage) -> [String: CoverageStatus] {
  Dictionary(
    uniqueKeysWithValues: coverage.classes.flatMap { entry in
      entry.methods.map { ("\(entry.name)::\($0.signature)", $0.status) }
    }
  )
}

@Suite
struct CoverageTests {
  private let older = """
    class KERNEL IOExample : public IOService
    {
    public:
        virtual bool init() override;
        virtual kern_return_t Start(IOService * provider) override;
        virtual kern_return_t Legacy(uint32_t value);
    private:
        virtual void _Plumbing();
    };
    """

  private let newer = """
    class KERNEL IOExample : public IOService
    {
    public:
        virtual bool init() override;
        virtual kern_return_t Start(IOService * provider) override;
        virtual kern_return_t Added(uint64_t value);
    private:
        virtual void _Plumbing();
    };
    """

  @Test
  func mergesSDKPresenceAndAppliesAppleExclusions() throws {
    let coverage = Coverage([surface("27.0", newer), surface("24.4", older)])
    let methods = try #require(coverage.classes.first).methods

    #expect(coverage.sdks == ["24.4", "27.0"])
    #expect(methods.map(\.signature) == methods.map(\.signature).sorted())
    #expect(methods.count == 5)
    let byName = Dictionary(uniqueKeysWithValues: methods.map { ($0.name, $0) })
    #expect(byName["Start"]?.sdks == ["24.4", "27.0"])
    #expect(byName["Legacy"]?.sdks == ["24.4"])
    #expect(byName["Added"]?.sdks == ["27.0"])
    #expect(byName["Start"]?.status == .gap)
    #expect(byName["_Plumbing"]?.status == .excluded)
    #expect(byName["_Plumbing"]?.excludedBy == .apple)
    #expect(byName["_Plumbing"]?.note == "declared private in the SDK header")
    // Lifecycle hooks are public in the header, so only evidence decides their status.
    #expect(byName["init"]?.status == .gap)
    #expect(byName["init"]?.excludedBy == nil)
  }

  @Test
  func appliesEvidenceToTheDeclaringClassAndOverload() throws {
    let header = """
      class KERNEL IOExample : public IOService
      {
      public:
          virtual kern_return_t Start(IOService * provider) override;
          virtual void Notify(uint32_t value);
          virtual void Notify(uint64_t value, bool urgent);
          virtual void Notify(const char * name);
      };
      class KERNEL IOExampleChild : public IOExample
      {
      public:
          virtual void Unused();
      };
      """
    let coverage = Coverage([surface("24.4", header)])
    let native = NativeEvidence(
      uses: [
        use("IOExample", "Start", nil, kind: .override, in: "Runtime::Start_Impl"),
        use("IOExampleChild", "Notify", ["uint64_t", "bool"]), use("IOExample", "Notify", ["int"]),
        use("IOExample", "Missing", []), use("OSObject", "retain", []),
      ],
      bases: [:]
    )
    let evidence = CoverageEvidence(coverage: coverage, native: native)
    let notify = CoverageEvidence.MemberKey("IOExample", "void Notify(uint64_t, bool)")
    let unused = CoverageEvidence.MemberKey("IOExampleChild", "void Unused()")
    let applied = coverage.applying(evidence, documented: [notify, unused])
    let methods = Dictionary(
      uniqueKeysWithValues: applied.classes.flatMap { entry in
        entry.methods.map { ("\(entry.name)::\($0.signature)", $0) }
      }
    )

    let start = methods["IOExample::kern_return_t Start(IOService*)"]
    #expect(start?.status == .generated)
    #expect(start?.evidence == ["Runtime.cpp: Runtime::Start_Impl"])
    #expect(methods["IOExample::void Notify(uint64_t, bool)"]?.status == .swiftAPI)
    #expect(
      methods["IOExample::void Notify(uint64_t, bool)"]?.evidence == ["Runtime.cpp: Runtime::Start"]
    )
    #expect(methods["IOExample::void Notify(uint32_t)"]?.status == .gap)
    #expect(methods["IOExample::void Notify(const char*)"]?.status == .gap)
    // Documentation without evidence leaves a gap.
    #expect(methods["IOExampleChild::void Unused()"]?.status == .gap)
    // An ambiguous overload and an undeclared member stay unresolved; classes no SDK declares
    // are not listed.
    #expect(evidence.unresolved.map(\.method).sorted() == ["Missing", "Notify"])
  }

  @Test
  func excludesOnlyPublicMembersTheRuntimeDoesNotReach() {
    let coverage = Coverage([surface("24.4", older)])
    let native = NativeEvidence(
      uses: [use("IOExample", "Start", nil, kind: .override, in: "Runtime::Start_Impl")],
      bases: [:]
    )
    let exclusions: Set = [
      Coverage.Exclusion(className: "IOExample", signature: "bool init()", reason: "Owned"),
      Coverage.Exclusion(
        className: "IOExample",
        signature: "kern_return_t Start(IOService*)",
        reason: "Owned"
      ), Coverage.Exclusion(className: "IOExample", signature: "void _Plumbing()", reason: "Owned"),
    ]
    let applied = coverage.applying(
      CoverageEvidence(coverage: coverage, native: native),
      exclusions: exclusions
    )
    let methods = Dictionary(uniqueKeysWithValues: applied.classes[0].methods.map { ($0.name, $0) })

    #expect(methods["init"]?.status == .excluded)
    #expect(methods["init"]?.excludedBy == .swifterkit)
    #expect(methods["init"]?.note == "Owned")
    #expect(methods["Start"]?.status == .generated)
    #expect(methods["_Plumbing"]?.excludedBy == .apple)
    #expect(methods["_Plumbing"]?.note == "declared private in the SDK header")
    #expect(methods["Legacy"]?.status == .gap)
  }

  @Test
  func attributesIIGInterfaceDeclarationsToTheirClass() {
    let header = """
      class LOCALONLY IOExample : public OSContainer
      {
      public:
          virtual uint32_t getUsage() = 0;
      };
      class LOCALONLY IOExampleInterface : public OSContainer
      {
      public:
          virtual void open();
      };
      """
    let coverage = Coverage([surface("24.4", header)])
    // IIG declares a LOCALONLY class's pure virtuals again on `<Class>Interface`, and clang
    // resolves calls through a class pointer to that declaration.
    let native = NativeEvidence(
      uses: [
        use("IOExampleInterface", "getUsage", []), use("IOExampleInterfaceInterface", "open", []),
      ],
      bases: [:]
    )
    let applied = statuses(coverage.applying(CoverageEvidence(coverage: coverage, native: native)))

    #expect(applied["IOExample::uint32_t getUsage()"] == .generated)
    #expect(applied["IOExampleInterface::void open()"] == .generated)
  }

  @Test
  func attributesCallsToTheReceiversOverride() {
    let header = """
      class KERNEL IOSource : public OSObject
      {
      public:
          virtual kern_return_t Cancel(IOCancelHandler handler);
          virtual kern_return_t Enable(bool enable);
      };
      class KERNEL IOTimerSource : public IOSource
      {
      public:
          virtual kern_return_t Cancel(IOCancelHandler handler) override;
      };
      """
    let coverage = Coverage([surface("24.4", header)])
    // IIG declares only `Cancel_Impl` on the generated subclass, so clang names the base's
    // declaration; the receiver's class decides which override the call reaches.
    var cancel = use("IOSource", "Cancel", ["IOCancelHandler"])
    cancel.receiver = "IOTimerSource"
    var enable = use("IOSource", "Enable", ["bool"])
    enable.receiver = "IOTimerSource"
    var unknown = use("IOSource", "Cancel", ["IOCancelHandler"], in: "Runtime::Stop")
    unknown.receiver = "Runtime"
    let evidence = CoverageEvidence(
      coverage: coverage,
      native: NativeEvidence(uses: [cancel, enable, unknown], bases: [:])
    )

    #expect(
      evidence.members.keys.map { "\($0.className)::\($0.signature)" }.sorted() == [
        "IOSource::kern_return_t Cancel(IOCancelHandler)", "IOSource::kern_return_t Enable(bool)",
        "IOTimerSource::kern_return_t Cancel(IOCancelHandler)",
      ]
    )
    #expect(
      evidence.members[.init("IOSource", "kern_return_t Cancel(IOCancelHandler)")] == [
        "Runtime.cpp: Runtime::Stop"
      ]
    )
  }

  @Test
  func attributesDispatchedCallsToOverridesOfClassesTheRuntimeHolds() {
    let header = """
      class LOCALONLY IOObject : public OSObject
      {
      public:
          virtual kern_return_t SetProperties(OSDictionary * properties);
      };
      class LOCALONLY IODevice : public IOObject
      {
      public:
          virtual kern_return_t SetProperties(OSDictionary * properties) override;
          virtual kern_return_t AddEntity(IOEntity * entity);
      };
      class LOCALONLY IOEntity : public IOObject
      {
      public:
          virtual kern_return_t SetProperties(OSDictionary * properties) override;
      };
      class LOCALONLY IOUnused : public IOObject
      {
      public:
          virtual kern_return_t SetProperties(OSDictionary * properties) override;
      };
      """
    let coverage = Coverage([surface("24.4", header)])
    // A call through an `IOObject *` reaches the override of whichever class the object has,
    // and the runtime holds devices and entities; a call on its own object does not dispatch.
    var dispatched = use("IOObject", "SetProperties", ["OSDictionary*"], in: "Runtime::Set")
    dispatched.receiver = "IOObject"
    dispatched.dispatched = true
    var own = use("IOObject", "SetProperties", ["OSDictionary*"], in: "Runtime::Own")
    own.receiver = "IOObject"
    var add = use("IODevice", "AddEntity", ["IOEntity*"])
    add.receiver = "IODevice"
    let entity = use("IOEntity", "SetProperties", nil, kind: .override, in: "Entity::Set_Impl")
    let evidence = CoverageEvidence(
      coverage: coverage,
      native: NativeEvidence(uses: [dispatched, own, add, entity], bases: [:])
    )
    let setProperties = "kern_return_t SetProperties(OSDictionary*)"

    #expect(
      evidence.members[.init("IOObject", setProperties)] == [
        "Runtime.cpp: Runtime::Set", "Runtime.cpp: Runtime::Own", "Runtime.cpp: Entity::Set_Impl",
      ]
    )
    #expect(evidence.members[.init("IODevice", setProperties)] == ["Runtime.cpp: Runtime::Set"])
    #expect(
      evidence.members[.init("IOEntity", setProperties)] == [
        "Runtime.cpp: Runtime::Set", "Runtime.cpp: Entity::Set_Impl",
      ]
    )
    #expect(evidence.members[.init("IOUnused", setProperties)] == nil)
  }

  @Test
  func attributesOverridesToEveryDeclarationTheyOverride() {
    let header = """
      class LOCALONLY IOObject : public OSObject
      {
      public:
          virtual bool init();
          virtual void Stop(int reason);
      };
      class LOCALONLY IOEventService : public IOObject
      {
      public:
          virtual void Stop(int reason) override;
          virtual void Stop(bool force);
      };
      class LOCALONLY IOUserEventService : public IOEventService
      {
      public:
          virtual bool init() override;
          virtual void Stop(int reason) override;
      };
      """
    let coverage = Coverage([surface("24.4", header)])
    // `IOUserEventService::Stop` overrides the virtual its superclasses declare first, so the
    // runtime's override overrides theirs too, but not an overload with other parameters.
    let stop = use("IOUserEventService", "Stop", nil, kind: .override, in: "Runtime::Stop_Impl")
    let initializer = use("IOUserEventService", "init", [], kind: .override, in: "Runtime::init")
    let evidence = CoverageEvidence(
      coverage: coverage,
      native: NativeEvidence(uses: [stop, initializer], bases: [:])
    )

    for className in ["IOObject", "IOEventService", "IOUserEventService"] {
      #expect(
        evidence.members[.init(className, "void Stop(int)")] == ["Runtime.cpp: Runtime::Stop_Impl"]
      )
    }
    #expect(evidence.members[.init("IOEventService", "void Stop(bool)")] == nil)
    #expect(evidence.members[.init("IOObject", "bool init()")] == ["Runtime.cpp: Runtime::init"])
  }
}
