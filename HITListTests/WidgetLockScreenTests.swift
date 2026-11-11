import XCTest
import SwiftUI
import WidgetKit
import HITListCore
@testable import HITList

/// Brief 74, item 7: Today on the iPhone's Lock Screen, circular, rectangular and inline, at their exact sizes. The Lock
/// Screen tints them itself (vibrant); the sheet shows them white on a dark tile.
@MainActor
final class WidgetLockScreenTests: XCTestCase {
    private let morningAfter = WidgetRenders.seeded.addingTimeInterval(22 * 3600)

    func testTheInlineWords() {
        XCTAssertEqual(TodayLockScreenView.inlineText(0), "Nothing due today")
        XCTAssertEqual(TodayLockScreenView.inlineText(1), "1 task today")
        XCTAssertEqual(TodayLockScreenView.inlineText(3), "3 tasks today")
    }

    #if os(iOS)
    private let families: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline]

    private func view(_ snapshot: WidgetSnapshot?, at now: Date, _ family: WidgetFamily) -> AnyView {
        AnyView(TodayLockScreenView(snapshot: snapshot, now: now, family: family).foregroundStyle(.white))
    }

    func testTheContactSheet() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        var empty = snapshot
        empty.tasks = []
        for device in WidgetRenders.devices {
            let s = device.sizes
            let rows: [[WidgetRenders.Cell]] = [
                families.map { .init(caption: "\(WidgetRenders.familyName($0)), Tuesday 10:00", size: s[$0]!,
                                     view: view(snapshot, at: WidgetRenders.seeded, $0), bare: true) },
                families.map { .init(caption: "\(WidgetRenders.familyName($0)), Wednesday 08:00", size: s[$0]!,
                                     view: view(snapshot, at: morningAfter, $0), bare: true) },
                families.map { .init(caption: "\(WidgetRenders.familyName($0)), nothing due", size: s[$0]!,
                                     view: view(empty, at: morningAfter, $0), bare: true) },
            ]
            try WidgetRenders.keep(WidgetRenders.Sheet(title: "Lock Screen · \(device.name)", rows: rows, palette: .slate),
                                   named: "Lock Screen · \(device.name)", scale: device.scale, in: self)
        }
    }
    #endif
}
