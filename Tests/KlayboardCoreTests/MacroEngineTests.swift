import Testing
@testable import KlayboardCore

/// Types `string` one character at a time the way KeyboardViewController
/// does: insert into the document, feed the engine, check for a trigger.
private func type(_ string: String, into proxy: MockTextProxy, engine: MacroEngine) {
    for c in string {
        let s = String(c)
        proxy.insertText(s)
        engine.feedKeystroke(s)
        engine.checkTriggerLocally(proxy: proxy)
    }
}

private func engine(with macros: [(String, String)]) -> MacroEngine {
    let engine = MacroEngine()
    engine.loadMacros(
        builtIn: BuiltInMacros.expansions,
        user: macros.map { MacroDefinition(trigger: $0.0, expansion: $0.1) }
    )
    return engine
}

@MainActor
@Suite("Macro engine")
struct MacroEngineTests {

    @Test func triggerIsReplacedByExpansion() {
        let proxy = MockTextProxy()
        type("mail @@", into: proxy, engine: engine(with: [("@@", "me@example.com")]))
        #expect(proxy.text == "mail me@example.com")
    }

    @Test func textWithoutTriggerIsUntouched() {
        let proxy = MockTextProxy()
        type("plain text @", into: proxy, engine: engine(with: [("@@", "x")]))
        #expect(proxy.text == "plain text @")
    }

    @Test func backspaceRemovesCharacterFromBuffer() {
        let proxy = MockTextProxy()
        let e = engine(with: [("@@", "x")])
        type("@", into: proxy, engine: e)
        proxy.deleteBackward()
        e.handleBackspace()
        type("@", into: proxy, engine: e)
        #expect(proxy.text == "@")
    }

    @Test func resetBufferStopsAPartialTrigger() {
        let proxy = MockTextProxy()
        let e = engine(with: [("@@", "x")])
        type("@", into: proxy, engine: e)
        e.resetBuffer()
        type("@", into: proxy, engine: e)
        #expect(proxy.text == "@@")
    }

    @Test func disabledMacroDoesNotFire() {
        let proxy = MockTextProxy()
        let e = MacroEngine()
        e.loadMacros(builtIn: [:], user: [MacroDefinition(trigger: "@@", expansion: "x", isEnabled: false)])
        type("@@", into: proxy, engine: e)
        #expect(proxy.text == "@@")
    }

    @Test func namedMacroPlacesCursorInside() {
        let proxy = MockTextProxy()
        let e = engine(with: [])
        e.executeMacro(named: "md_bold", proxy: proxy)
        #expect(proxy.text == "****")
        #expect(proxy.cursor == 2)
    }

    @Test func longTriggerFires() {
        let trigger = ";;signature-long" // 16 characters
        let proxy = MockTextProxy()
        type(trigger, into: proxy, engine: engine(with: [(trigger, "Kind regards")]))
        withKnownIssue("Bug: the typing buffer holds 15 characters, so longer triggers never match") {
            #expect(proxy.text == "Kind regards")
        }
    }

    @Test func longestOverlappingTriggerWins() {
        // "cab" ends with "ab": both triggers match after the last keystroke.
        withKnownIssue("Bug: triggers are checked in dictionary order, so which one fires is arbitrary", isIntermittent: true) {
            for _ in 0..<20 {
                let proxy = MockTextProxy()
                type("cab", into: proxy, engine: engine(with: [("ab", "SHORT"), ("cab", "LONG")]))
                #expect(proxy.text == "LONG")
            }
        }
    }
}
