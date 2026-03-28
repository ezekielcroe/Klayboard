// KeyboardDataStructures.swift
// Power-User iOS Keyboard — Core Data Layer
//
// All layout data is hardcoded as Swift structs (no JSON parsing at init).
// UserOverride and MacroDefinition are serialized via Codable to App Group UserDefaults.

import Foundation
import CoreGraphics

// MARK: - App Group Constants

enum AppConstants {
    static let appGroupID      = "group.com.GeekyZeke.Klayboard"
    static let userConfigKey   = "userConfiguration"
    static let feedbackChanged = "PowerKeyboardConfigChanged"
}

// ─────────────────────────────────────────────
// MARK: - Key Action Model
// ─────────────────────────────────────────────

/// Every possible action a key can perform.
/// Kept as a flat enum so the touch handler is a single switch — no polymorphism overhead.
enum KeyAction: Codable, Hashable {
    // Basic input
    case character(String)
    case space
    case returnKey
    case backspace

    // Modifiers / state
    case shift
    case capsLock
    case switchLayout(LayoutID)

    // Cursor navigation
    case moveCursorForwardWord
    case moveCursorBackwardWord
    case moveCursorForward
    case moveCursorBackward

    // Deletion
    case deleteWord
    case deleteToLineStart

    // Text manipulation
    case toggleCase
    case insertMacro(String)

    // Clipboard (requires Full Access)
    case copy
    case paste

    // Row visibility
    case toggleUtilityRow

    // Utility
    case dismissKeyboard
    case nextKeyboard
    case none
}

// ─────────────────────────────────────────────
// MARK: - Key Definition
// ─────────────────────────────────────────────

/// A single key on the keyboard.
/// `widthMultiplier` is relative to a 1.0-unit standard character key.
struct KeyDefinition: Codable, Hashable {
    let id: String
    let label: String
    let action: KeyAction
    let altAction: KeyAction?       // long-press / swipe-down secondary
    let swipeUpAction: KeyAction? // swipe-up tertiary
    let widthMultiplier: CGFloat
    let style: KeyStyle

    init(
        id: String,
        label: String,
        action: KeyAction,
        altAction: KeyAction? = nil,
        swipeUpAction: KeyAction? = nil,
        widthMultiplier: CGFloat = 1.0,
        style: KeyStyle = .standard
    ) {
        self.id = id
        self.label = label
        self.action = action
        self.altAction = altAction
        self.swipeUpAction = swipeUpAction
        self.widthMultiplier = widthMultiplier
        self.style = style
    }
}

enum KeyStyle: String, Codable, Hashable {
    case standard
    case modifier
    case utility
    case spacebar
}

// ─────────────────────────────────────────────
// MARK: - Layout Row
// ─────────────────────────────────────────────

struct LayoutRow: Codable, Hashable {
    let keys: [KeyDefinition]
    let baseHeight: CGFloat         // default height in points before user scaling
    let tag: RowTag                 // semantic tag for conditional visibility

    init(keys: [KeyDefinition], baseHeight: CGFloat = 44.0, tag: RowTag = .alpha) {
        self.keys = keys
        self.baseHeight = baseHeight
        self.tag = tag
    }
}

/// Semantic row tags control which rows are visible in 5-row vs 6-row mode.
enum RowTag: String, Codable, Hashable {
    case utility        // Row 1 — hideable in 5-row mode
    case number         // Row 2 — always visible
    case alpha          // Rows 3-5 — always visible
    case bottom         // Spacebar row — always visible
}

// ─────────────────────────────────────────────
// MARK: - Layout Identifier
// ─────────────────────────────────────────────

enum LayoutID: String, Codable, Hashable, CaseIterable {
    case standard
    case coding
    case markdown
    case symbols
}

// ─────────────────────────────────────────────
// MARK: - Row Mode
// ─────────────────────────────────────────────

/// User preference for keyboard row count.
enum RowMode: String, Codable, Hashable, CaseIterable {
    case fiveRows           // utility row hidden; toggle button in bottom row
    case sixRows            // all rows visible

