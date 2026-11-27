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
    /// Rows as configured by the controller.
    private var sourceRows: [LayoutRow] = []
    /// Rows as rendered: `sourceRows`, or their split form when `isSplit`.
    private var rows: [LayoutRow] = []
    /// Per rendered row, the index of the first right-half key (split only).
    private var rightHalfStarts: [Int] = []
    /// Whether the rendered rows are currently split. Decided in
    /// layoutSubviews from the usable width, so it follows fold/unfold.
    private var isSplit = false
    /// User preference; the split only happens when the keyboard is wide.
    var splitOnWideScreens: Bool = true {
        didSet { if splitOnWideScreens != oldValue { setNeedsLayout() } }
    }
    /// Share of the width left empty between the halves (Settings slider).
    var splitGap: CGFloat = CGFloat(UserConfiguration.defaultSplitGap) {
        didSet { if splitGap != oldValue { setNeedsLayout() } }
    }
    /// Hit cells on the inner edges of a split extend this far into the
    /// center gap, for thumbs that overshoot toward the middle.
    private let splitInnerHitSlop: CGFloat = 16.0
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

    /// Minimum vertical travel for a swipe. The effective threshold scales
    /// with key height (see `swipeThreshold(for:)`), never below this.
    private let minSwipeThreshold: CGFloat = 18.0
    /// Swipe threshold as a fraction of the key's height (24pt on a 44pt key).
    private let swipeThresholdPerKeyHeight: CGFloat = 0.55
    /// A swipe must be this many times more vertical than horizontal
    /// (1.5 ≈ within 34° of vertical). Was 1.0 (45°).
    private let swipeDominance: CGFloat = 1.5
    /// Swipes that dismiss the keyboard are destructive to flow, so they
    /// need twice the travel.
    private let dismissSwipeMultiplier: CGFloat = 2.0

    /// Touches that were still down when another touch began (thumb
    /// rollover during fast typing). Their vertical drift is the finger
    /// lifting toward the next key, not a gesture, so swipes are ignored.
    private var overlappedTouches: Set<UITouch> = []

    /// Where each touch first landed. `startTouchLocations` is reset when a
    /// touch slides onto another key; this one never is.
    private var touchDownPoints: [UITouch: CGPoint] = [:]
    /// Touches that slid off their initial key. Their touch-down point does
    /// not belong to the committed key, so they are excluded from calibration.
    private var retargetedTouches: Set<UITouch> = []
    /// Bigram context captured when each touch began.
    private var contextByTouch: [UITouch: BigramContext] = [:]

    // ── Key order (rollover) ─────────────────
    /// Press order of live touches, so rolled-over keys commit oldest first.
    private var touchSequence: [UITouch: Int] = [:]
    private var nextTouchSequence = 0
    /// Touches whose key was committed early because another finger landed.
    /// Their release must not fire the key again or hide the newer popup.
    private var earlyCommittedTouches: Set<UITouch> = []

    // ── Touch Accuracy Model ─────────────────
    private var touchModel = TouchModel()
    private let bigramModel = BigramModel()

    /// Supplies the text context before the cursor at touch-down.
    /// Owned by KeyboardViewController, which tracks its own insertions and
    /// re-syncs from the document proxy after edits it can't track locally.
    var bigramContextProvider: (() -> BigramContext)?

    /// How strongly bigram frequency influences key targeting.
    /// 0.0 = pure geometry. 0.35 = moderate bias. 0.6 = strong bias.
    var bigramInfluence: CGFloat = 0.25

    /// During touchesMoved the active key keeps the touch until the finger
    /// is this many points outside its hit cell. Prevents micro-drift flips.
    private let hysteresisMargin: CGFloat = 6.0

    /// Width of the band on each side of a boundary between two CHARACTER
    /// keys where the probabilistic model (Gaussian + bigram) may override
    /// plain cell ownership. Outside the band, the cell owner always wins.
    private let ambiguityBand: CGFloat = 6.0

    /// Maximum penalty (log-probability units) for a neighbouring character
    /// key. It grows linearly from 0 at the shared boundary to this value at
    /// the far edge of the band, so the model decides freely at the boundary
    /// and the owner becomes progressively harder to override.
    private let containmentBonus: CGFloat = 1.5

    /// Hit cells on the outer edges of the keyboard extend this far beyond
    /// the view, so slight overshoot during a slide doesn't cancel the key.
    private let outerHitSlop: CGFloat = 20.0

    // ── Calibration sample queue ──────────────
    // Samples are held back for a few characters and dropped if the
    // character they belong to is deleted, so typos don't train the model
    // toward the wrong key. `nil` entries are placeholders for characters
    // that produced no sample, keeping the queue aligned with the text.
    private struct CalibrationSample {
        let point: CGPoint
        let center: CGPoint
    }
    private var pendingCalibration: [CalibrationSample?] = []
    private let calibrationCommitDelay = 3

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Configuration
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func configure(rows: [LayoutRow], scale: CGFloat, shiftState: ShiftState, showPopups: Bool) {
        self.sourceRows = rows
        self.scale = scale
        self.shiftState = shiftState
        self.showPopups = showPopups
        applyRows()
    }

    /// Derives the rendered rows from `sourceRows` and `isSplit`, rebuilding
    /// key views only if the set of keys changed.
    private func applyRows() {
        if isSplit {
            let split = sourceRows.map(SplitLayout.split)
            rows = zip(sourceRows, split).map { source, s in
                LayoutRow(keys: s.keys, baseHeight: source.baseHeight, tag: source.tag)
            }
            rightHalfStarts = split.map(\.rightStart)
        } else {
            rows = sourceRows
            rightHalfStarts = []
        }

        let newFingerprint = Self.fingerprint(for: rows)
        let layoutChanged = (newFingerprint != layoutFingerprint)

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
        let usableWidth = bounds.width - safeAreaInsets.left - safeAreaInsets.right
        let wantsSplit = SplitLayout.shouldSplit(usableWidth: usableWidth, enabled: splitOnWideScreens)
        if wantsSplit != isSplit {
            isSplit = wantsSplit
            applyRows()
        }
        layoutKeys()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
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
        overlappedTouches.removeAll()
        touchDownPoints.removeAll()
        retargetedTouches.removeAll()
        contextByTouch.removeAll()
        touchSequence.removeAll()
        earlyCommittedTouches.removeAll()
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
        // Keys stay inside the safe area: a horizontal inset (such as a
        // vertical system bar) can sit on either edge, independently.
        let contentMinX = safeAreaInsets.left
        let usableWidth = bounds.width - safeAreaInsets.left - safeAreaInsets.right
        guard usableWidth > 0 else { return }

        // Split: rows are laid out as a contiguous keyboard of `keyAreaWidth`
        // and every right-half key is shifted right by `gap`.
        let keyAreaWidth = isSplit ? SplitLayout.keyAreaWidth(usableWidth: usableWidth, gap: splitGap) : usableWidth
        let gap = usableWidth - keyAreaWidth

        var yOffset: CGFloat = 0
        var keyIndex = 0

        for (rowIndex, row) in rows.enumerated() {
            let rowH = row.baseHeight * scale
            let totalUnits = row.keys.reduce(CGFloat(0)) { $0 + $1.widthMultiplier }
            let totalSpacing = interKeySpacing * CGFloat(max(row.keys.count - 1, 0)) + edgeInset * 2
            let unitWidth = (keyAreaWidth - totalSpacing) / totalUnits
            let rightStart = isSplit ? rightHalfStarts[rowIndex] : row.keys.count
            var xOffset = contentMinX + edgeInset

            // Hit cells tile the keyboard with no gaps: each boundary sits in
            // the middle of the visual gap between two keys, and the outer
            // keys/rows extend past the view edges. In a split, the inner
            // edges reach only `splitInnerHitSlop` into the center gap, so
            // the middle of the gap is dead space.
            let isFirstRow = rowIndex == 0
            let isLastRow = rowIndex == rows.count - 1
            let cellTop = isFirstRow ? -outerHitSlop : yOffset - interRowSpacing / 2
            let cellBottom = isLastRow ? bounds.height + outerHitSlop : yOffset + rowH + interRowSpacing / 2

            for (keyInRow, keyDef) in row.keys.enumerated() {
                guard keyIndex < keyViews.count else { break }
                let kv = keyViews[keyIndex]
                if keyInRow == rightStart, keyInRow > 0 { xOffset += gap }
                let keyW = unitWidth * keyDef.widthMultiplier
                kv.frame = CGRect(x: xOffset, y: yOffset, width: keyW, height: rowH)

                let cellLeft: CGFloat
                if keyInRow == 0 {
                    cellLeft = -outerHitSlop
                } else if keyInRow == rightStart {
                    cellLeft = xOffset - splitInnerHitSlop
                } else {
                    cellLeft = xOffset - interKeySpacing / 2
                }
                let cellRight: CGFloat
                if keyInRow == row.keys.count - 1 {
                    cellRight = bounds.width + outerHitSlop
                } else if keyInRow == rightStart - 1 {
                    cellRight = xOffset + keyW + splitInnerHitSlop
                } else {
                    cellRight = xOffset + keyW + interKeySpacing / 2
                }
                kv.hitRect = CGRect(x: cellLeft, y: cellTop,
                                    width: cellRight - cellLeft, height: cellBottom - cellTop)

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
        // KEY ORDER: commit keys that are still held BEFORE handling the new
        // touches, so characters come out in press order. Must run first so
        // the new touch's bigram context includes the committed character.
        commitRolledOverTouches()

        for touch in touches {
            // Any touch still down is now part of a rollover.
            for other in activeKeyByTouch.keys { overlappedTouches.insert(other) }

            let context = bigramContextProvider?() ?? .none
            guard let kv = hitKeyView(for: touch, context: context) else { continue }

            // Track state
            let pt = touch.location(in: self)
            activeKeyByTouch[touch] = kv
            startTouchLocations[touch] = pt
            touchDownPoints[touch] = pt
            contextByTouch[touch] = context
            touchSequence[touch] = nextTouchSequence
            nextTouchSequence &+= 1

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
               !overlappedTouches.contains(touch),
               let startLoc = startTouchLocations[touch],
               let kv = activeKeyByTouch[touch] {

                let dy = currentLoc.y - startLoc.y
                let dx = currentLoc.x - startLoc.x
                let threshold = swipeThreshold(for: kv)

                // Must be clearly vertical
                if abs(dy) > abs(dx) * swipeDominance {
                    if dy > threshold {
                        // SWIPE DOWN — primary alt-action
                        if let alt = kv.definition.altAction {
                            longPressActionHandler?(alt)
                            noteAltActionCommitted(alt)
                            kv.flashAlt()
                            swipeConsumedTouches.insert(touch)
                            cancelLongPress(for: touch)
                            hidePopup()
                            continue
                        }
                    } else if let swipeUp = kv.definition.swipeUpAction,
                              dy < -threshold * (swipeUp == .dismissKeyboard ? dismissSwipeMultiplier : 1) {
                        // SWIPE UP — tertiary action
                        actionHandler?(swipeUp)
                        swipeConsumedTouches.insert(touch)
                        cancelLongPress(for: touch)
                        hidePopup()
                        continue
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

            let newKV = hitKeyViewForMove(for: touch, currentKey: activeKeyByTouch[touch],
                                          context: contextByTouch[touch] ?? .none)
            let oldKV = activeKeyByTouch[touch]

            if newKV !== oldKV {
                oldKV?.setHighlighted(false)
                hidePopup()
                cancelLongPress(for: touch)
                if oldKV?.definition.action == .backspace { deleteEndedHandler?() }

                if let nkv = newKV {
                    activeKeyByTouch[touch] = nkv
                    retargetedTouches.insert(touch)
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
                cleanUpTouch(touch)
                continue
            }

            // Variant picker commit path
            if let picker = pickerByTouch[touch] {
                let selected = picker.selectedVariant
                actionHandler?(.character(selected))
                noteCharacterCommitted(sample: nil)
                dismissPicker(for: touch)
                activeKeyByTouch[touch]?.setHighlighted(false)
                if activeKeyByTouch[touch]?.definition.action == .backspace { deleteEndedHandler?() }
                cleanUpTouch(touch)
                continue
            }

            if let kv = activeKeyByTouch[touch] {
                kv.setHighlighted(false)
                // An early-committed key's popup is already gone; the popup on
                // screen now belongs to the newer touch.
                if !earlyCommittedTouches.contains(touch) { hidePopup() }
                cancelLongPress(for: touch)

                // ONLY fire standard action if a gesture/long-press/early
                // commit didn't consume the touch
                if !swipeConsumedTouches.contains(touch) {
                    actionHandler?(kv.definition.action)
                    queueCalibrationSample(for: touch, key: kv)
                }

                if kv.definition.action == .backspace { deleteEndedHandler?() }
            }

            cleanUpTouch(touch)
        }
    }

    /// Queues a calibration sample for a committed character key, using the
    /// TOUCH-DOWN point. Touches that slid onto this key are queued as
    /// placeholders: their touch-down point belongs to a different key.
    private func queueCalibrationSample(for touch: UITouch, key kv: KeyView) {
        guard case .character = kv.definition.action else { return }
        var sample: CalibrationSample?
        if kv.definition.style == .standard,
           !retargetedTouches.contains(touch),
           let down = touchDownPoints[touch] {
            sample = CalibrationSample(point: down,
                                       center: CGPoint(x: kv.frame.midX, y: kv.frame.midY))
        }
        noteCharacterCommitted(sample: sample)
    }

    // ── Key order (rollover) ─────────────────

    /// When a new finger lands while earlier keys are still held, commit the
    /// earlier keys now (oldest first), as the system keyboard does.
    /// Otherwise fast two-thumb typing inserts in RELEASE order: press t,
    /// press h, lift h, lift t → "ht".
    ///
    /// Only plain character and space keys commit early. Keys in the middle
    /// of something (accent picker open, trackpad mode, swipe already fired)
    /// and keys with hold behaviour (backspace repeat, shift) are left alone.
    private func commitRolledOverTouches() {
        let pending = activeKeyByTouch
            .filter { touch, kv in
                !swipeConsumedTouches.contains(touch)
                    && pickerByTouch[touch] == nil
                    && !cursorModeTouches.contains(touch)
                    && Self.commitsOnRollover(kv.definition.action)
            }
            .sorted { (touchSequence[$0.key] ?? 0) < (touchSequence[$1.key] ?? 0) }

        for (touch, kv) in pending {
            cancelLongPress(for: touch)   // no accent picker / trackpad mode later
            kv.setHighlighted(false)
            hidePopup()
            actionHandler?(kv.definition.action)
            queueCalibrationSample(for: touch, key: kv)
            // Consumed: release won't fire again, and the touch no longer
            // swipes or slides onto other keys.
            swipeConsumedTouches.insert(touch)
            earlyCommittedTouches.insert(touch)
        }
    }

    private static func commitsOnRollover(_ action: KeyAction) -> Bool {
        switch action {
        case .character, .space: return true
        default:                 return false
        }
    }

    /// Removes every piece of per-touch tracking state.
    private func cleanUpTouch(_ touch: UITouch) {
        activeKeyByTouch.removeValue(forKey: touch)
        startTouchLocations.removeValue(forKey: touch)
        swipeConsumedTouches.remove(touch)
        overlappedTouches.remove(touch)
        touchDownPoints.removeValue(forKey: touch)
        retargetedTouches.remove(touch)
        contextByTouch.removeValue(forKey: touch)
        touchSequence.removeValue(forKey: touch)
        earlyCommittedTouches.remove(touch)
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

            cleanUpTouch(touch)
        }
        hidePopup()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Hit Testing (Gaussian + Containment + Hysteresis)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Initial hit test for touchesBegan. No hysteresis.
    private func hitKeyView(for touch: UITouch, context: BigramContext) -> KeyView? {
        bestKeyView(at: touch.location(in: self), currentKey: nil, context: context)
    }

    /// Hit test for touchesMoved. The active key keeps the touch until the
    /// finger is `hysteresisMargin` outside its cell.
    private func hitKeyViewForMove(for touch: UITouch, currentKey: KeyView?, context: BigramContext) -> KeyView? {
        bestKeyView(at: touch.location(in: self), currentKey: currentKey, context: context)
    }

    /// Picks the key for a touch point.
    ///
    /// 1. OWNERSHIP. Every key has a hit cell (its frame grown to the middle
    ///    of the surrounding gaps, so cells tile the keyboard). The key whose
    ///    cell contains the point owns it. A non-character key (shift,
    ///    backspace, space, utility…) only ever receives touches inside its
    ///    own cell, and a character key's cell can never be claimed by one.
    ///    (Previously modifiers scored ~0 in a 8–12pt band OUTSIDE their
    ///    frame, which beat letters near their own edges: the bottom of
    ///    z…m went to space/return, the top of the number row to the
    ///    utility row, the outer edges of z/m to shift/backspace.)
    ///
    /// 2. DISAMBIGUATION, character keys only. Neighbouring character keys
    ///    within `ambiguityBand` of the point compete with the owner on
    ///    Gaussian + bigram score. A neighbour pays a penalty that rises from
    ///    0 at the shared boundary to `containmentBonus` at the band's far
    ///    edge, so the language model only matters for genuinely ambiguous
    ///    touches.
    private func bestKeyView(at pt: CGPoint, currentKey: KeyView?, context: BigramContext) -> KeyView? {

        // Hysteresis (touchesMoved only)
        if let current = currentKey,
           current.hitRect.insetBy(dx: -hysteresisMargin, dy: -hysteresisMargin).contains(pt) {
            return current
        }

        guard let owner = keyViews.first(where: { $0.hitRect.contains(pt) }) else { return nil }
        guard owner.definition.style == .standard else { return owner }

        var bestKey = owner
        var bestScore = characterScore(for: owner, at: pt, context: context)

        for kv in keyViews where kv !== owner && kv.definition.style == .standard {
            let outside = Self.distance(from: pt, to: kv.hitRect)
            guard outside < ambiguityBand else { continue }
            let penalty = containmentBonus * (outside / ambiguityBand)
            let score = characterScore(for: kv, at: pt, context: context) - penalty
            if score > bestScore {
                bestScore = score
                bestKey = kv
            }
        }
        return bestKey
    }

    /// Gaussian log-probability of the point for this key, plus the bigram
    /// weight of the key's letter given the preceding text.
    private func characterScore(for kv: KeyView, at pt: CGPoint, context: BigramContext) -> CGFloat {
        var score = touchModel.logProbability(
            touchPoint: pt,
            keyCenter: CGPoint(x: kv.frame.midX, y: kv.frame.midY),
            keyWidth: kv.frame.width,
            scale: scale
        )
        if bigramInfluence > 0,
           case .character(let c) = kv.definition.action,
           c.count == 1,
           let next = c.lowercased().first {
            score += bigramModel.weight(context: context, next: next) * bigramInfluence
        }
        return score
    }

    /// Distance from a point to a rectangle (0 if inside).
    private static func distance(from pt: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - pt.x, 0, pt.x - rect.maxX)
        let dy = max(rect.minY - pt.y, 0, pt.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    // ── Swipe threshold ──────────────────────

    private func swipeThreshold(for kv: KeyView) -> CGFloat {
        max(minSwipeThreshold, kv.frame.height * swipeThresholdPerKeyHeight)
    }

    // ── Calibration queue ────────────────────

    /// Records that one character was inserted by this view. `sample` is nil
    /// when the character shouldn't train the model (accent picker, swipe
    /// alt-character, slid-onto key).
    private func noteCharacterCommitted(sample: CalibrationSample?) {
        pendingCalibration.append(sample)
        if pendingCalibration.count > calibrationCommitDelay {
            commit(pendingCalibration.removeFirst())
        }
    }

    /// Alt actions fired by swipe-down or long-press insert a character
    /// that has no calibration sample; keep the queue aligned with the text.
    private func noteAltActionCommitted(_ action: KeyAction) {
        if case .character = action { noteCharacterCommitted(sample: nil) }
    }

    private func commit(_ sample: CalibrationSample?) {
        guard let s = sample else { return }
        touchModel.recordCalibrationSample(touchPoint: s.point, keyCenter: s.center, scale: scale)
    }

    /// Call when ONE character before the cursor was deleted (backspace).
    /// Drops the sample for that character so the typo isn't learned.
    func calibrationCharacterDeleted() {
        if !pendingCalibration.isEmpty { pendingCalibration.removeLast() }
    }

    /// Call when the word is finished (space / return): the user accepted
    /// what they typed, so the pending samples are trustworthy.
    func calibrationCommitPending() {
        pendingCalibration.forEach(commit)
        pendingCalibration.removeAll()
    }

    /// Call when the text changed in a way the queue can't follow
    /// (word delete, cursor move, paste, macro, emoji). Drops pending samples.
    func calibrationDiscardPending() {
        pendingCalibration.removeAll()
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
                    self.noteAltActionCommitted(alt)
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

        // Visual cue: dim everything but the spacebar (both halves of a
        // split spacebar).
        UIView.animate(withDuration: 0.15) {
            for kv in self.keyViews where kv !== spacebar && kv.definition.action != .space {
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

        // Must not receive touches: if another finger lands on the picker,
        // its touch would be owned by this view and lost when it is removed.
        isUserInteractionEnabled = false
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
    /// Gap-filled touch target, in the keyboard's coordinate space.
    /// Set by KeyboardRenderView.layoutKeys().
    var hitRect: CGRect = .zero
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
        // Must not receive touches. The popup covers the row above the
        // pressed key; during two-thumb typing the other thumb lands on it,
        // and when the popup is removed that touch's touchesEnded never
        // reaches KeyboardRenderView — the keystroke is dropped, the key
        // stays highlighted, and per-touch state (timers, pickers) leaks.
        isUserInteractionEnabled = false
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
