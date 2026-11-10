import XCTest
@testable import HITListCore

/// Brief 59: a Flipboard switch judged from any `FilterableTask`, without the app.
final class FlipboardSwitchTests: XCTestCase {
    private let cal = Fixed.calendar
    /// Wednesday 2026-10-21 14:30 UTC.
    private let now = Fixed.now

    private func shave(due: Date?, labels: [String] = ["flipboard"], recurring: Bool = true,
                       hasTime: Bool = false, completed: Bool = false) -> PlainTask {
        PlainTask(title: "Shave", dueDate: due, hasDueTime: hasTime, isCompleted: completed,
                  labelNames: labels, isRecurring: recurring)
    }

    // MARK: - Membership

    func testAMemberIsAnOpenRecurringTaskCarryingTheLabel() {
        let due = Fixed.date(2026, 10, 25)
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: due)))
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: due, labels: ["home", "FlipBoard"])), "the label in any case")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, labels: ["home"])), "no label")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, recurring: false)), "no repeat")
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: Fixed.date(2026, 10, 25, 21), hasTime: true)),
                      "a switch may have a time (brief 72: \"Take meds 21:00\")")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, completed: true)), "completed")
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: nil)), "never flipped, no date yet")
    }

    func testTheLabelAloneIsNotMembership() {
        XCTAssertTrue(FlipboardSwitch.hasLabel(["Errands", "flipboard"]))
        XCTAssertFalse(FlipboardSwitch.hasLabel(["flip"]))
        XCTAssertFalse(FlipboardSwitch.hasLabel([]))
    }

    // MARK: - Sides

    func testGreenIsDueAfterTodayRedIsDueTodayOverdueOrUndated() {
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 22), now: now, calendar: cal), .green, "due tomorrow")
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 21), now: now, calendar: cal), .red, "due today")
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 21, 23), now: now, calendar: cal), .red, "later today")
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 14), now: now, calendar: cal), .red, "overdue")
        XCTAssertEqual(FlipboardSwitch.side(due: nil, now: now, calendar: cal), .red, "never flipped")
    }

    func testOverdueIsPastItsDueDayNotMerelyDueToday() {
        XCTAssertFalse(FlipboardSwitch.isOverdue(due: Fixed.date(2026, 10, 21), now: now, calendar: cal))
        XCTAssertTrue(FlipboardSwitch.isOverdue(due: Fixed.date(2026, 10, 20), now: now, calendar: cal))
        XCTAssertFalse(FlipboardSwitch.isOverdue(due: nil, now: now, calendar: cal))
    }

    func testALooseTimedSwitchIsRedAllOfItsDayCalmUntilItsTime() {
        // Due today at 21:00; now is 14:30.
        let due = Fixed.date(2026, 10, 21, 21)
        XCTAssertEqual(FlipboardSwitch.side(due: due, hasTime: true, now: now, calendar: cal), .red)
        XCTAssertFalse(FlipboardSwitch.isDueNow(due: due, hasTime: true, now: now, calendar: cal))
        XCTAssertFalse(FlipboardSwitch.isLate(due: due, hasTime: true, now: now, calendar: cal))
        XCTAssertTrue(FlipboardSwitch.isDueNow(due: due, hasTime: true, now: Fixed.date(2026, 10, 21, 21), calendar: cal))
        XCTAssertTrue(FlipboardSwitch.isLate(due: due, hasTime: true, now: Fixed.date(2026, 10, 21, 22), calendar: cal))
        XCTAssertTrue(FlipboardSwitch.isDueNow(due: Fixed.date(2026, 10, 20, 21), hasTime: true, now: now, calendar: cal), "yesterday's")
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 22, 8), hasTime: true, now: now, calendar: cal), .green)
    }

    func testALooseUntimedSwitchIsDueFromTheStartOfItsDay() {
        XCTAssertTrue(FlipboardSwitch.isDueNow(due: Fixed.date(2026, 10, 21), hasTime: false, now: Fixed.date(2026, 10, 21, 0, 1), calendar: cal))
        XCTAssertFalse(FlipboardSwitch.isDueNow(due: Fixed.date(2026, 10, 22), hasTime: false, now: now, calendar: cal))
        XCTAssertTrue(FlipboardSwitch.isDueNow(due: nil, hasTime: false, now: now, calendar: cal), "never flipped")
        XCTAssertFalse(FlipboardSwitch.isLate(due: Fixed.date(2026, 10, 21), hasTime: false, now: now, calendar: cal), "due today")
        XCTAssertTrue(FlipboardSwitch.isLate(due: Fixed.date(2026, 10, 19), hasTime: false, now: now, calendar: cal), "overdue")
    }

    func testABoardsSwitchFollowsTheBoardsClock() {
        // A daily board resetting at 04:00: at 01:30 on Thursday a switch due "Thursday" is still green.
        let board = SwitchboardSchedule(cadence: .daily)
        let switchOnBoard = PlainTask(title: "Floss", dueDate: Fixed.date(2026, 10, 22), labelNames: ["flipboard"],
                                      isRecurring: true, switchboard: board)
        XCTAssertEqual(FlipboardSwitch.side(of: switchOnBoard, now: Fixed.date(2026, 10, 22, 1, 30), calendar: cal), .green)
        XCTAssertEqual(FlipboardSwitch.side(of: switchOnBoard, now: Fixed.date(2026, 10, 22, 4), calendar: cal), .red)
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 22), board: board, now: Fixed.date(2026, 10, 22, 1, 30),
                                            calendar: cal), .green, "the plain-values form agrees")
        XCTAssertFalse(FlipboardSwitch.isOverdue(due: nil, now: now, calendar: cal))
    }

    func testTheSideOfATaskIsNilWhenItIsNotASwitch() {
        XCTAssertEqual(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 30)), now: now, calendar: cal), .green)
        XCTAssertEqual(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 1)), now: now, calendar: cal), .red)
        XCTAssertNil(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 30), labels: []), now: now, calendar: cal))
    }
}

