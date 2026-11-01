import SwiftUI

/// The cards' time row: a `HITField`-styled box showing "9:00 AM" (or "Add time"), that takes typed
/// times ("9am", "17:30", "noon"; `PickerTime.parse`) on Return, turns red for anything else, and has
/// a × that removes the time.
struct PickerTimeField: View {
    var time: PickerTime?
    var placeholder = "Add time"
    /// Changing it gives the field the keyboard.
    var focusTrigger = 0
    /// Nil removes the time.
    var onCommit: (PickerTime?) -> Void

    @State private var text: String
    @State private var invalid = false
    @FocusState private var isFocused: Bool

    init(time: PickerTime?, placeholder: String = "Add time", focusTrigger: Int = 0, onCommit: @escaping (PickerTime?) -> Void) {
        self.time = time
        self.placeholder = placeholder
        self.focusTrigger = focusTrigger
        self.onCommit = onCommit
        _text = State(initialValue: time?.text() ?? "")
    }

    var body: some View {
        HStack(spacing: HITSpacing.s) {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocused ? Theme.accent : Theme.secondaryText)
            TextField(text: $text) {
                Text(placeholder).foregroundStyle(Theme.secondaryText)
            }
            .textFieldStyle(.plain)
            .foregroundStyle(HITColor.text)
            .focused($isFocused)
            .onSubmit(commit)
            .accessibilityIdentifier("pickerTimeField")
            if time != nil || !text.isEmpty {
                Button(action: clear) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(HITIconButtonStyle(font: .system(size: 14)))
                    .accessibilityLabel("Remove the time")
                    .help("No time")
            }
        }
        .modifier(HITFieldChrome(isFocused: isFocused, isInvalid: invalid))
        .help("Type a time, e.g. 9am, 17:30 or noon, then Return")
        .onChange(of: text) { _, _ in invalid = false }
        .onChange(of: time) { _, newTime in
            if !isFocused { text = newTime?.text() ?? "" }
        }
        .onChange(of: focusTrigger) { _, _ in isFocused = true }
    }

    private func commit() {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            if time != nil { onCommit(nil) }
            return
        }
        guard let parsed = PickerTime.parse(typed) else {
            invalid = true
            return
        }
        text = parsed.text()
        onCommit(parsed)
    }

    private func clear() {
        text = ""
        invalid = false
        if time != nil { onCommit(nil) }
    }
}
