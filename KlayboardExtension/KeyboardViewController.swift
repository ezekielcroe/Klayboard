// KeyboardViewController.swift
// The UIInputViewController — entry point for the keyboard extension.
//
// PERFORMANCE: Shift-state changes call updateKeyboardView() which does NOT
// rebuild key views — it only updates labels in-place. Full rebuilds only
// happen on layout switch, row-mode toggle, or config reload.

import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {

    // ── State ──────────────────────────────────
    private var config: UserConfiguration = .default
    private var currentLayout: KeyboardLayout!
    private var shiftState: ShiftState = .off
    private var utilityRowExpanded: Bool = false
    private var previousLayoutID: LayoutID?
    private var lastInsertedChar: Character?
    private var secondLastInsertedChar: Character?
    private var lastSpaceTapTime: TimeInterval = 0

    // ── Caps lock ──────────────────────────────
    /// Shift → caps lock only if the second tap lands within this window.
    /// A slower second tap means "cancel shift", not "lock".
    private static let capsLockDoubleTapWindow: CFTimeInterval = 0.35
    private var lastShiftTapTime: CFTimeInterval = 0

    // ── Bigram context ─────────────────────────
    /// The last few characters before the cursor, maintained locally from
    /// our own insertions. The document proxy's context lags our inserts
    /// during fast typing, so it is only read (re-synced) after edits we
    /// can't track character-by-character.
    private var contextBuffer: String = ""
    private var contextNeedsResync = true
    private static let contextBufferLength = 4

    // ── Engines ────────────────────────────────
    private let macroEngine = MacroEngine()
    private let cursorEngine = CursorEngine()
    private let clipboardHistory = ClipboardHistory()
    private var clipboardHistoryView: ClipboardHistoryView?
    private var haptic: UIImpactFeedbackGenerator?
    private var emojiPickerView: EmojiPickerView?

    // ── Rendering ──────────────────────────────
    private var keyboardView: KeyboardRenderView!
    private var heightConstraint: NSLayoutConstraint?
    private var containerHeightConstraint: NSLayoutConstraint?

    // ── Delete repeat ──────────────────────────
    private var deleteTimer: Timer?
    private var deleteRepeatCount: Int = 0
    private var deleteRepeatHasFired: Bool = false

    // ── Toast overlay ────────────────────────
    private var toastLabel: UILabel?

    // ── Sound ─────────────────────────────────
    private static let clickSoundID: SystemSoundID    = 1104
    private static let deleteSoundID: SystemSoundID   = 1155
    private static let modifierSoundID: SystemSoundID = 1156

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Lifecycle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    override func viewDidLoad() {
        super.viewDidLoad()
        loadConfiguration()
        buildKeyboardView()

        let defaults = UserDefaults(suiteName: AppConstants.appGroupID)
        defaults?.set(Date().timeIntervalSince1970, forKey: "keyboardExtensionActivated")
        defaults?.synchronize()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadConfiguration()
        rebuildLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboardView?.setNeedsLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateHeight()
            self.keyboardView?.frame = CGRect(origin: .zero, size: size)
            self.keyboardView?.setNeedsLayout()
            self.keyboardView?.layoutIfNeeded()
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Next appearance may be a different field.
        invalidateTextContext()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        checkContextConsistency()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        checkContextConsistency()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        haptic = nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Configuration
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadConfiguration() {
        config = UserConfiguration.load()
        macroEngine.loadMacros(builtIn: BuiltInMacros.expansions, user: config.macros)

        if config.hapticFeedbackEnabled {
            haptic = UIImpactFeedbackGenerator(style: .light)
            haptic?.prepare()
        } else {
            haptic = nil
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - View Construction
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildKeyboardView() {
        keyboardView = KeyboardRenderView()

        keyboardView.translatesAutoresizingMaskIntoConstraints = false

        keyboardView.actionHandler = { [weak self] action in
            self?.handleAction(action)
        }
        keyboardView.longPressActionHandler = { [weak self] action in
            self?.handleAction(action)
        }
        keyboardView.deleteBeganHandler = { [weak self] in
            self?.startDeleteRepeat()
        }
        keyboardView.deleteEndedHandler = { [weak self] in
            self?.stopDeleteRepeat()
        }
        
        keyboardView.cursorModeBeganHandler = { [weak self] in
            self?.playHaptic()
        }
        keyboardView.cursorModeMovedHandler = { [weak self] offset in
            self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        }
        keyboardView.cursorModeEndedHandler = { [weak self] in
            self?.resetInsertTracking()
            self?.macroEngine.resetBuffer()
        }
        keyboardView.bigramContextProvider = { [weak self] in
            self?.currentBigramContext() ?? .none
        }
        view.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        rebuildLayout()
    }

    /// Full rebuild — called when layout, row mode, or overrides change.
    private func rebuildLayout() {
        var base = BaseLayouts.layout(for: config.activeLayoutID, rowMode: config.rowMode, altScheme: config.altScheme)

        if !needsInputModeSwitchKey {
            base = base.removingKey(withID: "globe")
        }

        currentLayout = base.applying(overrides: config.overrides)
        updateKeyboardView()
        updateHeight()
    }

    /// Pushes current rows + shift state to the render view.
    /// The render view internally decides whether to rebuild or just update labels.
    private func updateKeyboardView() {
        let rows = currentLayout.visibleRows(
            mode: config.rowMode,
            utilityExpanded: utilityRowExpanded
        )

        keyboardView.longPressDuration = config.longPressDuration

        keyboardView.configure(
            rows: rows,
            scale: config.height.clamped,
            shiftState: shiftState,
            showPopups: config.showKeyPopups
        )
    }

    private func updateHeight() {
        guard currentLayout != nil else { return }
        let totalHeight = currentLayout.totalHeight(
            mode: config.rowMode,
            utilityExpanded: utilityRowExpanded,
            scale: config.height.clamped
        )

        // 1. Constrain the System's Root View
        if let constraint = heightConstraint {
            if constraint.constant != totalHeight {
                constraint.constant = totalHeight
            }
        } else {
            heightConstraint = view.heightAnchor.constraint(equalToConstant: totalHeight)
            heightConstraint?.priority = UILayoutPriority(rawValue: 999)
            heightConstraint?.isActive = true
        }

        // 2. Constrain our Custom Keyboard Container
        if let containerConstraint = containerHeightConstraint {
            if containerConstraint.constant != totalHeight {
                containerConstraint.constant = totalHeight
            }
        } else {
            containerHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: totalHeight)
            containerHeightConstraint?.isActive = true
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Feedback
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func playHaptic() {
        guard config.hapticFeedbackEnabled else { return }
        haptic?.impactOccurred()
        haptic?.prepare()
    }

    private func playSound(for action: KeyAction) {
        guard config.soundFeedbackEnabled else { return }
        switch action {
        case .backspace, .deleteWord, .deleteToLineStart:
            AudioServicesPlaySystemSound(Self.deleteSoundID)
        case .shift, .capsLock, .switchLayout, .toggleUtilityRow, .nextKeyboard, .dismissKeyboard:
            AudioServicesPlaySystemSound(Self.modifierSoundID)
        default:
            AudioServicesPlaySystemSound(Self.clickSoundID)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Action Dispatch
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func handleAction(_ action: KeyAction) {
        playHaptic()
        playSound(for: action)

        switch action {

        // ── Basic input ──────────────────────────
        case .character(let c):
            let previousShiftState = shiftState

            let output: String
            switch shiftState {
            case .off:      output = c
            case .shifted:  output = c.uppercased(); shiftState = .off
            case .capsLock: output = c.uppercased()
            }

            textDocumentProxy.insertText(output)
            trackInserted(output)
            appendContext(output)

            // 1. Feed the local macro engine
            macroEngine.feedKeystroke(output)
            if macroEngine.checkTriggerLocally(proxy: textDocumentProxy) {
                invalidateTextContext()
            }

            // 3. THE UI FIX: Only update the view if the shift state actually dropped!
            if shiftState != previousShiftState {
                updateKeyboardView()
            }

        case .space:
            let now = Date().timeIntervalSince1970
            let isDoubleTap = (now - lastSpaceTapTime) < 0.5
            lastSpaceTapTime = now

            if isDoubleTap,
               lastInsertedChar == " ",
               let prev = secondLastInsertedChar,
               !prev.isWhitespace, !prev.isPunctuation {

                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(". ")

                trackInserted(". ") // This correctly updates last=" ", secondLast="."
                if !contextBuffer.isEmpty { contextBuffer.removeLast() }
                appendContext(". ")

                // Keep local buffer perfectly in sync with the auto-period
                macroEngine.handleBackspace()
                macroEngine.feedKeystroke(". ")
                if macroEngine.checkTriggerLocally(proxy: textDocumentProxy) {
                    invalidateTextContext()
                }

                if shiftState == .off {
                    shiftState = .shifted
                    updateKeyboardView()
                }
            } else {
                textDocumentProxy.insertText(" ")
                trackInserted(" ")
                appendContext(" ")

                macroEngine.feedKeystroke(" ")
                if macroEngine.checkTriggerLocally(proxy: textDocumentProxy) {
                    invalidateTextContext()
                }
            }
            // Word finished: the user accepted it, so its touches may train
            // the calibration model.
            keyboardView.calibrationCommitPending()

        case .returnKey:
            textDocumentProxy.insertText("\n")
            trackInserted("\n")
            appendContext("\n")
            keyboardView.calibrationCommitPending()
            macroEngine.resetBuffer() // Newlines break macro context

        case .backspace:
            if !deleteRepeatHasFired {
                textDocumentProxy.deleteBackward()
                noteDeletedOneCharacter()
            }
            lastInsertedChar = nil
            secondLastInsertedChar = nil
            macroEngine.handleBackspace()

        // ── Modifiers ────────────────────────────
        case .shift:
            let now = CACurrentMediaTime()
            switch shiftState {
            case .off:
                shiftState = .shifted
            case .shifted:
                // Quick double-tap locks; a slower second tap cancels shift.
                let isDoubleTap = (now - lastShiftTapTime) < Self.capsLockDoubleTapWindow
                shiftState = isDoubleTap ? .capsLock : .off
            case .capsLock:
                shiftState = .off
            }
            lastShiftTapTime = now
            updateKeyboardView()

        case .capsLock:
            shiftState = (shiftState == .capsLock) ? .off : .capsLock
            updateKeyboardView()

        case .switchLayout(let layoutID):
            if layoutID == .symbols {
                previousLayoutID = config.activeLayoutID
            }
            let target: LayoutID
            if layoutID == .standard, let prev = previousLayoutID, prev != .symbols {
                target = prev
                previousLayoutID = nil
            } else {
                target = layoutID
            }
            config.activeLayoutID = target
            rebuildLayout()

        // ── Cursor navigation ────────────────────
        case .moveCursorForward:
            textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
            resetInsertTracking()
            macroEngine.resetBuffer()

        case .moveCursorBackward:
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
            resetInsertTracking()
            macroEngine.resetBuffer()

        case .moveCursorForwardWord:
            cursorEngine.moveForwardByWord(proxy: textDocumentProxy)
            resetInsertTracking()
            macroEngine.resetBuffer()

        case .moveCursorBackwardWord:
            cursorEngine.moveBackwardByWord(proxy: textDocumentProxy)
            resetInsertTracking()
            macroEngine.resetBuffer()

        // ── Deletion ─────────────────────────────
        case .deleteWord:
            cursorEngine.deleteBackwardWord(proxy: textDocumentProxy)
            resetInsertTracking()
            macroEngine.resetBuffer()

        case .deleteToLineStart:
            cursorEngine.deleteToLineStart(proxy: textDocumentProxy)
            resetInsertTracking()
            macroEngine.resetBuffer()

        // ── Text manipulation ────────────────────
        case .toggleCase:
            cursorEngine.toggleCase(proxy: textDocumentProxy)
            invalidateTextContext()
            macroEngine.resetBuffer()

        case .shiftTab:
            cursorEngine.shiftTab(proxy: textDocumentProxy)
            resetInsertTracking()
            macroEngine.resetBuffer()

        case .insertMacro(let macroKey):
            macroEngine.executeMacro(named: macroKey, proxy: textDocumentProxy)
            resetInsertTracking()
            macroEngine.resetBuffer()

        // ── Clipboard ────────────────────────────
        case .copy:
            // Tap: copy only. Mark the change as seen so the history panel's
            // next poll doesn't pick this copy up anyway.
            if let text = textDocumentProxy.selectedText, !text.isEmpty {
                UIPasteboard.general.string = text
                clipboardHistory.markCurrentClipboardSeen()
                if text.count >= 80 {
                    showToast("Copied — may be truncated. Use system Copy for large selections.", warning: true)
                } else {
                    showToast("Copied")
                }
            }

        case .copyAndSave:
            // Swipe down: copy AND save to Klayboard's history.
            if let text = textDocumentProxy.selectedText, !text.isEmpty {
                UIPasteboard.general.string = text
                switch clipboardHistory.add(text) {
                case .tooLarge:
                    showToast("Copied — too large to save to history.", warning: true)
                case .added, .empty:
                    if text.count >= 80 {
                        showToast("Copied & saved — may be truncated. Use system Copy for large selections.", warning: true)
                    } else {
                        showToast("Copied & saved")
                    }
                }
            }

        case .cut:
            if let text = textDocumentProxy.selectedText, !text.isEmpty {
                let mayBeTruncated = text.count >= 80
                UIPasteboard.general.string = text
                textDocumentProxy.deleteBackward()
                resetInsertTracking()
                macroEngine.resetBuffer()
                if mayBeTruncated {
                    showToast("Cut — clipboard may be truncated. Use system Cut for large selections.", warning: true)
                } else {
                    showToast("Cut")
                }
            }

        case .paste:
            if let text = UIPasteboard.general.string {
                insertLongText(text)
                resetInsertTracking()
                macroEngine.resetBuffer()
            }

        case .showClipboardHistory:
            showClipboardPanel()

        case .showEmojiPicker:
            showEmojiPanel()

        // ── Row toggle ───────────────────────────
        case .toggleUtilityRow:
            utilityRowExpanded.toggle()
            rebuildLayout()

        // ── System ───────────────────────────────
        case .dismissKeyboard:
            dismissKeyboard()

        case .nextKeyboard:
            advanceToNextInputMode()

        case .none:
            break
        }
    }

    // ── Double-space tracking ────────────────────

    private func trackInserted(_ text: String) {
        for char in text {
            secondLastInsertedChar = lastInsertedChar
            lastInsertedChar = char
        }
    }

    private func resetInsertTracking() {
        lastInsertedChar = nil
        secondLastInsertedChar = nil
        invalidateTextContext()
    }

    // ── Bigram context & calibration bookkeeping ──

    private func appendContext(_ text: String) {
        contextBuffer.append(text)
        if contextBuffer.count > Self.contextBufferLength {
            contextBuffer = String(contextBuffer.suffix(Self.contextBufferLength))
        }
    }

    /// One character before the cursor was deleted by backspace.
    private func noteDeletedOneCharacter() {
        if contextBuffer.isEmpty {
            contextNeedsResync = true
        } else {
            contextBuffer.removeLast()
            // Emptied a short buffer: we no longer know what precedes the cursor.
            if contextBuffer.isEmpty { contextNeedsResync = true }
        }
        keyboardView.calibrationCharacterDeleted()
    }

    /// The text before the cursor changed in a way we can't follow locally.
    private func invalidateTextContext() {
        contextNeedsResync = true
        keyboardView?.calibrationDiscardPending()
    }

    /// Called by the render view at touch-down.
    private func currentBigramContext() -> BigramContext {
        if contextNeedsResync {
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            contextBuffer = String(before.suffix(Self.contextBufferLength))
            contextNeedsResync = false
        }
        return BigramContext(previous: contextBuffer.last)
    }

    /// textDidChange / selectionDidChange fire for external edits and cursor
    /// taps, but also (later) for our own insertions. The proxy may still be
    /// a keystroke or two behind us, so if its context matches our buffer
    /// minus its last 0–2 characters it is our own typing and is ignored.
    private func checkContextConsistency() {
        guard !contextNeedsResync else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let consistent = (0...2).contains { k in
            let tail = String(contextBuffer.dropLast(k))
            return !tail.isEmpty && before.hasSuffix(tail)
        }
        if !consistent { invalidateTextContext() }
    }

    // ── Delete key repeat ────────────────────────

    private func startDeleteRepeat() {
        deleteRepeatCount = 0
        deleteRepeatHasFired = false

        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.deleteRepeatHasFired = true
            self.textDocumentProxy.deleteBackward()
            self.noteDeletedOneCharacter()

            self.deleteRepeatCount = 0
            self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.deleteRepeatCount += 1
                if self.deleteRepeatCount > 5 {
                    self.cursorEngine.deleteBackwardWord(proxy: self.textDocumentProxy)
                    self.invalidateTextContext()
                } else {
                    self.textDocumentProxy.deleteBackward()
                    self.noteDeletedOneCharacter()
                }
            }
        }
    }

    private func stopDeleteRepeat() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        deleteRepeatCount = 0
        deleteRepeatHasFired = false
    }

    // ── Clipboard Panel ────────────────────────

    private func showClipboardPanel() {
        guard clipboardHistoryView == nil else { return }

        clipboardHistory.pollClipboard()
        let cv = ClipboardHistoryView(items: clipboardHistory.recentItems)
        cv.delegate = self
        cv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cv)

        NSLayoutConstraint.activate([
            cv.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            cv.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            cv.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])

        clipboardHistoryView = cv
    }

    // ── Emoji Picker ────────────────────────

    private func showEmojiPanel() {
        guard emojiPickerView == nil else { return }
        let ev = EmojiPickerView(frame: .zero)
        ev.delegate = self
        ev.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ev)
        NSLayoutConstraint.activate([
            ev.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            ev.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            ev.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            ev.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
        emojiPickerView = ev
    }

    // ── Toast Overlay ─────────────────────────

    /// Shows a brief overlay message at the top of the keyboard.
    /// - Parameters:
    ///   - message: The text to display.
    ///   - warning: If true, uses a longer display duration and amber tint.
    private func showToast(_ message: String, warning: Bool = false) {
        // Remove any existing toast immediately
        toastLabel?.removeFromSuperview()

        let label = UILabel()
        label.text = message
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = warning ? .white : .label
        label.backgroundColor = warning
            ? UIColor.systemOrange.withAlphaComponent(0.92)
            : UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false

        // Padding via content insets isn't available on UILabel,
        // so wrap in a container or just add spacing to the text.
        // Keeping it simple: use a fixed-height constraint.
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])

        toastLabel = label

        // Fade in
        label.alpha = 0
        UIView.animate(withDuration: 0.15) { label.alpha = 1 }

        // Auto-dismiss
        let duration: TimeInterval = warning ? 3.0 : 1.2
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard self?.toastLabel === label else { return }
            UIView.animate(withDuration: 0.25, animations: { label.alpha = 0 }) { _ in
                label.removeFromSuperview()
                if self?.toastLabel === label { self?.toastLabel = nil }
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Shift State
// ─────────────────────────────────────────────

enum ShiftState: Equatable {
    case off
    case shifted
    case capsLock
}

// ─────────────────────────────────────────────
// MARK: - Emoji Picker Delegate
// ─────────────────────────────────────────────

extension KeyboardViewController: EmojiPickerViewDelegate {
    func emojiPickerDidSelect(emoji: String) {
        textDocumentProxy.insertText(emoji)
        emojiPickerView?.recordUse(of: emoji)
        resetInsertTracking()
        macroEngine.resetBuffer()
    }

    func emojiPickerDidTapBackspace() {
        textDocumentProxy.deleteBackward()
        noteDeletedOneCharacter()
    }

    func emojiPickerDidDismiss() {
        emojiPickerView?.removeFromSuperview()
        emojiPickerView = nil
    }
}

// ─────────────────────────────────────────────
// MARK: - Clipboard History Delegate
// ─────────────────────────────────────────────

extension KeyboardViewController: ClipboardHistoryViewDelegate {
    func clipboardHistoryDidSelect(text: String) {
        insertLongText(text)
        clipboardHistoryDidDismiss()
        resetInsertTracking()
        macroEngine.resetBuffer()
    }

    /// Inserts text through the document proxy in fixed-size chunks.
    /// UITextDocumentProxy.insertText can silently truncate very long
    /// strings in some host apps. Chunking avoids the limit entirely.
    private func insertLongText(_ text: String) {
        let chunkSize = 200
        var remaining = text[...]
        while !remaining.isEmpty {
            let chunk = remaining.prefix(chunkSize)
            textDocumentProxy.insertText(String(chunk))
            remaining = remaining.dropFirst(chunk.count)
        }
    }

    func clipboardHistoryDidDismiss() {
        clipboardHistoryView?.removeFromSuperview()
        clipboardHistoryView = nil
    }

    func clipboardHistoryDidClear() {
        clipboardHistory.clearAll()
        clipboardHistoryView?.updateItems([])
    }

    func clipboardHistoryDidRemove(text: String) {
        clipboardHistory.remove(text)
    }
}