    var displayName: String {
        switch self {
        case .fiveRows: return "5 Rows (Compact)"
        case .sixRows:  return "6 Rows (Full)"
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Full Keyboard Layout
// ─────────────────────────────────────────────

struct KeyboardLayout: Codable, Hashable {
    let id: LayoutID
    let displayName: String
    let rows: [LayoutRow]

    /// Returns visible rows based on row mode and utility-row toggle state.
    func visibleRows(mode: RowMode, utilityExpanded: Bool) -> [LayoutRow] {
        switch mode {
        case .sixRows:
            return rows
        case .fiveRows:
            if utilityExpanded {
                return rows  // temporarily show all when toggled
            }
            return rows.filter { $0.tag != .utility }
        }
    }

    /// Total height for the given configuration.
    func totalHeight(mode: RowMode, utilityExpanded: Bool, scale: CGFloat, spacing: CGFloat = 6.0) -> CGFloat {
        let visible = visibleRows(mode: mode, utilityExpanded: utilityExpanded)
        let rowHeights = visible.reduce(0) { $0 + ($1.baseHeight * scale) }
        return rowHeights + spacing * CGFloat(max(visible.count - 1, 0))
    }

    /// Returns a copy with the specified key ID removed from all rows.
    /// Used to strip the globe key when `needsInputModeSwitchKey` is false.
    func removingKey(withID keyID: String) -> KeyboardLayout {
        let filteredRows = rows.map { row in
            let filtered = row.keys.filter { $0.id != keyID }
            return LayoutRow(keys: filtered, baseHeight: row.baseHeight, tag: row.tag)
        }
        return KeyboardLayout(id: id, displayName: displayName, rows: filteredRows)
    }
}

// ─────────────────────────────────────────────
// MARK: - Macro Definition
// ─────────────────────────────────────────────

struct MacroDefinition: Codable, Hashable, Identifiable {
    let id: UUID
    let trigger: String
    let expansion: String
    let isEnabled: Bool

    init(trigger: String, expansion: String, isEnabled: Bool = true) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
        self.isEnabled = isEnabled
    }
}

// ─────────────────────────────────────────────
// MARK: - User Override
// ─────────────────────────────────────────────

struct UserOverride: Codable, Hashable, Identifiable {
    let id: UUID
    let targetKeyID: String
    let newLabel: String?
    let newAction: KeyAction
    let newAltAction: KeyAction?
    let newswipeUpAction: KeyAction?
    let appliesToLayouts: Set<LayoutID>

    init(
        targetKeyID: String,
        newLabel: String? = nil,
        newAction: KeyAction,
        newAltAction: KeyAction? = nil,
        newswipeUpAction: KeyAction? = nil,
        appliesToLayouts: Set<LayoutID> = []
    ) {
        self.id = UUID()
        self.targetKeyID = targetKeyID
        self.newLabel = newLabel
        self.newAction = newAction
        self.newAltAction = newAltAction
        self.newswipeUpAction = newswipeUpAction
        self.appliesToLayouts = appliesToLayouts
    }
}

// ─────────────────────────────────────────────
// MARK: - Height Configuration
// ─────────────────────────────────────────────

struct HeightConfiguration: Codable, Hashable {
    /// Scale factor applied to every row's baseHeight. Range: 0.75 … 1.4
    var scaleFactor: CGFloat

    static let `default` = HeightConfiguration(scaleFactor: 1.0)
    static let compact   = HeightConfiguration(scaleFactor: 0.80)
    static let tall      = HeightConfiguration(scaleFactor: 1.25)

    var clamped: CGFloat { min(max(scaleFactor, 0.75), 1.4) }
}

// ─────────────────────────────────────────────
// MARK: - Aggregate User Configuration
// ─────────────────────────────────────────────

struct UserConfiguration: Codable {
    var activeLayoutID: LayoutID
    var rowMode: RowMode
    var macros: [MacroDefinition]
    var overrides: [UserOverride]
    var height: HeightConfiguration
    var hapticFeedbackEnabled: Bool
    var soundFeedbackEnabled: Bool
    var showKeyPopups: Bool
    var longPressDuration: Double

    static let `default` = UserConfiguration(
        activeLayoutID: .standard,
        rowMode: .sixRows,
        macros: [],
        overrides: [],
        height: .default,
        hapticFeedbackEnabled: true,
        soundFeedbackEnabled: false,
        showKeyPopups: true,
        longPressDuration: 0.2
    )
}

// ─────────────────────────────────────────────
// MARK: - App Group Persistence
// ─────────────────────────────────────────────

extension UserConfiguration {
    func save() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID) else { return }
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: AppConstants.userConfigKey)
            defaults.synchronize()
        }
    }

    static func load() -> UserConfiguration {
        guard
            let defaults = UserDefaults(suiteName: AppConstants.appGroupID),
            let data = defaults.data(forKey: AppConstants.userConfigKey),
            let config = try? JSONDecoder().decode(UserConfiguration.self, from: data)
        else {
            return .default
        }
        return config
    }
}

// ─────────────────────────────────────────────
// MARK: - Override Application
// ─────────────────────────────────────────────

extension KeyboardLayout {
    func applying(overrides: [UserOverride]) -> KeyboardLayout {
        let applicable = overrides.filter {
            $0.appliesToLayouts.isEmpty || $0.appliesToLayouts.contains(self.id)
        }
        guard !applicable.isEmpty else { return self }

        let map = Dictionary(applicable.map { ($0.targetKeyID, $0) },
                             uniquingKeysWith: { _, latest in latest })

        let patchedRows = rows.map { row in
            LayoutRow(
                keys: row.keys.map { key in
                    guard let ov = map[key.id] else { return key }
                    return KeyDefinition(
                        id: key.id,
                        label: ov.newLabel ?? key.label,
                        action: ov.newAction,
                        altAction: ov.newAltAction ?? key.altAction,
                        swipeUpAction: key.swipeUpAction,
                        widthMultiplier: key.widthMultiplier,
                        style: key.style
                    )
                },
                baseHeight: row.baseHeight,
                tag: row.tag
            )
        }
        return KeyboardLayout(id: id, displayName: displayName, rows: patchedRows)
    }
}
