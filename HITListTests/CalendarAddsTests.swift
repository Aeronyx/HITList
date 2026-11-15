import XCTest
import HITListCore
@testable import HITList

/// Brief 136 item 4: Add to Calendar. One event per choice, a toast with Undo, never a second copy, write-only access
/// asked for only while events are off. The fake source records what would have been written.
@MainActor
final class CalendarAddsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "CalendarAddsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    private func make(access: CalendarAccess) -> (FakeCalendarSource, CalendarEvents, CalendarAdds) {
        let source = FakeCalendarSource(access: access, grants: true)
        source.calendarList = [CalendarInfo(id: "work", title: "Work", colorHex: "#5E81F4", source: "iCloud"),
                               CalendarInfo(id: "home", title: "Home", colorHex: "#34C759", source: "iCloud")]
        let events = CalendarEvents(source: source, defaults: defaults)
        let c = calendar
        return (source, events, CalendarAdds(events: events, calendar: { c }))
    }

    private let taskID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    func testOnlyADatedOpenTaskCanBeAdded() {
        XCTAssertTrue(CalendarAdds.canAdd(due: Date(), isCompleted: false))
        XCTAssertFalse(CalendarAdds.canAdd(due: nil, isCompleted: false))
        XCTAssertFalse(CalendarAdds.canAdd(due: Date(), isCompleted: true))
    }

    func testAddsOneEventToThePickedCalendarAndUndoRemovesIt() async {
        let (source, events, adds) = make(access: .fullAccess)
        await events.setOn(true)
        events.setAddTarget("home")
        let notice = await adds.add(taskID: taskID, title: "Call the bank", notes: "fees", due: date(14, 15), hasTime: true)
        XCTAssertEqual(notice.message, "Added to Home")
        XCTAssertTrue(notice.canUndo)
        XCTAssertEqual(source.written.count, 1)
        XCTAssertEqual(source.written.first?.calendarID, "home")
        let draft = source.written.first?.draft
        XCTAssertEqual(draft?.title, "Call the bank")
        XCTAssertEqual(draft?.start, date(14, 15))
        XCTAssertEqual(draft?.end, date(14, 15, 30), "30 minutes")
        XCTAssertEqual(draft?.notes, "fees")
        XCTAssertEqual(draft?.url, URL(string: "hitlist://task/6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertEqual(source.writeRequests, 0, "full access is used as it is")
        await adds.undo()
        XCTAssertEqual(source.removed, ["written-1"], "Undo removes that one event")
        XCTAssertTrue(source.written.isEmpty)
        XCTAssertEqual(adds.notice?.kind, .removed)
        XCTAssertEqual(adds.notice?.canUndo, false, "nothing more to undo")
    }

    func testASecondAddSaysItIsAlreadyThere() async {
        let (source, events, adds) = make(access: .fullAccess)
        await events.setOn(true)
        await adds.add(taskID: taskID, title: "Call", notes: "", due: date(14, 15), hasTime: true)
        let again = await adds.add(taskID: taskID, title: "Call", notes: "", due: date(14, 9), hasTime: true)
        XCTAssertEqual(again.message, "Already on your calendar")
        XCTAssertFalse(again.canUndo)
        XCTAssertEqual(source.written.count, 1, "never a second copy")
    }

    func testACopyDeletedInCalendarCanBeAddedAgain() async {
        let (source, events, adds) = make(access: .fullAccess)
        await events.setOn(true)
        await adds.add(taskID: taskID, title: "Call", notes: "", due: date(14, 15), hasTime: true)
        source.all.removeAll { $0.url != nil }
        let again = await adds.add(taskID: taskID, title: "Call", notes: "", due: date(14, 15), hasTime: true)
        XCTAssertTrue(again.canUndo, "full access reads the calendar as it is now")
        XCTAssertEqual(source.written.count, 2)
    }

    func testAnEventWithTheTasksLinkFromAnEarlierRunCounts() async {
        let (source, events, adds) = make(access: .fullAccess)
        source.all = [CalendarEvent(id: "kept", title: "Call", start: date(14, 10), end: date(14, 10, 30), isAllDay: false,
                                    calendarID: "work", colorHex: "#5E81F4",
                                    url: URL(string: "hitlist://task/6F9619FF-8B86-D011-B42D-00C04FC964FF"))]
        await events.setOn(true)
        let notice = await adds.add(taskID: taskID, title: "Call", notes: "", due: date(14), hasTime: false)
        XCTAssertEqual(notice.kind, .already)
        XCTAssertTrue(source.written.isEmpty)
        let nextDay = await adds.add(taskID: taskID, title: "Call", notes: "", due: date(15), hasTime: false)
        XCTAssertTrue(nextDay.canUndo, "a repeating task's next day is a new event")
        XCTAssertEqual(source.written.first?.draft.isAllDay, true)
    }

    func testWhileEventsAreOffItAsksForWriteOnlyAccess() async {
        let (source, events, adds) = make(access: .notDetermined)
        XCTAssertFalse(events.isOn)
        let notice = await adds.add(taskID: taskID, title: "Taxes", notes: "", due: date(14), hasTime: false)
        XCTAssertEqual(source.writeRequests, 1)
        XCTAssertEqual(source.requests, 0, "never full access for adding")
        XCTAssertEqual(source.accessNow, .writeOnly)
        XCTAssertEqual(notice.message, "Added to your calendar", "write-only can't read the calendar's name")
        XCTAssertEqual(source.written.count, 1)
        let again = await adds.add(taskID: taskID, title: "Taxes", notes: "", due: date(14), hasTime: false)
        XCTAssertEqual(again.kind, .already, "remembered for the run, though write-only access can't read it back")
        XCTAssertEqual(source.writeRequests, 1, "asked once")
    }

    func testRefusedAccessWritesNothingAndAsksNothing() async {
        let (source, _, adds) = make(access: .denied)
        let notice = await adds.add(taskID: taskID, title: "Taxes", notes: "", due: date(14), hasTime: false)
        XCTAssertEqual(notice.kind, .refused)
        XCTAssertTrue(source.written.isEmpty)
        XCTAssertEqual(source.writeRequests, 0)
        let (said, _, refusing) = make(access: .notDetermined)
        said.grantsWrite = false
        let no = await refusing.add(taskID: taskID, title: "Taxes", notes: "", due: date(14), hasTime: false)
        XCTAssertEqual(no.kind, .refused)
        XCTAssertTrue(said.written.isEmpty)
    }

    func testTheToastGoesAwayWithoutUndoing() async {
        let (source, events, adds) = make(access: .fullAccess)
        await events.setOn(true)
        var shown: [CalendarAdds.Notice?] = []
        adds.onNotice = { shown.append($0) }
        await adds.add(taskID: taskID, title: "Call", notes: "", due: date(14, 15), hasTime: true)
        adds.dismiss()
        XCTAssertNil(adds.notice)
        XCTAssertEqual(shown.count, 2)
        XCTAssertNil(shown.last ?? nil)
        XCTAssertEqual(source.written.count, 1, "putting the toast away keeps the event")
        await adds.undo()
        XCTAssertTrue(source.removed.isEmpty, "no toast, no Undo")
    }
}
