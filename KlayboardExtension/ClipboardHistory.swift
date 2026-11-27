// ClipboardHistory.swift
// Local clipboard history manager for Klay keyboard.
//
// Monitors UIPasteboard.general.changeCount and stores up to 15
// unique recent clipboard items. Persists to App Group UserDefaults
// so history survives extension termination.
//
// PRIVACY: Zero network access. All data stays on-device in the
// shared App Group container. Items are plain strings only.

import UIKit

final class ClipboardHistory {

    // ── Configuration ────────────────────────
    static let maxItems = 15

    /// Largest item stored, in UTF-8 bytes (~16k characters of English).
    /// Bigger items are skipped, not truncated: pasting a silently
    /// shortened item back from history would lose text. Worst case the
    /// whole history is ~240KB, keeping launch memory small (history is
    /// decoded every time the extension starts).
    static let maxItemBytes = 16 * 1024

    enum InsertResult {
        case added
        case empty
        case tooLarge
    }
    private static let storageKey = AppConstants.clipboardHistoryKey

    // ── State ────────────────────────────────
    private var items: [String] = []
    private var lastChangeCount: Int = 0

    // ── Storage ──────────────────────────────
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupID)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Lifecycle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    init() {
        loadFromStorage()
        lastChangeCount = UIPasteboard.general.changeCount
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Public API
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Returns the current clipboard history, most recent first.
    var recentItems: [String] { items }

    /// Check if the system clipboard has changed since last poll.
    /// If so, capture the new content and prepend it to history.
    /// Call this from viewWillAppear, textDidChange, or before showing the panel.
    func pollClipboard() {
        let currentCount = UIPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let newText = UIPasteboard.general.string else { return }
        insert(newText)
    }

    /// Adds text the keyboard itself just copied. Avoids a pasteboard
    /// round-trip, and marks the current changeCount as seen so the next
    /// poll doesn't re-read it.
    @discardableResult
    func add(_ text: String) -> InsertResult {
        markCurrentClipboardSeen()
        return insert(text)
    }

    /// Call after the keyboard writes to the pasteboard WITHOUT wanting the
    /// text in history (plain tap-to-copy). Otherwise the next poll would
    /// see the changed changeCount and add it anyway.
    func markCurrentClipboardSeen() {
        lastChangeCount = UIPasteboard.general.changeCount
    }

    @discardableResult
    private func insert(_ newText: String) -> InsertResult {
        // utf8.count is O(1) for native Swift strings; check size before
        // doing any other work on a potentially huge string.
        guard newText.utf8.count <= Self.maxItemBytes else { return .tooLarge }

        // Trim whitespace for comparison but store the original
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        // Deduplicate: if this text is already in history, move it to the top
        items.removeAll { $0 == newText }

        // Prepend
        items.insert(newText, at: 0)

        // Enforce limit
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }

        saveToStorage()
        return .added
    }

    /// Removes all history items.
    func clearAll() {
        items.removeAll()
        saveToStorage()
    }

    /// Removes an item by value. Items are de-duplicated on insert, so the
    /// text identifies exactly one entry. Safer than an index when the
    /// caller's list may be out of date with ours.
    func remove(_ text: String) {
        guard let index = items.firstIndex(of: text) else { return }
        items.remove(at: index)
        saveToStorage()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Persistence
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadFromStorage() {
        guard let data = defaults?.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([String].self, from: data) else {
            items = []
            return
        }
        // Drop oversized items saved before the size cap existed, and
        // rewrite storage so they stop being decoded at every launch.
        let kept = stored.filter { $0.utf8.count <= Self.maxItemBytes }
        items = Array(kept.prefix(Self.maxItems))
        if items.count != stored.count { saveToStorage() }
    }

    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }
}
