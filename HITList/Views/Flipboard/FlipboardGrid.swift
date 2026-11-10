import SwiftUI

extension FlipboardLayout {
    /// The switch card's narrowest on the Mac and iPad grid (brief 69): about the Upcoming board's Add task
    /// card, so the name, the quick choices and the dials have room.
    static let cardMinWidth: CGFloat = 300

    /// The Switchboard card's narrowest in place (brief 72): its reset row holds the time field and a weekday.
    static let boardCardMinWidth: CGFloat = 380

    /// How many columns the card takes in the grid: as few as give it `minWidth`, never more than there are.
    static func cardSpan(columns: Int, cellWidth: CGFloat, spacing: CGFloat, minWidth: CGFloat = cardMinWidth) -> Int {
        guard columns > 1 else { return 1 }
        for span in 1...columns where CGFloat(span) * cellWidth + CGFloat(span - 1) * spacing >= minWidth {
            return span
        }
        return columns
    }

    /// A cell's place in the grid.
    struct Slot: Equatable {
        var row: Int
        var column: Int
        var span: Int
    }

    /// Tiles fill rows left to right, one column each; a wider cell (the switch card) that doesn't fit in what
    /// is left of its row starts the next one. A span is clamped to the row.
    static func slots(spans: [Int], columns: Int) -> [Slot] {
        let columns = max(1, columns)
        var row = 0, column = 0
        var result: [Slot] = []
        for wanted in spans {
            let span = min(columns, max(1, wanted))
            if column + span > columns {
                row += 1
                column = 0
            }
            result.append(Slot(row: row, column: column, span: span))
            column += span
            if column >= columns {
                row += 1
                column = 0
            }
        }
        return result
    }

    /// Every cell's frame in a grid `width` wide: `columns` equal columns, cells placed by `slots`, rows top-aligned.
    /// Every cell that doesn't keep its own height (every switch, and the + tile) is as tall as the tallest of them, so
    /// all the switches on a board are one size (George, 2026-11-08: "all switches should be the same width and
    /// height"); a cell that keeps its own (the switch card, which grows with its Discard row) is as tall as it
    /// measures. `measure` gives a cell's height at a width.
    static func frames(width: CGFloat, columns: Int, spacing: CGFloat, spans: [Int], keepsOwnHeight: [Bool],
                       measure: (_ index: Int, _ width: CGFloat) -> CGFloat) -> (frames: [CGRect], size: CGSize) {
        let columns = max(1, columns)
        let cell = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let slots = slots(spans: spans, columns: columns)
        let widths = slots.map { CGFloat($0.span) * cell + CGFloat($0.span - 1) * spacing }
        let measured = widths.indices.map { measure($0, widths[$0]) }
        let ownHeight = { (index: Int) in index < keepsOwnHeight.count && keepsOwnHeight[index] }
        let tile = measured.indices.filter { !ownHeight($0) }.map { measured[$0] }.max() ?? 0
        let heights = measured.indices.map { ownHeight($0) ? measured[$0] : tile }
        let rowCount = (slots.last?.row ?? -1) + 1
        var rowHeights = [CGFloat](repeating: 0, count: rowCount)
        for (slot, height) in zip(slots, heights) { rowHeights[slot.row] = max(rowHeights[slot.row], height) }
        var rowTops = [CGFloat](repeating: 0, count: rowCount)
        for row in rowHeights.indices.dropFirst() { rowTops[row] = rowTops[row - 1] + rowHeights[row - 1] + spacing }
        let frames = zip(slots, zip(widths, heights)).map { slot, size in
            CGRect(x: CGFloat(slot.column) * (cell + spacing), y: rowTops[slot.row], width: size.0, height: size.1)
        }
        let height = rowCount == 0 ? 0 : rowTops[rowCount - 1] + rowHeights[rowCount - 1]
        return (frames, CGSize(width: width, height: height))
    }
}

/// How many columns a cell of `FlipboardGrid` takes (1 unless set).
struct FlipboardGridSpan: LayoutValueKey {
    static let defaultValue = 1
}

/// Whether a cell of `FlipboardGrid` is as tall as it measures (the switch card) rather than the tiles' one height.
struct FlipboardGridKeepsOwnHeight: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// This cell of `FlipboardGrid` takes `span` columns.
    func flipboardGridSpan(_ span: Int) -> some View { layoutValue(key: FlipboardGridSpan.self, value: span) }

    /// This cell of `FlipboardGrid` keeps its own height instead of the tiles' one height.
    func flipboardGridKeepsOwnHeight() -> some View { layoutValue(key: FlipboardGridKeepsOwnHeight.self, value: true) }
}

/// The Flipboard's grid: `columns` equal columns, every tile the same height (the tallest's), rows top-aligned
/// (`FlipboardLayout.frames`). Unlike `LazyVGrid` a cell can take several columns (`flipboardGridSpan`), which the
/// switch card needs on the Mac and iPad: it opens in place of the + tile or of the switch it edits, as wide as two
/// tiles, and keeps its own height (`flipboardGridKeepsOwnHeight`).
struct FlipboardGrid: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 600, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (index, subview) in subviews.enumerated() where index < frames.count {
            let frame = frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    /// Measured every pass, no cache: a cell can grow on its own (the card's Discard row), and a board is a
    /// few dozen tiles at most.
    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        FlipboardLayout.frames(width: width, columns: columns, spacing: spacing,
                               spans: subviews.map { $0[FlipboardGridSpan.self] },
                               keepsOwnHeight: subviews.map { $0[FlipboardGridKeepsOwnHeight.self] }) { index, width in
            subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
    }
}

/// A switch that has just been added (or saved from its card) settles into its place in the grid (brief 69): it
/// comes in a touch small and springs to size with a little overshoot, like a part pressed into a panel.
/// Reduce Motion: nothing moves.
struct SwitchLanding: ViewModifier {
    /// Which switch lands, and a count so the same switch can land again.
    struct Mark: Equatable {
        let id: UUID
        let generation: Int
    }

    /// This tile's landing, or nil.
    let mark: Mark?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0

    /// How small it starts and how its spring settles.
    static let startScale: CGFloat = 0.86
    static let spring = Spring(response: 0.42, dampingRatio: 0.55)

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(Self.startScale, duration: 0.001)
                    // The spring's own settling time: a segment cut short holds wherever the spring was then
                    // (a tile stayed at 93%). Then exactly full size.
                    SpringKeyframe(1, spring: Self.spring)
                    LinearKeyframe(1, duration: 0.001)
                }
            }
            // A new tile appears already marked; an edited one is marked while on show.
            .onAppear { if mark != nil { settle() } }
            .onChange(of: mark) { _, new in if new != nil { settle() } }
    }

    private func settle() {
        guard !reduceMotion else { return }
        trigger += 1
    }
}
