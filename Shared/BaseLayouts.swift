// BaseLayouts.swift
// Hardcoded layout definitions — zero parsing overhead at launch.

import Foundation
import CoreGraphics

enum BaseLayouts {

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shared Row Fragments
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    // Reusable row definitions to avoid duplication across layouts.

    static let utilityRow = LayoutRow(keys: [
        KeyDefinition(id: "wordLeft",    label: "sf:chevron.left.2",        action: .moveCursorBackwardWord,  style: .utility),
        KeyDefinition(id: "wordRight",   label: "sf:chevron.right.2",       action: .moveCursorForwardWord,   style: .utility),
        KeyDefinition(id: "curLeft",     label: "sf:chevron.left",          action: .moveCursorBackward,      style: .utility),
        KeyDefinition(id: "curRight",    label: "sf:chevron.right",         action: .moveCursorForward,       style: .utility),
        KeyDefinition(id: "delWord",     label: "sf:delete.backward",       action: .deleteWord,              style: .utility),
        KeyDefinition(id: "delLine",     label: "sf:delete.backward.fill",  action: .deleteToLineStart,       style: .utility),
        KeyDefinition(id: "toggleCase",  label: "Aa",                       action: .toggleCase,              style: .utility),
        KeyDefinition(id: "copy",        label: "sf:doc.on.doc",            action: .copy,                    style: .utility),
        KeyDefinition(id: "paste",       label: "sf:doc.on.clipboard",      action: .paste,                   style: .utility),
    ], baseHeight: 38, tag: .utility)

    static let numberRow = LayoutRow(keys: [
        KeyDefinition(id: "1", label: "1", action: .character("1"), altAction: .character("!")),
        KeyDefinition(id: "2", label: "2", action: .character("2"), altAction: .character("@")),
        KeyDefinition(id: "3", label: "3", action: .character("3"), altAction: .character("#")),
        KeyDefinition(id: "4", label: "4", action: .character("4"), altAction: .character("$")),
        KeyDefinition(id: "5", label: "5", action: .character("5"), altAction: .character("%")),
        KeyDefinition(id: "6", label: "6", action: .character("6"), altAction: .character("^")),
        KeyDefinition(id: "7", label: "7", action: .character("7"), altAction: .character("&")),
        KeyDefinition(id: "8", label: "8", action: .character("8"), altAction: .character("*")),
        KeyDefinition(id: "9", label: "9", action: .character("9"), altAction: .character("(")),
        KeyDefinition(id: "0", label: "0", action: .character("0"), altAction: .character(")")),
    ], baseHeight: 42, tag: .number)

    static let topAlphaRow = LayoutRow(keys: [
        KeyDefinition(id: "q", label: "q", action: .character("q"), altAction: .character("+")),
        KeyDefinition(id: "w", label: "w", action: .character("w"), altAction: .character("=")),
        KeyDefinition(id: "e", label: "e", action: .character("e"), altAction: .character("\"")),
        KeyDefinition(id: "r", label: "r", action: .character("r"), altAction: .character("'")),
        KeyDefinition(id: "t", label: "t", action: .character("t"), altAction: .character(":")),
        KeyDefinition(id: "y", label: "y", action: .character("y"), altAction: .character(";")),
        KeyDefinition(id: "u", label: "u", action: .character("u"), altAction: .character("[")),
        KeyDefinition(id: "i", label: "i", action: .character("i"), altAction: .character("]")),
        KeyDefinition(id: "o", label: "o", action: .character("o"), altAction: .character("{")),
        KeyDefinition(id: "p", label: "p", action: .character("p"), altAction: .character("}")),
    ], baseHeight: 44, tag: .alpha)

    static let midAlphaRow = LayoutRow(keys: [
        KeyDefinition(id: "a", label: "a", action: .character("a"), altAction: .character("-")),
        KeyDefinition(id: "s", label: "s", action: .character("s"), altAction: .character("_")),
        KeyDefinition(id: "d", label: "d", action: .character("d"), altAction: .character("\\")),
        KeyDefinition(id: "f", label: "f", action: .character("f"), altAction: .character("|")),
        KeyDefinition(id: "g", label: "g", action: .character("g"), altAction: .character("~")),
        KeyDefinition(id: "h", label: "h", action: .character("h"), altAction: .character("<")),
        KeyDefinition(id: "j", label: "j", action: .character("j"), altAction: .character(">")),
        KeyDefinition(id: "k", label: "k", action: .character("k"), altAction: .character("?")),
        KeyDefinition(id: "l", label: "l", action: .character("l"), altAction: .character("/")),
    ], baseHeight: 44, tag: .alpha)

