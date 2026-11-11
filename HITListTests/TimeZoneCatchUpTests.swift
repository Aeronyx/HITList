import XCTest
import SwiftData
import HITListCore
@testable import HITList
#if os(iOS)
import UIKit
#endif

/// Brief 82, item 4 (rule 3): everything catches up by itself when the zone or the day changes. One source,
/// `CalendarChange`, turns the system's notifications (and a change missed while the app was suspended) into one
/// `didChange` that the reminders, the badge, the morning summary, the widgets, calendar events and the screens that
/// decide what today is all listen to. Every clock and zone is injected.
@MainActor
final class TimeZoneCatchUpTests: XCTestCase {
    private var center: NotificationCenter!
    private var heard: [String] = []
    private var token: NSObjectProtocol?

    override func setUp() async throws {
        center = NotificationCenter()
        heard = []
        token = center.addObserver(forName: CalendarChange.didChange, object: nil, queue: nil) { [unowned self] note in
            MainActor.assumeIsolated { self.heard.append(note.userInfo?[CalendarChange.reasonKey] as? String ?? "?") }
        }
    }

    override func tearDown() async throws {
        if let token { center.removeObserver(token) }
        center = nil
    }

    /// Lets the main queue deliver what was posted with `queue: .main`.
    private func settle() async throws { try await Task.sleep(for: .milliseconds(100)) }

    // MARK: - The source

    /// Each of the system's notifications (zone, clock, midnight, iOS's significant time change) is one change, after
    /// the zone has been read again.
    func testEverySystemChangeOfTheCalendarIsOneChangeAfterTheZoneIsReadAgain() async throws {
        var resets = 0
        let source = CalendarChange(center: center, resetZone: { resets += 1 })
        source.start()
        defer { source.stop() }
        for trigger in CalendarChange.systemTriggers { center.post(name: trigger.name, object: nil) }
        try await settle()
        var expected = ["time zone", "clock", "day changed"]
        #if os(iOS)
        expected.append("significant time change")
        #endif
        XCTAssertEqual(heard, expected)
        XCTAssertEqual(resets, expected.count, "Foundation keeps the first zone it read until it is told to read it again")
    }

    /// The app comes forward after a flight it slept through: another zone is a change.
    func testComingForwardInAnotherZoneIsAChange() async throws {
        var zone = TimeZone(identifier: "America/Chicago")!
        let noon = TimeZoneStoreTests.local(2026, 11, 12, 12, in: TimeZoneStoreTests.chicago)
        let source = CalendarChange(center: center, resetZone: {}, currentZone: { zone }, clock: { noon })
        source.start()
        defer { source.stop() }
        center.post(name: CalendarChange.becameActive, object: nil)
        try await settle()
        XCTAssertEqual(heard, [], "same zone, same day: nothing changed")
        zone = TimeZone(identifier: "America/Los_Angeles")!
        center.post(name: CalendarChange.becameActive, object: nil)
        try await settle()
        XCTAssertEqual(heard, ["back in another time zone"])
        XCTAssertEqual(source.lastSeen?.zone, "America/Los_Angeles")
    }

    /// The app comes forward the morning after (suspended over midnight): another day is a change, once.
    func testComingForwardOnAnotherDayIsAChangeOnce() async throws {
        let chicago = TimeZoneStoreTests.chicago
        var now = TimeZoneStoreTests.local(2026, 11, 11, 23, 50, in: chicago)
        let source = CalendarChange(center: center, resetZone: {}, currentZone: { chicago.timeZone }, clock: { now })
        source.start()
        defer { source.stop() }
        now = TimeZoneStoreTests.local(2026, 11, 12, 7, 5, in: chicago)
        center.post(name: CalendarChange.becameActive, object: nil)
        center.post(name: CalendarChange.becameActive, object: nil)
        try await settle()
        XCTAssertEqual(heard, ["back on another day"])
    }

    // MARK: - Who listens

    /// Reminders, the badge and the morning summary reschedule on the shared source, under the change's own reason;
    /// the scheduler no longer listens to the system's notifications itself.
    func testRemindersTheBadgeAndTheSummaryListenToTheSharedSource() async throws {
        let names = NotificationScheduler.triggers.map(\.name)
        XCTAssertTrue(names.contains(CalendarChange.didChange))
        for trigger in CalendarChange.systemTriggers { XCTAssertFalse(names.contains(trigger.name), trigger.reason) }
        var reasons: [String] = []
        let observers = NotificationScheduler.observeTriggers(in: center) { reasons.append($0) }
        defer { observers.forEach(center.removeObserver) }
        center.post(name: CalendarChange.didChange, object: nil, userInfo: [CalendarChange.reasonKey: "time zone"])
        try await settle()
        XCTAssertEqual(reasons, ["time zone"])
    }

