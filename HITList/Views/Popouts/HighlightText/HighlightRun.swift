import Foundation
import CoreGraphics
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// One highlight box in the quick-add title as the native text view keeps it (brief 47): the stretch of the
/// title from a box's first token to its last ("tom 4" in "[tom 4]", spaces between included), as UTF-16
/// offsets of the text view's string, with the box's colour and what switching it off does.
/// `TokenHighlightField` builds them from the parse; the text views draw and hit-test by them.
struct HighlightRun {
    /// From the first token's first character to the last token's last (`NSString` offsets).
    var range: NSRange
    /// The tint, already at the highlight's opacity.
    var color: CGColor
    /// The words as typed ("tom 4"), for VoiceOver and the Mac's tooltip.
    var words: String
    /// Switches every token in the box off (`TokenHighlightField.onDisable`, once per token).
    var switchOff: () -> Void

    /// Same place and colour: nothing to redraw.
    func looksLike(_ other: HighlightRun) -> Bool {
        NSEqualRanges(range, other.range) && color == other.color
    }
}

/// The rules the text views share, kept pure for the tests.
enum HighlightRules {
    /// Where a box is after an edit that replaced `old` (a range of the text before it) with `newLength`
    /// characters, until the next parse redraws it: a box before the edit stays, one after it moves with it,
    /// one whose characters the edit replaces or splits is not drawn (the parse decides what it is now).
    /// Keeps the boxes on their words in the moment between a keystroke and SwiftUI's update.
    static func carried(_ range: NSRange, overEditOf old: NSRange, newLength: Int) -> NSRange? {
        if NSMaxRange(range) <= old.location { return range }
        if range.location >= NSMaxRange(old) {
            return NSRange(location: range.location + newLength - old.length, length: range.length)
        }
        return nil
    }

    /// The text views' fields are UTF-16; the parser's tokens index the Swift string.
    static func nsRange(_ range: Range<String.Index>, in text: String) -> NSRange? {
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return nil }
        return NSRange(range, in: text)
    }
}

/// Where the boxes are, read from the text view's own TextKit layout: the same layout manager that draws
/// the glyphs, so a box sits on its words at every width, wrap and scroll position.
enum HighlightGeometry {
    /// One line's piece of a box, in text container coordinates. A box that wraps has one piece per line;
    /// each stands for the whole box (a click or tap on any piece switches the box off).
    struct Piece: Equatable {
        /// The box's index in the list given to `pieces`.
        var run: Int
        /// The line, counted from 0 at the top of the text.
        var line: Int
        var rect: CGRect
    }

    /// The pieces of `ranges` (UTF-16 ranges of the layout manager's text), in order: per line, from the
    /// first to the last non-space character of the box on that line (a space at a wrap is not boxed), as
    /// tall as the line.
    static func pieces(for ranges: [NSRange], layoutManager: NSLayoutManager, container: NSTextContainer) -> [Piece] {
        guard let storage = layoutManager.textStorage, storage.length > 0, !ranges.isEmpty else { return [] }
        let string = storage.string as NSString
        let all = layoutManager.glyphRange(for: container)
        // Every line fragment's glyph range, top to bottom: a piece's line is its index here.
        var lines: [(glyphs: NSRange, used: CGRect)] = []
        layoutManager.enumerateLineFragments(forGlyphRange: all) { _, used, _, glyphs, _ in
            lines.append((glyphs, used))
        }
        var pieces: [Piece] = []
        for (index, range) in ranges.enumerated() {
            let chars = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
            guard chars.length > 0 else { continue }
            let glyphs = layoutManager.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
            for (lineIndex, line) in lines.enumerated() {
                let onLine = NSIntersectionRange(line.glyphs, glyphs)
                guard onLine.length > 0 else { continue }
                var lineChars = layoutManager.characterRange(forGlyphRange: onLine, actualGlyphRange: nil)
                lineChars = trimmed(lineChars, in: string)
                guard lineChars.length > 0 else { continue }
                let lineGlyphs = layoutManager.glyphRange(forCharacterRange: lineChars, actualCharacterRange: nil)
                let bounds = layoutManager.boundingRect(forGlyphRange: lineGlyphs, in: container)
                let rect = CGRect(x: bounds.minX, y: line.used.minY, width: bounds.width, height: line.used.height)
                pieces.append(Piece(run: index, line: lineIndex, rect: rect))
            }
        }
        return pieces
    }

    /// The box under `point` (text container coordinates), if any.
    static func run(at point: CGPoint, in pieces: [Piece]) -> Int? {
        pieces.first { $0.rect.contains(point) }?.run
    }

    /// The text's height at `width` for `lines` lines at most (one at least, so the placeholder fits), laid
    /// out by TextKit as the field lays it out.
    static func height(of text: NSAttributedString, width: CGFloat, maxLines: Int, lineHeight: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        let lines = max(1, Int((used / max(lineHeight, 1)).rounded()))
        return lineHeight * CGFloat(min(lines, maxLines))
    }

    /// One line's height for `font` as TextKit 1 lays it out (what each line of the field adds).
    static func lineHeight(of font: HighlightPlatformFont) -> CGFloat {
        let storage = NSTextStorage(string: "Hg", attributes: [.font: font])
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height
    }

    /// `range` without white space at either end.
    private static func trimmed(_ range: NSRange, in string: NSString) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        let spaces = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = Unicode.Scalar(string.character(at: start)), spaces.contains(scalar) { start += 1 }
        while end > start, let scalar = Unicode.Scalar(string.character(at: end - 1)), spaces.contains(scalar) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
