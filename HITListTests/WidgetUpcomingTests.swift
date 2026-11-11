import XCTest
import SwiftUI
import WidgetKit
import HITListCore
@testable import HITList

/// Brief 74, item 5: the Upcoming widget, medium and large, at its exact size, on the demo week: the day it was seeded
/// (Tuesday 10 November, 10:00), with the week starting on Monday and on Sunday, the month's last days, and a fresh
/// install.
@MainActor
final class WidgetUpcomingTests: XCTestCase {
    private let families: [WidgetFamily] = [.systemMedium, .systemLarge]

    private func view(_ snapshot: WidgetSnapshot?, at now: Date, _ family: WidgetFamily) -> AnyView {
        AnyView(UpcomingWidgetView(snapshot: snapshot, now: now, family: family))
    }

    func testEveryFamilyRendersAtItsExactSize() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        for device in WidgetRenders.devices {
            for family in families {
                WidgetRenders.assertExactSize(view(snapshot, at: WidgetRenders.seeded, family),
                                              size: try XCTUnwrap(device.sizes[family]), scale: device.scale)
            }
        }
    }

    func testTheStripIsThisWeekFromTheWeekStart() throws {
        var snapshot = try WidgetRenders.demoSnapshot()
        let monday = WidgetContent.upcoming(snapshot, at: WidgetRenders.seeded)
        XCTAssertEqual(Calendar.current.component(.weekday, from: try XCTUnwrap(monday.week.first)), 2)
        XCTAssertTrue(monday.week.contains(monday.today))
        snapshot.weekStart = 1
        XCTAssertEqual(Calendar.current.component(.weekday, from: try XCTUnwrap(WidgetContent.upcoming(snapshot, at: WidgetRenders.seeded).week.first)), 1)
        XCTAssertFalse(monday.days.isEmpty)
        XCTAssertEqual(monday.days.first?.date, monday.today)
    }

    func testTheContactSheet() throws {
        let snapshot = try WidgetRenders.demoSnapshot()
        var sunday = snapshot
        sunday.weekStart = 1
        var empty = snapshot
        empty.tasks = []
        let monthEnd = Calendar.current.date(byAdding: .day, value: 19, to: WidgetRenders.seeded)! // Sunday 29 Nov
        for device in WidgetRenders.devices {
            let s = device.sizes
            let rows: [[WidgetRenders.Cell]] = [
                families.map { .init(caption: "\(WidgetRenders.familyName($0)), Tuesday 10:00", size: s[$0]!,
                                     view: view(snapshot, at: WidgetRenders.seeded, $0)) },
                families.map { .init(caption: "\(WidgetRenders.familyName($0)), weeks from Sunday", size: s[$0]!,
                                     view: view(sunday, at: WidgetRenders.seeded, $0)) },
                [.init(caption: "Medium, Sunday 29 November", size: s[.systemMedium]!, view: view(snapshot, at: monthEnd, .systemMedium)),
                 .init(caption: "Medium, nothing coming up", size: s[.systemMedium]!, view: view(empty, at: WidgetRenders.seeded, .systemMedium))],
                [.init(caption: "Large, Sunday 29 November", size: s[.systemLarge]!, view: view(snapshot, at: monthEnd, .systemLarge)),
                 .init(caption: "Medium, before the app's first run", size: s[.systemMedium]!,
                       view: view(nil, at: WidgetRenders.seeded, .systemMedium))],
            ]
            try WidgetRenders.keep(WidgetRenders.Sheet(title: "Upcoming widget · \(device.name)", rows: rows, palette: .slate),
                                   named: "Upcoming widget · \(device.name)", scale: device.scale, in: self)
        }
    }
}
