import SwiftUI

/// One line of the quick-add card's sub-task list: a plain, borderless text field in Inter that tells its
/// owner about Return and about Backspace on an empty line. A SwiftUI `TextField` can do neither on the
/// iPhone's on-screen keyboard (`onKeyPress` sees hardware keys only) nor reliably on the Mac (the field
/// editor eats Delete), so this is a `UITextField` / `NSTextField` underneath.
///
/// Focus is the owner's: `isFocused` asks for it, `onFocus` reports the field took it (a tap).
struct SubtaskLineField: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool
    var onFocus: () -> Void = {}
    var onReturn: () -> Void
    var onDeleteEmpty: () -> Void

    #if os(macOS)
    static let fontSize: CGFloat = 13
    static let height: CGFloat = 22
    #else
    static let fontSize: CGFloat = 16
    static let height: CGFloat = 30
    #endif

    var body: some View {
        LineFieldRepresentable(placeholder: placeholder, text: $text, isFocused: isFocused, onFocus: onFocus,
                               onReturn: onReturn, onDeleteEmpty: onDeleteEmpty,
                               textColor: HITColor.text, placeholderColor: Theme.secondaryText, tint: Theme.accent)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity)
    }
}

#if os(iOS)
import UIKit

private final class BackspaceTextField: UITextField {
    var onDeleteEmpty: () -> Void = {}

    override func deleteBackward() {
        if (text ?? "").isEmpty { onDeleteEmpty() } else { super.deleteBackward() }
    }
}

private struct LineFieldRepresentable: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isFocused: Bool
    let onFocus: () -> Void
    let onReturn: () -> Void
    let onDeleteEmpty: () -> Void
    let textColor: Color
    let placeholderColor: Color
    let tint: Color

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BackspaceTextField {
        let field = BackspaceTextField()
        field.delegate = context.coordinator
        field.font = UIFont(name: HITFont.postScriptName(.regular), size: SubtaskLineField.fontSize)
            ?? .systemFont(ofSize: SubtaskLineField.fontSize)
        field.borderStyle = .none
        field.returnKeyType = .next
        field.autocapitalizationType = .sentences
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: BackspaceTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.textColor = UIColor(textColor)
        field.tintColor = UIColor(tint)
        field.attributedPlaceholder = NSAttributedString(string: placeholder,
                                                         attributes: [.foregroundColor: UIColor(placeholderColor)])
        field.onDeleteEmpty = { context.coordinator.parent.onDeleteEmpty() }
        if isFocused, !field.isFirstResponder {
            // After this update: a field just inserted is not in a window yet.
            DispatchQueue.main.async { if field.window != nil { field.becomeFirstResponder() } }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LineFieldRepresentable
        init(_ parent: LineFieldRepresentable) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldDidBeginEditing(_ textField: UITextField) { parent.onFocus() }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false
        }
    }
}

#else
import AppKit

private struct LineFieldRepresentable: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isFocused: Bool
    let onFocus: () -> Void
    let onReturn: () -> Void
    let onDeleteEmpty: () -> Void
    let textColor: Color
    let placeholderColor: Color
    let tint: Color

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusReportingTextField()
        field.delegate = context.coordinator
        field.onFocus = { context.coordinator.parent.onFocus() }
        field.font = NSFont(name: HITFont.postScriptName(.regular), size: SubtaskLineField.fontSize)
            ?? .systemFont(ofSize: SubtaskLineField.fontSize)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.textColor = NSColor(textColor)
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor(placeholderColor),
            .font: field.font ?? NSFont.systemFont(ofSize: SubtaskLineField.fontSize),
        ])
        (field.currentEditor() as? NSTextView)?.insertionPointColor = NSColor(tint)
        if isFocused, field.currentEditor() == nil {
            DispatchQueue.main.async {
                guard let window = field.window, field.currentEditor() == nil else { return }
                window.makeFirstResponder(field)
                (field.currentEditor() as? NSTextView)?.insertionPointColor = NSColor(tint)
                field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LineFieldRepresentable
        init(_ parent: LineFieldRepresentable) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onReturn()
                return true
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty:
                parent.onDeleteEmpty()
                return true
            default:
                return false
            }
        }
    }
}

/// Reports when a click (or Tab) puts the cursor in it.
private final class FocusReportingTextField: NSTextField {
    var onFocus: () -> Void = {}

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus() }
        return became
    }
}
#endif
