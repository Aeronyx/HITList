import SwiftUI

/// HITList's text input: slate `Theme.elevated` box, 10 pt radius, accent ring while focused, red ring
/// when `isInvalid`, grey placeholder, optional leading icon and trailing clear button.
///
///     HITField("Name", text: $name)
///     HITField("Search", text: $query, systemImage: "magnifyingglass", clearable: true)
///     HITField("Description", text: $notes, axis: .vertical, lineLimit: 2...6)
///     HITField("Name", text: $name, autofocus: true).onSubmit(save)
///
/// Modifiers that reach a `TextField` through the environment (`.onSubmit`, `.submitLabel`,
/// `.textInputAutocapitalization`, `.font`) work on `HITField` as usual.
/// For a `TextField` you can't replace (it needs a `selection:` binding, say), give it the same look
/// with `.textFieldStyle(HITTextFieldStyle())`; that variant has no focus ring.
struct HITField: View {
    let placeholder: String
    @Binding var text: String
    var systemImage: String?
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int> = 1...1
    var clearable = false
    var isInvalid = false
    var autofocus = false

    init(_ placeholder: String, text: Binding<String>, systemImage: String? = nil, axis: Axis = .horizontal,
         lineLimit: ClosedRange<Int>? = nil, clearable: Bool = false, isInvalid: Bool = false, autofocus: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.systemImage = systemImage
        self.axis = axis
        self.lineLimit = lineLimit ?? (axis == .vertical ? 1...6 : 1...1)
        self.clearable = clearable
        self.isInvalid = isInvalid
        self.autofocus = autofocus
    }

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: axis == .vertical ? .firstTextBaseline : .center, spacing: HITSpacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isFocused ? Theme.accent : Theme.secondaryText)
                    // VoiceOver stopped on it ("Search") before the field itself (brief 94).
                    .accessibilityHidden(true)
            }
            TextField(text: $text, axis: axis) {
                Text(placeholder).foregroundStyle(Theme.secondaryText)
            }
            .textFieldStyle(.plain)
            .lineLimit(lineLimit)
            .foregroundStyle(HITColor.text)
            .focused($isFocused)
            if clearable, !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(HITIconButtonStyle(font: .system(size: 14)))
                    .accessibilityLabel("Clear")
            }
        }
        .modifier(HITFieldChrome(isFocused: isFocused, isInvalid: isInvalid))
        .onAppear { if autofocus { isFocused = true } }
    }
}

/// The box around a field: padding, elevated fill, focus or error ring.
struct HITFieldChrome: ViewModifier {
    var isFocused: Bool
    var isInvalid = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let ringWidth: CGFloat = 1.5

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous)
        let ring: Color = isInvalid ? HITColor.danger : isFocused ? Theme.accent : .clear
        content
            .padding(.horizontal, HITSpacing.m)
            .padding(.vertical, HITSpacing.s + 2)
            .background(shape.fill(Theme.elevated))
            .overlay(shape.strokeBorder(ring, lineWidth: Self.ringWidth))
            // Soft glow outside the ring while focused.
            .shadow(color: isFocused && !isInvalid ? Theme.accent.opacity(0.25) : .clear, radius: 4)
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isFocused)
            .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isInvalid)
    }
}

/// `HITField`'s box for a plain `TextField`: `.textFieldStyle(HITTextFieldStyle(isInvalid: hasError))`.
struct HITTextFieldStyle: TextFieldStyle {
    var isInvalid = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .foregroundStyle(HITColor.text)
            .modifier(HITFieldChrome(isFocused: false, isInvalid: isInvalid))
    }
}
