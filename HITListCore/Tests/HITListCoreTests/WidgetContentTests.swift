import XCTest
@testable import HITListCore

/// Brief 74: what each widget shows at a moment, from the snapshot the app writes, by the same rules the app's lists
/// use. A widget is right at 00:01 and at a Switchboard's reset without the app running, so most of these sit either
/// side of midnight or a reset.
final class WidgetContentTests: XCTestCase {
    private let cal = Fixed.calendar
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date { Fixed.date(y, m, day, h, min) }

    private typealias Task = WidgetSnapshot.Task

    private func task(_ title: String, due: Date? = nil, time: Bool = false, priority: Int = 4, group: String? = nil,
                      labels: [String] = [], recurring: Bool = false, created: Date? = nil, optedIn: Bool = false,
                      board: UUID? = nil, clock: WidgetSnapshot.Clock? = nil, shared: Bool = false) -> Task {
        Task(id: UUID(), title: title, priority: priority, due: due, hasTime: time, groupName: group,
             groupColorHex: group == nil ? nil : "#5E81F4", labelNames: labels, isRecurring: recurring,
             createdAt: created ?? d(2026, 10, 1), isShared: shared, switchOptedIn: optedIn, switchboardID: board,
             clock: clock)
    }

    private func snapshot(_ tasks: [Task], loose: [UUID] = [], boards: [WidgetSnapshot.Switchboard] = [],
                          weekStart: Int = 2) -> WidgetSnapshot {
        WidgetSnapshot(writtenAt: d(2026, 10, 21, 9), themeID: "slate", weekStart: weekStart, tasks: tasks,
                       looseSwitchIDs: loose, switchboards: boards)
    }

    /// A daily board resetting at 04:00.
    private let daily = WidgetSnapshot.Clock(SwitchboardSchedule(cadence: .daily, resetMinutes: 4 * 60))

    // MARK: - Today

    func testTodayIsOverdueThenTodayInTheListsOrder() {
        let late = task("Late", due: d(2026, 10, 19))
        let p1 = task("Urgent", due: d(2026, 10, 21), priority: 1)
        let timed = task("At three", due: d(2026, 10, 21, 15), time: true)
        let allDay = task("Some time today", due: d(2026, 10, 21))
        let tomorrow = task("Tomorrow", due: d(2026, 10, 22))
        let today = WidgetContent.today(snapshot([tomorrow, allDay, timed, late, p1]), at: Fixed.now, calendar: cal)
        XCTAssertEqual(today.overdue.map(\.title), ["Late"])
        XCTAssertEqual(today.today.map(\.title), ["Urgent", "Some time today", "At three"])
        XCTAssertEqual(today.rows.map(\.title), ["Late", "Urgent", "Some time today", "At three"])
        XCTAssertEqual(today.count, 4)
    }

    func testAtMidnightTomorrowsTasksArriveAndTodaysBecomeOverdue() {
        let tonight = task("Tonight", due: d(2026, 10, 21, 23), time: true)
        let tomorrow = task("Tomorrow", due: d(2026, 10, 22))
        let snap = snapshot([tonight, tomorrow])
        let before = WidgetContent.today(snap, at: d(2026, 10, 21, 23, 59), calendar: cal)
        XCTAssertEqual(before.overdue.map(\.title), [])
        XCTAssertEqual(before.today.map(\.title), ["Tonight"])
        let after = WidgetContent.today(snap, at: d(2026, 10, 22, 0, 1), calendar: cal)
        XCTAssertEqual(after.overdue.map(\.title), ["Tonight"])
        XCTAssertEqual(after.today.map(\.title), ["Tomorrow"])
    }

    func testASwitchIsNotTodaysUnlessItOptedInAndIsDue() {
        let quiet = task("Water the plants", due: d(2026, 10, 20), labels: ["flipboard"], recurring: true)
        let opted = task("Take meds", due: d(2026, 10, 20), labels: ["flipboard"], recurring: true, optedIn: true)
        let today = WidgetContent.today(snapshot([quiet, opted]), at: Fixed.now, calendar: cal)
        XCTAssertEqual(today.overdue.map(\.title), [], "an opted-in switch is today's, never overdue")
        XCTAssertEqual(today.today.map(\.title), ["Take meds"])
    }

    func testAnOptedInSwitchOnABoardArrivesAtTheReset() {
        let board = UUID()
        // Flipped on Tuesday evening: due Wednesday's board day, which starts at 04:00 Wednesday.
        let floss = task("Floss", due: d(2026, 10, 21), labels: ["flipboard"], recurring: true, optedIn: true,
                         board: board, clock: daily)
        let snap = snapshot([floss])
        XCTAssertTrue(WidgetContent.today(snap, at: d(2026, 10, 21, 3, 59), calendar: cal).isEmpty,
                      "still Tuesday's board day: green")
        XCTAssertEqual(WidgetContent.today(snap, at: d(2026, 10, 21, 4, 0), calendar: cal).today.map(\.title), ["Floss"])
    }

