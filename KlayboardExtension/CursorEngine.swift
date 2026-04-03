// CursorEngine.swift
// Word-level cursor movement, word deletion, line deletion, and case toggling.
// All operations go through UITextDocumentProxy — the only text access iOS allows.

import UIKit

final class CursorEngine {

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Word Boundaries
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Characters that constitute word boundaries.
    private let wordBreaks: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(.punctuationCharacters)
        set.formUnion(CharacterSet(charactersIn: "(){}[]<>\"'`"))
        return set
    }()

    /// Returns the number of characters from the cursor to the previous word start.
    /// Returns 0 if there's no text before the cursor.
    private func distanceToPreviousWordBoundary(proxy: UITextDocumentProxy) -> Int {
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else { return 0 }

        let chars = Array(before)
        var i = chars.count - 1

        // Skip trailing whitespace/punctuation
        while i >= 0, isWordBreak(chars[i]) { i -= 1 }
        // Skip the word body
        while i >= 0, !isWordBreak(chars[i]) { i -= 1 }

        return chars.count - (i + 1)
    }

    /// Returns the number of characters from the cursor to the next word end.
    private func distanceToNextWordBoundary(proxy: UITextDocumentProxy) -> Int {
        guard let after = proxy.documentContextAfterInput, !after.isEmpty else { return 0 }

        let chars = Array(after)
        var i = 0

        // Skip leading whitespace/punctuation
        while i < chars.count, isWordBreak(chars[i]) { i += 1 }
        // Skip the word body
        while i < chars.count, !isWordBreak(chars[i]) { i += 1 }

        return i
    }

    private func isWordBreak(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return true }
        return wordBreaks.contains(scalar)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Cursor Movement
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func moveBackwardByWord(proxy: UITextDocumentProxy) {
        let dist = distanceToPreviousWordBoundary(proxy: proxy)
        guard dist > 0 else { return }
        proxy.adjustTextPosition(byCharacterOffset: -dist)
    }

    func moveForwardByWord(proxy: UITextDocumentProxy) {
        let dist = distanceToNextWordBoundary(proxy: proxy)
        guard dist > 0 else { return }
        proxy.adjustTextPosition(byCharacterOffset: dist)
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Indentation
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Reads backwards from the cursor. Removes 1 tab character, or up to 4 spaces.
    func shiftTab(proxy: UITextDocumentProxy) {
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else { return }
        
        // 1. If it's a hard tab, delete one character
        if before.hasSuffix("\t") {
            proxy.deleteBackward()
            return
        }
        
        // 2. If it's soft spaces, delete up to 4, stopping if we hit a non-space
        var spacesToDelete = 0
        for char in before.reversed() {
            if char == " " && spacesToDelete < 4 {
                spacesToDelete += 1
            } else {
                break
            }
        }
        
        for _ in 0..<spacesToDelete {
            proxy.deleteBackward()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Deletion
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Deletes the previous word (equivalent to Opt+Backspace on macOS).
    func deleteBackwardWord(proxy: UITextDocumentProxy) {
        let dist = distanceToPreviousWordBoundary(proxy: proxy)
        guard dist > 0 else { return }
        for _ in 0..<dist {
            proxy.deleteBackward()
        }
    }

    /// Deletes everything from cursor to the beginning of the current line.
    func deleteToLineStart(proxy: UITextDocumentProxy) {
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else { return }

        // Find the last newline — delete up to that point (or all if no newline)
        if let nlRange = before.range(of: "\n", options: .backwards) {
            let afterNewline = before[nlRange.upperBound...]
            let count = afterNewline.count
            for _ in 0..<count {
                proxy.deleteBackward()
            }
        } else {
            // No newline found — delete everything before cursor
            // documentContextBeforeInput may be truncated; delete what we have
            for _ in 0..<before.count {
                proxy.deleteBackward()
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Case Toggle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Reads the previous word, cycles its case (lower → Upper → UPPER → lower),
    /// then replaces it in-place.
    func toggleCase(proxy: UITextDocumentProxy) {
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else { return }

        // Extract the last word
        let chars = Array(before)
        var end = chars.count - 1

        // Skip trailing whitespace
        while end >= 0, isWordBreak(chars[end]) { end -= 1 }
        guard end >= 0 else { return }

        var start = end
        while start > 0, !isWordBreak(chars[start - 1]) { start -= 1 }

        let wordChars = chars[start...end]
        let word = String(wordChars)
        guard !word.isEmpty else { return }

        // Determine next case
        let toggled: String
        if word == word.lowercased() {
            // lower → Title Case
            toggled = word.prefix(1).uppercased() + word.dropFirst().lowercased()
        } else if word == word.prefix(1).uppercased() + word.dropFirst().lowercased() {
            // Title → UPPER
            toggled = word.uppercased()
        } else {
            // UPPER or mixed → lower
            toggled = word.lowercased()
        }

        // Capture any trailing punctuation/whitespace between word end and cursor
        let trailing = (end + 1 < chars.count) ? String(chars[(end + 1)...]) : ""

        // Delete from word start to cursor (word + trailing)
        let deleteCount = chars.count - start
        for _ in 0..<deleteCount {
            proxy.deleteBackward()
        }
        // Re-insert toggled word + original trailing characters
        proxy.insertText(toggled + trailing)
    }
}