    static let bottomAlphaRow = LayoutRow(keys: [
        KeyDefinition(id: "shift", label: "sf:shift",       action: .shift,            widthMultiplier: 1.5, style: .modifier),
        KeyDefinition(id: "z",     label: "z",              action: .character("z"),   altAction: .character("`")),
        KeyDefinition(id: "x",     label: "x",              action: .character("x"),   altAction: .character("•")),
        KeyDefinition(id: "c",     label: "c",              action: .character("c"),   altAction: .character("§")),
        KeyDefinition(id: "v",     label: "v",              action: .character("v"),   altAction: .character("¶")),
        KeyDefinition(id: "b",     label: "b",              action: .character("b"),   altAction: .character("°")),
        KeyDefinition(id: "n",     label: "n",              action: .character("n"),   altAction: .character(",")),
        KeyDefinition(id: "m",     label: "m",              action: .character("m"),   altAction: .character(".")),
        KeyDefinition(id: "bksp",  label: "sf:delete.left", action: .backspace,        widthMultiplier: 1.5, style: .modifier),
    ], baseHeight: 44, tag: .alpha)

    /// Standard spacebar row (Period removed, Spacebar widened to 5.5)
    static let spacebarRow = LayoutRow(keys: [
        KeyDefinition(id: "symbols", label: "123",            action: .switchLayout(.symbols), widthMultiplier: 1.3, style: .modifier),
        KeyDefinition(id: "globe",   label: "sf:globe",       action: .nextKeyboard,           style: .modifier),
        KeyDefinition(id: "space",   label: " ",              action: .space, swipeUpAction: .dismissKeyboard, widthMultiplier: 5.5, style: .spacebar),
        KeyDefinition(id: "return",  label: "return",         action: .returnKey,              widthMultiplier: 1.5, style: .modifier),
    ], baseHeight: 44, tag: .bottom)

    /// Spacebar row variant with a utility-row toggle (Period removed, Spacebar widened to 4.8)
    static let spacebarRowWithToggle = LayoutRow(keys: [
        KeyDefinition(id: "utilToggle", label: "sf:slider.horizontal.3", action: .toggleUtilityRow, style: .utility),
        KeyDefinition(id: "symbols",    label: "123",            action: .switchLayout(.symbols), widthMultiplier: 1.2, style: .modifier),
        KeyDefinition(id: "globe",      label: "sf:globe",      action: .nextKeyboard,           style: .modifier),
        KeyDefinition(id: "space",      label: " ",             action: .space, swipeUpAction: .dismissKeyboard, widthMultiplier: 4.8, style: .spacebar),
        KeyDefinition(id: "return",     label: "return",        action: .returnKey,              widthMultiplier: 1.3, style: .modifier),
    ], baseHeight: 44, tag: .bottom)

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Standard QWERTY
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let standard = KeyboardLayout(
        id: .standard,
        displayName: "Standard",
        rows: [utilityRow, numberRow, topAlphaRow, midAlphaRow, bottomAlphaRow, spacebarRow]
    )

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Coding
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let codingUtilityRow = LayoutRow(keys: [
        KeyDefinition(id: "tab",       label: "TAB",                     action: .character("\t"),           style: .utility),
        KeyDefinition(id: "wordLeft",  label: "sf:chevron.left.2",       action: .moveCursorBackwardWord,   style: .utility),
        KeyDefinition(id: "wordRight", label: "sf:chevron.right.2",      action: .moveCursorForwardWord,    style: .utility),
        KeyDefinition(id: "curLeft",   label: "sf:chevron.left",         action: .moveCursorBackward,       style: .utility),
        KeyDefinition(id: "curRight",  label: "sf:chevron.right",        action: .moveCursorForward,        style: .utility),
        KeyDefinition(id: "delWord",   label: "sf:delete.backward",      action: .deleteWord,               style: .utility),
        KeyDefinition(id: "delLine",   label: "sf:delete.backward.fill", action: .deleteToLineStart,        style: .utility),
        KeyDefinition(id: "copy",      label: "sf:doc.on.doc",           action: .copy,                     style: .utility),
        KeyDefinition(id: "paste",     label: "sf:doc.on.clipboard",     action: .paste,                    style: .utility),
    ], baseHeight: 38, tag: .utility)

