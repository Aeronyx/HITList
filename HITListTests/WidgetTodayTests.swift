import XCTest
import SwiftUI
import WidgetKit
import HITListCore
@testable import HITList

/// Brief 74, item 4: the Today widget in every family, at its exact size, on the demo week. The sheet shows the
/// morning after the demo was seeded (Wednesday 08:00: three overdue, one today), the day it was seeded (Tuesday
/// 10:00), an empty day and a fresh install.
@MainActor
final class WidgetTodayTests: XCTestCase {
    private let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    /// Wednesday 11 November, 08:00.
    private let morningAfter = WidgetRenders.seeded.addingTimeInterval(22 * 3600)

    private func view(_ snapshot: WidgetSnapshot?, at now: Date, _ family: WidgetFamily) -> AnyView {
        AnyView(TodayWidgetView(snapshot: snapshot, now: now, family: family))
    }

    func testEveryFamilyRendersAtItsExactSize() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        for device in WidgetRenders.devices {
            for family in families {
                let size = try XCTUnwrap(device.sizes[family])
                WidgetRenders.assertExactSize(view(snapshot, at: morningAfter, family), size: size, scale: device.scale)
            }
        }
    }

    func testTheMorningAfterHasOverdueAndToday() throws {
        let today = WidgetContent.today(try WidgetRenders.demoSnapshot(), at: morningAfter)
        XCTAssertEqual(today.overdue.map(\.title).sorted(), ["Buy groceries", "Gym", "Reply to Sam about the lease"])
        XCTAssertEqual(today.today.map(\.title), ["Call the dentist"])
    }

    func testTheContactSheet() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        var empty = snapshot
        empty.tasks = []
        for device in WidgetRenders.devices {
            let s = device.sizes
            let rows: [[WidgetRenders.Cell]] = [
                families.map { family in
                    .init(caption: "\(WidgetRenders.familyName(family)), Wednesday 08:00", size: s[family]!,
                          view: view(snapshot, at: morningAfter, family))
                },
                families.map { family in
                    .init(caption: "\(WidgetRenders.familyName(family)), Tuesday 10:00", size: s[family]!,
                          view: view(snapshot, at: WidgetRenders.seeded, family))
                },
                [.init(caption: "Small, nothing due", size: s[.systemSmall]!, view: view(empty, at: morningAfter, .systemSmall)),
                 .init(caption: "Medium, nothing due", size: s[.systemMedium]!, view: view(empty, at: morningAfter, .systemMedium)),
                 .init(caption: "Small, before the app's first run", size: s[.systemSmall]!,
                       view: view(nil, at: morningAfter, .systemSmall))],
            ]
            let pixels = try WidgetRenders.keep(WidgetRenders.Sheet(title: "Today widget · \(device.name)", rows: rows, palette: .slate),
                                                named: "Today widget · \(device.name)", scale: device.scale, in: self)
            XCTAssertGreaterThan(pixels.width, 0)
        }
    }
}
