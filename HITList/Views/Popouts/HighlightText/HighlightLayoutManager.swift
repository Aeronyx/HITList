#if os(iOS)
import UIKit
typealias HighlightEditActions = NSTextStorage.EditActions
#else
import AppKit
typealias HighlightEditActions = NSTextStorageEditActions
#endif

/// The title's TextKit layout manager: it lays the text out as usual and, before the selection and the
/// glyphs, fills a rounded box behind each highlight (`HighlightRun`), placed from its own line fragments
/// (`HighlightGeometry`). Drawing happens in the text view's own drawing pass, so the boxes move with the
/// words when the text wraps, scrolls or is edited; nothing sits above the text view to fight its cursor
/// or its touches (brief 47).
final class HighlightLayoutManager: NSLayoutManager {
    /// The boxes to draw. Set by the text view after each parse; edits move them in between (`processEditing`).
    var runs: [HighlightRun] = [] {
        didSet {
            guard runs.count != oldValue.count || zip(runs, oldValue).contains(where: { !$0.looksLike($1) }) else { return }
            invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0))
            onRunsChange?()
        }
    }
    /// Characters being composed by an input method (marked text): a box there waits until it is committed.
    var composing: NSRange? {
        didSet { if composing != oldValue { invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0)) } }
    }
    /// The boxes' corner radius (`TokenHighlightField.highlightRadius`).
    var cornerRadius: CGFloat = 4
    /// Called when the boxes change, so the view can redraw and refresh its cursor rects or pointer regions.
    var onRunsChange: (() -> Void)?

    override init() {
        super.init()
        // Its own delegate, for where a line may break (`HighlightLineBreaks`).
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    /// The runs that are drawn and can be hit: not inside the text being composed.
    var visibleRuns: [Int] {
        runs.indices.filter { index in
            guard let composing, composing.length > 0 else { return true }
            return NSIntersectionRange(composing, runs[index].range).length == 0
        }
    }

    /// The visible boxes' pieces, in text container coordinates; `Piece.run` indexes `runs`.
    func pieces() -> [HighlightGeometry.Piece] {
        guard let container = textContainers.first else { return [] }
        let visible = visibleRuns
        return HighlightGeometry.pieces(for: visible.map { runs[$0].range }, layoutManager: self, container: container)
            .map { HighlightGeometry.Piece(run: visible[$0.run], line: $0.line, rect: $0.rect) }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        #if os(iOS)
        let context = UIGraphicsGetCurrentContext()
        #else
        let context = NSGraphicsContext.current?.cgContext
        #endif
        if let context, !runs.isEmpty {
            context.saveGState()
            for piece in pieces() {
                let rect = piece.rect.offsetBy(dx: origin.x, dy: origin.y)
                let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
                context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.setFillColor(runs[piece.run].color)
                context.fillPath()
            }
            context.restoreGState()
        }
        // The selection and any background attributes draw over the boxes.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Every edit (typing, paste, dictation, undo, marked text) moves the boxes after it and drops the ones
    /// it touches, so they stay on their words until the parse of the new text replaces them.
    override func processEditing(for textStorage: NSTextStorage, edited editMask: HighlightEditActions,
                                 range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta,
                             invalidatedRange: invalidatedCharRange)
        guard editMask.contains(.editedCharacters), !runs.isEmpty else { return }
        let old = NSRange(location: newCharRange.location, length: newCharRange.length - delta)
        runs = runs.compactMap { run in
            guard let moved = HighlightRules.carried(run.range, overEditOf: old, newLength: newCharRange.length) else { return nil }
            var run = run
            run.range = moved
            return run
        }
    }
}

extension HighlightLayoutManager: NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        HighlightLineBreaks.allowsBreak(before: charIndex, in: (textStorage?.string ?? "") as NSString)
    }
}

/// Where the title may wrap. TextKit takes a "!" for the end of a word, so "!30mb" at a line's end left the "!" on
/// one line and "30mb" on the next, its highlight in two pieces (round 25, on the iPhone, in the very title a friend
/// had typed). A "!" stays with the word it starts ("!30mb", "!at", "!!1"): the line breaks before the "!" instead.
/// A "!" that ends a sentence has a space after it and wraps as it always did.
enum HighlightLineBreaks {
    static func allowsBreak(before index: Int, in text: NSString) -> Bool {
        guard index > 0, index < text.length, text.character(at: index - 1) == 0x21 else { return true }
        guard let next = Unicode.Scalar(text.character(at: index)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(next)
    }
}
