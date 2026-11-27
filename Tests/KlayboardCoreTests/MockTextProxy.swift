import UIKit

/// In-memory stand-in for the host app's text field.
///
/// `cursor` counts Characters, matching how CursorEngine and MacroEngine
/// compute distances. (Real hosts may count UTF-16 units in
/// adjustTextPosition; that difference is not modelled here.)
final class MockTextProxy: NSObject, UITextDocumentProxy {
    var text: String
    var cursor: Int

    init(_ text: String = "", cursor: Int? = nil) {
        self.text = text
        self.cursor = cursor ?? text.count
    }

    // MARK: UITextDocumentProxy

    var documentContextBeforeInput: String? {
        cursor == 0 ? nil : String(text.prefix(cursor))
    }

    var documentContextAfterInput: String? {
        cursor == text.count ? nil : String(text.dropFirst(cursor))
    }

    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID = UUID()

    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursor = min(max(cursor + offset, 0), text.count)
    }

    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}

    // MARK: UIKeyInput

    var hasText: Bool { !text.isEmpty }

    func insertText(_ string: String) {
        let index = text.index(text.startIndex, offsetBy: cursor)
        text.insert(contentsOf: string, at: index)
        cursor += string.count
    }

    func deleteBackward() {
        guard cursor > 0 else { return }
        let index = text.index(text.startIndex, offsetBy: cursor - 1)
        text.remove(at: index)
        cursor -= 1
    }
}
