import Foundation
import Testing

@testable import SwifterKitCoverage

@Suite
struct ClangASTTests {
  /// A reduced `-ast-dump=json` of a runtime class that overrides `Start` through IIG and calls
  /// `Notify` on its provider. Like clang, later locations omit a file that repeats.
  private let dump = """
    {"kind": "TranslationUnitDecl", "inner": [
      {"id": "0x1", "kind": "CXXRecordDecl", "name": "IOExample",
       "loc": {"file": "/sdk/IOExample.h", "line": 3},
       "range": {"begin": {"line": 3}, "end": {"line": 9}},
       "inner": [
        {"id": "0x2", "kind": "CXXMethodDecl", "name": "Notify", "loc": {"line": 5},
         "type": {"qualType": "void (uint64_t, struct Payload *) const"}},
        {"id": "0x3", "kind": "CXXMethodDecl", "name": "Start", "loc": {"line": 6},
         "type": {"qualType": "kern_return_t (IOService *, OSDispatchMethod)"}}
      ]},
      {"id": "0x4", "kind": "CXXRecordDecl", "name": "Runtime", "completeDefinition": true,
       "loc": {"file": "/src/Runtime.h", "line": 2},
       "bases": [{"type": {"qualType": "IOExample"}}],
       "inner": [
        {"id": "0x5", "kind": "CXXMethodDecl", "name": "Start_Impl", "loc": {"line": 4},
         "type": {"qualType": "kern_return_t (IOExample_Start_Args)"}},
        {"id": "0x6", "kind": "CXXMethodDecl", "name": "Notify", "loc": {"line": 5},
         "type": {"qualType": "void (uint64_t, struct Payload *) const"},
         "inner": [{"kind": "OverrideAttr"}]}
      ]},
      {"id": "0x7", "kind": "CXXMethodDecl", "name": "Start_Impl", "parentDeclContextId": "0x4",
       "previousDecl": "0x5",
       "loc": {"spellingLoc": {"file": "/sdk/Macros.h", "line": 1},
               "expansionLoc": {"file": "/src/Runtime.cpp", "line": 10}},
       "range": {"begin": {"line": 10}, "end": {"line": 14}},
       "type": {"qualType": "kern_return_t (IOExample_Start_Args)"},
       "inner": [{"kind": "CompoundStmt", "inner": [
         {"kind": "MemberExpr", "referencedMemberDecl": "0x2",
          "range": {"begin": {"line": 11}, "end": {"line": 11}}},
         {"kind": "DeclRefExpr", "referencedDecl": {"id": "0x3"},
          "range": {"begin": {"file": "/sdk/Other.h", "line": 1}, "end": {"line": 1}}}
       ]}]},
      {"id": "0x8", "kind": "CXXMethodDecl", "name": "Notify", "parentDeclContextId": "0x4",
       "previousDecl": "0x6", "loc": {"file": "/src/Runtime.cpp", "line": 20},
       "type": {"qualType": "void (uint64_t, struct Payload *) const"},
       "inner": [{"kind": "CompoundStmt"}]}
    ]}
    """

