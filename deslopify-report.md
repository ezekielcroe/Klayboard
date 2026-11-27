# Deslopify report: Klayboard

## Summary

Klayboard is a custom iOS keyboard for power typists: a keyboard extension (`KlayboardExtension`) plus a container app (`Klayboard`) for onboarding and settings. It is live on the App Store, so changes here reach real users' typing.

**Overall state: healthy for a vibe-coded project.** The code is readable, heavily commented, and mostly free of the usual slop: no secrets, no `TODO`s, no swallowed errors beyond two deliberate decode fallbacks, no compiler warnings in a normal build. The main risks are in the text-expansion (macro) engine, which can delete text the user didn't type in some situations, and a few places where the app and the keyboard disagree about shared data.

**Scope agreed in intake**
- Change level: **Clean and fix**. Safe cleanup, tests and bug fixes; unclear intent comes back as a question; UX ideas are proposed, not built.
- Critical flows: typing itself, **gestures and accents** (swipe-down symbols, swipe-up dismiss, hold-for-accents, spacebar trackpad), **macros and clipboard**, **settings sync** (app → keyboard).
- Git: the iPhone Duo work is committed on branch `iphone-duo`; this pass is on `deslopify/2026-11-27`, one commit per changeset.
- `FullProjectSource.txt` and `mergecode.py` are left untouched and now ignored by git.

## How to run and verify

- App + keyboard: open `Klayboard.xcodeproj`, run the `Klayboard` scheme on a simulator or device, then add the keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard.
- Tests: see "Tests added" below.

## Inventory

| | |
|---|---|
| Stack | Swift, UIKit, programmatic UI (no storyboards). Xcode project with file-system-synchronised groups. |
| Targets | `Klayboard` (container app, iOS 17.6+), `KlayboardExtension` (keyboard, iOS 15.6+). `Shared/` is compiled into both. |
| Storage | App Group `group.com.GeekyZeke.Klayboard` UserDefaults: `userConfiguration` (JSON), `clipboardHistory`, `emojiRecents`, touch calibration, onboarding flags. |
| Network / external services | None. |
| Keyboard pieces | `KeyboardViewController` (actions, text tracking), `KeyboardRenderView` (layout, touch model, gestures), `MacroEngine`, `CursorEngine`, `ClipboardHistory`, `TouchModel`, `BigramModel`, `AccentVariants`, `SplitLayout`, emoji and clipboard panels. |
| App screens | Onboarding (5 pages), Settings (table), Customize Keys. |
| Tests | None existed. |
| Lint / dead-code tools | None installed (no SwiftLint or Periphery); dead code found by symbol search. |

## Findings from mapping

**Dead or abandoned code**
- `BaseLayouts.spacebarRowWithToggle`: an earlier way of adding the 5-row toggle key; the current code injects the key at runtime instead. Never used.
- `AppConstants.feedbackChanged`, `ClipboardHistory.removeItem(at:)`, `.isEmpty`, `.count`, `TouchModel.resetCalibration()`: never called.
- The `.cut` action handler: no layout has a Cut key (it was removed on purpose because it could lose text), and the key customizer can't assign it.
- Per-user Xcode files (`xcuserdata/`) are tracked in git.

**Duplication**
- The "does this override apply to this layout" check is written out four times in `KeyCustomizationViewController`, and `effectiveDefinition` re-implements `KeyboardLayout.applying(overrides:)`.
- The clipboard-history storage key is a string literal in two places (keyboard and app).

**Config**
- The keyboard extension is version 1.5 (build 2) while the app is 1.6 (build 1). Xcode warns on every build; App Store Connect flags mismatched extension versions.
- A build setting names a `LaunchScreen` storyboard that doesn't exist. The plist's `UILaunchScreen` entry is what actually provides the launch screen.
- README says to open `Klayboard.xcworkspace`; there is only `Klayboard.xcodeproj`.

## Changes made

_(filled in as commits land)_

## Bugs found

| Severity | What happens | Where | Status |
|----------|--------------|-------|--------|

## Questions for you

## Tests added

## Remaining cleanup

## UX/UI recommendations