/// Briefs 59 and 72, the listing rule: a switch is on the Flipboard only, green or red, unless it opted in
/// ("Overdue becomes task"); an opted-in switch is a task for today once it is due, every day, until it is flipped.
/// One core function decides it for every list.
final class FlipboardListingTests: XCTestCase {
    private let cal = Fixed.calendar
    /// Wednesday 2026-10-21 14:30 UTC.
    private let now = Fixed.now

    private func titles<T: FilterableTask>(_ tasks: [T]) -> [String] { tasks.map(\.filterTitle) }

    /// Due Oct 30: green, opted in (still on the Flipboard only).
    private var green: PlainTask {
        PlainTask(title: "Shave", dueDate: Fixed.date(2026, 10, 30), projectName: "Home",
                  labelNames: ["flipboard"], isRecurring: true, switchOptedIn: true)
    }
    /// Due Oct 18, three days ago: red, opted in.
    private var red: PlainTask {
        PlainTask(title: "Water plants", dueDate: Fixed.date(2026, 10, 18), projectName: "Home",
                  labelNames: ["flipboard"], isRecurring: true, switchOptedIn: true)
    }
    /// Never flipped, no date: red, opted in.
    private var fresh: PlainTask {
        PlainTask(title: "Floss", projectName: "Home", labelNames: ["flipboard"], isRecurring: true, switchOptedIn: true)
    }
    /// Due Oct 19, two days ago: red, and as every switch is by default (brief 72), not opted in: never a task.
    private var quiet: PlainTask {
        PlainTask(title: "Stretch", dueDate: Fixed.date(2026, 10, 19), projectName: "Home",
                  labelNames: ["flipboard"], isRecurring: true)
    }
    /// An ordinary recurring task three days overdue: keeps its date.
    private var plainRecurring: PlainTask {
        PlainTask(title: "Pay rent", dueDate: Fixed.date(2026, 10, 18), isRecurring: true)
    }
    private var tomorrow: PlainTask { PlainTask(title: "Dentist", dueDate: Fixed.date(2026, 10, 22)) }
    private var yesterday: PlainTask { PlainTask(title: "Call Sam", dueDate: Fixed.date(2026, 10, 20)) }
    private var dueToday: PlainTask { PlainTask(title: "Groceries", dueDate: Fixed.date(2026, 10, 21)) }

    private var all: [PlainTask] { [green, red, fresh, quiet, plainRecurring, tomorrow, yesterday, dueToday] }

    // MARK: - The rule

