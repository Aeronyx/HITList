import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@testable import HITList

/// Round 34, brief 173: at the accessibility text sizes what a person reads keeps growing, and the dense controls
/// that cannot grow without breaking stop at `HITType.controlSizeCap`.
@MainActor
final class LargeTextTests: XCTestCase {
    /// The first accessibility size: the largest at which the iPhone's pictures of every capped control held.
    func testTheCapIsTheFirstAccessibilitySize() {
        XCTAssertEqual(HITType.controlSizeCap, .accessibility1)
        XCTAssertTrue(HITType.controlSizeCap.isAccessibilitySize)
    }

    #if os(iOS)
    private func height(_ view: some View, width: CGFloat, _ size: DynamicTypeSize) -> CGFloat {
        // Its own height (a tile fills what it is offered), at the width it would have.
        let sized = view.fixedSize(horizontal: false, vertical: true).frame(width: width)
            .environment(\.dynamicTypeSize, size)
        return UIHostingController(rootView: sized).sizeThatFits(in: CGSize(width: width, height: 4000)).height
    }

    /// Each capped control is as tall at the largest size as at the cap, and still grows below it.
    func testTheDenseControlsStopGrowingAtTheCap() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let strip = WeekStrip(calendar: calendar)
        let controls: [(String, AnyView, CGFloat)] = [
            ("a switch's face", AnyView(FlipSwitchFace.standIn), 180),
            ("the Add switch outline", AnyView(AddSwitchTile(action: {})), 180),
            ("the theme grid", AnyView(ThemeSwatchRow(selection: .slate) { _ in }), 360),
            ("the week strip", AnyView(WeekStripView(strip: strip, today: today, focusedDay: today, counts: [:],
                                                     weeks: -1...4, visibleWeek: .constant(0), dropTarget: .constant(nil),
                                                     onDrop: { _, _ in false }, onSelect: { _ in })), 402),
        ]
        for (name, view, width) in controls {
            let atCap = height(view, width: width, HITType.controlSizeCap)
            XCTAssertEqual(height(view, width: width, .accessibility5), atCap, accuracy: 0.5,
                           "\(name) grew past the cap")
            XCTAssertEqual(height(view, width: width, .accessibility3), atCap, accuracy: 0.5,
                           "\(name) grew past the cap")
            XCTAssertLessThan(height(view, width: width, .large), atCap, "\(name) no longer grows below the cap")
        }
    }

    /// Quick add's row of chips is as tall as its chips (with their 1 pt borders) at every size up to the cap, so no
    /// chip is cut along its edge (brief 169's pictures, AX1); and a chip's words fit inside the chip there.
    func testQuickAddsChipRowIsAsTallAsItsChips() {
        XCTAssertEqual(QuickAddChipRow<EmptyView, Int>.minimumHeight, HITChip.Size.compact.height + 2)
        func chip() -> some View { HITChip("11:00 AM", systemImage: "alarm", isSelected: true, size: .compact) {} }
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility5] {
            let row = QuickAddChipRow(signature: [0: "11:00 AM"]) { chip(); chip() }
                .dynamicTypeSize(...HITType.controlSizeCap)
            let chipHeight = height(chip(), width: 200, min(size, HITType.controlSizeCap))
            XCTAssertGreaterThanOrEqual(height(row, width: 360, size), chipHeight + 2 - 0.5,
                                        "the row is shorter than its chips at \(size)")
            // Offered less room than that, it still takes a chip's height.
            let squeezed = UIHostingController(rootView: row.environment(\.dynamicTypeSize, size))
                .sizeThatFits(in: CGSize(width: 360, height: 12)).height
            XCTAssertGreaterThanOrEqual(squeezed, QuickAddChipRow<EmptyView, Int>.minimumHeight - 0.5,
                                        "a squeezed row cut its chips at \(size)")
            let words = Text("11:00 AM").font(HITType.subheadlineMedium).lineLimit(1).fixedSize()
            XCTAssertLessThanOrEqual(height(words, width: 200, min(size, HITType.controlSizeCap)), chipHeight,
                                     "a chip's words are taller than the chip at \(size)")
        }
    }
    #endif
}
