import Testing
import CoreGraphics
@testable import KlayboardCore

@Suite("Layouts and overrides")
struct LayoutTests {

    @Test func sixRowModeShowsUtilityRow() {
        let layout = BaseLayouts.layout(for: .standard, rowMode: .sixRows)
        #expect(layout.visibleRows(mode: .sixRows, utilityExpanded: false).contains { $0.tag == .utility })
    }

    @Test func fiveRowModeHidesUtilityRowUntilExpanded() {
        let layout = BaseLayouts.layout(for: .standard, rowMode: .fiveRows)
        #expect(!layout.visibleRows(mode: .fiveRows, utilityExpanded: false).contains { $0.tag == .utility })
        #expect(layout.visibleRows(mode: .fiveRows, utilityExpanded: true).contains { $0.tag == .utility })
    }

    @Test func fiveRowModeAddsOneToggleKey() {
        for id in LayoutID.allCases {
            let layout = BaseLayouts.layout(for: id, rowMode: .fiveRows)
            let toggles = layout.rows.flatMap(\.keys).filter { $0.id == "utilToggle" }
            #expect(toggles.count == 1, "layout \(id)")
        }
    }

    @Test(arguments: LayoutID.allCases)
    func fiveRowModeNeverWidensSpacebar(id: LayoutID) {
        func spaceWidth(_ mode: RowMode) -> CGFloat? {
            BaseLayouts.layout(for: id, rowMode: mode).rows.flatMap(\.keys).first { $0.id == "space" }?.widthMultiplier
        }
        guard let six = spaceWidth(.sixRows), let five = spaceWidth(.fiveRows) else { return }
        #expect(five <= six)
    }

    @Test func totalHeightAddsRowsAndSpacing() {
        let layout = BaseLayouts.layout(for: .standard, rowMode: .sixRows)
        let rows = layout.visibleRows(mode: .sixRows, utilityExpanded: false)
        let expected = rows.reduce(0) { $0 + $1.baseHeight } + 6 * CGFloat(rows.count - 1)
        #expect(layout.totalHeight(mode: .sixRows, utilityExpanded: false, scale: 1) == expected)
    }

    @Test func removingKeyDropsItEverywhere() {
        let layout = BaseLayouts.layout(for: .standard, rowMode: .sixRows).removingKey(withID: "globe")
        #expect(!layout.rows.flatMap(\.keys).contains { $0.id == "globe" })
    }

    @Test func overrideAppliesOnlyToItsLayout() {
        let override = UserOverride(targetKeyID: "q", newLabel: "!", newAction: .character("!"), appliesToLayouts: [.coding])
        let standard = BaseLayouts.layout(for: .standard, rowMode: .sixRows).applying(overrides: [override])
        let coding = BaseLayouts.layout(for: .coding, rowMode: .sixRows).applying(overrides: [override])
        #expect(standard.rows.flatMap(\.keys).first { $0.id == "q" }?.action == .character("q"))
        #expect(coding.rows.flatMap(\.keys).first { $0.id == "q" }?.action == .character("!"))
    }

    @Test func overrideWithoutAltKeepsBaseAlt() {
        let base = BaseLayouts.layout(for: .standard, rowMode: .sixRows)
        let baseAlt = base.rows.flatMap(\.keys).first { $0.id == "q" }?.altAction
        let override = UserOverride(targetKeyID: "q", newAction: .character("!"))
        let patched = base.applying(overrides: [override]).rows.flatMap(\.keys).first { $0.id == "q" }
        #expect(patched?.altAction == baseAlt)
    }

    @Test func altSchemesDifferOnSomeKey() {
        let familiar = BaseLayouts.layout(for: .standard, rowMode: .sixRows, altScheme: .familiar)
        let grouped = BaseLayouts.layout(for: .standard, rowMode: .sixRows, altScheme: .grouped)
        let a = familiar.rows.flatMap(\.keys).map(\.altAction)
        let b = grouped.rows.flatMap(\.keys).map(\.altAction)
        #expect(a != b)
    }
}

@Suite("Wide-screen split")
struct SplitLayoutTests {
    private func row(_ id: LayoutID = .standard, tag: RowTag, index: Int = 0) -> LayoutRow {
        BaseLayouts.layout(for: id, rowMode: .sixRows).rows.filter { $0.tag == tag }[index]
    }

    @Test func splitsOnlyWhenWideAndEnabled() {
        #expect(!SplitLayout.shouldSplit(usableWidth: 466, enabled: true))
        #expect(SplitLayout.shouldSplit(usableWidth: 799, enabled: true))
        #expect(!SplitLayout.shouldSplit(usableWidth: 799, enabled: false))
    }

    @Test func keyAreaIsCapped() {
        #expect(SplitLayout.keyAreaWidth(usableWidth: 800) == 800 * SplitLayout.keyAreaFraction)
        #expect(SplitLayout.keyAreaWidth(usableWidth: 5000) == SplitLayout.maxKeyAreaWidth)
    }

    @Test func topLetterRowSplitsFiveAndFive() {
        let top = row(tag: .alpha, index: 0)
        let split = SplitLayout.split(top)
        #expect(split.keys.map(\.id) == top.keys.map(\.id))
        #expect(split.keys[split.rightStart].id == "y")
    }

    @Test func homeRowSplitsAfterG() {
        let split = SplitLayout.split(row(tag: .alpha, index: 1))
        #expect(split.keys[split.rightStart - 1].id == "g")
        #expect(split.keys[split.rightStart].id == "h")
    }

    @Test func spacebarBecomesTwoEqualHalves() {
        let bottom = row(tag: .bottom)
        let space = bottom.keys.first { $0.id == "space" }!
        let split = SplitLayout.split(bottom)
        let left = split.keys[split.rightStart - 1]
        let right = split.keys[split.rightStart]
        #expect(left.id == "space.left" && right.id == "space.right")
        #expect(left.widthMultiplier == right.widthMultiplier)
        #expect(left.widthMultiplier + right.widthMultiplier == space.widthMultiplier)
        #expect(left.action == .space && right.action == .space)
        #expect(left.swipeUpAction == .dismissKeyboard && right.swipeUpAction == .dismissKeyboard)
    }

    @Test func everyLayoutKeepsAllKeys() {
        for id in LayoutID.allCases {
            for row in BaseLayouts.layout(for: id, rowMode: .fiveRows).rows {
                let split = SplitLayout.split(row)
                let ids = Set(split.keys.map { $0.id.replacingOccurrences(of: ".left", with: "").replacingOccurrences(of: ".right", with: "") })
                #expect(ids == Set(row.keys.map(\.id)))
                #expect((0...split.keys.count).contains(split.rightStart))
            }
        }
    }
}
