import Testing
@testable import KlayboardCore

@MainActor
@Suite("Cursor engine")
struct CursorEngineTests {
    let engine = CursorEngine()

    @Test func backwardWordStopsAtWordStart() {
        let proxy = MockTextProxy("hello world")
        engine.moveBackwardByWord(proxy: proxy)
        #expect(proxy.cursor == 6)
    }

    @Test func backwardWordSkipsTrailingPunctuation() {
        let proxy = MockTextProxy("foo, bar.")
        engine.moveBackwardByWord(proxy: proxy)
        #expect(proxy.cursor == 5)
    }

    @Test func forwardWordStopsAtWordEnd() {
        let proxy = MockTextProxy("hello world", cursor: 0)
        engine.moveForwardByWord(proxy: proxy)
        #expect(proxy.cursor == 5)
        engine.moveForwardByWord(proxy: proxy)
        #expect(proxy.cursor == 11)
    }

    @Test func wordMovesAtTheEdgesDoNothing() {
        let start = MockTextProxy("abc", cursor: 0)
        engine.moveBackwardByWord(proxy: start)
        #expect(start.cursor == 0)
        let end = MockTextProxy("abc")
        engine.moveForwardByWord(proxy: end)
        #expect(end.cursor == 3)
    }

    @Test func deleteWordRemovesPreviousWord() {
        let proxy = MockTextProxy("hello world")
        engine.deleteBackwardWord(proxy: proxy)
        #expect(proxy.text == "hello ")
    }

    @Test func deleteToLineStartKeepsEarlierLines() {
        let proxy = MockTextProxy("first\nsecond line")
        engine.deleteToLineStart(proxy: proxy)
        #expect(proxy.text == "first\n")
    }

    @Test func deleteToLineStartWithoutNewlineClearsAll() {
        let proxy = MockTextProxy("only line")
        engine.deleteToLineStart(proxy: proxy)
        #expect(proxy.text == "")
    }

    @Test func toggleCaseCyclesLowerTitleUpper() {
        let proxy = MockTextProxy("say word")
        engine.toggleCase(proxy: proxy)
        #expect(proxy.text == "say Word")
        engine.toggleCase(proxy: proxy)
        #expect(proxy.text == "say WORD")
        engine.toggleCase(proxy: proxy)
        #expect(proxy.text == "say word")
    }

    @Test func toggleCaseKeepsTrailingPunctuation() {
        let proxy = MockTextProxy("word, ")
        engine.toggleCase(proxy: proxy)
        #expect(proxy.text == "Word, ")
        #expect(proxy.cursor == 6)
    }

    /// A one-letter word is the same in Title and UPPER case, so it
    /// alternates between the two cases.
    @Test func toggleCaseOnSingleLetter() {
        let proxy = MockTextProxy("a")
        engine.toggleCase(proxy: proxy)
        #expect(proxy.text == "A")
        engine.toggleCase(proxy: proxy)
        #expect(proxy.text == "a")
    }

    @Test func shiftTabRemovesOneHardTab() {
        let proxy = MockTextProxy("x\t\t")
        engine.shiftTab(proxy: proxy)
        #expect(proxy.text == "x\t")
    }

    @Test func shiftTabRemovesUpToFourSpaces() {
        let proxy = MockTextProxy("x      ")
        engine.shiftTab(proxy: proxy)
        #expect(proxy.text == "x  ")
    }
}
