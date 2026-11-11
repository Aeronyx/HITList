import SwiftUI

/// The switch card's time (brief 96, George: "the add time bar is strangely long"): a chip the size and style of the
/// Switchboard chip beside it, never a bar across the card. "Add time", or the time lit with a × that takes it away; a
/// tap opens a field in the chip's place, the same height, that takes "9pm", "21:00" or "noon" (`PickerTime.parse`)
/// on Return or when it lets go of the keyboard. The Switchboard card's reset time is the same control, which always
/// has a time (`allowsNone: false`).
struct SwitchTimeChip: View {
    var time: PickerTime?
    var placeholder = "Add time"
    /// The time can be taken away (a switch's); false: there is always one (a board's reset).
    var allowsNone = true
    /// What VoiceOver calls it: "Time", "Resets at".
    var speechName = "Time"
    /// The time typed (nil: taken away).
    var onCommit: (PickerTime?) -> Void
    /// The field closed after Return: the card gives its name the keyboard back.
    var onFinish: () -> Void = {}

    @State private var isEditing = false
    @State private var text = ""
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The field's width: room for "12:45 PM" in the chips' type, with the clock.
    #if os(macOS)
    static let fieldWidth: CGFloat = 96
    #else
    static let fieldWidth: CGFloat = 112
    #endif

    /// What Return (or letting go) does with what is typed. Pure, so tests pin it.
    enum Outcome: Equatable {
        /// A new time, or nil: none.
        case set(PickerTime?)
        /// Nothing changes.
        case keep
        /// Not a time: the field turns red and stays.
        case invalid
    }

    static func outcome(typing raw: String, time: PickerTime?, allowsNone: Bool) -> Outcome {
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return allowsNone && time != nil ? .set(nil) : .keep }
        guard let parsed = PickerTime.parse(typed) else { return .invalid }
        return parsed == time ? .keep : .set(parsed)
    }

    var body: some View {
        SwiftUI.Group {
            if isEditing { field } else { chip }
        }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isEditing)
    }

    private var chip: some View {
        let shown = time?.text()
        return HITChip(shown ?? placeholder, systemImage: "clock", isSelected: time != nil,
                       speech: "\(speechName): \(shown ?? "none")",
                       onDismiss: allowsNone && time != nil ? { onCommit(nil) } : nil) {
            startEditing()
        }
        .fixedSize()
        .help("Type a time, e.g. 9pm, 21:00 or noon")
        .accessibilityHint("Opens a field for the time")
        .accessibilityIdentifier("switchTime")
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.chip, style: .continuous)
        return HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
            TextField(text: $text) {
                Text(time?.text() ?? "9pm").foregroundStyle(Theme.secondaryText)
            }
            .textFieldStyle(.plain)
            .font(HITType.control)
            .foregroundStyle(HITColor.text)
            .lineLimit(1)
            .focused($isFocused)
            .onSubmit { finish(fromReturn: true) }
            .submitLabel(.done)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #else
            .onExitCommand { close() }
            #endif
            .accessibilityLabel(speechName)
            .accessibilityIdentifier("switchTimeField")
        }
        .padding(.horizontal, HITSpacing.s + 2)
        .frame(width: Self.fieldWidth, height: HITChip.Size.regular.height)
        .background(shape.fill(Theme.elevated))
        .overlay(shape.strokeBorder(isInvalid ? HITColor.danger : Theme.accent, lineWidth: 1))
        .onChange(of: text) { _, _ in isInvalid = false }
        // Letting go of the keyboard (a tap on the name, a chip) takes what was typed, or forgets a typo.
        .onChange(of: isFocused) { _, focused in if !focused { finish(fromReturn: false) } }
        .task {
            // The field takes the keyboard once it is on screen (asked again a moment later: on the Mac the click
            // that opened it can win the first time).
            for delay in [0, 60, 150] {
                guard (try? await Task.sleep(for: .milliseconds(delay))) != nil else { return }
                if !isFocused { isFocused = true }
            }
        }
    }

    private func startEditing() {
        text = ""
        isInvalid = false
        isEditing = true
    }

    private func finish(fromReturn: Bool) {
        guard isEditing else { return }
        switch Self.outcome(typing: text, time: time, allowsNone: allowsNone) {
        case .set(let new):
            onCommit(new)
        case .keep:
            break
        case .invalid:
            // Return on a typo asks again; letting go forgets it.
            if fromReturn {
                isInvalid = true
                return
            }
        }
        close()
        if fromReturn { onFinish() }
    }

    private func close() {
        isEditing = false
        isInvalid = false
    }
}