    func testASwitchIsNeverATaskByDefault() {
        XCTAssertEqual(FlipboardSwitch.listing(for: quiet, now: now, calendar: cal), .hidden, "red, but not opted in")
        var never = fresh
        never.filterSwitchOptedIn = false
        XCTAssertEqual(FlipboardSwitch.listing(for: never, now: now, calendar: cal), .hidden)
        XCTAssertEqual(FlipboardSwitch.listedDueDate(for: quiet, now: now, calendar: cal), Fixed.date(2026, 10, 19))
        XCTAssertFalse(TaskOrdering.isInToday(quiet, now: now, calendar: cal))
        XCTAssertFalse(TaskOrdering.isInInbox(quiet, now: now, calendar: cal))
        XCTAssertNil(TaskOrdering.todaySection(of: quiet, now: now, calendar: cal))
    }

    func testAnOptedInTimedSwitchIsTodaysFromItsTime() {
        // "Take meds 21:00", opted in, due today: off every list until 21:00, then today's (never overdue).
        let meds = PlainTask(title: "Take meds", dueDate: Fixed.date(2026, 10, 21, 21), hasDueTime: true,
                             labelNames: ["flipboard"], isRecurring: true, switchOptedIn: true)
        XCTAssertEqual(FlipboardSwitch.listing(for: meds, now: now, calendar: cal), .hidden, "14:30: not yet")
        let nine = Fixed.date(2026, 10, 21, 21)
        XCTAssertEqual(FlipboardSwitch.listing(for: meds, now: nine, calendar: cal), .today)
        let listed = FlipboardSwitch.listed(meds, now: nine, calendar: cal)
        XCTAssertEqual(listed.filterDueDate, Fixed.date(2026, 10, 21))
        XCTAssertFalse(listed.filterHasDueTime, "a today task, not one at midnight")
        XCTAssertEqual(FlipboardSwitch.listing(for: listed, now: nine, calendar: cal), .today, "judged again, still today's")
        XCTAssertEqual(titles(TaskOrdering.today([meds], now: nine, calendar: cal).today), ["Take meds"])
        XCTAssertEqual(titles(TaskOrdering.today([meds], now: Fixed.date(2026, 10, 22, 9), calendar: cal).today), ["Take meds"],
                       "missed yesterday: today's, not overdue")
    }

    func testAnOptedInBoardSwitchIsTodaysFromTheBoardsReset() {
        // A daily board resetting at 04:00; Floss flipped yesterday evening, so due on Thursday's board day.
        let board = SwitchboardSchedule(cadence: .daily)
        let floss = PlainTask(title: "Floss", dueDate: Fixed.date(2026, 10, 22), labelNames: ["flipboard"],
                              isRecurring: true, switchOptedIn: true, switchboard: board)
        XCTAssertEqual(FlipboardSwitch.listing(for: floss, now: Fixed.date(2026, 10, 22, 1, 30), calendar: cal), .hidden,
                       "01:30 is still Wednesday's board day: done")
        XCTAssertEqual(FlipboardSwitch.listing(for: floss, now: Fixed.date(2026, 10, 22, 4), calendar: cal), .today)
        let listed = FlipboardSwitch.listed(floss, now: Fixed.date(2026, 10, 23, 2), calendar: cal)
        XCTAssertEqual(listed.filterDueDate, Fixed.date(2026, 10, 23), "listed under the calendar day it is")
        XCTAssertEqual(FlipboardSwitch.listing(for: listed, now: Fixed.date(2026, 10, 23, 2), calendar: cal), .today)
    }

    func testTheRuleFromPlainValues() {
        XCTAssertEqual(FlipboardSwitch.listing(isSwitch: false, optedIn: true, due: nil, hasTime: false, board: nil, now: now, calendar: cal),
                       .unchanged)
        XCTAssertEqual(FlipboardSwitch.listing(isSwitch: true, optedIn: false, due: nil, hasTime: false, board: nil, now: now, calendar: cal),
                       .hidden)
        XCTAssertEqual(FlipboardSwitch.listing(isSwitch: true, optedIn: true, due: nil, hasTime: false, board: nil, now: now, calendar: cal),
                       .today)
    }

    func testAnOptedInSwitchIsTodaysOnceDueGreenOnesNever() {
        XCTAssertEqual(FlipboardSwitch.listing(for: green, now: now, calendar: cal), .hidden)
        XCTAssertEqual(FlipboardSwitch.listing(for: red, now: now, calendar: cal), .today)
        XCTAssertEqual(FlipboardSwitch.listing(for: fresh, now: now, calendar: cal), .today)
        XCTAssertEqual(FlipboardSwitch.listing(for: plainRecurring, now: now, calendar: cal), .unchanged)
        XCTAssertEqual(FlipboardSwitch.listing(for: tomorrow, now: now, calendar: cal), .unchanged)
        var done = red
        done.filterIsCompleted = true
        XCTAssertEqual(FlipboardSwitch.listing(for: done, now: now, calendar: cal), .unchanged, "not a switch once completed")
    }

