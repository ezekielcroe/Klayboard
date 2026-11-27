// SplitLayout.swift
// Two-half key layout for wide keyboards, such as the unfolded iPhone Duo.
//
// A full-width keyboard on a ~950pt screen has ~90pt letter keys and puts
// the middle of every row out of thumb reach. When the keyboard is wide
// enough, each row is cut at its width midpoint and the two halves are
// pushed to the outer edges with an empty gap between them. Key sizes and
// row geometry are otherwise the same as a contiguous keyboard of the
// halves' combined width, so muscle memory carries over.

import CoreGraphics

enum SplitLayout {

    /// Usable keyboard width (after safe-area insets) at which rows split.
    /// Every iPhone, and the Duo's outer screen (466pt), stays below this.
    static let minimumWidth: CGFloat = 600

    /// Share of the usable width taken by the two halves together at the
    /// default gap. The rest is the center gap.
    static let keyAreaFraction: CGFloat = 1 - CGFloat(UserConfiguration.defaultSplitGap)

    /// Upper bound on the halves' combined width at the default gap, so very
    /// wide keyboards widen the gap rather than the keys. Scales with the
    /// user's gap setting, so the slider still has an effect there.
    static let maxKeyAreaWidth: CGFloat = 620

    /// A spacebar straddling the midpoint is only cut in two if each half is
    /// at least this many width units. Any other straddling key goes whole
    /// to the side holding more of it.
    private static let minimumPieceUnits: CGFloat = 1.0

    static func shouldSplit(usableWidth: CGFloat, enabled: Bool) -> Bool {
        enabled && usableWidth >= minimumWidth
    }

    /// Combined width of the two halves for a given usable width and gap
    /// (the share of the width left empty in the middle).
    static func keyAreaWidth(
        usableWidth: CGFloat,
        gap: CGFloat = CGFloat(UserConfiguration.defaultSplitGap)
    ) -> CGFloat {
        let fraction = 1 - gap
        return min(usableWidth * fraction, maxKeyAreaWidth * fraction / keyAreaFraction)
    }

    /// Splits a row at its width midpoint.
    ///
    /// Returns the keys to render and the index of the first key in the
    /// right half. A spacebar that straddles the midpoint becomes two equal
    /// spacebars, one per half, so each thumb has its own; any other
    /// straddling key goes whole to one side.
    static func split(_ row: LayoutRow) -> (keys: [KeyDefinition], rightStart: Int) {
        let keys = row.keys
        let total = keys.reduce(CGFloat(0)) { $0 + $1.widthMultiplier }
        let mid = total / 2
        let epsilon: CGFloat = 0.001

        var start: CGFloat = 0
        for (i, key) in keys.enumerated() {
            let end = start + key.widthMultiplier
            if end <= mid + epsilon {
                start = end
                continue
            }
            if start >= mid - epsilon {
                return (keys, i)
            }

            // A spacebar is cut at its own center, not the row's, so both
            // thumbs get the same amount of space. The row's halves end up
            // slightly unequal, which only moves the inner edge of that row.
            let halfSpace = key.widthMultiplier / 2
            if key.style == .spacebar, halfSpace >= minimumPieceUnits {
                let halves = [
                    key.resized(id: key.id + ".left", widthMultiplier: halfSpace),
                    key.resized(id: key.id + ".right", widthMultiplier: halfSpace),
                ]
                return (Array(keys[..<i]) + halves + Array(keys[(i + 1)...]), i + 1)
            }
            let leftPart = mid - start
            let rightPart = end - mid
            return (keys, leftPart >= rightPart ? i + 1 : i)
        }
        return (keys, keys.count)
    }
}

private extension KeyDefinition {
    func resized(id: String, widthMultiplier: CGFloat) -> KeyDefinition {
        KeyDefinition(
            id: id,
            label: label,
            action: action,
            altAction: altAction,
            swipeUpAction: swipeUpAction,
            widthMultiplier: widthMultiplier,
            style: style
        )
    }
}
