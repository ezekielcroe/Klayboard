// MacroEngine.swift
// Local text expansion engine.
// Monitors a local buffer for trigger strings and replaces them with expansions.
// Zero network access — everything runs in-process.

import UIKit

final class MacroEngine {

    // ── Storage ──────────────────────────────
    /// Named built-in macros (e.g. "md_bold"), run by utility keys.
    private var expansions: [String: String] = [:]

    /// Cursor offset map for macros that need cursor repositioning.
    private let cursorOffsets: [String: Int] = BuiltInMacros.cursorOffsets

    /// Trigger-based macros (e.g., "@@" → "user@example.com"), longest
    /// trigger first. Checked against the local trailing text buffer after
    /// every keystroke; when several triggers end the buffer ("ab" and
    /// "cab"), the longest one wins.
    private var triggerMacros: [(trigger: String, expansion: String)] = []

    // ── Local tracking buffer ────────────────
    private var recentTypingBuffer: String = ""
    /// Long enough to hold the longest trigger; at least 15 characters.
    private var maxBufferLength: Int = 15

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Loading
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func loadMacros(builtIn: [String: String], user: [MacroDefinition]) {
        // Start with built-in macros (keyed by macro name, e.g. "md_bold")
        expansions = builtIn

        // User-defined trigger macros. A later macro with the same trigger
        // replaces an earlier one.
        var byTrigger: [String: String] = [:]
        for macro in user where macro.isEnabled && !macro.trigger.isEmpty {
            byTrigger[macro.trigger] = macro.expansion
        }
        triggerMacros = byTrigger
            .map { (trigger: $0.key, expansion: $0.value) }
            .sorted { $0.trigger.count != $1.trigger.count
                ? $0.trigger.count > $1.trigger.count
                : $0.trigger < $1.trigger }
        maxBufferLength = max(15, triggerMacros.first?.trigger.count ?? 0)
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
        
        // Wipe the buffer because text was manipulated
        resetBuffer()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Local Buffer Management
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Feed a newly typed character into the local buffer
    func feedKeystroke(_ text: String) {
        recentTypingBuffer.append(text)
        if recentTypingBuffer.count > maxBufferLength {
            recentTypingBuffer.removeFirst(recentTypingBuffer.count - maxBufferLength)
        }
    }

    /// Remove the last character if the user hits backspace
    func handleBackspace() {
        if !recentTypingBuffer.isEmpty {
            recentTypingBuffer.removeLast()
        }
    }

    /// Clear the buffer (call this when the cursor is manually moved)
    func resetBuffer() {
        recentTypingBuffer = ""
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Trigger Detection (Optimized)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Checks the local buffer for a trigger. NO synchronous proxy reads!
    /// Returns true if a macro fired (the text before the cursor changed).
    @discardableResult
    func checkTriggerLocally(proxy: UITextDocumentProxy) -> Bool {
        guard !triggerMacros.isEmpty, !recentTypingBuffer.isEmpty else { return false }

        for (trigger, expansion) in triggerMacros {
            if recentTypingBuffer.hasSuffix(trigger) {
                
                // MATCH FOUND! Now we are allowed to talk to the proxy.
                for _ in 0..<trigger.count {
                    proxy.deleteBackward()
                }
                
                // Insert the expansion
                proxy.insertText(expansion)
                
                // Wipe the buffer so we don't double-fire
                resetBuffer()
                return true // Only fire one macro per keystroke
            }
        }
        return false
    }
}
