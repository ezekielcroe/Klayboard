// MacroEngine.swift
// Local text expansion engine.
// Monitors a local buffer for trigger strings and replaces them with expansions.
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
    /// These are checked against the local trailing text buffer after every keystroke.
    private var triggerMacros: [String: String] = [:]
    private var maxTriggerLength: Int = 0

    // ── Local tracking buffer ────────────────
    private var recentTypingBuffer: String = ""
    private let maxBufferLength: Int = 15 // Keeps memory footprint virtually zero

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
    func checkTriggerLocally(proxy: UITextDocumentProxy) {
        guard maxTriggerLength > 0 else { return }
        guard !recentTypingBuffer.isEmpty else { return }

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
                return // Only fire one macro per keystroke
            }
        }
    }
}
