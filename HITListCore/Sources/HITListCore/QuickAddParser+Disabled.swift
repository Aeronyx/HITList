import Foundation

/// A recognised token the user has switched off by tapping its highlight in the quick-add card (brief 28):
/// the words stay in the title as plain text. A token is known by its kind and its words (case and
/// spacing ignored), not by where it sits, so the choice survives typing anywhere else in the text.
public struct QuickAddTokenKey: Hashable, Codable, Sendable {
    public var kind: QuickAddToken.Kind
    /// Lowercased, runs of whitespace as one space.
    public var text: String

    public init(kind: QuickAddToken.Kind, text: String) {
        self.kind = kind
        self.text = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public init(_ token: QuickAddToken) {
        self.init(kind: token.kind, text: token.text)
    }
}

extension QuickAddToken.Kind: Codable {}

extension QuickAddToken {
    /// What identifies this token when it is switched off.
    public var key: QuickAddTokenKey { QuickAddTokenKey(self) }
}

extension QuickAddParser {
    /// `parse(_:)`, with every token whose key is in `disabled` left as plain title text: it sets
    /// nothing, is not in `tokens`, and its words appear in `title` exactly as typed. Words the parser
    /// would have read differently once a token is off are read again (switching off the winning "p3"
    /// lets the superseded "p2" before it apply again; another copy of a switched-off "tom" stays plain
    /// too). A superseded token whose key is switched off is masked as well, so it never comes back.
    /// Token ranges index `input`.
    ///
    /// How: each switched-off span is swapped for a one-character placeholder no rule matches and the
    /// text is parsed again, until no switched-off token is left; ranges and the title are then mapped
    /// back to the text as typed.
    public func parse(_ input: String, disabling disabled: Set<QuickAddTokenKey>) -> QuickAddResult {
        guard !disabled.isEmpty else { return parse(input) }
        var masked = MaskedText(input)
        var result = parse(input)
        // Each round masks at least one more word, so this ends within the word count.
        while true {
            let off = result.tokens.filter { disabled.contains($0.key) }
            guard !off.isEmpty else { break }
            let spans = off.map { masked.originalOffsets(of: $0.range) }
            masked.mask(spans)
            result = parse(masked.text)
        }
        guard masked.hasMasks else { return result }
        result.tokens = result.tokens.map { token in
            let offsets = masked.originalOffsets(of: token.range)
            let range = masked.originalIndex(offsets.lowerBound)..<masked.originalIndex(offsets.upperBound)
            return QuickAddToken(kind: token.kind, range: range, text: String(input[range]), isSuperseded: token.isSuperseded)
        }
        result.title = masked.restoringPlaceholders(in: result.title)
        return result
    }
}

/// The input with some spans swapped for placeholders, and the way back. Offsets are UTF-8 offsets
/// into the original text (placeholders sit between whole words, so every mapped offset falls on a
/// character boundary).
private struct MaskedText {
    let original: String
    /// Masked spans of `original`, sorted, not overlapping.
    private(set) var spans: [Range<Int>] = []
    private(set) var text: String
    /// The masked text's pieces in order: either a run copied from the original or a placeholder.
    private var pieces: [(masked: Range<Int>, original: Range<Int>, isPlaceholder: Bool)] = []

    /// Supplementary Private Use Area-A: nothing the parser recognises, and nothing anyone types.
    private static let placeholderBase: UInt32 = 0xF0000

    init(_ original: String) {
        self.original = original
        self.text = original
        rebuild()
    }

    var hasMasks: Bool { !spans.isEmpty }

    mutating func mask(_ newSpans: [Range<Int>]) {
        var all = spans
        for span in newSpans where !span.isEmpty && !all.contains(where: { $0.overlaps(span) }) {
            all.append(span)
        }
        spans = all.sorted { $0.lowerBound < $1.lowerBound }
        rebuild()
    }

    private mutating func rebuild() {
        let bytes = Array(original.utf8)
        var out: [UInt8] = []
        pieces = []
        var cursor = 0
        func copy(upTo end: Int) {
            guard end > cursor else { return }
            pieces.append((out.count..<(out.count + end - cursor), cursor..<end, false))
            out.append(contentsOf: bytes[cursor..<end])
            cursor = end
        }
        for (k, span) in spans.enumerated() {
            copy(upTo: span.lowerBound)
            let placeholder = Array(String(Self.placeholder(k)).utf8)
            pieces.append((out.count..<(out.count + placeholder.count), span, true))
            out.append(contentsOf: placeholder)
            cursor = span.upperBound
        }
        copy(upTo: bytes.count)
        text = String(decoding: out, as: UTF8.self)
    }

    private static func placeholder(_ k: Int) -> Character {
        Character(Unicode.Scalar(placeholderBase + UInt32(k))!)
    }

    /// A range of `text` as UTF-8 offsets into `original`; a placeholder maps to its whole span.
    func originalOffsets(of range: Range<String.Index>) -> Range<Int> {
        let lower = text.utf8.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.utf8.distance(from: text.startIndex, to: range.upperBound)
        return map(lower, isUpper: false)..<max(map(lower, isUpper: false), map(upper, isUpper: true))
    }

    private func map(_ offset: Int, isUpper: Bool) -> Int {
        for piece in pieces {
            let inside = isUpper ? (piece.masked.lowerBound < offset && offset <= piece.masked.upperBound)
                                 : (piece.masked.lowerBound <= offset && offset < piece.masked.upperBound)
            guard inside else { continue }
            if piece.isPlaceholder { return isUpper ? piece.original.upperBound : piece.original.lowerBound }
            return piece.original.lowerBound + (offset - piece.masked.lowerBound)
        }
        return isUpper || offset > 0 ? original.utf8.count : 0
    }

    func originalIndex(_ offset: Int) -> String.Index {
        original.utf8.index(original.startIndex, offsetBy: offset)
    }

    /// The parser's title with each placeholder back to the words it stood for.
    func restoringPlaceholders(in title: String) -> String {
        var out = ""
        for character in title {
            if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
               scalar.value >= Self.placeholderBase, Int(scalar.value - Self.placeholderBase) < spans.count {
                let span = spans[Int(scalar.value - Self.placeholderBase)]
                out += String(original[originalIndex(span.lowerBound)..<originalIndex(span.upperBound)])
            } else {
                out.append(character)
            }
        }
        return out
    }
}
