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

import CoreGraphics

struct TouchModel {

    // ── Gaussian Base Parameters ────────────────────
    // These define the probability cloud at scale = 1.0.
    // At other scales, σy is adjusted dynamically (see logProbability).

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
    /// Scaled proportionally with keyboard height so the bias doesn't
    /// overshoot on compact layouts.
    var baseYBias: CGFloat = 2.0

    /// Per-user calibration offset, learned from typing history.
    /// Applied to every touch point before scoring.
    var calibrationOffset: CGPoint = .zero

    // ── Scoring ─────────────────────────────────────

    /// Returns the log-probability that a touch at `touchPoint` was aimed at `keyCenter`.
    ///
    /// - Parameter scale: The current keyboard height scale factor (0.75 … 1.4).
    ///   At 1.0, base sigma values are used directly. At lower scales, σy widens
    ///   inversely to compensate for compressed row height. At higher scales, σy
    ///   tightens slightly for more precision on oversized keys.
    ///
    /// Uses log-probability instead of raw probability because:
    /// 1. It avoids floating-point underflow for distant keys
    /// 2. Comparison uses simple > instead of multiplying tiny numbers
    /// 3. The normalization constant cancels out (same for all keys), so we skip it
    ///
    /// Higher (closer to 0) = more likely. All values are ≤ 0.
    func logProbability(touchPoint: CGPoint, keyCenter: CGPoint, scale: CGFloat = 1.0) -> CGFloat {
        let adjustedX = touchPoint.x - calibrationOffset.x
        let adjustedY = touchPoint.y - calibrationOffset.y

        // Scale-adjusted parameters:
        // σx stays constant (key width doesn't change with scale)
        // σy widens as keys get shorter (divide by scale)
        // yBias shrinks proportionally (multiply by scale)
        let clampedScale = max(scale, 0.5)  // safety floor to avoid division issues
        let sx = baseSigmaX
        let sy = baseSigmaY / clampedScale
        let yb = baseYBias * clampedScale

        let dx = adjustedX - keyCenter.x
        let dy = adjustedY - (keyCenter.y + yb)

        // Standard Gaussian exponent: -0.5 * ((dx/σx)² + (dy/σy)²)
        let exponent = -0.5 * ((dx * dx) / (sx * sx)
                              + (dy * dy) / (sy * sy))
        return exponent
    }

    // ── Calibration ─────────────────────────────────

    /// Exponential moving average weight. Higher = adapts faster but more jittery.
    private static let emaAlpha: CGFloat = 0.025

    /// Updates the calibration offset based on a confirmed keystroke.
    /// Call this after a character key is tapped (not for modifiers/spacebar/delete).
    ///
    /// `touchPoint`: where the finger actually landed
    /// `keyCenter`:  the center of the key that was selected
    mutating func recordCalibrationSample(touchPoint: CGPoint, keyCenter: CGPoint) {
        let dx = touchPoint.x - keyCenter.x
        let dy = touchPoint.y - keyCenter.y

        // Exponential moving average — converges quickly, adapts to grip changes
        calibrationOffset = CGPoint(
            x: calibrationOffset.x + Self.emaAlpha * (dx - calibrationOffset.x),
            y: calibrationOffset.y + Self.emaAlpha * (dy - calibrationOffset.y)
        )
    }

    /// Resets calibration to zero. Called from Settings → "Reset Typing Calibration".
    mutating func resetCalibration() {
        calibrationOffset = .zero
    }
}
