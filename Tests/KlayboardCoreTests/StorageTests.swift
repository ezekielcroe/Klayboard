import Testing
import Foundation
@testable import KlayboardCore

@Suite("Saved configuration", .serialized)
struct ConfigurationTests {
    private var defaults: UserDefaults { UserDefaults(suiteName: AppConstants.appGroupID)! }

    @Test func roundTripsThroughAppGroup() {
        var config = UserConfiguration.default
        config.activeLayoutID = .coding
        config.rowMode = .fiveRows
        config.splitsOnWideScreens = false
        config.splitGap = 0.25
        config.macros = [MacroDefinition(trigger: "@@", expansion: "x")]
        config.save()

        let loaded = UserConfiguration.load()
        #expect(loaded.activeLayoutID == .coding)
        #expect(loaded.rowMode == .fiveRows)
        #expect(loaded.splitsOnWideScreens == false)
        #expect(loaded.splitGap == 0.25)
        #expect(loaded.macros.map(\.trigger) == ["@@"])
        defaults.removeObject(forKey: AppConstants.userConfigKey)
    }

    /// Configurations saved by versions before the split setting existed
    /// must still load (and default to splitting).
    @Test func loadsConfigurationWithoutSplitSetting() throws {
        var config = UserConfiguration.default
        config.activeLayoutID = .markdown
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        json.removeValue(forKey: "wideScreenSplit")
        json.removeValue(forKey: "splitGapFraction")
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: AppConstants.userConfigKey)

        let loaded = UserConfiguration.load()
        #expect(loaded.activeLayoutID == .markdown)
        #expect(loaded.splitsOnWideScreens)
        #expect(loaded.splitGap == UserConfiguration.defaultSplitGap)
        defaults.removeObject(forKey: AppConstants.userConfigKey)
    }

    @Test func unreadableConfigurationFallsBackToDefault() {
        defaults.set(Data("not json".utf8), forKey: AppConstants.userConfigKey)
        #expect(UserConfiguration.load().activeLayoutID == UserConfiguration.default.activeLayoutID)
        defaults.removeObject(forKey: AppConstants.userConfigKey)
    }

    @Test func splitGapIsClamped() {
        var config = UserConfiguration.default
        config.splitGap = 5
        #expect(config.splitGap == UserConfiguration.splitGapRange.upperBound)
        config.splitGap = -1
        #expect(config.splitGap == UserConfiguration.splitGapRange.lowerBound)
    }

    @Test func heightScaleIsClamped() {
        #expect(HeightConfiguration(scaleFactor: 0.1).clamped == 0.75)
        #expect(HeightConfiguration(scaleFactor: 9).clamped == 1.4)
    }
}

@Suite("Clipboard history", .serialized)
struct ClipboardHistoryTests {
    private static let storageKey = AppConstants.clipboardHistoryKey
    private var defaults: UserDefaults { UserDefaults(suiteName: AppConstants.appGroupID)! }

    private func fresh() -> ClipboardHistory {
        defaults.removeObject(forKey: Self.storageKey)
        return ClipboardHistory()
    }

    @Test func newestFirstAndDeduplicated() {
        let history = fresh()
        history.add("one")
        history.add("two")
        history.add("one")
        #expect(history.recentItems == ["one", "two"])
    }

    @Test func keepsAtMostFifteen() {
        let history = fresh()
        for i in 0..<20 { history.add("item \(i)") }
        #expect(history.recentItems.count == ClipboardHistory.maxItems)
        #expect(history.recentItems.first == "item 19")
    }

    @Test func rejectsEmptyAndOversizedText() {
        let history = fresh()
        #expect(history.add("   \n") == .empty)
        #expect(history.add(String(repeating: "x", count: ClipboardHistory.maxItemBytes + 1)) == .tooLarge)
        #expect(history.recentItems.isEmpty)
    }

    @Test func survivesRelaunch() {
        let history = fresh()
        history.add("kept")
        #expect(ClipboardHistory().recentItems == ["kept"])
    }

    @Test func removeDeletesOneItem() {
        let history = fresh()
        history.add("a")
        history.add("b")
        history.remove("a")
        #expect(history.recentItems == ["b"])
    }

    /// "Clear Clipboard History" in the app removes the stored list. A
    /// keyboard that is already running must not write the old items back.
    @Test func clearingFromTheAppSticks() {
        let keyboard = fresh()
        keyboard.add("secret")
        defaults.removeObject(forKey: Self.storageKey)   // what the app does
        keyboard.add("new")
        #expect(ClipboardHistory().recentItems == ["new"])
    }
}

@Suite("Accents and context")
struct SmallLogicTests {
    @Test func everyVariantSetStartsWithItsBaseLetter() {
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            if let set = AccentVariants.variants(for: String(letter)) {
                #expect(set.first == String(letter))
            }
        }
    }

    @Test func uppercaseKeyFindsSameVariants() {
        #expect(AccentVariants.variants(for: "E") == AccentVariants.variants(for: "e"))
        #expect(AccentVariants.variants(for: "ab") == nil)
    }

    @Test func shiftedDisplayHandlesSpecialCases() {
        #expect(AccentVariants.shiftedDisplay("é") == "É")
        #expect(AccentVariants.shiftedDisplay("ß") == "ẞ")
        #expect(AccentVariants.shiftedDisplay("µ") == "µ")
        #expect(AccentVariants.shiftedDisplay("∫") == "∫")
    }

    @Test func bigramContextClassification() {
        #expect(BigramContext(previous: nil) == .wordStart)
        #expect(BigramContext(previous: " ") == .wordStart)
        #expect(BigramContext(previous: "\n") == .wordStart)
        #expect(BigramContext(previous: "T") == .letter("t"))
        #expect(BigramContext(previous: "3") == BigramContext.none)
        #expect(BigramContext(previous: "é") == BigramContext.none)
    }
}
