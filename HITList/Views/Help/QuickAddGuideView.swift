import SwiftUI
import HITListCore

/// The quick add guide's groups (brief 98): one card per topic, a row per example, the typed words drawn with the
/// parser's own highlights and a caption under them. No header of its own: the page's title says Quick add (the
/// Settings sheet's page, `SettingsPage.quickAddGuide`), or the row above it does (the Mac's Settings → General).
struct QuickAddGuidePage: View {
    /// When the examples are typed: their dates are worked out from it.
    var now = Date()

    var body: some View {
        let weekStart = Preferences.weekStartWeekday()
        let parser = QuickAddGuide.parser(now: now, calendar: .current, weekStart: weekStart)
        ForEach(QuickAddGuide.sections(now: now, calendar: .current, weekStart: weekStart)) { section in
            HITGroup(section.title) {
                ForEach(section.examples) { example in
                    QuickAddGuideRow(example: example, result: parser.parse(example.typed))
                }
            }
        }
    }
}

/// One example: what is typed, highlighted as the quick-add card would, and what it does.
struct QuickAddGuideRow: View {
    let example: QuickAddGuide.Example
    let result: QuickAddResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            QuickAddGuideLine(text: example.typed, tokens: result.tokens, priority: result.priority)
                .font(HITType.body)
                .foregroundStyle(HITColor.text)
            Text(example.caption)
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hitRowPadding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(example.typed). \(example.caption)"))
        .accessibilityIdentifier("guide-example")
    }
}

/// Typed words with the quick-add field's highlights: the same boxes (`TokenHighlightField`'s grouping, its tint
/// strength and corners) behind the same tokens, drawn as text so they wrap with it.
struct QuickAddGuideLine: View {
    let text: String
    let tokens: [QuickAddToken]
    let priority: Priority

    /// Pieces of `text` in order: plain words, or a box (its index and colour).
    struct Piece: Equatable {
        var text: String
        var box: Int?
        var kind: QuickAddToken.Kind?
    }

    /// `text` cut into plain words and boxes, as `TokenHighlightField` draws them (neighbours of one colour with only
    /// spaces between are one box: "tom 9").
    static func pieces(_ text: String, tokens: [QuickAddToken], priority: Priority) -> [Piece] {
        let drawable = TokenHighlightField.drawable(tokens, in: text)
        let boxes = TokenHighlightField.members(of: TokenHighlightField.groups(drawable, in: text, priority: priority))
        var pieces: [Piece] = []
        var cursor = text.startIndex
        for (number, members) in boxes.enumerated() {
            guard let first = members.first, let last = members.last else { continue }
            let range = drawable[first].range.lowerBound..<drawable[last].range.upperBound
            guard range.lowerBound >= cursor else { continue }
            if cursor < range.lowerBound { pieces.append(Piece(text: String(text[cursor..<range.lowerBound]))) }
            pieces.append(Piece(text: String(text[range]), box: number, kind: drawable[first].kind))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { pieces.append(Piece(text: String(text[cursor...]))) }
        return pieces
    }

    var body: some View {
        let parts = Self.pieces(text, tokens: tokens, priority: priority).map { piece -> Text in
            guard let box = piece.box, let kind = piece.kind else { return Text(verbatim: piece.text) }
            let tint = PopoutTint.token(kind, priority: priority).opacity(TokenHighlightField.highlightOpacity)
            return Text(verbatim: piece.text).customAttribute(GuideBox(number: box, color: tint))
        }
        parts.reduce(Text(verbatim: "")) { Text("\($0)\($1)") }
            .textRenderer(GuideBoxRenderer())
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A run of text inside a highlight box.
private struct GuideBox: TextAttribute {
    var number: Int
    var color: Color
}

/// Draws each box behind its words, one rounded rectangle per line it covers, then the text. The box is the field's
/// (`HighlightGeometry.boxRect`): from a little above the capitals to below the descenders, `boxPadding` ems of room
/// above and below and a little less either side.
private struct GuideBoxRenderer: TextRenderer {
    /// Inter's capital height and its line's ascent plus descent, in ems (the field reads them from the font).
    static let capHeight: CGFloat = 0.727
    static let lineEms: CGFloat = 1.211

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            var boxes: [(number: Int, color: Color, rect: CGRect)] = []
            for run in line {
                guard let box = run[GuideBox.self] else { continue }
                let rect = Self.boxRect(run.typographicBounds)
                if let last = boxes.last, last.number == box.number {
                    boxes[boxes.count - 1].rect = last.rect.union(rect)
                } else {
                    boxes.append((box.number, box.color, rect))
                }
            }
            for box in boxes {
                let shape = RoundedRectangle(cornerRadius: TokenHighlightField.highlightRadius, style: .continuous)
                context.fill(shape.path(in: box.rect), with: .color(box.color))
            }
        }
        for line in layout { context.draw(line) }
    }

    static func boxRect(_ bounds: Text.Layout.TypographicBounds) -> CGRect {
        let em = (bounds.ascent + bounds.descent) / lineEms
        let baseline = bounds.origin.y
        let pad = HighlightGeometry.boxPadding * em
        let side = 0.6 * pad
        let top = baseline - (capHeight + 0.03) * em - pad
        let bottom = baseline + bounds.descent + pad
        return CGRect(x: bounds.origin.x - side, y: top, width: bounds.width + 2 * side, height: bottom - top)
    }
}
