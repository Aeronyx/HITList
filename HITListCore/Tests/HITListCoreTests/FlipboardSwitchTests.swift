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

    func testAMemberIsAnOpenRecurringTaskWithoutATimeCarryingTheLabel() {
        let due = Fixed.date(2026, 10, 25)
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: due)))
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: due, labels: ["home", "FlipBoard"])), "the label in any case")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, labels: ["home"])), "no label")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, recurring: false)), "no repeat")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, hasTime: true)), "a time of day")
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

    func testTheSideOfATaskIsNilWhenItIsNotASwitch() {
        XCTAssertEqual(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 30)), now: now, calendar: cal), .green)
        XCTAssertEqual(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 1)), now: now, calendar: cal), .red)
        XCTAssertNil(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 30), labels: []), now: now, calendar: cal))
    }
}

/// Brief 59, the listing rule: a green switch is on the Flipboard only; a red one is a task for today,
/// every day, until it is flipped. One core function decides it for every list.
final class FlipboardListingTests: XCTestCase {
    private let cal = Fixed.calendar
    /// Wednesday 2026-10-21 14:30 UTC.
    private let now = Fixed.now

    private func titles<T: FilterableTask>(_ tasks: [T]) -> [String] { tasks.map(\.filterTitle) }

    /// Due Oct 30: green.
    private var green: PlainTask {
        PlainTask(title: "Shave", dueDate: Fixed.date(2026, 10, 30), projectName: "Home",
                  labelNames: ["flipboard"], isRecurring: true)
    }
    /// Due Oct 18, three days ago: red.
    private var red: PlainTask {
        PlainTask(title: "Water plants", dueDate: Fixed.date(2026, 10, 18), projectName: "Home",
                  labelNames: ["flipboard"], isRecurring: true)
    }
    /// Never flipped, no date: red.
    private var fresh: PlainTask {
        PlainTask(title: "Floss", projectName: "Home", labelNames: ["flipboard"], isRecurring: true)
    }
    /// An ordinary recurring task three days overdue: keeps its date.
    private var plainRecurring: PlainTask {
        PlainTask(title: "Pay rent", dueDate: Fixed.date(2026, 10, 18), isRecurring: true)
    }
    private var tomorrow: PlainTask { PlainTask(title: "Dentist", dueDate: Fixed.date(2026, 10, 22)) }
    private var yesterday: PlainTask { PlainTask(title: "Call Sam", dueDate: Fixed.date(2026, 10, 20)) }
    private var dueToday: PlainTask { PlainTask(title: "Groceries", dueDate: Fixed.date(2026, 10, 21)) }

    private var all: [PlainTask] { [green, red, fresh, plainRecurring, tomorrow, yesterday, dueToday] }

    // MARK: - The rule

    func testGreenIsHiddenRedIsTodayEverythingElseUnchanged() {
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
    }

    // MARK: - Inbox

    func testTheInboxHidesGreenSwitchesAndKeepsRedOnesAsToday() {
        XCTAssertFalse(TaskOrdering.isInInbox(green, now: now, calendar: cal))
        XCTAssertTrue(TaskOrdering.isInInbox(red, now: now, calendar: cal))
        XCTAssertTrue(TaskOrdering.isInInbox(fresh, now: now, calendar: cal), "a red switch is dated today, even in a Group")
        let inbox = TaskOrdering.inbox(all, now: now, calendar: cal)
        XCTAssertFalse(titles(inbox).contains("Shave"))
        // All P4: by listed due date, so the overdue switch sorts with today's tasks, after yesterday's.
        XCTAssertEqual(titles(inbox), ["Pay rent", "Call Sam", "Floss", "Groceries", "Water plants", "Dentist"])
    }

    // MARK: - Search

    func testSearchLeavesGreenSwitchesOut() {
        let tasks = [green, red, PlainTask(title: "Shave the dog")]
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "shave", now: now, calendar: cal)), ["Shave the dog"])
        XCTAssertEqual(titles(TaskOrdering.search(tasks, text: "water", now: now, calendar: cal)), ["Water plants"])
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
        XCTAssertEqual(Set(try apply("@flipboard")), ["Shave", "Water plants", "Floss"])
        XCTAssertEqual(Set(try apply("@FlipBoard")), ["Shave", "Water plants", "Floss"], "any case")
        XCTAssertEqual(try apply("@flipboard & overdue"), ["Water plants"], "its real date")
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
                       ["Pay rent", "Water plants", "Call Sam"])
    }

    func testOrdinaryRecurringTasksKeepTheirDatesEverywhere() throws {
        XCTAssertTrue(try apply("overdue").contains("Pay rent"))
        XCTAssertEqual(TaskOrdering.todaySection(of: plainRecurring, now: now, calendar: cal), .overdue)
        XCTAssertTrue(TaskOrdering.isInInbox(plainRecurring, now: now, calendar: cal))
    }
}