    func testARedSwitchIsListedAsDueAtTheStartOfToday() {
        XCTAssertEqual(FlipboardSwitch.listedDueDate(for: red, now: now, calendar: cal), Fixed.date(2026, 10, 21))
        XCTAssertEqual(FlipboardSwitch.listedDueDate(for: fresh, now: now, calendar: cal), Fixed.date(2026, 10, 21))
        XCTAssertEqual(FlipboardSwitch.listedDueDate(for: plainRecurring, now: now, calendar: cal), Fixed.date(2026, 10, 18))
        XCTAssertEqual(FlipboardSwitch.listedDueDate(for: green, now: now, calendar: cal), Fixed.date(2026, 10, 30),
                       "hidden keeps its own date for whoever asks")
    }

    func testTheListedViewOfARedSwitchIsATodayTask() {
        let listed = FlipboardSwitch.listed(red, now: now, calendar: cal)
        XCTAssertEqual(listed.filterTitle, "Water plants")
        XCTAssertEqual(listed.filterDueDate, Fixed.date(2026, 10, 21))
        XCTAssertEqual(listed.filterLabelNames, ["flipboard"])
        XCTAssertEqual(listed.filterProjectName, "Home")
    }

    // MARK: - Today

    func testTodayListsTheRedSwitchesAsTodayNeverAsOverdue() {
        let list = TaskOrdering.today(all, now: now, calendar: cal)
        XCTAssertEqual(titles(list.overdue), ["Pay rent", "Call Sam"])
        XCTAssertEqual(Set(titles(list.today)), ["Water plants", "Floss", "Groceries"])
        XCTAssertFalse(titles(list.today + list.overdue).contains("Shave"))
        XCTAssertFalse(titles(list.today + list.overdue).contains("Stretch"), "not opted in")
    }

    func testTodaySectionOfATask() {
        XCTAssertEqual(TaskOrdering.todaySection(of: red, now: now, calendar: cal), .today)
        XCTAssertEqual(TaskOrdering.todaySection(of: fresh, now: now, calendar: cal), .today)
        XCTAssertNil(TaskOrdering.todaySection(of: green, now: now, calendar: cal))
        XCTAssertEqual(TaskOrdering.todaySection(of: plainRecurring, now: now, calendar: cal), .overdue)
        XCTAssertEqual(TaskOrdering.todaySection(of: dueToday, now: now, calendar: cal), .today)
        XCTAssertNil(TaskOrdering.todaySection(of: tomorrow, now: now, calendar: cal))
    }

    func testIsInTodayAgreesWithTheList() {
        XCTAssertTrue(TaskOrdering.isInToday(red, now: now, calendar: cal))
        XCTAssertTrue(TaskOrdering.isInToday(fresh, now: now, calendar: cal), "never flipped: red, so today")
        XCTAssertFalse(TaskOrdering.isInToday(green, now: now, calendar: cal))
        XCTAssertFalse(TaskOrdering.isInToday(quiet, now: now, calendar: cal))
    }

    // MARK: - Inbox

    func testTheInboxHidesGreenSwitchesAndKeepsRedOnesAsToday() {
        XCTAssertFalse(TaskOrdering.isInInbox(green, now: now, calendar: cal))
        XCTAssertTrue(TaskOrdering.isInInbox(red, now: now, calendar: cal))
        XCTAssertTrue(TaskOrdering.isInInbox(fresh, now: now, calendar: cal), "a red switch is dated today, even in a Group")
        let inbox = TaskOrdering.inbox(all, now: now, calendar: cal)
        XCTAssertFalse(titles(inbox).contains("Shave"))
        XCTAssertFalse(titles(inbox).contains("Stretch"))
        // All P4: by listed due date, so the overdue switch sorts with today's tasks, after yesterday's.
        XCTAssertEqual(titles(inbox), ["Pay rent", "Call Sam", "Floss", "Groceries", "Water plants", "Dentist"])
    }

    // MARK: - Search

