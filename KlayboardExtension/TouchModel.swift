// TouchModel.swift
// Gaussian touch probability model for geometric key disambiguation.
//
// Instead of binary hit-testing (touch inside rectangle → key, else → nil),
// this models the user's finger as a 2D Gaussian distribution and scores
// each key by the probability that the user intended it. When a touch lands
// on the boundary between two keys, the key with the higher probability wins.
//
// SCALE-AWARE: The vertical spread (σy) scales inversely with the keyboard
// height scale factor. When keys are compressed (0.75×–0.80×), the Gaussian
// widens vertically to compensate — because the user's finger doesn't shrink
// with the keyboard. Horizontal spread (σx) is unaffected because key WIDTH
// is determined by screen width and doesn't change with scale.
//
// CALIBRATION PERSISTENCE: The learned offset survives extension termination.
// It is saved to App Group UserDefaults every `saveInterval` samples and
// loaded once when the render view is created. The EMA converges over ~100
// samples; without persistence the extension is usually killed first.
//

import CoreGraphics
import Foundation

struct TouchModel {

    // ── Gaussian Base Parameters ────────────────────

    /// Base horizontal spread (σx). Thumbs are wider than they are tall,
    /// so horizontal error tolerance is larger. This does NOT scale with
    /// keyboard height because key width is always derived from screen width.
    var baseSigmaX: CGFloat = 9.0

    /// Base vertical spread (σy) at scale 1.0. Adjusted at runtime by
    /// dividing by the current keyboard scale factor — smaller keys get
    /// a proportionally wider Gaussian because the finger stays the same size.
    var baseSigmaY: CGFloat = 7.5

    /// Base vertical bias at scale 1.0: users consistently hit slightly below
    /// key center because the thumb approaches from the bottom of the screen.
    var baseYBias: CGFloat = 2.0

    /// Per-user calibration offset, learned from typing history.
    /// Applied to every touch point before scoring.
    var calibrationOffset: CGPoint = .zero

    // ── Persistence ─────────────────────────────────

    private static let calibrationXKey = "touchCalibrationOffsetX"
    private static let calibrationYKey = "touchCalibrationOffsetY"

    /// Save to App Group UserDefaults every N samples. Keeps write volume low
    /// while guaranteeing at most N samples of learning are lost on jetsam.
    private static let saveInterval = 15
    private var samplesSinceSave = 0

    /// Hard cap on offset magnitude. Calibration corrects grip bias, which is
    /// a few points; anything larger is drift or corrupted state and would
    /// misdirect every touch on the keyboard.
    private static let maxOffsetMagnitude: CGFloat = 8.0

    // ── Scoring ─────────────────────────────────────

    /// Returns the log-probability that a touch at `touchPoint` was aimed at `keyCenter`.
    /// Higher (closer to 0) = more likely. All values are ≤ 0.
    func logProbability(touchPoint: CGPoint, keyCenter: CGPoint, scale: CGFloat = 1.0) -> CGFloat {
        let adjustedX = touchPoint.x - calibrationOffset.x
        let adjustedY = touchPoint.y - calibrationOffset.y

        // σx stays constant (key width doesn't change with scale)
        // σy widens as keys get shorter (divide by scale)
        // yBias shrinks proportionally (multiply by scale)
        let clampedScale = max(scale, 0.5)
        let sx = baseSigmaX
        let sy = baseSigmaY / clampedScale
        let yb = baseYBias * clampedScale

        let dx = adjustedX - keyCenter.x
        let dy = adjustedY - (keyCenter.y + yb)

        let exponent = -0.5 * ((dx * dx) / (sx * sx)
                              + (dy * dy) / (sy * sy))
        return exponent
    }

    // ── Calibration ─────────────────────────────────

    /// Exponential moving average weight. Higher = adapts faster but more jittery.
    private static let emaAlpha: CGFloat = 0.025

    /// Updates the calibration offset based on a confirmed keystroke.
    /// Call this after a character key is tapped (not for modifiers/spacebar/delete).
    mutating func recordCalibrationSample(touchPoint: CGPoint, keyCenter: CGPoint) {
        let dx = touchPoint.x - keyCenter.x
        let dy = touchPoint.y - keyCenter.y

        var newX = calibrationOffset.x + Self.emaAlpha * (dx - calibrationOffset.x)
        var newY = calibrationOffset.y + Self.emaAlpha * (dy - calibrationOffset.y)

        newX = min(max(newX, -Self.maxOffsetMagnitude), Self.maxOffsetMagnitude)
        newY = min(max(newY, -Self.maxOffsetMagnitude), Self.maxOffsetMagnitude)
        calibrationOffset = CGPoint(x: newX, y: newY)

        samplesSinceSave += 1
        if samplesSinceSave >= Self.saveInterval {
            samplesSinceSave = 0
            saveCalibration()
        }
    }

    // ── Load / Save / Reset ─────────────────────────

    /// Loads the persisted offset. Call once when the render view is created.
    mutating func loadCalibration() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID),
              let x = defaults.object(forKey: Self.calibrationXKey) as? Double,
              let y = defaults.object(forKey: Self.calibrationYKey) as? Double else { return }
        calibrationOffset = CGPoint(
            x: min(max(CGFloat(x), -Self.maxOffsetMagnitude), Self.maxOffsetMagnitude),
            y: min(max(CGFloat(y), -Self.maxOffsetMagnitude), Self.maxOffsetMagnitude)
        )
    }

    func saveCalibration() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID) else { return }
        defaults.set(Double(calibrationOffset.x), forKey: Self.calibrationXKey)
        defaults.set(Double(calibrationOffset.y), forKey: Self.calibrationYKey)
    }

    /// Resets calibration to zero and clears persisted state.
    /// The Settings app can achieve the same by removing both keys from the
    /// App Group suite; the extension picks that up on its next cold launch.
    mutating func resetCalibration() {
        calibrationOffset = .zero
        samplesSinceSave = 0
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID) else { return }
        defaults.removeObject(forKey: Self.calibrationXKey)
        defaults.removeObject(forKey: Self.calibrationYKey)
    }
}