    func testNothingDueIsEmpty() {
        let today = WidgetContent.today(snapshot([task("Next week", due: d(2026, 10, 28))]), at: Fixed.now, calendar: cal)
        XCTAssertTrue(today.isEmpty)
        XCTAssertEqual(today.count, 0)
    }

    func testSharedTasksAreRowsLikeYours() {
        let shared = task("Pick up the cake", due: d(2026, 10, 21), priority: 2, group: "Shared Tasks", shared: true)
        let mine = task("Mine", due: d(2026, 10, 21), priority: 3)
        XCTAssertEqual(WidgetContent.today(snapshot([mine, shared]), at: Fixed.now, calendar: cal).today.map(\.title),
                       ["Pick up the cake", "Mine"])
    }

    // MARK: - Upcoming

    func testTheWeekStartsOnTheSettingsDay() {
        // Wednesday 21 October 2026.
        let monday = WidgetContent.upcoming(snapshot([], weekStart: 2), at: Fixed.now, calendar: cal)
        XCTAssertEqual(monday.week.first, d(2026, 10, 19))
        XCTAssertEqual(monday.week.count, 7)
        XCTAssertEqual(monday.week.last, d(2026, 10, 25))
        let sunday = WidgetContent.upcoming(snapshot([], weekStart: 1), at: Fixed.now, calendar: cal)
        XCTAssertEqual(sunday.week.first, d(2026, 10, 18))
        XCTAssertEqual(monday.today, d(2026, 10, 21))
    }

    func testDotsCountOpenScheduledTasksPerDayButNotSwitches() {
        let a = task("A", due: d(2026, 10, 22, 9), time: true)
        let b = task("B", due: d(2026, 10, 22))
        let late = task("Late", due: d(2026, 10, 20))
        let sw = task("Switch", due: d(2026, 10, 23), labels: ["flipboard"], recurring: true)
        let up = WidgetContent.upcoming(snapshot([a, b, late, sw]), at: Fixed.now, calendar: cal)
        XCTAssertEqual(up.counts[d(2026, 10, 22)], 2)
        XCTAssertEqual(up.counts[d(2026, 10, 20)], 1, "overdue days keep their dot, as the app's strip does")
        XCTAssertNil(up.counts[d(2026, 10, 23)], "a switch is on the Flipboard only")
    }

    func testTheNextDaysListTheirTasksFromTodayOn() {
        let late = task("Late", due: d(2026, 10, 20))
        let today = task("Today", due: d(2026, 10, 21))
        let fri = task("Friday", due: d(2026, 10, 23), priority: 1)
        let fri2 = task("Friday too", due: d(2026, 10, 23, 8), time: true)
        let far = task("Far", due: d(2026, 12, 25))
        let up = WidgetContent.upcoming(snapshot([fri2, far, late, today, fri]), at: Fixed.now, calendar: cal)
        XCTAssertEqual(up.days.map(\.date), [d(2026, 10, 21), d(2026, 10, 23)], "empty days and days past the horizon are left out")
        XCTAssertEqual(up.days.last?.tasks.map(\.title), ["Friday", "Friday too"])
    }

    func testAfterMidnightUpcomingStartsAtTheNewDay() {
        let tue = task("Wednesday's", due: d(2026, 10, 21))
        let thu = task("Thursday's", due: d(2026, 10, 22))
        let up = WidgetContent.upcoming(snapshot([tue, thu]), at: d(2026, 10, 22, 0, 1), calendar: cal)
        XCTAssertEqual(up.today, d(2026, 10, 22))
        XCTAssertEqual(up.days.map(\.date), [d(2026, 10, 22)])
    }

    // MARK: - Flipboard

    func testTheLooseSwitchesInTheBoardsOrderWithTheirSides() {
        let red = task("Water", due: d(2026, 10, 20), labels: ["flipboard"], recurring: true)
        let green = task("Recycling", due: d(2026, 10, 24), labels: ["flipboard"], recurring: true)
        let board = WidgetContent.flipboard(snapshot([green, red], loose: [red.id, green.id]), board: nil, at: Fixed.now,
                                            calendar: cal)
        XCTAssertNil(board.boardID)
        XCTAssertEqual(board.title, "Flipboard")
        XCTAssertNil(board.line)
        XCTAssertEqual(board.lights.map(\.task.title), ["Water", "Recycling"])
        XCTAssertEqual(board.lights.map(\.side), [.red, .green])
        XCTAssertEqual(board.doneText, "1 of 2")
        XCTAssertEqual(board.summary, "1 of 2")
    }

    func testALooseSwitchTurnsRedAtMidnight() {
        let sw = task("Water", due: d(2026, 10, 22), labels: ["flipboard"], recurring: true)
        let snap = snapshot([sw], loose: [sw.id])
        XCTAssertEqual(WidgetContent.flipboard(snap, board: nil, at: d(2026, 10, 21, 23, 59), calendar: cal).lights.map(\.side), [.green])
        XCTAssertEqual(WidgetContent.flipboard(snap, board: nil, at: d(2026, 10, 22, 0, 0), calendar: cal).lights.map(\.side), [.red])
    }

