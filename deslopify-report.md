# Deslopify report: Klayboard

## Summary

Klayboard is a custom iOS keyboard for power typists: a keyboard extension (`KlayboardExtension`) plus a container app (`Klayboard`) for onboarding and settings. It is live on the App Store, so changes here reach real users' typing.

**Overall state: healthy for a vibe-coded project, now with a safety net.** The code was already readable and well commented, with no secrets, no `TODO`s, no swallowed errors beyond two deliberate fallbacks, and no compiler warnings in a normal build. The serious problems were in the **text-expansion (macro) engine**, which could delete text you had typed in some everyday situations, and in **data shared between the app and the keyboard**, where clearing clipboard history in the app could be undone. Both are fixed.

**Numbers:** 50 tests added (previously none). 10 bugs fixed, 2 build-config problems fixed, 4 behaviour-preserving cleanups. Nothing is Critical in the security sense (the app has no network code and no accounts), but the first macro bug changed or deleted text you had typed, which is the worst thing a keyboard can do.

**Scope agreed in intake**
- Change level: **Clean and fix**. Safe cleanup, tests and bug fixes; unclear intent comes back as a question; UX ideas are proposed, not built.
- Critical flows: typing itself, **gestures and accents**, **macros and clipboard**, **settings sync** (app → keyboard). Onboarding wasn't marked critical but was checked on the iPhone Duo.
- Git: the iPhone Duo work is on branch `iphone-duo` (1 commit on top of `main`). This pass is on `deslopify/2026-11-27`, branched from it, one commit per change. Nothing is pushed or merged.
- `FullProjectSource.txt` and `mergecode.py` are untouched and now ignored by git.

**Not covered:** the touch-targeting maths (`TouchModel`, `BigramModel` weights, hit-testing in `KeyboardRenderView`) has no unit tests. It's tightly bound to `UITouch` and was tuned by hand, so I left it alone rather than risk changing how typing feels. The emoji and clipboard panels were read but not exercised in the simulator.

## How to run and verify

- **App + keyboard:** open `Klayboard.xcodeproj`, run the `Klayboard` scheme, then add the keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard.
- **Tests:** `scripts/test.sh` (defaults to the "iPhone 17" simulator; pass another name, e.g. `scripts/test.sh "iPhone Duo"`). 50 tests, all passing.

## Inventory

| | |
|---|---|
| Stack | Swift, UIKit, programmatic UI (no storyboards). Xcode project with file-system-synchronised groups. |
| Targets | `Klayboard` (container app, iOS 17.6+), `KlayboardExtension` (keyboard, iOS 15.6+). `Shared/` is compiled into both. |
| Storage | App Group `group.com.GeekyZeke.Klayboard` UserDefaults: `userConfiguration` (JSON), `clipboardHistory`, `emojiRecents`, touch calibration, onboarding flags. |
| Network / external services | None. |
| Keyboard pieces | `KeyboardViewController` (actions, text tracking), `KeyboardRenderView` (layout, touch model, gestures), `MacroEngine`, `CursorEngine`, `ClipboardHistory`, `TouchModel`, `BigramModel`, `AccentVariants`, `SplitLayout`, emoji and clipboard panels. |
| App screens | Onboarding (5 pages), Settings (table), Customize Keys. |

## Changes made

All on `deslopify/2026-11-27`, oldest first.

