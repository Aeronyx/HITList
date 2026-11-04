import Foundation

/// A recognised token's kind and words (case and spacing ignored), not where it sits: what a switched-off
/// token is known by (brief 28). The quick-add card adds the place (`QuickAddDisabledPhrase`, brief 41).
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

/// One switched-off phrase where it sits in the text (brief 41): its key and its place, so another copy of
/// the same words typed elsewhere is highlighted, and the phrase is forgotten once its words are edited or
/// deleted (retyping them highlights them again). `carried(_:from:to:)` follows each place through an edit.
public struct QuickAddDisabledPhrase: Hashable, Codable, Sendable {
    public var key: QuickAddTokenKey
    /// UTF-8 offsets of the words as typed.
    public var start: Int
    public var length: Int

    public init(key: QuickAddTokenKey, start: Int, length: Int) {
        self.key = key
        self.start = start
        self.length = length
    }

    /// The token `token` of `text` (its range indexes `text`); nil if the range is not inside it.
    public init?(_ token: QuickAddToken, in text: String) {
        guard token.range.lowerBound >= text.startIndex, token.range.upperBound <= text.endIndex else { return nil }
        let start = text.utf8.distance(from: text.startIndex, to: token.range.lowerBound)
        let end = text.utf8.distance(from: text.startIndex, to: token.range.upperBound)
        self.init(key: token.key, start: start, length: end - start)
    }

    var span: Range<Int> { start..<(start + length) }

    /// The phrases still in the text after it changed from `old` to `new`: a phrase before or after the
    /// changed stretch moves with it; one the change touches (a character of it typed over, deleted or put
    /// inside it) is forgotten, as is one whose words are no longer there.
    public static func carried(_ phrases: Set<QuickAddDisabledPhrase>, from old: String, to new: String) -> Set<QuickAddDisabledPhrase> {
        guard !phrases.isEmpty, old != new else { return phrases }
        let a = Array(old.utf8), b = Array(new.utf8)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let changedEnd = a.count - suffix
        let delta = b.count - a.count
        var kept = Set<QuickAddDisabledPhrase>()
        for var phrase in phrases {
            if phrase.span.upperBound <= prefix {
                // Before the change.
            } else if phrase.start >= changedEnd {
                phrase.start += delta
            } else {
                continue
            }
            if phrase.isPresent(in: new) { kept.insert(phrase) }
        }
        return kept
    }

    /// Its words are at its place in `text`.
    func isPresent(in text: String) -> Bool {
        let utf8 = text.utf8
        guard start >= 0, length > 0, start + length <= utf8.count,
              let lower = utf8.index(utf8.startIndex, offsetBy: start, limitedBy: utf8.endIndex),
              let upper = utf8.index(lower, offsetBy: length, limitedBy: utf8.endIndex),
              String.Index(lower, within: text) != nil, String.Index(upper, within: text) != nil else { return false }
        return QuickAddTokenKey(kind: key.kind, text: String(text[lower..<upper])) == key
    }
}

extension QuickAddParser {
    /// `parse(_:)`, with every token whose key is in `disabled` left as plain title text, wherever it sits:
    /// it sets nothing, is not in `tokens`, and its words appear in `title` exactly as typed. Words the parser
    /// would have read differently once a token is off are read again (switching off the winning "p3"
    /// lets the superseded "p2" before it apply again; another copy of a switched-off "tom" stays plain
    /// too). A superseded token whose key is switched off is masked as well, so it never comes back.
    /// Token ranges index `input`. The quick-add card switches off phrases by place instead
    /// (`parse(_:switchedOff:)`).
    public func parse(_ input: String, disabling disabled: Set<QuickAddTokenKey>) -> QuickAddResult {
        guard !disabled.isEmpty else { return parse(input) }
        return parse(input) { key, _ in disabled.contains(key) }
    }

    /// `parse(_:disabling:)` for phrases switched off where they sit (brief 41): only the token with that key
    /// at that place is plain; the same words typed anywhere else are read as usual.
    public func parse(_ input: String, switchedOff phrases: Set<QuickAddDisabledPhrase>) -> QuickAddResult {
        guard !phrases.isEmpty else { return parse(input) }
        return parse(input) { key, span in
            phrases.contains(QuickAddDisabledPhrase(key: key, start: span.lowerBound, length: span.count))
        }
    }

    /// How: each switched-off span is swapped for a one-character placeholder no rule matches and the
    /// text is parsed again, until no switched-off token is left; ranges and the title are then mapped
    /// back to the text as typed. `isOff` gets a token's key and its UTF-8 span in `input`.
    private func parse(_ input: String, isOff: (QuickAddTokenKey, Range<Int>) -> Bool) -> QuickAddResult {
        var masked = MaskedText(input)
        var result = parse(input)
        // Each round masks at least one more word, so this ends within the word count.
        while true {
            let spans = result.tokens.compactMap { token -> Range<Int>? in
                let span = masked.originalOffsets(of: token.range)
                let words = String(input[masked.originalIndex(span.lowerBound)..<masked.originalIndex(span.upperBound)])
                return isOff(QuickAddTokenKey(kind: token.kind, text: words), span) ? span : nil
            }
            guard !spans.isEmpty else { break }
            let before = masked.spanCount
            masked.mask(spans)
            // Nothing new to mask (a span already masked): stop rather than go round again.
            guard masked.spanCount > before else { break }
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
    var spanCount: Int { spans.count }

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