    func testSearchLeavesGreenSwitchesOut() {
        let tasks = [green, red, quiet, PlainTask(title: "Shave the dog")]
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "shave", now: now, calendar: cal)), ["Shave the dog"])
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "water", now: now, calendar: cal)), ["Water plants"])
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "stretch", now: now, calendar: cal)), [], "not opted in")
    }

    // MARK: - Filters

    private func apply(_ source: String, _ tasks: [PlainTask]? = nil) throws -> [String] {
        titles(try FilterQuery(source, calendar: cal, now: now).apply(to: tasks ?? all, now: now, calendar: cal))
    }

    func testAFilterNeverListsAGreenSwitch() throws {
        XCTAssertFalse(try apply("all").contains("Shave"))
        XCTAssertFalse(try apply("#Home").contains("Shave"))
        XCTAssertFalse(try apply("recurring").contains("Shave"))
        XCTAssertFalse(try apply("next 30 days").contains("Shave"))
        XCTAssertFalse(try apply("search: shave").contains("Shave"))
        XCTAssertFalse(try apply("all").contains("Stretch"), "a red switch that didn't opt in")
        XCTAssertFalse(try apply("overdue | today").contains("Stretch"))
        let query = try FilterQuery("all", calendar: cal, now: now)
        XCTAssertFalse(query.matches(green, now: now, calendar: cal))
        XCTAssertTrue(query.matches(red, now: now, calendar: cal))
    }

    func testAFilterSeesARedSwitchAsDueToday() throws {
        XCTAssertEqual(try apply("overdue"), ["Pay rent", "Call Sam"])
        XCTAssertEqual(Set(try apply("today")), ["Water plants", "Floss", "Groceries"])
        XCTAssertEqual(Set(try apply("overdue | today")), ["Pay rent", "Call Sam", "Water plants", "Floss", "Groceries"])
        XCTAssertFalse(try apply("no date").contains("Floss"), "a never-flipped switch is a today task")
        let focus = try FilterQuery("today", calendar: cal, now: now)
        XCTAssertTrue(focus.matches(red, now: now, calendar: cal))
    }

    func testAFilterSortsARedSwitchAsDueToday() throws {
        // Due-then-priority: yesterday's task first, the switch among today's.
        XCTAssertEqual(try apply("overdue | today | tomorrow"),
                       ["Pay rent", "Call Sam", "Floss", "Groceries", "Water plants", "Dentist"])
    }

    func testAQueryThatNamesTheFlipboardSeesSwitchesAsTheyAre() throws {
        XCTAssertEqual(Set(try apply("@flipboard")), ["Shave", "Water plants", "Floss", "Stretch"], "every switch, opted in or not")
        XCTAssertEqual(Set(try apply("@FlipBoard")), ["Shave", "Water plants", "Floss", "Stretch"], "any case")
        XCTAssertEqual(try apply("@flipboard & overdue"), ["Water plants", "Stretch"], "its real date")
        XCTAssertEqual(try apply("@flipboard & 7 days | @flipboard & next 30 days"), ["Shave"])
        XCTAssertEqual(try apply("!@flipboard & #Home"), [], "naming it to leave it out is naming it too")
        XCTAssertTrue(try FilterQuery("@flipboard", calendar: cal, now: now).namesFlipboard)
        XCTAssertTrue(try FilterQuery("p1 | @flip*", calendar: cal, now: now).namesFlipboard)
        XCTAssertFalse(try FilterQuery("@home | #Flipboard", calendar: cal, now: now).namesFlipboard,
                       "a Group called Flipboard is not the label")
    }

    func testTheRuleCanBeTurnedOffForToolsThatListEveryTask() throws {
        let query = try FilterQuery("all", calendar: cal, now: now)
        let every = titles(query.apply(to: all, now: now, calendar: cal, flipboardRule: false))
        XCTAssertTrue(every.contains("Shave"))
        let overdue = try FilterQuery("overdue", calendar: cal, now: now)
        XCTAssertEqual(titles(overdue.apply(to: all, now: now, calendar: cal, flipboardRule: false)),
                       ["Pay rent", "Water plants", "Stretch", "Call Sam"])
    }

    func testOrdinaryRecurringTasksKeepTheirDatesEverywhere() throws {
        XCTAssertTrue(try apply("overdue").contains("Pay rent"))
        XCTAssertEqual(TaskOrdering.todaySection(of: plainRecurring, now: now, calendar: cal), .overdue)
        XCTAssertTrue(TaskOrdering.isInInbox(plainRecurring, now: now, calendar: cal))
    }
}
