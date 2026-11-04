import SwiftUI
import HITListCore

/// The quick-add title: `HITField`'s box (`HITFieldChrome`) around a wrapping text field, with each
/// recognised token (dates, times, repeats, `#project`, `@label`, `p1`-`p4`, `!15mb`) tinted behind the
/// text as you type, in a lightly rounded box that reads as a button. Highlights of the same colour with
/// only spaces between them are one box ("[tom 4]", brief 37). Tapping (clicking) a box switches its
/// tokens off (`onDisable`, once per token): their words stay as plain text in the title. Return never
/// starts a new line: on the Mac it submits, on iOS it does nothing (`TitleReturn`, brief 36). `bordered: false` drops the box, for the quick-add card where the card
/// itself is the frame.
///
/// How the highlights are drawn and hit: under the field sits a copy of the text with clear glyphs, each
/// token's words tagged with `TokenSpan`. SwiftUI reports that copy's line layout (`Text.LayoutKey`), and
/// the runs carrying a `TokenSpan` give each token's rectangles on each line (`TokenHighlightField.areas`),
/// joined per line into boxes for runs of same-coloured tokens (`groups`, `boxes`).
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
        let groups = Self.groups(tokens, in: text, priority: priority)
        return ZStack(alignment: .topLeading) {
            Self.highlightText(text, tokens: tokens)
                .foregroundStyle(.clear)
                .lineLimit(1...4)
                .padding(.horizontal, Self.editorTextInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
                .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { proxy in
                        ForEach(Self.boxes(Self.areas(layouts, in: proxy), groups: groups)) { box in
                            RoundedRectangle(cornerRadius: Self.highlightRadius, style: .continuous)
                                .fill(PopoutTint.token(tokens[box.tokens[0]].kind, priority: priority).opacity(Self.highlightOpacity))
                                .frame(width: box.rect.width, height: box.rect.height)
                                .position(x: box.rect.midX, y: box.rect.midY)
                        }
                    }
                }
            editor
        }
        .font(HITType.taskName)
        .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
            if let onDisable {
                GeometryReader { proxy in
                    ForEach(Self.boxes(Self.areas(layouts, in: proxy), groups: groups)) { box in
                        tapTarget(for: box.tokens.map { tokens[$0] }, box: box, onDisable: onDisable)
                    }
                }
            }
        }
        .onChange(of: text) { old, new in
            // A vertical field takes Return as a newline. iPhone: dropped, the text stays as it was (brief 36:
            // confirm only by the button); the Mac: submit. A pasted line break becomes a space on both.
            guard let outcome = TitleReturn.resolve(old: old, new: new) else { return }
            text = outcome.text
            if outcome.submits { onSubmit() }
        }
    }

    /// The field, with "Keep “tom 4” as text" as a VoiceOver action per box when highlights can be tapped.
    private var editor: some View {
        let tokens = drawableTokens
        let members = Self.members(of: Self.groups(tokens, in: text, priority: priority))
        return input.accessibilityActions {
            if let onDisable {
                ForEach(Array(members.enumerated()), id: \.offset) { _, indices in
                    let box = indices.map { tokens[$0] }
                    Button("Keep “\(Self.words(of: box, in: text))” as text") { box.forEach(onDisable) }
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
        // A plain "return" key, not the blue check: Return does nothing here (`TitleReturn`), and the card's
        // Confirm pill is the only way to add (George, 0.4.1).
        .submitLabel(.return)
        // Standard autocorrect and sentence capitals (George, 0.4.0): the parser reads tokens without
        // regard to case, so "Tom" and "P1" still work.
        .textInputAutocapitalization(.sentences)
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

    /// A clear, rounded shape over one piece of a box; tapping it switches off every token in the box (a
    /// joined "[tom 4]" goes in one tap, whichever line the tap lands on).
    private func tapTarget(for box: [QuickAddToken], box piece: Box, onDisable: @escaping (QuickAddToken) -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.highlightRadius, style: .continuous)
        return Color.clear
            .contentShape(shape)
            .frame(width: piece.rect.width, height: piece.rect.height)
            .onTapGesture { box.forEach(onDisable) }
            #if os(macOS)
            .pointerStyle(.link)
            .help("Click to keep “\(Self.words(of: box, in: text))” as text")
            #endif
            .position(x: piece.rect.midX, y: piece.rect.midY)
            .accessibilityHidden(true)
    }

    private var drawableTokens: [QuickAddToken] { Self.drawable(tokens, in: text) }

    /// The tokens that can be drawn on this text: not superseded, in order, not overlapping, inside it.
    static func drawable(_ tokens: [QuickAddToken], in text: String) -> [QuickAddToken] {
        var result: [QuickAddToken] = []
        for token in tokens.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            guard !token.isSuperseded, token.range.upperBound <= text.endIndex, !token.range.isEmpty,
                  result.last.map({ $0.range.upperBound <= token.range.lowerBound }) ?? true else { continue }
            result.append(token)
        }
        return result
    }

    /// The words a box covers, as typed: "tom 4".
    static func words(of box: [QuickAddToken], in text: String) -> String {
        guard let first = box.first, let last = box.last, first.range.lowerBound <= last.range.upperBound,
              last.range.upperBound <= text.endIndex else { return box.map(\.text).joined(separator: " ") }
        return String(text[first.range.lowerBound..<last.range.upperBound])
    }

    // MARK: Layout of the highlights (internal for the render tests)

    /// Tags the words of token number `index` in the clear copy.
    struct TokenSpan: TextAttribute {
        let index: Int
    }

    /// Which box each of `tokens` (drawable, in order) belongs to: neighbours of the same colour with only
    /// spaces between them share one (George, 2026-11-04: "[tom] [4]" should be "[tom 4]"). Numbered from 0
    /// in order; a word, an overridden phrase or another colour between two tokens starts a new box.
    static func groups(_ tokens: [QuickAddToken], in text: String, priority: Priority) -> [Int] {
        var groups: [Int] = []
        for (index, token) in tokens.enumerated() {
            guard let previous = groups.last else { groups.append(0); continue }
            let before = tokens[index - 1]
            let gap = before.range.upperBound <= token.range.lowerBound && token.range.lowerBound <= text.endIndex
                ? text[before.range.upperBound..<token.range.lowerBound] : "x"
            let joins = gap.allSatisfy { $0.isWhitespace && !$0.isNewline }
                && PopoutTint.token(before.kind, priority: priority) == PopoutTint.token(token.kind, priority: priority)
            groups.append(joins ? previous : previous + 1)
        }
        return groups
    }

    /// Token indices per group, in order.
    static func members(of groups: [Int]) -> [[Int]] {
        var members: [[Int]] = []
        for (index, group) in groups.enumerated() {
            if group < members.count { members[group].append(index) } else { members.append([index]) }
        }
        return members
    }

    /// One piece of a highlight box: the box's tokens' areas on one line joined into one rectangle, the
    /// spaces between them included. A box that wraps has one piece per line; each stands for the box.
    struct Box: Identifiable, Equatable {
        /// Every token in the box (indices into the list given to `highlightText`), on any line.
        var tokens: [Int]
        var line: Int
        var rect: CGRect
        var id: String { "\(tokens[0]).\(line)" }
    }

    /// The boxes for `areas` (from `areas(_:in:)`), with `groups` from `groups(_:in:priority:)`.
    static func boxes(_ areas: [Area], groups: [Int]) -> [Box] {
        let members = members(of: groups)
        var boxes: [Box] = []
        var lastGroup: Int?
        for area in areas where area.token < groups.count {
            let group = groups[area.token]
            if let last = boxes.indices.last, lastGroup == group, boxes[last].line == area.line {
                boxes[last].rect = boxes[last].rect.union(area.rect)
            } else {
                boxes.append(Box(tokens: members[group], line: area.line, rect: area.rect))
            }
            lastGroup = group
        }
        return boxes
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

/// Return typed into a one-line title (the quick-add field and the editor's title, both vertical fields that
/// take it as a line break). iPhone and iPad (brief 36, George: "only allow task confirmation via the
/// Confirm task button"): the typed break is dropped and the title stays exactly as it was. The Mac: Return
/// confirms, as before. A pasted line break becomes a space either way (`TaskLimits.singleLine`).
enum TitleReturn {
    struct Outcome: Equatable {
        var text: String
        var submits: Bool
    }

    #if os(macOS)
    static let returnSubmits = true
    #else
    static let returnSubmits = false
    #endif

    /// What the field's text becomes after a change from `old` to `new`; nil when `new` has no line break.
    static func resolve(old: String, new: String, returnSubmits: Bool = returnSubmits) -> Outcome? {
        guard new.contains(where: \.isNewline) else { return nil }
        if returnSubmits { return Outcome(text: TaskLimits.singleLine(new), submits: true) }
        if isTypedReturn(old: old, new: new) { return Outcome(text: old, submits: false) }
        return Outcome(text: TaskLimits.singleLine(new), submits: false)
    }

    /// `new` is `old` with one line break put in somewhere: the Return key, not a paste.
    private static func isTypedReturn(old: String, new: String) -> Bool {
        let before = Array(old), after = Array(new)
        guard after.count == before.count + 1 else { return false }
        let i = zip(before, after).prefix { $0 == $1 }.count
        return after[i].isNewline && after[(i + 1)...].elementsEqual(before[i...])
    }
}
