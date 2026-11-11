import XCTest
import SwiftUI
import WidgetKit
import HITListCore
@testable import HITList

/// Brief 74, item 6: the Flipboard widget, small and medium, at its exact size, on the demo week's boards: the loose
/// switches, Before Bed (daily, 04:00) and Deep Clean (weekly), on the day they were seeded and either side of Before
/// Bed's reset.
@MainActor
final class WidgetFlipboardTests: XCTestCase {
    private let families: [WidgetFamily] = [.systemSmall, .systemMedium]
    private let beforeReset = WidgetRenders.seeded.addingTimeInterval(17 * 3600 + 59 * 60) // Wednesday 03:59
    private let atReset = WidgetRenders.seeded.addingTimeInterval(18 * 3600)               // Wednesday 04:00

    private func view(_ snapshot: WidgetSnapshot?, board: UUID?, at now: Date, _ family: WidgetFamily) -> AnyView {
        AnyView(FlipboardWidgetView(snapshot: snapshot, boardID: board, now: now, family: family))
    }

    /// The pills' red and green are the board's own lights.
    func testThePillsAreTheBoardsLights() {
        XCTAssertEqual(WidgetLights.red, FlipLightStyle.red)
        XCTAssertEqual(WidgetLights.green, FlipLightStyle.green)
        XCTAssertEqual(WidgetLights.color(.red), FlipboardPalette.ledOn)
        XCTAssertEqual(WidgetLights.color(.green), FlipboardPalette.ledGreen)
    }

    func testBeforeBedTurnsRedTogetherAtItsReset() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        let bed = try XCTUnwrap(snapshot.switchboards.first { $0.name == "Before Bed" })
        let before = WidgetContent.flipboard(snapshot, board: bed.id, at: beforeReset)
        XCTAssertEqual(before.lights.filter { $0.side == .green }.map(\.task.title).sorted(), ["Brush teeth", "Floss"])
        XCTAssertEqual(before.summary, "\(bed.line) · 2 of 4")
        let after = WidgetContent.flipboard(snapshot, board: bed.id, at: atReset)
        XCTAssertTrue(after.lights.allSatisfy { $0.side == .red })
        XCTAssertEqual(after.summary, "\(bed.line) · 0 of 4")
    }

    func testEveryFamilyRendersAtItsExactSize() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        for device in WidgetRenders.devices {
            for family in families {
                for board in [nil] + snapshot.switchboards.map(\.id) {
                    WidgetRenders.assertExactSize(view(snapshot, board: board, at: WidgetRenders.seeded, family),
                                                  size: try XCTUnwrap(device.sizes[family]), scale: device.scale)
                }
            }
        }
    }

    func testTheContactSheet() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        let bed = snapshot.switchboards.first { $0.name == "Before Bed" }?.id
        let clean = snapshot.switchboards.first { $0.name == "Deep Clean" }?.id
        var empty = snapshot
        empty.looseSwitchIDs = []
        for device in WidgetRenders.devices {
            let s = device.sizes
            func cell(_ caption: String, _ board: UUID?, _ now: Date, _ family: WidgetFamily, _ snap: WidgetSnapshot? = nil) -> WidgetRenders.Cell {
                .init(caption: "\(WidgetRenders.familyName(family)), \(caption)", size: s[family]!,
                      view: view(snap ?? snapshot, board: board, at: now, family))
            }
            let rows: [[WidgetRenders.Cell]] = [
                [cell("Before Bed, Wednesday 03:59", bed, beforeReset, .systemSmall),
                 cell("Before Bed, Wednesday 03:59", bed, beforeReset, .systemMedium)],
                [cell("Before Bed, Wednesday 04:00", bed, atReset, .systemSmall),
                 cell("Before Bed, Wednesday 04:00", bed, atReset, .systemMedium)],
                [cell("loose switches, Tuesday 10:00", nil, WidgetRenders.seeded, .systemSmall),
                 cell("Deep Clean, Tuesday 10:00", clean, WidgetRenders.seeded, .systemMedium)],
                [cell("no loose switches", nil, WidgetRenders.seeded, .systemSmall, empty),
                 .init(caption: "Medium, before the app's first run", size: s[.systemMedium]!,
                       view: view(nil, board: nil, at: WidgetRenders.seeded, .systemMedium))],
            ]
            try WidgetRenders.keep(WidgetRenders.Sheet(title: "Flipboard widget · \(device.name)", rows: rows, palette: .slate),
                                   named: "Flipboard widget · \(device.name)", scale: device.scale, in: self)
        }
    }
}