    static let codingBottomRow = LayoutRow(keys: [
        KeyDefinition(id: "shift",  label: "sf:shift",       action: .shift,            widthMultiplier: 1.2, style: .modifier),
        KeyDefinition(id: "z",      label: "z",              action: .character("z")),
        KeyDefinition(id: "x",      label: "x",              action: .character("x")),
        KeyDefinition(id: "c",      label: "c",              action: .character("c")),
        KeyDefinition(id: "v",      label: "v",              action: .character("v")),
        KeyDefinition(id: "b",      label: "b",              action: .character("b")),
        KeyDefinition(id: "n",      label: "n",              action: .character("n")),
        KeyDefinition(id: "m",      label: "m",              action: .character("m")),
        KeyDefinition(id: "under",  label: "_",              action: .character("_"),   altAction: .character("-")),
        KeyDefinition(id: "bksp",   label: "sf:delete.left", action: .backspace,        widthMultiplier: 1.2, style: .modifier),
    ], baseHeight: 44, tag: .alpha)

    static let codingSpacebarRow = LayoutRow(keys: [
        KeyDefinition(id: "symbols", label: "#+=",   action: .switchLayout(.symbols), widthMultiplier: 1.2, style: .modifier),
        KeyDefinition(id: "lbrace",  label: "{",     action: .character("{"),         altAction: .character("[")),
        KeyDefinition(id: "rbrace",  label: "}",     action: .character("}"),         altAction: .character("]")),
        KeyDefinition(id: "space",   label: " ",     action: .space, swipeUpAction: .dismissKeyboard, widthMultiplier: 3.0, style: .spacebar),
        KeyDefinition(id: "semi",    label: ";",     action: .character(";"),         altAction: .character(":")),
        KeyDefinition(id: "slash",   label: "/",     action: .character("/"),         altAction: .character("\\")),
        KeyDefinition(id: "eq",      label: "=",     action: .character("="),         altAction: .character("+")),
        KeyDefinition(id: "return",  label: "sf:return", action: .returnKey,          widthMultiplier: 1.2, style: .modifier),
    ], baseHeight: 44, tag: .bottom)

    static let coding = KeyboardLayout(
        id: .coding,
        displayName: "Coding",
        rows: [codingUtilityRow, numberRow, topAlphaRow, midAlphaRow, codingBottomRow, codingSpacebarRow]
    )

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Markdown
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let markdownUtilityRow = LayoutRow(keys: [
        KeyDefinition(id: "heading",   label: "H#",               action: .insertMacro("md_heading"),   style: .utility),
        KeyDefinition(id: "bold",      label: "sf:bold",          action: .insertMacro("md_bold"),      style: .utility),
        KeyDefinition(id: "italic",    label: "sf:italic",        action: .insertMacro("md_italic"),    style: .utility),
        KeyDefinition(id: "code",      label: "</>",              action: .insertMacro("md_code"),      style: .utility),
        KeyDefinition(id: "codeBlock", label: "```",              action: .insertMacro("md_codeblock"), style: .utility),
        KeyDefinition(id: "link",      label: "sf:link",          action: .insertMacro("md_link"),      style: .utility),
        KeyDefinition(id: "list",      label: "sf:list.bullet",   action: .insertMacro("md_list"),      style: .utility),
        KeyDefinition(id: "quote",     label: "sf:text.quote",    action: .insertMacro("md_quote"),     style: .utility),
        KeyDefinition(id: "hr",        label: "───",              action: .insertMacro("md_hr"),        style: .utility),
    ], baseHeight: 38, tag: .utility)

