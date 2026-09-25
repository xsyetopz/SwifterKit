import Testing

@testable import SwifterKitCoverage

@Suite
struct IIGParserTests {
  @Test
  func parsesClassesMethodsAndAnnotations() throws {
    let classes = IIGParser.parse(
      """
      #ifndef _EXAMPLE_IIG
      #define _EXAMPLE_IIG
      class OSAction;
      /* A block comment with class Fake { */
      class KERNEL IOExamplePipe : public OSObject
      {
      public:
          // A line comment.
          virtual kern_return_t
          AsyncIO(IOMemoryDescriptor *dataBuffer,
                  uint32_t            length,
                  OSAction           *completion TYPE(CompleteAsyncIO)) LOCAL;
          virtual void
          CompleteAsyncIO(OSAction *action TARGET, IOReturn status) = 0;
          static OSDictionary *
          CreateMatching(const char * key, OSDictionary * matching) LOCALONLY;
          virtual kern_return_t GetSpeed(uint8_t *speed) const;
      private:
          virtual void _Internal(uint32_t value) LOCAL;
      };
      #endif
      """
    )

    let pipe = try #require(classes.first)
    #expect(classes.count == 1)
    #expect(pipe.name == "IOExamplePipe")
    #expect(pipe.superclass == "OSObject")
    #expect(pipe.isKernel)
    #expect(!pipe.isExtension)
    #expect(
      pipe.methods.map(\.signature) == [
        "kern_return_t AsyncIO(IOMemoryDescriptor*, uint32_t, OSAction*)",
        "void CompleteAsyncIO(OSAction*, IOReturn)",
        "OSDictionary* CreateMatching(const char*, OSDictionary*)",
        "kern_return_t GetSpeed(uint8_t*) const", "void _Internal(uint32_t)",
      ]
    )
    #expect(pipe.methods[0].annotations == ["LOCAL"])
    #expect(pipe.methods[2].isStatic)
    #expect(pipe.methods[2].annotations == ["LOCALONLY"])
    #expect(pipe.methods[4].access == .private)
    #expect(pipe.methods.allSatisfy { $0.conditions.isEmpty })
  }

  @Test
  func treatsMembersBeforeAnySpecifierAsPublic() throws {
    let serial = try #require(
      IIGParser.parse(
        """
        class KERNEL IOUserSerial : protected IOService
        {
            virtual kern_return_t RxError(bool overrun, bool gotBreak);
        };
        """
      ).first
    )
    #expect(serial.superclass == "IOService")
    #expect(serial.methods.map(\.access) == [.public])
  }

  @Test
  func recordsConditionsAndExtensions() throws {
    let classes = IIGParser.parse(
      """
      class IOExample : public IOService
      {
      public:
      #if KERNEL
          virtual void KernelOnly();
      #else
          virtual void ClientSide();
      #endif
      #if 0
          virtual void Disabled();
      #endif
      };
      class EXTENDS (IOExample) IOExamplePrivate
      {
          virtual kern_return_t _Plumbing(uint32_t count);
      };
      enum class IOExampleMode : uint32_t { first };
      """
    )

    #expect(classes.map(\.name) == ["IOExample", "IOExamplePrivate"])
    #expect(classes[0].methods.map(\.conditions) == [["KERNEL"], ["!(KERNEL)"], ["0"]])
    #expect(classes[1].isExtension)
    #expect(classes[1].superclass == "IOExample")
  }

  @Test
  func normalizesParameterNamesArraysAndDefaults() {
    #expect(
      IIGParser.normalizedParameters(
        "const uint32_t lengths[16], unsigned long count = 0, struct Foo * foo, void"
      ) == "const uint32_t[16], unsigned long, struct Foo*"
    )
  }

  @Test
  func removesCommentsButKeepsLinesAndStrings() {
    let text = "a /* x\ny */ b // c\n\"// not a comment\""
    #expect(IIGSource.removingComments(text) == "a \n b \n\"// not a comment\"")
  }
}
