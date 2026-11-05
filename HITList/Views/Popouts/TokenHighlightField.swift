import SwiftUI
import HITListCore

/// The quick-add title: `HITField`'s box (`HITFieldChrome`) around a wrapping text field, with each
/// recognised token (dates, times, repeats, `#project`, `@label`, `p1`-`p4`, `!15mb`) tinted behind the
/// text as you type, in a lightly rounded box that reads as a button. Highlights of the same colour with
/// only spaces between them are one box ("[tom 4]", brief 37). A box is switched off two ways (George,
/// 2026-11-05): a tap or click on it, or Backspace with the caret right after it, which deletes nothing the
/// first time (the next Backspace deletes a letter). Either way `onDisable` runs once per token in the box
/// and the words stay as plain title text; Undo brings the box back (`onEnable`). Return never starts a new
/// line: on the Mac it submits, on iOS it does nothing (`TitleReturn`, brief 36). `bordered: false` drops
/// the box, for the quick-add card where the card itself is the frame.
///
/// How the highlights are drawn and hit (brief 47): the field is the platform's own text view
/// (`HighlightTextField`: `UITextView` / `NSTextView` on TextKit 1), whose layout manager draws each box
/// behind its glyphs from the text view's own line layout, so boxes sit on the words at every width, wrap
/// and scroll. The same view hit-tests the boxes for taps, clicks, the Mac's pointing hand and the iPad
/// pointer, and owns Backspace; nothing is layered above it.
struct TokenHighlightField: View {
    let placeholder: String
    @Binding var text: String
    var tokens: [QuickAddToken]
    var priority: Priority
    var focus: FocusState<Bool>.Binding
    var bordered = true
    /// A highlight was tapped, clicked or backspaced; nil leaves the highlights as decoration.
    var onDisable: ((QuickAddToken) -> Void)? = nil
    /// Undo of `onDisable`: the token lights up again. Nil: switching off is not undoable.
    var onEnable: ((QuickAddToken) -> Void)? = nil
    var onSubmit: () -> Void

    /// The highlight's corners (George, brief 28: "slightly rounded, like a button").
    static let highlightRadius: CGFloat = 4
    /// The highlight's tint strength, as before.
    static let highlightOpacity: Double = 0.3

    var body: some View {
        if bordered {
            field.modifier(HITFieldChrome(isFocused: focus.wrappedValue))
        } else {
            field
        }
    }

    private var field: some View {
        HighlightTextField(placeholder: placeholder, text: $text, runs: runs, style: .current(),
                           isFocused: focus.wrappedValue, onFocusChange: { focus.wrappedValue = $0 },
                           onSubmit: onSubmit)
            .focused(focus)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: text) { old, new in
                // The text views turn Return and pasted line breaks into what they should be before they land;
                // a line break that arrives some other way (the owner's text) is resolved here, as before.
                guard let outcome = TitleReturn.resolve(old: old, new: new) else { return }
                text = outcome.text
                if outcome.submits { onSubmit() }
            }
    }

    /// The boxes as the text view keeps them: place, colour, words, and switching off and back on.
    private var runs: [HighlightRun] {
        let tokens = Self.drawable(tokens, in: text)
        return Self.spans(tokens, in: text, priority: priority).map { span in
            let members = span.tokens.map { tokens[$0] }
            let tint = PopoutTint.token(members[0].kind, priority: priority).opacity(Self.highlightOpacity)
            return HighlightRun(range: span.range, color: HighlightPlatformColor(tint).cgColor,
                                words: Self.words(of: members, in: text),
                                switchOff: { [onDisable] in members.forEach { onDisable?($0) } },
                                switchOn: onEnable.map { enable in { members.reversed().forEach(enable) } })
        }
    }

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

    // MARK: Boxes (internal for the tests)

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

    /// One highlight box's stretch of the title: its tokens, and the text from the first one's start to the
    /// last one's end (spaces between included), in the text view's UTF-16 offsets. Where the box is drawn,
    /// line by line, is the text view's layout (`HighlightGeometry.pieces`).
    struct Span: Equatable {
        /// Indices into the drawable tokens.
        var tokens: [Int]
        var range: NSRange
    }

    /// The boxes' spans for `tokens` (drawable, in order) in `text`.
    static func spans(_ tokens: [QuickAddToken], in text: String, priority: Priority) -> [Span] {
        members(of: groups(tokens, in: text, priority: priority)).compactMap { indices in
            guard let first = indices.first, let last = indices.last,
                  tokens[first].range.lowerBound <= tokens[last].range.upperBound,
                  let range = HighlightRules.nsRange(tokens[first].range.lowerBound..<tokens[last].range.upperBound, in: text)
            else { return nil }
            return Span(tokens: indices, range: range)
        }
    }

    // MARK: The SwiftUI copy and click targets (no longer drawn; item 4 removes them)

    #if os(macOS)
    /// The Mac `TextEditor` starts its text this far in (its text container's line-fragment padding, which
    /// `PopoutTests.testTheMacEditorInsetMatchesTheHighlightCopy` pins); the clear copy is inset the same so
    /// the tints sit under the words.
    static let editorTextInset: CGFloat = 5
    #else
    static let editorTextInset: CGFloat = 0
    #endif

    #if os(macOS)
    /// A highlight box's click target on the Mac: an AppKit view above the text, so the pointing hand wins
    /// over the I-beam (George, 0.5.0: "my cursor should replace with the 'clickable' cursor"). SwiftUI's
    /// `.pointerStyle(.link)` on a shape lost to the `TextEditor` underneath: the text view's own cursor rect
    /// and its mouse-moved I-beam came first. This view is what the pointer meets over a box (`hitTest`), it
    /// sets the hand on entering and on every move, and a click on it switches the box off.
    struct ClickTarget: NSViewRepresentable {
        var help: String
        var action: () -> Void

        func makeNSView(context: Context) -> View { View() }

        func updateNSView(_ view: View, context: Context) {
            view.action = action
            view.toolTip = help
        }

        final class View: NSView {
            var action: () -> Void = {}

            override func resetCursorRects() {
                addCursorRect(bounds, cursor: .pointingHand)
            }

            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
                addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited,
                                                                      .activeInKeyWindow, .inVisibleRect],
                                               owner: self))
            }

            override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
            override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
            override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            override func mouseDown(with event: NSEvent) { action() }
        }
    }
    #endif

    /// Tags the words of token number `index` in the clear copy.
    struct TokenSpan: TextAttribute {
        let index: Int
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