    static let markdown = KeyboardLayout(
        id: .markdown,
        displayName: "Markdown",
        rows: [markdownUtilityRow, numberRow, topAlphaRow, midAlphaRow, bottomAlphaRow, spacebarRow]
    )

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Symbols
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let symbols = KeyboardLayout(
        id: .symbols,
        displayName: "Symbols",
        rows: [
            utilityRow,
            numberRow,
            LayoutRow(keys: [
                KeyDefinition(id: "at",     label: "@",  action: .character("@")),
                KeyDefinition(id: "hash",   label: "#",  action: .character("#")),
                KeyDefinition(id: "dollar", label: "$",  action: .character("$")),
                KeyDefinition(id: "amp",    label: "&",  action: .character("&")),
                KeyDefinition(id: "star",   label: "*",  action: .character("*")),
                KeyDefinition(id: "lparen", label: "(",  action: .character("(")),
                KeyDefinition(id: "rparen", label: ")",  action: .character(")")),
                KeyDefinition(id: "squot",  label: "'",  action: .character("'"), altAction: .character("`")),
                KeyDefinition(id: "dquot",  label: "\"", action: .character("\""))
            ], baseHeight: 44, tag: .alpha),
            LayoutRow(keys: [
                KeyDefinition(id: "pct",    label: "%",  action: .character("%")),
                KeyDefinition(id: "minus",  label: "-",  action: .character("-"), altAction: .character("–")),
                KeyDefinition(id: "plus",   label: "+",  action: .character("+")),
                KeyDefinition(id: "eq",     label: "=",  action: .character("=")),
                KeyDefinition(id: "pipe",   label: "|",  action: .character("|")),
                KeyDefinition(id: "lbrack", label: "[",  action: .character("[")),
                KeyDefinition(id: "rbrack", label: "]",  action: .character("]")),
                KeyDefinition(id: "lbrace", label: "{",  action: .character("{")),
                KeyDefinition(id: "rbrace", label: "}",  action: .character("}")),
            ], baseHeight: 44, tag: .alpha),
            LayoutRow(keys: [
                KeyDefinition(id: "shift",  label: "sf:shift",       action: .shift,            widthMultiplier: 1.5, style: .modifier),
                KeyDefinition(id: "tilde",  label: "~",              action: .character("~")),
                KeyDefinition(id: "lt",     label: "<",              action: .character("<")),
                KeyDefinition(id: "gt",     label: ">",              action: .character(">")),
                KeyDefinition(id: "excl",   label: "!",              action: .character("!")),
                KeyDefinition(id: "ques",   label: "?",              action: .character("?")),
                KeyDefinition(id: "bslash", label: "\\",             action: .character("\\")),
                KeyDefinition(id: "bksp",   label: "sf:delete.left", action: .backspace,        widthMultiplier: 1.5, style: .modifier),
            ], baseHeight: 44, tag: .alpha),
            LayoutRow(keys: [
                KeyDefinition(id: "abc",     label: "ABC",   action: .switchLayout(.standard), widthMultiplier: 1.3, style: .modifier),
                KeyDefinition(id: "globe",   label: "sf:globe", action: .nextKeyboard,         style: .modifier),
                KeyDefinition(id: "space",   label: " ",     action: .space,                   widthMultiplier: 4.5, style: .spacebar),
                KeyDefinition(id: "comma",   label: ",",     action: .character(","),           altAction: .character(";")),
                KeyDefinition(id: "return",  label: "return",action: .returnKey,                widthMultiplier: 1.5, style: .modifier),
            ], baseHeight: 44, tag: .bottom),
        ]
    )

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Registry
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let all: [LayoutID: KeyboardLayout] = [
        .standard: standard,
        .coding:   coding,
        .markdown: markdown,
        .symbols:  symbols,
    ]

    /// Returns the layout with the spacebar row swapped for the toggle variant when in 5-row mode.
    static func layout(for id: LayoutID, rowMode: RowMode) -> KeyboardLayout {
        guard var layout = all[id] else { return standard }
        
        if rowMode == .fiveRows {
            var rows = layout.rows
            if let idx = rows.lastIndex(where: { $0.tag == .bottom }) {
                let original = rows[idx]
                var keys = original.keys
                
                // Inject toggle button as first key if not already present
                if !keys.contains(where: { $0.id == "utilToggle" }) {
                    let toggleKey = KeyDefinition(
                        id: "utilToggle",
                        label: "sf:slider.horizontal.3",
                        action: .toggleUtilityRow,
                        style: .utility
                    )
                    keys.insert(toggleKey, at: 0)
                    
                    // Rebuild the spacebar to shrink it AND preserve its swipe action
                    keys = keys.map { k in
                        if k.id == "space" {
                            return KeyDefinition(
                                id: k.id,
                                label: k.label,
                                action: k.action,
                                altAction: k.altAction,
                                swipeUpAction: k.swipeUpAction, // <--- PRESERVES THE GESTURE
                                widthMultiplier: max(k.widthMultiplier - 1.0, 3.5),
                                style: k.style
                            )
                        }
                        return k
                    }
                    rows[idx] = LayoutRow(keys: keys, baseHeight: original.baseHeight, tag: original.tag)
                }
            }
            layout = KeyboardLayout(id: layout.id, displayName: layout.displayName, rows: rows)
        }
        return layout
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Built-In Macros
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum BuiltInMacros {
    static let expansions: [String: String] = [
        "md_heading":   "## ",
        "md_bold":      "****",
        "md_italic":    "__",
        "md_code":      "``",
        "md_codeblock": "```\n\n```",
        "md_link":      "[](url)",
        "md_list":      "- ",
        "md_quote":     "> ",
        "md_hr":        "\n---\n",
    ]

    /// Macros that need the cursor repositioned after insertion.
    /// Value = number of characters to move back from end.
    static let cursorOffsets: [String: Int] = [
        "md_bold":      2,   // place cursor between ** **
        "md_italic":    1,
        "md_code":      1,
        "md_codeblock": 4,   // place cursor on the blank line
        "md_link":      5,   // place cursor inside []
    ]
}