| Commit | Kind | What and why |
|---|---|---|
| Ignore local source-bundling helper files | Config | Keeps `FullProjectSource.txt` / `mergecode.py` out of git. |
| Add characterisation tests for keyboard logic | Tests | See "Tests added". |
| Remove unused code and per-user Xcode files | Cleanup (behaviour-preserving) | Deleted `spacebarRowWithToggle`, `AppConstants.feedbackChanged`, `ClipboardHistory.removeItem(at:)` / `isEmpty` / `count`, `TouchModel.resetCalibration()`, a duplicated file header; stopped tracking `xcuserdata/`. |
| Share override matching and the clipboard storage key | Cleanup (behaviour-preserving) | Five hand-copied "does this override apply to this layout" checks → `UserOverride.applies(to:)` / `targets(_:in:)`. Clipboard storage key moved to `AppConstants`. |
| Fix README project name and document the tests | Docs | README said `.xcworkspace`; there's only `.xcodeproj`. |
| Rename EmojiPickerViewDelegate.swift | Cleanup (behaviour-preserving) | File holds `EmojiPickerView`. |
| Fix macros firing on deleted / moved-away text | **Bug fix** | See bug 1. |
| Fix long and overlapping macro triggers | **Bug fix** | Bugs 2 and 3. |
| Fix clipboard history reappearing after "Clear" | **Bug fix** | Bug 4. |
| Fix key customizer ignoring the Grouped scheme | **Bug fix** | Bug 5. |
| Fix case toggle stuck on one-letter words | **Bug fix** | Bug 6. |
| Fix 5-row mode widening the Coding spacebar | **Bug fix** | Bug 7. |
| Match the extension's version to the app | Config fix | Extension was 1.5 (build 2) inside app 1.6 (build 1); App Store Connect flags this. Now 1.6 (1). |
| Remove launch-screen setting for a missing storyboard | Config fix | `UILaunchScreen` in the plist already provides the launch screen. |
| Let constraints size the keyboard during rotation / fold | Cleanup | `viewWillTransition` set a frame on a constraint-laid-out view. Verified by unfolding the Duo simulator with the keyboard open. |
| Small UX improvements (agreed) | UX | Recommendations 2, 3, 5 and 6, plus three issues found while checking them: see the UX section. |
| Fix the Markdown layout's missing icon | **Bug fix** | Bug 8. |

## Bugs found

| # | Severity | What happens | Where | Status |
|---|---|---|---|---|
| 1 | **High** | With a macro like `zz`: type `hi zq`, **hold** backspace to delete `zq`, type `z`. The keyboard thought you'd typed `zz` and deleted 2 characters (your `z` *and the space*), giving `hiEXPANDED`. The same happened after tapping elsewhere in the text, or using the emoji panel's ⌫. In short, macros could eat text you typed. | `KeyboardViewController` (macro buffer not updated on repeat-delete / cursor moves) | **Fixed**, and checked by hand in the simulator: now gives `hi z`, and `hi zz` still expands correctly. |
| 2 | Medium | Macro triggers longer than 15 characters never fired. | `MacroEngine` | **Fixed** (test) |
| 3 | Medium | If two triggers overlap (`ab` and `cab`), which one fired was random from launch to launch. Now the longest wins. | `MacroEngine` | **Fixed** (test) |
| 4 | Medium | "Clear Clipboard History" in the app was undone the next time you copied something with the keyboard; the old items (possibly passwords or addresses) came back. | `ClipboardHistory` | **Fixed** (test) |
| 5 | Medium | With the Grouped symbol scheme on, Customize Keys showed Familiar symbols, and saving a key silently replaced its Grouped swipe-down symbol with the Familiar one. | `KeyCustomizationViewController` | **Fixed** |
| 6 | Low | The `Aa` key on a one-letter word (`a` → `A`) could never get back to lowercase. | `CursorEngine.toggleCase` | **Fixed** (test) |
| 7 | Low | In 5-row mode the Coding layout's spacebar got *wider* (3 → 3.5 units), squeezing the bracket and symbol keys. | `BaseLayouts.layout(for:)` | **Fixed** (test) |
| 8 | Low | The Coding layout's "switch to Markdown" key and the Markdown row in Settings used an icon name that doesn't exist (`text.format`), so both showed blank. | `BaseLayouts`, `SettingsViewController` | **Fixed** (test checks every key icon exists) |
| 9 | Low | Settings reused table cells without clearing them, so after a reload a switch could appear on the wrong row (seen on "Clear Clipboard History"). | `SettingsViewController` | **Fixed** |
| 10 | Low | In Customize Keys the keyboard covered the edit fields and Save button, and the page couldn't scroll them into view. | `KeyCustomizationViewController` | **Fixed** |

## Questions for you