    /// The widgets reload on a calendar change even when the snapshot is the same: their timelines were worked out at
    /// the old midnights and resets.
    func testTheWidgetsReloadOnACalendarChangeEvenWhenNothingIsWritten() {
        var reloads = 0
        let writer = WidgetSnapshotWriter(fileURL: { nil }, reload: { reloads += 1 }, confirmedSince: { _ in false })
        writer.calendarChanged()
        XCTAssertEqual(reloads, 1)
    }

    /// One source: nothing in the app listens to the system's calendar notifications but `CalendarChange`.
    func testNothingElseListensToTheSystemsCalendarNotifications() throws {
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let root = checkout.appendingPathComponent("HITList")
        var files: [String: String] = [:]
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in walker where url.pathExtension == "swift" {
                files[url.lastPathComponent] = try? String(contentsOf: url, encoding: .utf8)
            }
        }
        guard files.count > 50 else { throw XCTSkip("this test host can't read the sources (\(files.count) files)") }
        let words = ["NSSystemTimeZoneDidChange", "NSSystemClockDidChange", "NSCalendarDayChanged", "significantTimeChangeNotification"]
        let listeners = files.filter { _, text in words.contains { (text).contains($0) } }.keys.sorted()
        XCTAssertEqual(listeners, ["CalendarChange.swift", "CalendarChangeDebug.swift"])
    }

    // MARK: - What a change does

    /// The same instant, before and after a flight from Chicago to Los Angeles: at 01:30 Thursday in Chicago a task due
    /// Thursday is Today's; it is 23:30 Wednesday in Los Angeles, so it is tomorrow's there, and Wednesday's task is
    /// today's. Today, the badge and Upcoming regroup by the zone alone, with no relaunch.
    func testAZoneChangeRegroupsTodayTheBadgeAndUpcomingAtTheSameInstant() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let hook = DayAnchoring.SaveHook(container: container, calendar: { TimeZoneStoreTests.chicago })
        defer { hook.stop() }
        let chicago = TimeZoneStoreTests.chicago, la = TimeZoneStoreTests.losAngeles
        let thursday = TaskItem(title: "Thursday", dueDate: DayAnchor.start(of: .init(year: 2026, month: 11, day: 12), calendar: chicago))
        let wednesday = TaskItem(title: "Wednesday", dueDate: DayAnchor.start(of: .init(year: 2026, month: 11, day: 11), calendar: chicago))
        context.insert(thursday)
        context.insert(wednesday)
        try context.save()
        let instant = TimeZoneStoreTests.local(2026, 11, 12, 1, 30, in: chicago)
        XCTAssertEqual(la.dateComponents([.day, .hour, .minute], from: instant), DateComponents(day: 11, hour: 23, minute: 30))
        let tasks = [thursday, wednesday]

        let inChicago = TaskOrdering.today(tasks, now: instant, calendar: chicago)
        XCTAssertEqual(inChicago.today.map(\.title), ["Thursday"])
        XCTAssertEqual(inChicago.overdue.map(\.title), ["Wednesday"])
        let inLA = TaskOrdering.today(tasks, now: instant, calendar: la)
        XCTAssertEqual(inLA.today.map(\.title), ["Wednesday"])
        XCTAssertEqual(inLA.overdue.map(\.title), [])
        XCTAssertEqual(UpcomingDays.days(tasks, now: instant, dayCount: 3, calendar: la).map { $0.tasks.map(\.title) },
                       [["Wednesday"], ["Thursday"]])

        let items = tasks.map { NotificationPlan.Item($0) }
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: items, now: instant, calendar: chicago), 2)
        XCTAssertEqual(NotificationPlan.badgeCount(tasks: items, now: instant, calendar: la), 1)
    }

    /// The source's change reaches a screen's clock: the moment it posts is the `now` a screen redraws with.
    func testAScreensClockHearsAChange() async throws {
        var moments: [Date] = []
        let subscription = CalendarChange.moments.sink { moments.append($0) }
        defer { subscription.cancel() }
        NotificationCenter.default.post(name: CalendarChange.didChange, object: nil, userInfo: [CalendarChange.reasonKey: "time zone"])
        XCTAssertEqual(moments.count, 1)
    }
}
