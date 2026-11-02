import SwiftUI
import HITListCore

/// The quick-add title: `HITField`'s box (`HITFieldChrome`) around a wrapping text field, with each
/// recognised token (dates, times, repeats, `#project`, `@label`, `p1`-`p4`, `!15mb`) tinted behind the
/// text as you type, in a lightly rounded box that reads as a button. Tapping (clicking) a highlight
/// switches that token off (`onDisable`): its words stay as plain text in the title. Return submits
/// instead of starting a new line. `bordered: false` drops the box, for the quick-add card where the card
/// itself is the frame.
///
/// How the highlights are drawn and hit: under the field sits a copy of the text with clear glyphs, each
/// token's words tagged with `TokenSpan`. SwiftUI reports that copy's line layout (`Text.LayoutKey`), and
/// the runs carrying a `TokenSpan` give each token's rectangles on each line (`TokenHighlightField.areas`).
/// The tints are rounded rectangles drawn behind the field at those places, and the tap targets are clear
/// shapes at the same places above it, so the field itself stays a plain `TextField` (iOS) / `TextEditor`
/// (Mac) and keeps its focus, placeholder, Return and cap. A tap anywhere else still lands in the field.
struct TokenHighlightField: View {
    let placeholder: String
    @Binding var text: String
    var tokens: [QuickAddToken]
    var priority: Priority
    var focus: FocusState<Bool>.Binding
    var bordered = true
    /// A highlight was tapped; nil leaves the highlights as decoration.
    var onDisable: ((QuickAddToken) -> Void)? = nil
    var onSubmit: () -> Void

    /// The highlight's corners (George, brief 28: "slightly rounded, like a button").
    static let highlightRadius: CGFloat = 4
    /// The highlight's tint strength, as before.
    static let highlightOpacity: Double = 0.3
    #if os(macOS)
    /// The Mac `TextEditor` starts its text this far in (its text container's line-fragment padding, which
    /// `PopoutTests.testTheMacEditorInsetMatchesTheHighlightCopy` pins); the clear copy is inset the same so
    /// the tints sit under the words.
    static let editorTextInset: CGFloat = 5
    #else
    static let editorTextInset: CGFloat = 0
    #endif

    var body: some View {
        if bordered {
            field.modifier(HITFieldChrome(isFocused: focus.wrappedValue))
        } else {
            field
        }
    }

