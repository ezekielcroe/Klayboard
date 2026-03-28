# Klayboard ⌨️⚡️

**A lightning-fast, zero-bloat custom iOS keyboard built for speed, precision, and absolute user control.**

Stripped of RAM-heavy predictive AI and aggressive auto-correct, Klayboard guarantees deterministic typing: *what you press is exactly what appears on the screen.* Designed specifically for power users, developers, and writers, it brings desktop-level keyboard utility to iOS.

## ✨ Key Features

* **Deterministic Typing Engine:** No AI, no aggressive autocorrect, no lag. Pure, instant input.
* **Advanced Gestures:** Swipe down on any alpha key for instant symbol input. Swipe up on the spacebar to dismiss the keyboard instantly, bypassing the iOS bezel deadzone.
* **Local Text Expansion (Macros):** A customizable utility row allows you to trigger instant text expansions (e.g., Markdown snippets, code blocks, or email templates) completely offline.
* **Precision Cursor Control:** Dedicated keys for word-by-word and character-by-character cursor navigation, plus line-deletion tools.
* **Dynamic Architectures:** Switch seamlessly between a 6-row layout (with a dedicated number row) and a 5-row "Compact" layout (with a hideable utility row).
* **Developer & Writer Layouts:** Built-in layouts optimized for QWERTY, Coding, Markdown, and advanced Symbols.
* **Customizable Ergonomics:** Adjustable keyboard height, long-press duration sliders, and toggles for haptic/audio feedback.

## 🛠 Architecture & Performance

Klayboard circumvents standard iOS Custom Keyboard memory limits and layout engine bottlenecks:
* **Frame-Based Key Rendering:** While the root container uses Auto Layout to perfectly anchor to the iOS system window, the actual keys are drawn programmatically using math-based frame calculations. This prevents constraint-thrashing and keeps the memory footprint incredibly low.
* **Touch-Tracking Engine:** A bespoke, multi-touch gesture engine tracks initial touch locations, vectors, and swipe thresholds to seamlessly differentiate between taps, long-presses, and vertical swipes without misfires.

## 🚀 Building & Installation

1. Clone the repository and open `Klayboard.xcworkspace`.
2. Update the **Bundle Identifier** for both the `Klayboard` container app and the `KlayboardExtension` targets.
3. Configure the **App Group**:
   * Ensure you have an App Group registered in your Apple Developer account.
   * Update the App Group ID in both targets' "Signing & Capabilities" tabs.
   * Update the `AppConstants.appGroupID` string in `Shared/KeyboardDataStructures.swift` to match.
4. Build and run on your physical iOS device.
5. Go to **Settings > General > Keyboard > Keyboards > Add New Keyboard...** and select Klayboard.

## 🔒 Privacy First
Klayboard is completely offline. It contains zero networking code and does not log, store, or transmit your keystrokes. For full details on why Apple's "Allow Full Access" toggle is requested, please see the [Privacy Policy](PrivacyPolicy.md).
