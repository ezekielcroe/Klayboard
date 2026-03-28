// MacroEngine.swift
// Local text expansion engine.
// Monitors documentContextBeforeInput for trigger strings and replaces them with expansions.
// Zero network access — everything runs in-process.

import UIKit

final class MacroEngine {

    // ── Storage ──────────────────────────────
    /// Combined dictionary: built-in macros + user-defined macros.
    /// User macros override built-in macros with the same key.
    private var expansions: [String: String] = [:]

    /// Cursor offset map for macros that need cursor repositioning.
    private var cursorOffsets: [String: Int] = BuiltInMacros.cursorOffsets

    /// Trigger-based macros (e.g., "@@" → "user@example.com").
    /// These are checked against the trailing text after every keystroke.
    private var triggerMacros: [String: String] = [:]
    private var maxTriggerLength: Int = 0

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Loading
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func loadMacros(builtIn: [String: String], user: [MacroDefinition]) {
        // Start with built-in macros (keyed by macro name, e.g. "md_bold")
        expansions = builtIn

        // User-defined trigger macros
        triggerMacros.removeAll()
        for macro in user where macro.isEnabled {
            triggerMacros[macro.trigger] = macro.expansion
        }
        maxTriggerLength = triggerMacros.keys.map(\.count).max() ?? 0
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Named Macro Execution
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Execute a macro by its name (e.g., "md_bold").
    /// Called directly from a utility key's .insertMacro action.
    func executeMacro(named key: String, proxy: UITextDocumentProxy) {
        guard let text = expansions[key] else { return }
        proxy.insertText(text)

        // Reposition cursor if needed (e.g., between ** **)
        if let offset = cursorOffsets[key], offset > 0 {
            proxy.adjustTextPosition(byCharacterOffset: -offset)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Trigger Detection
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Called after every text change to check if the user just typed a trigger.
    /// This is O(triggers × maxTriggerLength) but both are small (~dozens).
    func checkTrigger(proxy: UITextDocumentProxy) {
        guard maxTriggerLength > 0 else { return }
        guard let before = proxy.documentContextBeforeInput else { return }
        guard !before.isEmpty else { return }

        // Only inspect the tail of the string (up to longest trigger length)
        let tail = String(before.suffix(maxTriggerLength + 2)) // +2 for safety

        for (trigger, expansion) in triggerMacros {
            if tail.hasSuffix(trigger) {
                // Delete the trigger characters
                for _ in 0..<trigger.count {
                    proxy.deleteBackward()
                }
                // Insert the expansion
                proxy.insertText(expansion)
                return // Only fire one macro per keystroke
            }
        }
    }
}