1. **Settings that fail to load reset everything.** If the saved settings ever fail to decode (for example, a future version adds a field the wrong way), the keyboard and app silently fall back to defaults, and the next change you make in the app saves over the old data, so **all macros and key customizations are lost**. I made the new split setting safe, and there's a test for that. Want me to make loading more forgiving (decode field by field, keep the old data if it can't be read)? Medium effort.
2. **Cut action.** `.cut` is still handled in the keyboard, but no key uses it (a code comment says it was removed because it could delete text it never saved). Delete the handler, or keep it for later?
3. **Editing a macro re-enables it.** Macros have an on/off flag, and disabled ones show greyed out, but there's no switch in the app, and editing a macro always saves it as enabled. Is there meant to be an on/off switch?
4. **Key customization only covers the default layout.** Customize Keys edits whichever layout is the "Default Layout". To customize the Coding layout you have to make it your default first. Intended?

## Tests added

`Tests/KlayboardCoreTests`, run with `scripts/test.sh`. A small `Package.swift` compiles the same source files the keyboard ships, so the tests exercise real keyboard code. The Xcode project is unchanged by this.

| Suite | Covers |
|---|---|
| Macro engine (8) | expansion, partial triggers, backspace, reset, disabled macros, named Markdown macros + cursor placement, long triggers, overlapping triggers |
| Cursor engine (12) | word jumps, delete word, delete to line start, case cycling (incl. one-letter words), shift-tab |
| Key icons (1) | every SF Symbol a key uses exists |
| Layouts and overrides (9) | 5/6-row visibility, toggle key injection, spacebar width, heights, removing the globe key, per-layout overrides, alt schemes |
| Wide-screen split (6) | when to split, width cap, where rows split, equal spacebar halves, no keys lost in any layout |
| Saved configuration (4) | round trip, loading settings saved before the split option existed, corrupt data fallback, height clamp |
| Clipboard history (6) | ordering, de-dupe, 15-item cap, empty / oversized items, relaunch, clear from the app sticks |
| Accents and context (4) | variant sets, shifted forms (ß → ẞ), bigram context |

## Remaining cleanup

| Item | Why not done | Effort |
|---|---|---|
| Swift 6 concurrency warnings (~40 with strict checking: timers in `KeyboardRenderView`, `KeyboardViewController`, onboarding). | They're harmless today (everything runs on the main thread) and only appear with stricter checks turned on; fixing them touches the touch and timer code in the critical typing path. Best done as its own change with careful typing tests. | Medium |
| `OnboardingViewController.swift` is ~1,240 lines holding 5 page classes. | Natural split into one file per page, but it's not critical and moving code makes the history harder to follow. Happy to do it if you want. | Small |
| `KeyboardRenderView.swift` (~1,180 lines) also holds `VariantPickerView`, `KeyView`, `KeyPopupView`. | Same as above. | Small |
| No tests for touch targeting (`TouchModel`, hit-testing). | Bound to `UITouch`; would need a refactor to test. | Medium–large |

## UX/UI recommendations

Ordered by impact on the critical flows.

| # | Issue | Suggested change | Effort | Status |
|---|---|---|---|---|
| 1 | Macros can only be added or edited in a two-field alert. No on/off switch, no warning for triggers that hijack normal typing (e.g. a single `a`). | A small macro editor screen: trigger, multi-line expansion, on/off switch, warning for risky triggers. | Medium | Open |
| 2 | "Clear Clipboard History" gave no feedback after confirming. | Row shows the item count; after clearing it reads "Clipboard History Is Empty" (greyed, not tappable) with a success haptic. Confirmation says how many items will go. Refreshes when you return to the app. | Small | **Done**, checked in simulator |
| 3 | Customize Keys used an emoji badge ("🔵 Q (customized)") and blocking "OK" alerts. | Plain blue "Customized" label; empty-field error shown under the field and cleared as you type; tapping a system key explains inline; buttons say "Save Key" and "Reset All". | Small | **Done**, checked in simulator |
| 4 | The split keyboard uses a fixed gap. | A "Split width" slider under the split toggle. | Small–medium | Open |
| 5 | Copy / cut warnings were long ("Copied — may be truncated. Use system Copy for large selections."). | Shortened to e.g. "Copied. Long text may be cut off — use system Copy." The 80-character threshold is unchanged: iOS doesn't tell the keyboard whether a selection was cut short, so it can't warn only when it actually happened. | Small | **Done** (wording only) |
| 6 | Onboarding's Enable page button said "Skip to Tour" / "Continue" / "Next" depending on state. | Always "Next"; the status line does the guiding. | Small | **Done** |