    func testABoardTurnsRedTogetherAtItsReset() {
        let id = UUID()
        let floss = task("Floss", due: d(2026, 10, 22), labels: ["flipboard"], recurring: true, board: id, clock: daily)
        let meds = task("Take meds", due: d(2026, 10, 22, 21), time: true, labels: ["flipboard"], recurring: true,
                        board: id, clock: daily)
        let bed = WidgetSnapshot.Switchboard(id: id, name: "Before Bed", line: "Daily · resets 4:00 AM", clock: daily,
                                             switchIDs: [meds.id, floss.id])
        let snap = snapshot([floss, meds], boards: [bed])
        // Both flipped on Wednesday's board day; Thursday's begins at 04:00 Thursday.
        let night = WidgetContent.flipboard(snap, board: id, at: d(2026, 10, 22, 3, 59), calendar: cal)
        XCTAssertEqual(night.title, "Before Bed")
        XCTAssertEqual(night.lights.map(\.task.title), ["Take meds", "Floss"])
        XCTAssertEqual(night.lights.map(\.side), [.green, .green])
        XCTAssertEqual(night.summary, "Daily · resets 4:00 AM · 2 of 2")
        let reset = WidgetContent.flipboard(snap, board: id, at: d(2026, 10, 22, 4, 0), calendar: cal)
        XCTAssertEqual(reset.lights.map(\.side), [.red, .red])
        XCTAssertEqual(reset.summary, "Daily · resets 4:00 AM · 0 of 2")
    }

    func testABoardThatIsGoneShowsTheLooseSwitches() {
        let sw = task("Water", due: d(2026, 10, 20), labels: ["flipboard"], recurring: true)
        let board = WidgetContent.flipboard(snapshot([sw], loose: [sw.id]), board: UUID(), at: Fixed.now, calendar: cal)
        XCTAssertNil(board.boardID)
        XCTAssertEqual(board.lights.map(\.task.title), ["Water"])
    }

    func testAnEmptyBoardHasNoCount() {
        let board = WidgetContent.flipboard(snapshot([]), board: nil, at: Fixed.now, calendar: cal)
        XCTAssertTrue(board.lights.isEmpty)
        XCTAssertNil(board.doneText)
        XCTAssertEqual(board.summary, "")
    }

    // MARK: - Timeline

    func testTheTimelineChangesAtMidnightAtResetsAndAtDueTimes() {
        let id = UUID()
        let at3 = task("At three", due: d(2026, 10, 21, 15), time: true)
        let earlier = task("This morning", due: d(2026, 10, 21, 9), time: true)
        let floss = task("Floss", due: d(2026, 10, 22), labels: ["flipboard"], recurring: true, board: id, clock: daily)
        let bed = WidgetSnapshot.Switchboard(id: id, name: "Before Bed", line: "", clock: daily, switchIDs: [floss.id])
        let changes = WidgetContent.changes(snapshot([at3, earlier, floss], boards: [bed]), after: Fixed.now, calendar: cal)
        XCTAssertEqual(changes.first, d(2026, 10, 21, 15), "a timed task turns red at its time")
        XCTAssertTrue(changes.contains(d(2026, 10, 22)), "midnight")
        XCTAssertTrue(changes.contains(d(2026, 10, 22, 4)), "the board's reset")
        XCTAssertFalse(changes.contains(d(2026, 10, 21, 9)), "nothing in the past")
        XCTAssertEqual(changes, changes.sorted())
        XCTAssertEqual(Set(changes).count, changes.count)
        XCTAssertTrue(changes.allSatisfy { $0 > Fixed.now && $0 <= Fixed.now.addingTimeInterval(36 * 3600) })
    }

    func testAnOptedInTimedSwitchArrivesAtItsTime() {
        let id = UUID()
        // Red for Wednesday's board day, due at 21:00: it becomes Today's task at 21:00.
        let meds = task("Take meds", due: d(2026, 10, 21, 21), time: true, labels: ["flipboard"], recurring: true,
                        optedIn: true, board: id, clock: daily)
        let bed = WidgetSnapshot.Switchboard(id: id, name: "Before Bed", line: "", clock: daily, switchIDs: [meds.id])
        let snap = snapshot([meds], boards: [bed])
        XCTAssertTrue(WidgetContent.changes(snap, after: Fixed.now, calendar: cal).contains(d(2026, 10, 21, 21)))
        XCTAssertTrue(WidgetContent.today(snap, at: d(2026, 10, 21, 20, 59), calendar: cal).isEmpty)
        XCTAssertEqual(WidgetContent.today(snap, at: d(2026, 10, 21, 21), calendar: cal).count, 1)
    }

    func testTheTimelineAlwaysReachesTheNextMidnight() {
        XCTAssertEqual(WidgetContent.changes(snapshot([]), after: d(2026, 10, 21, 23, 59), calendar: cal),
                       [d(2026, 10, 22), d(2026, 10, 23)])
    }
}
