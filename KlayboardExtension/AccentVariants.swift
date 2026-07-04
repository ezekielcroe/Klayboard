//
//  AccentVariants.swift
//  Klayboard
//
//  Created by Yeo Zhi Zheng on 5/7/26.
//


// AccentVariants.swift
// Variant sets for the long-press picker: accents plus macOS Option-key
// characters (Opt+p = π, Opt+g = ©, Opt+v = √, …).
//
// The base character is always the FIRST entry, so a long-press released
// without horizontal movement inserts the plain letter.
//
// DEAD KEYS EXCLUDED: on macOS, Opt+e/i/n/u/h/k produce combining dead keys
// (´ ˆ ˜ ¨ ˙ ˚) whose end products (é î ñ ü …) are already in these sets.
// The standalone spacing accents are close to useless in running text, so
// they are omitted; h and k therefore have no variant set and keep their
// altAction long-press.
//
// Variants are stored lowercase where case exists. `shiftedDisplay(_:)`
// handles caseless symbols and the ß/µ special cases (String.uppercased()
// turns ß into "SS" and µ into Greek capital Μ).

import Foundation

enum AccentVariants {

    private static let table: [Character: [String]] = [
        "a": ["a", "à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "b": ["b", "∫"],
        "c": ["c", "ç", "ć", "č"],
        "d": ["d", "∂"],
        "e": ["e", "è", "é", "ê", "ë", "ē", "ė", "ę"],
        "f": ["f", "ƒ"],
        "g": ["g", "©"],
        "i": ["i", "î", "ï", "í", "ī", "į", "ì"],
        "j": ["j", "∆"],
        "l": ["l", "ł", "¬"],
        "m": ["m", "µ"],
        "n": ["n", "ñ", "ń"],
        "o": ["o", "ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"],
        "p": ["p", "π"],
        "q": ["q", "œ"],
        "r": ["r", "®"],
        "s": ["s", "ß", "ś", "š"],
        "t": ["t", "†"],
        "u": ["u", "û", "ü", "ù", "ú", "ū"],
        "v": ["v", "√"],
        "w": ["w", "∑"],
        "x": ["x", "≈"],
        "y": ["y", "ÿ", "¥"],
        "z": ["z", "ž", "ź", "ż", "Ω"],
    ]

    /// Returns the variant set for a single-character key string, or nil if
    /// the key has no variants (long-press then falls back to altAction).
    static func variants(for keyCharacter: String) -> [String]? {
        guard keyCharacter.count == 1,
              let first = keyCharacter.lowercased().first else { return nil }
        return table[first]
    }

    /// Display/commit form when shift or caps lock is active.
    /// Symbols and already-uppercase entries pass through unchanged.
    static func shiftedDisplay(_ variant: String) -> String {
        switch variant {
        case "ß": return "ẞ"
        case "µ": return "µ"
        default:
            let upper = variant.uppercased()
            // Multi-character expansions (ligature edge cases) stay lowercase.
            return upper.count == variant.count ? upper : variant
        }
    }
}