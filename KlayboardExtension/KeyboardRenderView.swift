// KeyboardRenderView.swift
// Programmatic, frame-based keyboard renderer with gesture support.
//

import UIKit

final class KeyboardRenderView: UIView {

    // ── Callbacks ────────────────────────────
    var actionHandler: ((KeyAction) -> Void)?
    var longPressActionHandler: ((KeyAction) -> Void)?
    var deleteBeganHandler: (() -> Void)?
    var deleteEndedHandler: (() -> Void)?

    // ── Layout data ──────────────────────────
    private var rows: [LayoutRow] = []
    private var scale: CGFloat = 1.0
    private var shiftState: ShiftState = .off
    private var showPopups: Bool = true
    var longPressDuration: TimeInterval = 0.2

    private let interRowSpacing: CGFloat = 6.0
    private let interKeySpacing: CGFloat = 4.0
    private let edgeInset: CGFloat = 3.0

    // ── Rendered key views ───────────────────
    private var keyViews: [KeyView] = []
    private var popupView: KeyPopupView?
    private var layoutFingerprint: String = ""

    // ── Touch tracking ───────────────────────
    private var activeKeyByTouch: [UITouch: KeyView] = [:]
    private var longPressTimers: [UITouch: Timer] = [:]

    // ── Gesture tracking ─────────────────────
    private var startTouchLocations: [UITouch: CGPoint] = [:]
    private var swipeConsumedTouches: Set<UITouch> = []
    private let swipeThreshold: CGFloat = 18.0

    // ── Touch Accuracy Model ─────────────────
    private var touchModel = TouchModel()
    private let bigramModel = BigramModel()

    /// The last character the user typed. Set by KeyboardViewController
    /// after each character insertion. Used for bigram-weighted targeting.
    var lastTypedCharacter: Character?

    /// How strongly bigram frequency influences key targeting.
    /// 0.0 = pure geometry. 0.35 = moderate bias. 0.6 = strong bias.
    var bigramInfluence: CGFloat = 0.25

    /// Hysteresis bonus (in log-probability units) given to the currently
    /// active key during touchesMoved. The finger must exceed this margin
    /// before the active key switches. Prevents micro-drift key flipping.
    private let hysteresisBonus: CGFloat = 2.0

    /// Log-probability bonus for touches that land inside a key's visual
    /// rectangle. Makes "clearly inside this key" nearly impossible to
    /// override by a neighboring key's Gaussian score.
    private let containmentBonus: CGFloat = 1.5

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Configuration
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func configure(rows: [LayoutRow], scale: CGFloat, shiftState: ShiftState, showPopups: Bool) {
        let newFingerprint = Self.fingerprint(for: rows)
        let layoutChanged = (newFingerprint != layoutFingerprint)

        self.rows = rows
        self.scale = scale
        self.shiftState = shiftState
        self.showPopups = showPopups

        if layoutChanged {
            layoutFingerprint = newFingerprint
            rebuildKeyViews()
        } else {
            // Lightweight path: just update shift state on existing views.
            for kv in keyViews {
                kv.updateShiftState(shiftState)
            }
        }
    }

    private static func fingerprint(for rows: [LayoutRow]) -> String {
        rows.map { row in
            row.keys.map(\.id).joined(separator: ",")
        }.joined(separator: "|")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - View Lifecycle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(named: "KeyboardBackground") ?? UIColor.systemGray6
    }

