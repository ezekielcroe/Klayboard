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
    private static let storageKey = "clipboardHistory"

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

        guard let newText = UIPasteboard.general.string,
              !newText.isEmpty else { return }

        // Trim whitespace for comparison but store the original
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Deduplicate: if this text is already in history, move it to the top
        items.removeAll { $0 == newText }

        // Prepend
        items.insert(newText, at: 0)

        // Enforce limit
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }

        saveToStorage()
    }

    /// Removes all history items.
    func clearAll() {
        items.removeAll()
        saveToStorage()
    }

    /// Removes a single item at the given index.
    func removeItem(at index: Int) {
        guard index >= 0, index < items.count else { return }
        items.remove(at: index)
        saveToStorage()
    }

    /// Returns true if history is empty.
    var isEmpty: Bool { items.isEmpty }

    /// Number of items currently stored.
    var count: Int { items.count }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Persistence
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadFromStorage() {
        guard let data = defaults?.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([String].self, from: data) else {
            items = []
            return
        }
        items = Array(stored.prefix(Self.maxItems))
    }

    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }
}
