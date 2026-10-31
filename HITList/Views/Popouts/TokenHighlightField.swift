import SwiftUI
import HITListCore

/// The quick-add title: `HITField`'s box (`HITFieldChrome`) around a wrapping text field, with each
/// recognised token (dates, times, repeats, `#project`, `@label`, `p1`-`p4`) tinted behind the text as
/// you type. The tint is a copy of the text drawn underneath with clear glyphs, so the field itself
/// stays a plain `TextField`. Return submits instead of starting a new line. `bordered: false` drops
/// the box, for the quick-add card where the card itself is the frame.
struct TokenHighlightField: View {
    let placeholder: String
    @Binding var text: String
    var tokens: [QuickAddToken]
    var priority: Priority
    var focus: FocusState<Bool>.Binding
    var bordered = true
    var onSubmit: () -> Void

    var body: some View {
        if bordered {
            field.modifier(HITFieldChrome(isFocused: focus.wrappedValue))
        } else {
            field
        }
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            Text(highlighted)
                .lineLimit(1...4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            TextField(text: $text, axis: .vertical) {
                Text(placeholder).foregroundStyle(Theme.secondaryText)
            }
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .foregroundStyle(HITColor.text)
            .focused(focus)
            .onSubmit(onSubmit)
            #if os(iOS)
            .submitLabel(.done)
            .autocorrectionDisabled()
            #endif
        }
        .font(HITType.taskName)
        .onChange(of: text) { _, new in
            // A vertical field takes Return as a newline; treat it as submit.
            guard new.contains(where: \.isNewline) else { return }
            text = new.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            onSubmit()
        }
    }

    /// The text with clear glyphs and a tinted background behind each token.
    private var highlighted: AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = .clear
        for token in tokens {
            guard token.range.upperBound <= text.endIndex else { continue }
            let start = text.distance(from: text.startIndex, to: token.range.lowerBound)
            let length = text.distance(from: token.range.lowerBound, to: token.range.upperBound)
            let lower = attributed.characters.index(attributed.startIndex, offsetBy: start)
            let upper = attributed.characters.index(lower, offsetBy: length)
            attributed[lower..<upper].backgroundColor = PopoutTint.token(token.kind, priority: priority).opacity(0.3)
        }
        return attributed
    }
}
