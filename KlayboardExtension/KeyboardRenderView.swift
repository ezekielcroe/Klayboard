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
    var cursorModeBeganHandler: (() -> Void)?
    var cursorModeMovedHandler: ((Int) -> Void)?
    var cursorModeEndedHandler: (() -> Void)?

    // ── Layout data ──────────────────────────
    private var rows: [LayoutRow] = []
    private var scale: CGFloat = 1.0
    private var shiftState: ShiftState = .off
    private var showPopups: Bool = true
    var longPressDuration: TimeInterval = 0.2

    /// Spacebar trackpad activation delay. Deliberately NOT tied to
    /// longPressDuration: users tune that down to 0.15s for the variant
    /// picker, and at that threshold slow space taps would trip cursor
    /// mode constantly. The system keyboard uses ~0.5s.
    private let spacebarCursorDelay: TimeInterval = 0.45

    /// Horizontal points of finger travel per one character of cursor
    /// movement in trackpad mode.
    private let pointsPerCursorStep: CGFloat = 7.5

    // ── Cursor (trackpad) mode tracking ───────
    private var cursorModeTouches: Set<UITouch> = []
    private var cursorModeLastX: [UITouch: CGFloat] = [:]
    private var cursorModeAccumulator: [UITouch: CGFloat] = [:]

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

    // ── Variant picker tracking ──────────────
    private var pickerByTouch: [UITouch: VariantPickerView] = [:]

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
        touchModel.loadCalibration()
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
        dismissAllPickers()
        cursorModeTouches.removeAll()
        cursorModeLastX.removeAll()
        cursorModeAccumulator.removeAll()

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

            // Long-press timer: accent variants take precedence; altAction
            // is the fallback.
            scheduleLongPress(for: kv, touch: touch)

            if kv.definition.action == .backspace { deleteBeganHandler?() }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let currentLoc = touch.location(in: self)

            // 0. A touch that owns a variant picker only drives the picker.
            if let picker = pickerByTouch[touch] {
                picker.updateSelection(forTouchAt: currentLoc)
                continue
            }

            // 0b. A touch in cursor (trackpad) mode only moves the cursor.
            if cursorModeTouches.contains(touch) {
                handleCursorModeMove(touch: touch, currentX: currentLoc.x)
                continue
            }

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
            //
            //    VERTICAL-DOMINANT MOVEMENT IS RESERVED FOR SWIPES. A swipe
            //    down that drifted onto a neighboring key used to re-target
            //    mid-gesture: the slide switched the active key and reset the
            //    start location, the ±swipeThreshold was never crossed against
            //    the new start, and touchesEnded fired the neighbor's action
            //    (swipe down on "l" became a backspace tap). A touch moving
            //    mostly vertically now stays on its original key until it
            //    either crosses the threshold and fires the gesture, or ends.
            if swipeConsumedTouches.contains(touch) { continue }

            if let startLoc = startTouchLocations[touch] {
                let dxTotal = currentLoc.x - startLoc.x
                let dyTotal = currentLoc.y - startLoc.y
                if abs(dyTotal) > abs(dxTotal) { continue }
            }

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

                    // Restart the long-press clock on the new key. Without
                    // this, an early micro-slide canceled the timer and the
                    // long-press never fired for the rest of the touch —
                    // felt as an inconsistent, key-dependent delay.
                    scheduleLongPress(for: nkv, touch: touch)

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

            // Cursor (trackpad) mode exit path
            if cursorModeTouches.contains(touch) {
                exitCursorMode(touch: touch)
                activeKeyByTouch[touch]?.setHighlighted(false)
                activeKeyByTouch.removeValue(forKey: touch)
                startTouchLocations.removeValue(forKey: touch)
                swipeConsumedTouches.remove(touch)
                continue
            }

            // Variant picker commit path
            if let picker = pickerByTouch[touch] {
                let selected = picker.selectedVariant
                actionHandler?(.character(selected))
                dismissPicker(for: touch)
                activeKeyByTouch[touch]?.setHighlighted(false)
                if activeKeyByTouch[touch]?.definition.action == .backspace { deleteEndedHandler?() }
                activeKeyByTouch.removeValue(forKey: touch)
                startTouchLocations.removeValue(forKey: touch)
                swipeConsumedTouches.remove(touch)
                continue
            }

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
            dismissPicker(for: touch)
            if cursorModeTouches.contains(touch) {
                exitCursorMode(touch: touch)
            }

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
    /// Non-character keys (modifier/spacebar/utility) are scored by distance
    /// to the key's RECTANGLE EDGE. Any touch inside the frame scores 0, so
    /// key width has no effect on hit reliability and wide keys (spacebar)
    /// never lose their own touches to the rejection threshold.
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
                // ── NON-CHARACTER KEY: distance to rectangle edge ──
                //
                // Clamp the point to the key's frame; the distance from the
                // touch to the clamped point is the distance to the nearest
                // edge (0 anywhere inside). Score is independent of key
                // width, which is what broke the old center-distance formula
                // on the spacebar.

                let clampedX = min(max(pt.x, kv.frame.minX), kv.frame.maxX)
                let clampedY = min(max(pt.y, kv.frame.minY), kv.frame.maxY)
                let dx = pt.x - clampedX
                let dy = pt.y - clampedY
                let edgeDistSq = dx * dx + dy * dy

                let paddedRect = kv.frame.insetBy(dx: -8, dy: -12)
                if paddedRect.contains(pt) {
                    // Inside frame: edgeDistSq == 0 → score 0 (strong hit).
                    // Inside padded band: small negative, still comfortably
                    // above the rejection threshold.
                    score = -edgeDistSq * 0.001
                } else {
                    // Outside padded area: decay smoothly.
                    score = -edgeDistSq * 0.005 - 2.0
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

        // Reject touches too far from any key. Contained touches always pass:
        // character keys inside their own frame carry the containment bonus,
        // and non-character keys inside their frame score exactly 0.
        guard bestScore > -8.0 else { return nil }

        return bestKey
    }

    // ── Long press ───────────────────────────

    /// Starts (or restarts) the long-press timer for a key. Called from
    /// touchesBegan and from slide re-targeting, so a touch that settles onto
    /// a neighboring key gets a fresh, full-length long-press window there.
    private func scheduleLongPress(for kv: KeyView, touch: UITouch) {
        cancelLongPress(for: touch)

        // Spacebar owns a different long-press: cursor (trackpad) mode,
        // on its own fixed delay.
        if kv.definition.action == .space {
            let timer = Timer.scheduledTimer(withTimeInterval: spacebarCursorDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if !self.swipeConsumedTouches.contains(touch) {
                    self.enterCursorMode(touch: touch, spacebar: kv)
                }
                self.longPressTimers.removeValue(forKey: touch)
            }
            longPressTimers[touch] = timer
            return
        }

        let variants = Self.variantSet(for: kv.definition)
        guard variants != nil || kv.definition.altAction != nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Only fire if the touch hasn't been consumed by a swipe
            if !self.swipeConsumedTouches.contains(touch) {
                if let variants = variants {
                    self.presentVariantPicker(for: kv, variants: variants, touch: touch)
                } else if let alt = kv.definition.altAction {
                    self.longPressActionHandler?(alt)
                    kv.flashAlt()
                    self.swipeConsumedTouches.insert(touch)
                    self.hidePopup()
                }
            }
            self.longPressTimers.removeValue(forKey: touch)
        }
        longPressTimers[touch] = timer
    }

    private func cancelLongPress(for touch: UITouch) {
        longPressTimers[touch]?.invalidate()
        longPressTimers.removeValue(forKey: touch)
    }

    // ── Cursor (trackpad) mode ────────────────

    private func enterCursorMode(touch: UITouch, spacebar: KeyView) {
        cursorModeTouches.insert(touch)
        cursorModeLastX[touch] = touch.location(in: self).x
        cursorModeAccumulator[touch] = 0

        // Release must not insert a space, and the swipe-up dismiss must
        // stop competing with the drag.
        swipeConsumedTouches.insert(touch)

        // Visual cue: dim everything but the spacebar.
        UIView.animate(withDuration: 0.15) {
            for kv in self.keyViews where kv !== spacebar {
                kv.alpha = 0.35
            }
        }

        cursorModeBeganHandler?()
    }

    private func handleCursorModeMove(touch: UITouch, currentX: CGFloat) {
        guard let lastX = cursorModeLastX[touch] else { return }
        var acc = (cursorModeAccumulator[touch] ?? 0) + (currentX - lastX)
        cursorModeLastX[touch] = currentX

        let steps = Int(acc / pointsPerCursorStep)
        if steps != 0 {
            acc -= CGFloat(steps) * pointsPerCursorStep
            cursorModeMovedHandler?(steps)
        }
        cursorModeAccumulator[touch] = acc
    }

    private func exitCursorMode(touch: UITouch) {
        cursorModeTouches.remove(touch)
        cursorModeLastX.removeValue(forKey: touch)
        cursorModeAccumulator.removeValue(forKey: touch)

        if cursorModeTouches.isEmpty {
            UIView.animate(withDuration: 0.15) {
                for kv in self.keyViews { kv.alpha = 1.0 }
            }
        }

        cursorModeEndedHandler?()
    }

    // ── Variant picker ───────────────────────

    /// Returns the accent variant set for a key, or nil.
    /// Only plain character keys participate; utility/modifier keys and
    /// non-letter characters fall back to altAction long-press.
    private static func variantSet(for definition: KeyDefinition) -> [String]? {
        guard definition.style == .standard,
              case .character(let c) = definition.action else { return nil }
        return AccentVariants.variants(for: c)
    }

    private func presentVariantPicker(for keyView: KeyView, variants: [String], touch: UITouch) {
        hidePopup()

        let display: [String]
        switch shiftState {
        case .off:
            display = variants
        case .shifted, .capsLock:
            display = variants.map { AccentVariants.shiftedDisplay($0) }
        }

        let picker = VariantPickerView(keyView: keyView, variants: display, containerBounds: bounds)
        addSubview(picker)
        pickerByTouch[touch] = picker
        picker.updateSelection(forTouchAt: touch.location(in: self))
    }

    private func dismissPicker(for touch: UITouch) {
        pickerByTouch[touch]?.removeFromSuperview()
        pickerByTouch.removeValue(forKey: touch)
    }

    private func dismissAllPickers() {
        for (_, picker) in pickerByTouch { picker.removeFromSuperview() }
        pickerByTouch.removeAll()
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
// MARK: - VariantPickerView
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Horizontal slide-to-select accent picker shown above a key on long-press.
/// Selection is driven purely by the touch's x-coordinate in the keyboard's
/// coordinate space, so the finger can stay down on the key row (system
/// keyboard behavior) rather than having to travel up into the popup.
final class VariantPickerView: UIView {

    private let variants: [String]
    private var cells: [UILabel] = []
    private var selectedIndex: Int = 0

    private let cellWidth: CGFloat
    private let cellHeight: CGFloat = 42
    private let inset: CGFloat = 4

    var selectedVariant: String { variants[selectedIndex] }

    init(keyView: KeyView, variants: [String], containerBounds: CGRect) {
        self.variants = variants

        // Preferred cell width is 34pt; shrink uniformly if the full set
        // would overflow the keyboard width (floor 24pt keeps cells tappable).
        let preferred: CGFloat = 34
        let available = containerBounds.width - 8 - 8 // side margins + insets
        let fitted = available / CGFloat(max(variants.count, 1))
        self.cellWidth = max(24, min(preferred, fitted))

        let width = cellWidth * CGFloat(variants.count) + inset * 2
        let height = cellHeight + inset * 2

        var originX = keyView.frame.midX - width / 2
        originX = max(4, min(originX, containerBounds.width - width - 4))
        let originY = max(keyView.frame.minY - height - 6, 0)

        super.init(frame: CGRect(x: originX, y: originY, width: width, height: height))

        backgroundColor = UIColor.systemBackground
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)

        for (i, v) in variants.enumerated() {
            let lbl = UILabel(frame: CGRect(
                x: inset + CGFloat(i) * cellWidth,
                y: inset,
                width: cellWidth,
                height: cellHeight
            ))
            lbl.text = v
            lbl.textAlignment = .center
            lbl.font = UIFont.systemFont(ofSize: 22, weight: .regular)
            lbl.layer.cornerRadius = 6
            lbl.layer.masksToBounds = true
            addSubview(lbl)
            cells.append(lbl)
        }

        select(0)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `pt` is in the SUPERVIEW's (keyboard's) coordinate space.
    /// Only the x-coordinate matters; the finger may remain on the key row.
    func updateSelection(forTouchAt pt: CGPoint) {
        let localX = pt.x - frame.minX - inset
        let idx = Int(floor(localX / cellWidth))
        select(max(0, min(variants.count - 1, idx)))
    }

    private func select(_ index: Int) {
        selectedIndex = index
        styleCells()
    }

    private func styleCells() {
        for (i, cell) in cells.enumerated() {
            if i == selectedIndex {
                cell.backgroundColor = UIColor.systemBlue
                cell.textColor = .white
            } else {
                cell.backgroundColor = .clear
                cell.textColor = .label
            }
        }
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
