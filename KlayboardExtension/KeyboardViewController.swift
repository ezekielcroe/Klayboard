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

    // ── Engines ────────────────────────────────
    private let macroEngine = MacroEngine()
    private let cursorEngine = CursorEngine()
    private var haptic: UIImpactFeedbackGenerator?

    // ── Rendering ──────────────────────────────
    private var keyboardView: KeyboardRenderView!
    private var heightConstraint: NSLayoutConstraint?
    private var containerHeightConstraint: NSLayoutConstraint?

    // ── Delete repeat ──────────────────────────
    private var deleteTimer: Timer?
    private var deleteRepeatCount: Int = 0
    private var deleteRepeatHasFired: Bool = false

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

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        macroEngine.checkTrigger(proxy: textDocumentProxy)
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
        var base = BaseLayouts.layout(for: config.activeLayoutID, rowMode: config.rowMode)

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
            let output: String
            switch shiftState {
            case .off:      output = c
            case .shifted:  output = c.uppercased(); shiftState = .off
            case .capsLock: output = c.uppercased()
            }
            textDocumentProxy.insertText(output)
            trackInserted(output)
 
            // Feed the typed character to the touch model for bigram weighting.
            // Only lowercase letters a-z produce meaningful bigram context.
            // Numbers, punctuation, and symbols → nil (neutral targeting).
            if let ch = output.lowercased().first, ch >= "a", ch <= "z" {
                keyboardView.lastTypedCharacter = ch
            } else {
                keyboardView.lastTypedCharacter = nil
            }
 
            // Lightweight update — only changes labels, no view rebuild
            updateKeyboardView()

        case .space:
            if lastInsertedChar == " ",
               let prev = secondLastInsertedChar,
               !prev.isWhitespace, !prev.isPunctuation {
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(". ")
                trackInserted(". ")
                if shiftState == .off { shiftState = .shifted; updateKeyboardView() }
            } else {
                textDocumentProxy.insertText(" ")
                trackInserted(" ")
            }
            // Space breaks bigram context — next letter starts fresh
            keyboardView.lastTypedCharacter = nil

        case .returnKey:
            textDocumentProxy.insertText("\n")
            trackInserted("\n")
            // Newline breaks bigram context
            keyboardView.lastTypedCharacter = nil

        case .backspace:
            if !deleteRepeatHasFired {
                textDocumentProxy.deleteBackward()
            }
            resetInsertTracking()

        // ── Modifiers ────────────────────────────
        case .shift:
            switch shiftState {
            case .off:      shiftState = .shifted
            case .shifted:  shiftState = .capsLock
            case .capsLock: shiftState = .off
            }
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

        case .moveCursorBackward:
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
            resetInsertTracking()

        case .moveCursorForwardWord:
            cursorEngine.moveForwardByWord(proxy: textDocumentProxy)
            resetInsertTracking()

        case .moveCursorBackwardWord:
            cursorEngine.moveBackwardByWord(proxy: textDocumentProxy)
            resetInsertTracking()

        // ── Deletion ─────────────────────────────
        case .deleteWord:
            cursorEngine.deleteBackwardWord(proxy: textDocumentProxy)
            resetInsertTracking()

        case .deleteToLineStart:
            cursorEngine.deleteToLineStart(proxy: textDocumentProxy)
            resetInsertTracking()

        // ── Text manipulation ────────────────────
        case .toggleCase:
            cursorEngine.toggleCase(proxy: textDocumentProxy)

        case .insertMacro(let macroKey):
            macroEngine.executeMacro(named: macroKey, proxy: textDocumentProxy)
            resetInsertTracking()

        // ── Clipboard ────────────────────────────
        case .copy:
            if let text = textDocumentProxy.selectedText, !text.isEmpty {
                UIPasteboard.general.string = text
            }

        case .paste:
            if let text = UIPasteboard.general.string {
                textDocumentProxy.insertText(text)
                resetInsertTracking()
            }

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
        keyboardView.lastTypedCharacter = nil
    }

    // ── Delete key repeat ────────────────────────

    private func startDeleteRepeat() {
        deleteRepeatCount = 0
        deleteRepeatHasFired = false

        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.deleteRepeatHasFired = true
            self.textDocumentProxy.deleteBackward()

            self.deleteRepeatCount = 0
            self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.deleteRepeatCount += 1
                if self.deleteRepeatCount > 5 {
                    self.cursorEngine.deleteBackwardWord(proxy: self.textDocumentProxy)
                } else {
                    self.textDocumentProxy.deleteBackward()
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
}

// ─────────────────────────────────────────────
// MARK: - Shift State
// ─────────────────────────────────────────────

enum ShiftState: Equatable {
    case off
    case shifted
    case capsLock
}