    required init?(coder: NSCoder) { fatalError("Programmatic only") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutKeys()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Key View Construction
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func rebuildKeyViews() {
        // Cancel all in-flight touches before destroying views
        for (touch, kv) in activeKeyByTouch {
            kv.setHighlighted(false)
            cancelLongPress(for: touch)
        }
        activeKeyByTouch.removeAll()
        startTouchLocations.removeAll()
        swipeConsumedTouches.removeAll()

        keyViews.forEach { $0.removeFromSuperview() }
        keyViews.removeAll()
        popupView?.removeFromSuperview()

        for row in rows {
            for keyDef in row.keys {
                let kv = KeyView(definition: keyDef, shiftState: shiftState)
                addSubview(kv)
                keyViews.append(kv)
            }
        }
        setNeedsLayout()
    }

    private func layoutKeys() {
        let totalWidth = bounds.width
        guard totalWidth > 0 else { return }
        var yOffset: CGFloat = 0
        var keyIndex = 0

        for row in rows {
            let rowH = row.baseHeight * scale
            let totalUnits = row.keys.reduce(CGFloat(0)) { $0 + $1.widthMultiplier }
            let totalSpacing = interKeySpacing * CGFloat(max(row.keys.count - 1, 0)) + edgeInset * 2
            let unitWidth = (totalWidth - totalSpacing) / totalUnits
            var xOffset = edgeInset

            for keyDef in row.keys {
                guard keyIndex < keyViews.count else { break }
                let kv = keyViews[keyIndex]
                let keyW = unitWidth * keyDef.widthMultiplier
                kv.frame = CGRect(x: xOffset, y: yOffset, width: keyW, height: rowH)
                kv.layoutIfNeeded()
                xOffset += keyW + interKeySpacing
                keyIndex += 1
            }
            yOffset += rowH + interRowSpacing
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Raw Touch Handling & Gestures
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let kv = hitKeyView(for: touch) else { continue }

            // Track state
            activeKeyByTouch[touch] = kv
            startTouchLocations[touch] = touch.location(in: self)

            kv.setHighlighted(true)

            if showPopups, case .character = kv.definition.action {
                showPopup(for: kv)
            }

            // Start long-press timer
            if kv.definition.altAction != nil {
                let timer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    // Only fire if the touch hasn't been consumed by a swipe
                    if !self.swipeConsumedTouches.contains(touch), let alt = kv.definition.altAction {
                        self.longPressActionHandler?(alt)
                        kv.flashAlt()
                        self.swipeConsumedTouches.insert(touch)
                        self.hidePopup()
                    }
                    self.longPressTimers.removeValue(forKey: touch)
                }
                longPressTimers[touch] = timer
            }

            if kv.definition.action == .backspace { deleteBeganHandler?() }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let currentLoc = touch.location(in: self)

            // 1. Process Gestures first
            if !swipeConsumedTouches.contains(touch),
               let startLoc = startTouchLocations[touch],
               let kv = activeKeyByTouch[touch] {

                let dy = currentLoc.y - startLoc.y
                let dx = currentLoc.x - startLoc.x

                // Ensure it's mostly vertical
                if abs(dy) > abs(dx) {
                    if dy > swipeThreshold {
                        // SWIPE DOWN — primary alt-action
                        if let alt = kv.definition.altAction {
                            longPressActionHandler?(alt)
                            kv.flashAlt()
                            swipeConsumedTouches.insert(touch)
                            cancelLongPress(for: touch)
                            hidePopup()
                            continue
                        }
                    } else if dy < -swipeThreshold {
                        if let swipeUp = kv.definition.swipeUpAction {
                            actionHandler?(swipeUp)
                            swipeConsumedTouches.insert(touch)
                            cancelLongPress(for: touch)
                            hidePopup()
                            continue
                        }
                    }
                }
            }

            // 2. If not swiped, process normal sliding between keys.
            //    Uses hysteresis: the currently active key gets a bonus so
            //    micro-drift during a press doesn't flip to a neighbor.
            if swipeConsumedTouches.contains(touch) { continue }

            let newKV = hitKeyViewForMove(for: touch, currentKey: activeKeyByTouch[touch])
            let oldKV = activeKeyByTouch[touch]

            if newKV !== oldKV {
                oldKV?.setHighlighted(false)
                hidePopup()
                cancelLongPress(for: touch)
                if oldKV?.definition.action == .backspace { deleteEndedHandler?() }

                if let nkv = newKV {
                    activeKeyByTouch[touch] = nkv
                    nkv.setHighlighted(true)
                    startTouchLocations[touch] = currentLoc

                    if showPopups, case .character = nkv.definition.action {
                        showPopup(for: nkv)
                    }
                    if nkv.definition.action == .backspace { deleteBeganHandler?() }
                } else {
                    activeKeyByTouch.removeValue(forKey: touch)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let kv = activeKeyByTouch[touch] {
                kv.setHighlighted(false)
                hidePopup()
                cancelLongPress(for: touch)

                // ONLY fire standard action if a gesture/long-press didn't consume the touch
                if !swipeConsumedTouches.contains(touch) {
                    actionHandler?(kv.definition.action)
                }

                // Record calibration sample for character keys
                if !swipeConsumedTouches.contains(touch),
                   kv.definition.style == .standard {
                    let pt = touch.location(in: self)
                    let center = CGPoint(x: kv.frame.midX, y: kv.frame.midY)
                    touchModel.recordCalibrationSample(
                        touchPoint: pt,
                        keyCenter: center
                    )
                }

                if kv.definition.action == .backspace { deleteEndedHandler?() }
            }

            // Cleanup
            activeKeyByTouch.removeValue(forKey: touch)
            startTouchLocations.removeValue(forKey: touch)
            swipeConsumedTouches.remove(touch)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let kv = activeKeyByTouch[touch]
            kv?.setHighlighted(false)
            cancelLongPress(for: touch)
            if kv?.definition.action == .backspace { deleteEndedHandler?() }

            // Cleanup
            activeKeyByTouch.removeValue(forKey: touch)
            startTouchLocations.removeValue(forKey: touch)
            swipeConsumedTouches.remove(touch)
        }
        hidePopup()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Hit Testing (Gaussian + Containment + Hysteresis)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Initial hit test for touchesBegan. No hysteresis — pure scoring.
    private func hitKeyView(for touch: UITouch) -> KeyView? {
        let pt = touch.location(in: self)
        return bestKeyView(at: pt, currentKey: nil)
    }

    /// Hit test for touchesMoved. The currently active key receives a
    /// hysteresis bonus so micro-drift during a press doesn't flip keys.
    private func hitKeyViewForMove(for touch: UITouch, currentKey: KeyView?) -> KeyView? {
        let pt = touch.location(in: self)
        return bestKeyView(at: pt, currentKey: currentKey)
    }

    /// Core scoring logic. Evaluates ALL keys and returns the highest-scoring one.
    ///
    /// Character keys (.standard style) are scored with:
    ///   - Gaussian log-probability from finger position to key center
    ///   - Containment bonus if the touch is inside the key's rectangle
    ///   - Bigram weight from the previously typed character
    ///
    /// Non-character keys (modifier/spacebar/utility) are scored by strict
    /// rectangular containment with NO expansion, preventing shift/backspace
    /// from stealing boundary touches from adjacent character keys.
    ///
    /// If `currentKey` is provided (during touchesMoved), that key receives
    /// a hysteresis bonus so the finger must move significantly to switch.
    private func bestKeyView(at pt: CGPoint, currentKey: KeyView?) -> KeyView? {

        var bestKey: KeyView?
        var bestScore: CGFloat = -.greatestFiniteMagnitude

        for kv in keyViews {
            let center = CGPoint(x: kv.frame.midX, y: kv.frame.midY)
            var score: CGFloat

            if kv.definition.style == .standard {
                // ── CHARACTER KEY: Gaussian + containment + bigram ──

                score = touchModel.logProbability(
                    touchPoint: pt,
                    keyCenter: center,
                    scale: self.scale
                )

                // Containment bonus: touch inside this key's rect gets a
                // strong advantage, making it nearly unbeatable by neighbors.
                if kv.frame.contains(pt) {
                    score += containmentBonus
                }

                // Bigram boost: context-sensitive weighting from previous letter
                if bigramInfluence > 0,
                   let prev = lastTypedCharacter,
                   case .character(let c) = kv.definition.action,
                   let next = c.lowercased().first {
                    score += bigramModel.weight(prev: prev, next: next) * bigramInfluence
                }

            } else {
                // ── NON-CHARACTER KEY: Padded Hit Box ──
                
                let hitRect = kv.frame.insetBy(dx: -8, dy: -12) // Expand hit area safely
                
                if hitRect.contains(pt) {
                    let dx = pt.x - center.x
                    let dy = pt.y - center.y
                    // Inside padded area: treat as a strong hit
                    score = -(dx * dx + dy * dy) * 0.001
                } else {
                    // Outside padded area: decay smoothly instead of instantly dying
                    let dx = pt.x - center.x
                    let dy = pt.y - center.y
                    score = -(dx * dx + dy * dy) * 0.005 - 10.0
                }
            }

            // Hysteresis: active key gets a bonus during touchesMoved.
            // In touchesBegan, currentKey is nil → no bonus → pure scoring.
            if let current = currentKey, kv === current {
                score += hysteresisBonus
            }

            if score > bestScore {
                bestScore = score
                bestKey = kv
            }
        }

        // Reject touches too far from any key
        guard bestScore > -8.0 else { return nil }

        // Nearest-centroid fallback
        if bestKey == nil {
            var fallbackKey: KeyView?
            var fallbackDist: CGFloat = .greatestFiniteMagnitude
            for kv in keyViews {
                let center = CGPoint(x: kv.frame.midX, y: kv.frame.midY)
                let dist = (pt.x - center.x) * (pt.x - center.x)
                         + (pt.y - center.y) * (pt.y - center.y)
                if dist < fallbackDist {
                    fallbackDist = dist
                    fallbackKey = kv
                }
            }
            if fallbackDist < 40.0 * 40.0 {
                return fallbackKey
            }
        }

        return bestKey
    }

    // ── Long press ───────────────────────────

    private func cancelLongPress(for touch: UITouch) {
        longPressTimers[touch]?.invalidate()
        longPressTimers.removeValue(forKey: touch)
    }

    // ── Popup ────────────────────────────────

    private func showPopup(for keyView: KeyView) {
        hidePopup()
        let popup = KeyPopupView(keyView: keyView, shiftState: shiftState)
        addSubview(popup)
        popupView = popup
    }

    private func hidePopup() {
        popupView?.removeFromSuperview()
        popupView = nil
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - KeyView
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Lightweight view for a single key. Uses CALayer for rendering.
final class KeyView: UIView {

    let definition: KeyDefinition
    private let label = UILabel()
    private let altLabel = UILabel()
    private var currentShiftState: ShiftState

    init(definition: KeyDefinition, shiftState: ShiftState) {
        self.definition = definition
        self.currentShiftState = shiftState
        super.init(frame: .zero)
        setupAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateShiftState(_ newState: ShiftState) {
        guard newState != currentShiftState else { return }
        currentShiftState = newState
        updateLabelContent()
    }

    private func setupAppearance() {
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 0.5
        layer.masksToBounds = false

        applyStyle(definition.style, highlighted: false)

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.baselineAdjustment = .alignCenters
        addSubview(label)

        updateLabelContent()

        if let alt = definition.altAction, case .character(let c) = alt {
            altLabel.text = c
            altLabel.font = UIFont.systemFont(ofSize: 10, weight: .regular)
            altLabel.textColor = UIColor.secondaryLabel
            altLabel.textAlignment = .right
            addSubview(altLabel)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 2)
        altLabel.frame = CGRect(
            x: bounds.width - 14, y: 2,
            width: 12, height: 12
        )
    }

    private func updateLabelContent() {
        let text = definition.label

        if text.hasPrefix("sf:") {
            let symbolName = resolveSymbolName(String(text.dropFirst(3)))
            let pointSize: CGFloat = definition.style == .utility ? 14 : 18
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            if let img = UIImage(systemName: symbolName, withConfiguration: config) {
                let attachment = NSTextAttachment()
                attachment.image = img.withTintColor(label.textColor ?? .label, renderingMode: .alwaysOriginal)
                label.attributedText = NSAttributedString(attachment: attachment)
            } else {
                label.font = UIFont.systemFont(ofSize: pointSize)
                label.text = symbolName
            }
            return
        }

        let displayText: String
        switch currentShiftState {
        case .off:
            displayText = text
        case .shifted, .capsLock:
            if case .character = definition.action {
                displayText = text.uppercased()
            } else {
                displayText = text
            }
        }
        let fontSize: CGFloat = definition.style == .utility ? 13 : 20
        label.font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        label.text = displayText
    }

    private func resolveSymbolName(_ baseName: String) -> String {
        guard definition.action == .shift else { return baseName }
        switch currentShiftState {
        case .off:      return "shift"
        case .shifted:  return "shift.fill"
        case .capsLock: return "capslock.fill"
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        applyStyle(definition.style, highlighted: highlighted)
    }

    func flashAlt() {
        UIView.animate(withDuration: 0.08, animations: {
            self.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
        }, completion: { _ in
            self.applyStyle(self.definition.style, highlighted: false)
        })
    }

    private func applyStyle(_ style: KeyStyle, highlighted: Bool) {
        let isDark = traitCollection.userInterfaceStyle == .dark

        if highlighted {
            backgroundColor = UIColor.systemBlue.withAlphaComponent(0.4)
            label.textColor = .white
            return
        }

        switch style {
        case .standard:
            backgroundColor = isDark ? UIColor(white: 0.35, alpha: 1) : .white
            label.textColor = isDark ? .white : .black
        case .modifier:
            backgroundColor = isDark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.72, alpha: 1)
            label.textColor = isDark ? .white : .black
        case .utility:
            backgroundColor = isDark ? UIColor(white: 0.18, alpha: 1) : UIColor(white: 0.82, alpha: 1)
            label.textColor = UIColor.systemBlue
        case .spacebar:
            backgroundColor = isDark ? UIColor(white: 0.35, alpha: 1) : .white
            label.textColor = isDark ? .white : .black
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyStyle(definition.style, highlighted: false)
        updateLabelContent()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Key Popup View (magnified preview)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class KeyPopupView: UIView {
    init(keyView: KeyView, shiftState: ShiftState) {
        super.init(frame: .zero)

        let popW: CGFloat = max(keyView.frame.width + 12, 44)
        let popH: CGFloat = 56
        let originX = keyView.frame.midX - popW / 2
        let originY = keyView.frame.minY - popH - 4

        frame = CGRect(x: originX, y: max(originY, 0), width: popW, height: popH)
        backgroundColor = UIColor.systemBackground
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let lbl = UILabel(frame: bounds)
        lbl.textAlignment = .center
        lbl.font = UIFont.systemFont(ofSize: 28, weight: .light)

        let text = keyView.definition.label
        if !text.hasPrefix("sf:") {
            switch shiftState {
            case .off: lbl.text = text
            case .shifted, .capsLock: lbl.text = text.uppercased()
            }
        }
        addSubview(lbl)
    }

    required init?(coder: NSCoder) { fatalError() }
}
