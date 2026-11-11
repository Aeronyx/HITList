import XCTest
import HITListCore
@testable import HITList

/// Brief 77: the calendar store. Off by default and silent while off; on, it asks once, reads in the background and
/// keeps the events in memory only.
@MainActor
final class CalendarEventsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "CalendarEventsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    private func store(_ source: FakeCalendarSource) -> CalendarEvents {
        let c = calendar
        return CalendarEvents(source: source, defaults: defaults, calendar: { c }, now: { [self] in date(10, 8) })
    }

    private func makeSource(access: CalendarAccess = .notDetermined, grants: Bool = true) -> FakeCalendarSource {
        let source = FakeCalendarSource(access: access, grants: grants)
        source.calendarList = [CalendarInfo(id: "work", title: "Work", colorHex: "#5E81F4", source: "iCloud"),
                               CalendarInfo(id: "home", title: "Home", colorHex: "#34C759", source: "iCloud")]
        source.all = [
            CalendarEvent(id: "standup", title: "Standup", start: date(10, 9, 30), end: date(10, 10, 15), isAllDay: false,
                          calendarID: "work", colorHex: "#5E81F4"),
            CalendarEvent(id: "dinner", title: "Dinner", start: date(10, 19), end: date(10, 21), isAllDay: false,
                          calendarID: "home", colorHex: "#34C759"),
            CalendarEvent(id: "dentist", title: "Dentist", start: date(12, 9), end: date(12, 10), isAllDay: false,
                          calendarID: "home", colorHex: "#34C759"),
        ]
        return source
    }

    func testOffByDefaultAsksNothing() async {
        let source = makeSource()
        let events = store(source)
        XCTAssertFalse(events.isOn, "off by default")
        events.start()
        await Task.yield()
        XCTAssertTrue(events.events(on: date(10), calendar: calendar).isEmpty)
        XCTAssertEqual(source.requests, 0, "never prompts while off")
        XCTAssertEqual(source.reads, 0, "never reads a calendar while off")
    }

    func testSwitchingOnAsksOnceThenLoads() async {
        let source = makeSource()
        let events = store(source)
        let on = await events.setOn(true)
        XCTAssertTrue(on)
        XCTAssertEqual(source.requests, 1)
        XCTAssertEqual(events.access, .fullAccess)
        XCTAssertEqual(defaults.bool(forKey: Preferences.calendarEvents), true)
        XCTAssertEqual(events.events(on: date(10), calendar: calendar).map(\.event.id), ["standup", "dinner"])
        XCTAssertEqual(events.events(on: date(12), calendar: calendar).map(\.event.id), ["dentist"])
        XCTAssertEqual(events.calendars.map(\.id), ["work", "home"])
        // It reads from the start of today, at least two months ahead.
        XCTAssertEqual(source.lastRange?.start, date(10))
        XCTAssertGreaterThanOrEqual(source.lastRange?.end ?? .distantPast, calendar.date(byAdding: .day, value: 60, to: date(10))!)

        _ = await events.setOn(true)
        XCTAssertEqual(source.requests, 1, "asked once: the permission is known now")
    }

    func testRefusedStaysOffAndSaysWhy() async {
        let source = makeSource(grants: false)
        let events = store(source)
        let on = await events.setOn(true)
        XCTAssertFalse(on)
        XCTAssertFalse(events.isOn)
        XCTAssertEqual(events.access, .denied)
        XCTAssertTrue(events.access.isRefused)
        XCTAssertEqual(defaults.bool(forKey: Preferences.calendarEvents), false)
        XCTAssertEqual(source.reads, 0)

        // Already refused: no prompt again (the system wouldn't show one); only its settings change it.
        _ = await events.setOn(true)
        XCTAssertEqual(source.requests, 1)
    }

    func testWriteOnlyAccessReadsNothing() async {
        let source = makeSource(access: .writeOnly)
        let events = store(source)
        let on = await events.setOn(true)
        XCTAssertFalse(on)
        XCTAssertEqual(events.access, .writeOnly)
        XCTAssertTrue(events.access.isRefused)
        XCTAssertEqual(source.requests, 0)
    }

    func testHidingACalendar() async {
        let source = makeSource()
        let events = store(source)
        await events.setOn(true)
        events.setShown(false, calendarID: "home")
        XCTAssertEqual(events.events(on: date(10), calendar: calendar).map(\.event.id), ["standup"])
        XCTAssertEqual(defaults.stringArray(forKey: Preferences.calendarEventsHidden), ["home"])
        events.setShown(true, calendarID: "home")
        XCTAssertEqual(events.events(on: date(10), calendar: calendar).count, 2)
    }

    func testOnAtLaunchLoadsWithoutAsking() async throws {
        defaults.set(true, forKey: Preferences.calendarEvents)
        let source = makeSource(access: .fullAccess)
        let events = store(source)
        XCTAssertTrue(events.isOn)
        XCTAssertTrue(events.events(on: date(10), calendar: calendar).isEmpty, "nothing until the load finishes")
        events.start()
        try await waitForLoad(events, count: 1)
        XCTAssertEqual(events.events(on: date(10), calendar: calendar).count, 2)
        XCTAssertEqual(source.requests, 0)
    }

    func testChangesElsewhereReload() async throws {
        let source = makeSource()
        let events = store(source)
        await events.setOn(true)
        source.all.append(CalendarEvent(id: "new", title: "New", start: date(10, 15), end: date(10, 16), isAllDay: false,
                                        calendarID: "work", colorHex: "#5E81F4"))
        source.fireChange()
        try await waitForLoad(events, count: 2)
        XCTAssertEqual(events.events(on: date(10), calendar: calendar).map(\.event.id), ["standup", "new", "dinner"])
    }

    func testAccessWithdrawnInSystemSettingsEmptiesTheLists() async {
        let source = makeSource()
        let events = store(source)
        await events.setOn(true)
        source.accessNow = .denied
        await events.reload()
        XCTAssertTrue(events.events(on: date(10), calendar: calendar).isEmpty)
        XCTAssertTrue(events.loaded.isEmpty, "nothing kept once access is gone")
        XCTAssertTrue(events.isOn, "the setting stays; events come back if access does")
    }

    func testSwitchingOffForgetsTheEvents() async {
        let source = makeSource()
        let events = store(source)
        await events.setOn(true)
        await events.setOn(false)
        XCTAssertTrue(events.loaded.isEmpty)
        XCTAssertTrue(events.calendars.isEmpty)
        XCTAssertTrue(events.events(on: date(10), calendar: calendar).isEmpty)
    }

    func testCoveringFurtherDaysLoadsMore() async throws {
        let source = makeSource()
        let events = store(source)
        await events.setOn(true)
        let far = calendar.date(byAdding: .day, value: 100, to: date(10))!
        events.cover(through: far)
        try await waitForLoad(events, count: 2)
        XCTAssertGreaterThan(source.lastRange?.end ?? .distantPast, far)
    }

    private func waitForLoad(_ events: CalendarEvents, count: Int) async throws {
        for _ in 0..<200 where events.loads < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(events.loads, count)
    }
}

/// A calendar in memory: what EventKit would answer, and what was asked of it.
final class FakeCalendarSource: CalendarEventSource, @unchecked Sendable {
    var accessNow: CalendarAccess
    let grants: Bool
    var calendarList: [CalendarInfo] = []
    var all: [CalendarEvent] = []
    private(set) var requests = 0
    private(set) var reads = 0
    private(set) var lastRange: (start: Date, end: Date)?
    private var onChange: (@Sendable () -> Void)?

    init(access: CalendarAccess, grants: Bool) {
        accessNow = access
        self.grants = grants
    }

    func access() -> CalendarAccess { accessNow }

    func requestAccess() async -> CalendarAccess {
        requests += 1
        if accessNow == .notDetermined { accessNow = grants ? .fullAccess : .denied }
        return accessNow
    }

    func calendars() -> [CalendarInfo] { calendarList }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        reads += 1
        lastRange = (start, end)
        return all.filter { $0.start < end && $0.end > start }
    }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }

    func fireChange() { onChange?() }
}
