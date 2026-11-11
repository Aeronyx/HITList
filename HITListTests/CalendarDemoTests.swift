import XCTest
import HITListCore
@testable import HITList

/// Brief 77 item 6: the demo day (`-seedDemoEvents YES`), for screenshots and UI tests. Fake events only.
@MainActor
final class CalendarDemoTests: XCTestCase {
    func testTheArgument() {
        XCTAssertTrue(DemoEventSource.isRequested(arguments: ["HITList", "-seedDemoEvents", "YES"]))
        XCTAssertTrue(DemoEventSource.isRequested(arguments: ["HITList", "-seedDemoEvents"]))
        XCTAssertFalse(DemoEventSource.isRequested(arguments: ["HITList", "-seedDemoEvents", "NO"]))
        XCTAssertFalse(DemoEventSource.isRequested(arguments: ["HITList", "-seedDemoData", "YES"]))
        XCTAssertFalse(CalendarEvents.isDemo(arguments: ["HITList"]))
        XCTAssertTrue(CalendarEvents.defaultSource(arguments: ["HITList"]) is EventKitSource, "a device reads EventKit")
        XCTAssertTrue(CalendarEvents.defaultSource(arguments: ["HITList", "-seedDemoEvents", "YES"]) is DemoEventSource)
    }

    func testABelievableDayWithPastAndComingEvents() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 14, minute: 10, second: 0, of: Date())!
        let source = DemoEventSource(now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let all = source.events(from: today, to: calendar.date(byAdding: .day, value: 14, to: today)!)
        let day = CalendarDay.events(all, on: today, calendar: calendar)
        XCTAssertEqual(day.first?.event.title, "Sam's birthday", "all-day first")
        XCTAssertTrue(day.first?.isAllDay == true)
        XCTAssertGreaterThanOrEqual(day.count, 6)
        XCTAssertTrue(day.contains { CalendarDay.isPast($0, now: now) }, "some are over (dimmed)")
        XCTAssertTrue(day.contains { !$0.isAllDay && !CalendarDay.isPast($0, now: now) }, "some to come")
        XCTAssertEqual(Set(all.map(\.calendarID)), Set(source.calendars().map(\.id)), "every demo calendar has events")
        // A three-day trip shows on each of its days.
        let trip = (5...7).map { offset in
            CalendarDay.events(all, on: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
                .contains { $0.event.title == "Lisbon" }
        }
        XCTAssertEqual(trip, [true, true, true])
    }

    func testTheDemoIsOnForTheRunWithoutSavingIt() async {
        let suite = "CalendarDemoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let events = CalendarEvents(source: DemoEventSource(), defaults: defaults, onForTheRun: true)
        XCTAssertTrue(events.isOn)
        XCTAssertNil(defaults.object(forKey: Preferences.calendarEvents), "the setting itself stays as it was")
        await events.reload()
        XCTAssertTrue(events.isShowing)
        XCTAssertFalse(events.events(on: Date()).isEmpty)
    }
}