  @Test
  func readsOverridesAndCallsFromSourceFiles() throws {
    let ast = try ClangAST(json: Data(dump.utf8)) { $0.hasPrefix("/src/") }

    #expect(ast.bases == ["Runtime": "IOExample"])
    #expect(
      ast.uses.sorted() == [
        NativeUse(
          className: "IOExample",
          method: "Notify",
          parameters: ["uint64_t", "Payload*"],
          kind: .override,
          file: "Runtime.cpp",
          function: "Runtime::Notify"
        ),
        NativeUse(
          className: "IOExample",
          method: "Notify",
          parameters: ["uint64_t", "Payload*"],
          kind: .call,
          file: "Runtime.cpp",
          function: "Runtime::Start_Impl"
        ),
        NativeUse(
          className: "IOExample",
          method: "Start",
          parameters: nil,
          kind: .override,
          file: "Runtime.cpp",
          function: "Runtime::Start_Impl"
        ),
      ]
    )
  }

  /// A reduced dump in which `Runtime::Poll` calls `IOBase::Cancel` through an `IOTimer *` that
  /// clang converts to its base, through `this` inside an array initializer whose elements clang
  /// writes under `array_filler`, and through a
  /// template's `typename Family::Object *`, whose class only the member alias that
  /// follows names, and through an alias that names itself.
  private let receivers = """
    {"kind": "TranslationUnitDecl", "inner": [
      {"id": "0x1", "kind": "CXXRecordDecl", "name": "IOBase", "loc": {"file": "/sdk/IOBase.h"},
       "inner": [{"id": "0x2", "kind": "CXXMethodDecl", "name": "Cancel",
                  "type": {"qualType": "kern_return_t (int, OSDispatchMethod)"}}]},
      {"id": "0x3", "kind": "CXXRecordDecl", "name": "IOTimer",
       "bases": [{"type": {"qualType": "IOBase"}}]},
      {"id": "0x4", "kind": "CXXRecordDecl", "name": "Runtime", "completeDefinition": true,
       "loc": {"file": "/src/Runtime.h"},
       "bases": [{"type": {"qualType": "IOTimer"}}]},
      {"id": "0x5", "kind": "CXXMethodDecl", "name": "Poll", "parentDeclContextId": "0x4",
       "loc": {"file": "/src/Runtime.cpp"}, "type": {"qualType": "void ()"},
       "inner": [{"kind": "CompoundStmt", "inner": [
         {"kind": "MemberExpr", "referencedMemberDecl": "0x2", "range": {"end": {"line": 2}},
          "inner": [{"kind": "ImplicitCastExpr", "type": {"qualType": "IOBase *"},
                     "castKind": "UncheckedDerivedToBase",
                     "inner": [{"kind": "ImplicitCastExpr", "type": {"qualType": "IOTimer *"}}]}]},
         {"kind": "InitListExpr", "array_filler": [
           {"kind": "ImplicitValueInitExpr"},
           {"kind": "MemberExpr", "referencedMemberDecl": "0x2", "range": {"end": {"line": 3}},
            "inner": [{"kind": "CXXThisExpr", "type": {"qualType": "const Runtime *"}}]}
         ]},
         {"kind": "MemberExpr", "referencedMemberDecl": "0x2", "range": {"end": {"line": 4}},
          "inner": [{"kind": "ImplicitCastExpr",
                     "type": {"qualType": "typename Family::Object *"}}]},
         {"kind": "MemberExpr", "referencedMemberDecl": "0x2", "range": {"end": {"line": 5}},
          "inner": [{"kind": "DeclRefExpr", "type": {"qualType": "typename Family::State *"}}]}
       ]}]},
      {"id": "0x6", "kind": "CXXRecordDecl", "name": "Family", "completeDefinition": true,
       "loc": {"file": "/src/Runtime.cpp"},
       "inner": [{"kind": "TypeAliasDecl", "name": "Object", "type": {"qualType": "IOTimer"}},
                 {"kind": "TypeAliasDecl", "name": "State",
                  "type": {"qualType": "typename Family::State"}}]}
    ]}
    """

  @Test
  func readsReceiversAndArrayInitializers() throws {
    let ast = try ClangAST(json: Data(receivers.utf8)) { $0.hasPrefix("/src/") }

    #expect(
      ast.uses.map(\.receiver).sorted { ($0 ?? "") < ($1 ?? "") } == [
        nil, "IOTimer", "IOTimer", "IOTimer",
      ]
    )
    #expect(ast.uses.allSatisfy { $0.className == "IOBase" && $0.function == "Runtime::Poll" })
    // Only the call through a DriverKit pointer dispatches on an object of unknown class.
    #expect(
      ast.uses.filter { $0.dispatched }.compactMap(\.receiver).sorted() == ["IOTimer", "IOTimer"]
    )
  }

  @Test
  func readsReceiversOfClassesIIGDefinesInDerivedSources() throws {
    // IIG writes the runtime class's definition into `DerivedSources`, so a call on `this`
    // names a class defined in the tree but outside the sources whose uses are read. The
    // sources also forward-declare DriverKit classes, which does not make them the tree's.
    let json = """
      {"kind": "TranslationUnitDecl", "inner": [
        {"id": "0x1", "kind": "CXXRecordDecl", "name": "IOBase", "loc": {"file": "/sdk/IOBase.h"},
         "inner": [{"id": "0x2", "kind": "CXXMethodDecl", "name": "Cancel", "virtual": true,
                    "type": {"qualType": "kern_return_t (int)"}}]},
        {"id": "0x5", "kind": "CXXRecordDecl", "name": "IOBase",
         "loc": {"file": "/tree/Sources/State.h"}},
        {"id": "0x3", "kind": "CXXRecordDecl", "name": "Runtime", "completeDefinition": true,
         "loc": {"file": "/tree/DerivedSources/Runtime.h"},
         "bases": [{"type": {"qualType": "IOBase"}}]},
        {"id": "0x4", "kind": "CXXMethodDecl", "name": "Poll", "parentDeclContextId": "0x3",
         "loc": {"file": "/tree/Sources/Runtime.cpp"}, "type": {"qualType": "void ()"},
         "inner": [{"kind": "CompoundStmt", "inner": [
           {"kind": "MemberExpr", "referencedMemberDecl": "0x2", "range": {"end": {"line": 2}},
            "inner": [{"kind": "CXXThisExpr", "type": {"qualType": "Runtime *"}}]},
           {"kind": "MemberExpr", "referencedMemberDecl": "0x2", "range": {"end": {"line": 3}},
            "inner": [{"kind": "DeclRefExpr", "type": {"qualType": "IOBase *"}}]}
         ]}]}
      ]}
      """
    let ast = try ClangAST(
      json: Data(json.utf8),
      isTree: { $0.hasPrefix("/tree/") },
      isSource: { $0.hasPrefix("/tree/Sources/") }
    )

    // A forward declaration in the tree leaves a DriverKit class DriverKit's.
    let uses = ast.uses.sorted { ($0.dispatched ? 1 : 0) < ($1.dispatched ? 1 : 0) }
    #expect(uses.map(\.receiver) == ["IOBase", "IOBase"])
    #expect(uses.map(\.dispatched) == [false, true])
  }

  @Test
  func dispatchesOnlyVirtualAndIIGMembers() throws {
    // `IOReporter::addChannel` is neither virtual nor an IIG method, so a call through an
    // `IOReporter *` never reaches `IOHistogramReporter::addChannel`.
    let json = """
      {"kind": "TranslationUnitDecl", "inner": [
        {"id": "0x1", "kind": "CXXRecordDecl", "name": "IOBase", "loc": {"file": "/sdk/IOBase.h"},
         "inner": [
          {"id": "0x2", "kind": "CXXMethodDecl", "name": "Add",
           "type": {"qualType": "int (int)"}},
          {"id": "0x3", "kind": "CXXMethodDecl", "name": "Kind", "virtual": true,
           "type": {"qualType": "int () const"}},
          {"id": "0x4", "kind": "CXXMethodDecl", "name": "Cancel",
           "type": {"qualType": "kern_return_t (int, OSDispatchMethod)"}}]},
        {"kind": "FunctionDecl", "name": "Handle", "loc": {"file": "/src/Runtime.cpp"},
         "inner": [{"kind": "CompoundStmt", "inner": [
           {"kind": "MemberExpr", "referencedMemberDecl": "0x2", "range": {"end": {"line": 2}},
            "inner": [{"kind": "DeclRefExpr", "type": {"qualType": "IOBase *"}}]},
           {"kind": "MemberExpr", "referencedMemberDecl": "0x3", "range": {"end": {"line": 3}},
            "inner": [{"kind": "DeclRefExpr", "type": {"qualType": "const IOBase *"}}]},
           {"kind": "MemberExpr", "referencedMemberDecl": "0x4", "range": {"end": {"line": 4}},
            "inner": [{"kind": "DeclRefExpr", "type": {"qualType": "IOBase *"}}]}
         ]}]}
      ]}
      """
    let ast = try ClangAST(json: Data(json.utf8)) { $0.hasPrefix("/src/") }

    #expect(ast.uses.filter(\.dispatched).map(\.method).sorted() == ["Cancel", "Kind"])
  }

  @Test
  func normalizesParameterTypes() {
    #expect(ClangAST.parameters(ofType: "void (void)").isEmpty)
    #expect(ClangAST.parameters(ofType: "bool init() override").isEmpty)
    #expect(
      ClangAST.parameters(ofType: "kern_return_t (IOService *, OSDispatchMethod)") == ["IOService*"]
    )
    #expect(
      ClangAST.parameters(ofType: "void (void (^)(int, bool), const char [16], enum Mode) const")
        == ["void(^)(int,bool)", "constchar[16]", "Mode"]
    )
    #expect(
      ClangAST.parameters(ofType: "auto (uint64_t, void (*)(int)) -> kern_return_t (*)(bool)") == [
        "uint64_t", "void(*)(int)",
      ]
    )
    #expect(
      ClangAST.parameters(ofType: "kern_return_t Start(IOService*)")
        == ClangAST.parameters(ofType: "kern_return_t (IOService *)")
    )
  }

  @Test
  func parsesStatementsNestedDeeperThanADispatchWorkerStack() throws {
    // `HandleCommand`'s nested switches overflowed a dispatch worker's 512 KB stack.
    let depth = 240
    let nested =
      String(repeating: #"{"kind": "CompoundStmt", "inner": ["#, count: depth)
      + #"{"kind": "MemberExpr", "referencedMemberDecl": "0x2", "range": {"end": {"line": 2}}}"#
      + String(repeating: "]}", count: depth)
    let json = """
      {"kind": "TranslationUnitDecl", "inner": [
        {"id": "0x1", "kind": "CXXRecordDecl", "name": "IOBase", "loc": {"file": "/sdk/IOBase.h"},
         "inner": [{"id": "0x2", "kind": "CXXMethodDecl", "name": "Cancel",
                    "type": {"qualType": "kern_return_t ()"}}]},
        {"kind": "FunctionDecl", "name": "Handle", "loc": {"file": "/src/Runtime.cpp"},
         "inner": [\(nested)]}
      ]}
      """
    let ast = try NativeEvidence.parse(Data(json.utf8), treePrefix: "/src/", sourcePrefix: "/src/")

    #expect(ast.uses.map(\.function) == ["Handle"])
  }
}