    private var field: some View {
        let tokens = drawableTokens
        return ZStack(alignment: .topLeading) {
            Self.highlightText(text, tokens: tokens)
                .foregroundStyle(.clear)
                .lineLimit(1...4)
                .padding(.horizontal, Self.editorTextInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
                .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { proxy in
                        ForEach(Self.areas(layouts, in: proxy).filter { $0.token < tokens.count }) { area in
                            RoundedRectangle(cornerRadius: Self.highlightRadius, style: .continuous)
                                .fill(PopoutTint.token(tokens[area.token].kind, priority: priority).opacity(Self.highlightOpacity))
                                .frame(width: area.rect.width, height: area.rect.height)
                                .position(x: area.rect.midX, y: area.rect.midY)
                        }
                    }
                }
            editor
        }
        .font(HITType.taskName)
        .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
            if let onDisable {
                GeometryReader { proxy in
                    ForEach(Self.areas(layouts, in: proxy).filter { $0.token < tokens.count }) { area in
                        tapTarget(for: tokens[area.token], area: area, onDisable: onDisable)
                    }
                }
            }
        }
        .onChange(of: text) { _, new in
            // A vertical field takes Return as a newline; treat it as submit.
            guard new.contains(where: \.isNewline) else { return }
            text = new.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            onSubmit()
        }
    }

    /// The field, with "Keep “tom” as text" as a VoiceOver action per token when highlights can be tapped.
    private var editor: some View {
        input.accessibilityActions {
            if let onDisable {
                ForEach(Array(drawableTokens.enumerated()), id: \.offset) { _, token in
                    Button("Keep “\(token.text)” as text") { onDisable(token) }
                }
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        #if os(iOS)
        TextField(text: $text, axis: .vertical) {
            Text(placeholder).foregroundStyle(Theme.secondaryText)
        }
        .textFieldStyle(.plain)
        .lineLimit(1...4)
        .foregroundStyle(HITColor.text)
        .focused(focus)
        .onSubmit(onSubmit)
        .submitLabel(.done)
        .autocorrectionDisabled()
        #else
        // On the Mac a vertical-axis TextField kept drawing its text view's grey box behind the
        // words whatever was asked of it; a plain TextEditor honours a hidden background. Return
        // still submits (the newline check above), and the placeholder is drawn by hand.
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, Self.editorTextInset)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focusEffectDisabled()
                .foregroundStyle(HITColor.text)
                .focused(focus)
                .frame(minHeight: 24, maxHeight: 96)
                .fixedSize(horizontal: false, vertical: true)
        }
        #endif
    }

    /// A clear, rounded shape over one piece of a highlight; tapping it switches the token off.
    private func tapTarget(for token: QuickAddToken, area: Area, onDisable: @escaping (QuickAddToken) -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.highlightRadius, style: .continuous)
        return Color.clear
            .contentShape(shape)
            .frame(width: area.rect.width, height: area.rect.height)
            .onTapGesture { onDisable(token) }
            #if os(macOS)
            .pointerStyle(.link)
            .help("Click to keep “\(token.text)” as text")
            #endif
            .position(x: area.rect.midX, y: area.rect.midY)
            .accessibilityHidden(true)
    }

    /// The tokens that can be drawn on this text: in order, not overlapping, inside it.
    private var drawableTokens: [QuickAddToken] {
        var result: [QuickAddToken] = []
        for token in tokens.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            guard token.range.upperBound <= text.endIndex, !token.range.isEmpty,
                  result.last.map({ $0.range.upperBound <= token.range.lowerBound }) ?? true else { continue }
            result.append(token)
        }
        return result
    }

    // MARK: Layout of the highlights (internal for the render tests)

    /// Tags the words of token number `index` in the clear copy.
    struct TokenSpan: TextAttribute {
        let index: Int
    }

    /// One rectangle of one token's highlight (a token that wraps has one per line).
    struct Area: Identifiable, Equatable {
        /// The token's index in the list given to `highlightText`.
        var token: Int
        var line: Int
        var rect: CGRect
        var id: String { "\(token).\(line)" }
    }

    /// The text with each token's words tagged (`TokenSpan`); `tokens` must be in order and inside `text`.
    static func highlightText(_ text: String, tokens: [QuickAddToken]) -> Text {
        var pieces: [Text] = []
        var cursor = text.startIndex
        for (index, token) in tokens.enumerated() {
            guard token.range.lowerBound >= cursor, token.range.upperBound <= text.endIndex else { continue }
            if cursor < token.range.lowerBound { pieces.append(Text(verbatim: String(text[cursor..<token.range.lowerBound]))) }
            pieces.append(Text(verbatim: String(text[token.range])).customAttribute(TokenSpan(index: index)))
            cursor = token.range.upperBound
        }
        if cursor < text.endIndex { pieces.append(Text(verbatim: String(text[cursor...]))) }
        guard var joined = pieces.first else { return Text(verbatim: "") }
        for piece in pieces.dropFirst() { joined = Text("\(joined)\(piece)") }
        return joined
    }

    /// Where each token's highlight is, in `proxy`'s space: the tagged runs of every laid-out line, the
    /// runs of one token on one line joined into one rectangle. None when the copy was cut short (a title
    /// longer than the field's lines): the field then scrolls to the cursor while the copy keeps its first
    /// lines, so its places are not where the field's words are, and a tap there could switch off a token
    /// out of sight. The tokens still count; the VoiceOver actions still switch them off.
    static func areas(_ layouts: [Text.LayoutKey.AnchoredLayout], in proxy: GeometryProxy) -> [Area] {
        guard !layouts.contains(where: { $0.layout.isTruncated }) else { return [] }
        var areas: [Area] = []
        for anchored in layouts {
            let origin = proxy[anchored.origin]
            for (lineIndex, line) in anchored.layout.enumerated() {
                for run in line {
                    guard let span = run[TokenSpan.self] else { continue }
                    let rect = run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
                    if let last = areas.indices.last, areas[last].token == span.index, areas[last].line == lineIndex {
                        areas[last].rect = areas[last].rect.union(rect)
                    } else {
                        areas.append(Area(token: span.index, line: lineIndex, rect: rect))
                    }
                }
            }
        }
        return areas
    }
}
