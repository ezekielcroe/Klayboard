# Privacy Policy for Klayboard

**Last Updated:** March 28, 2026

Klayboard was built from the ground up to be a privacy-first utility. We believe your keystrokes belong to you. **Klayboard does not collect, log, store, or transmit any of your typing data.**

### 1. Data Collection
Klayboard operates 100% offline. The app contains absolutely no networking code, no analytics trackers, and no third-party SDKs. What happens on your device stays on your device. 

All custom macros, layouts, and settings you create are stored locally on your device inside a secure Apple App Group, which is only accessible by the Klayboard app and its keyboard extension.

### 2. Why does Klayboard request "Allow Full Access"?
When you enable Klayboard in your iOS Settings, Apple presents a default, unchangeable warning stating that "Full Access" allows the developer to transmit anything you type. **We do not do this.**

Klayboard requests "Allow Full Access" exclusively for the following local, device-level features:
* **Haptic Feedback:** iOS requires Full Access to trigger the device's physical vibration motor (`UIImpactFeedbackGenerator`) when you tap a key.
* **Clipboard Macros:** Klayboard's custom copy/paste shortcut buttons require Full Access to read from and write to your device's local clipboard (`UIPasteboard`).
* **Settings Synchronization:** Full Access ensures that the custom layouts and macros you configure in the Klayboard app sync reliably to the keyboard extension you use in other apps.

If you choose not to grant Full Access, you can still use Klayboard for standard typing, but haptics and clipboard shortcuts will be disabled.

### 3. Changes to This Privacy Policy
If we make any changes to this Privacy Policy, we will update the "Last Updated" date at the top of this page. Because we do not collect your email address or personal information, we encourage you to review this policy periodically.

### 4. Contact
If you have any questions or concerns about this Privacy Policy or Klayboard's architecture, please contact us at: **[Insert Your Developer Email / Twitter / Support Link Here]**.
