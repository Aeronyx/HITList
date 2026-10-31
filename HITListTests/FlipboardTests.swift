import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// The Flipboard's pure rules (fixed UTC calendar and dates) and its model actions (in-memory store;
/// these run on `Calendar.current` and `Date()` like `TaskActions`, so expectations use the same).
@MainActor
final class FlipboardTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        return cal
    }()
    private var utc: Calendar { Self.utc }
    private let cal = Calendar.current

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    /// 2026-month-day at hour:00 UTC.
    private func day(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private var today: Date { cal.startOfDay(for: Date()) }
    private func daysFromToday(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

    private let every3Days = RecurrenceRule(frequency: .daily, interval: 3)

    // MARK: Membership

    func testMembershipNeedsRepeatNoTimeOpenAndLabel() {
        let weekly = RecurrenceRule.weekly.encoded
        XCTAssertTrue(Flipboard.isMember(recurrence: weekly, hasDueTime: false, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertTrue(Flipboard.isMember(recurrence: weekly, hasDueTime: false, isCompleted: false, labelNames: ["home", "FlipBoard"]),
                      "label match ignores case")
        XCTAssertFalse(Flipboard.isMember(recurrence: weekly, hasDueTime: false, isCompleted: false, labelNames: ["home"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: nil, hasDueTime: false, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: "garbage", hasDueTime: false, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: weekly, hasDueTime: true, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: weekly, hasDueTime: false, isCompleted: true, labelNames: ["flipboard"]))
    }

    // MARK: Sides

    func testSideFromDates() {
        let now = day(10, 28, 15)
        XCTAssertEqual(Flipboard.side(due: day(10, 29), now: now, calendar: utc), .green, "due tomorrow")
        XCTAssertEqual(Flipboard.side(due: day(10, 28), now: now, calendar: utc), .red, "due today")
        XCTAssertEqual(Flipboard.side(due: day(10, 28, 23), now: now, calendar: utc), .red, "later today is still today")
        XCTAssertEqual(Flipboard.side(due: day(10, 20), now: now, calendar: utc), .red, "overdue")
        XCTAssertEqual(Flipboard.side(due: nil, now: now, calendar: utc), .red, "never flipped")
    }

    func testOverdueOnlyAfterTheDueDay() {
        let now = day(10, 28, 15)
        XCTAssertFalse(Flipboard.isOverdue(due: day(10, 28), now: now, calendar: utc))
        XCTAssertTrue(Flipboard.isOverdue(due: day(10, 27), now: now, calendar: utc))
        XCTAssertFalse(Flipboard.isOverdue(due: nil, now: now, calendar: utc))
        XCTAssertEqual(Flipboard.daysOverdue(due: day(10, 25), now: now, calendar: utc), 3)
        XCTAssertEqual(Flipboard.daysOverdue(due: day(10, 30), now: now, calendar: utc), 0)
    }

    // MARK: Interval extraction

    func testIntervalDaysForDailyEveryNAndWeeklyRules() {
        let due = day(10, 28) // a Wednesday
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: .daily, calendar: utc), 1)
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: every3Days, calendar: utc), 3)
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: .weekly, calendar: utc), 7)
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: RecurrenceRule(frequency: .weekly, interval: 2), calendar: utc), 14)
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: .monthly, calendar: utc), 30, "Sep 28 to Oct 28")
    }

    func testIntervalStartForWeekdayRuleIsThePreviousChosenDay() {
        let monWedFri = RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6])
        XCTAssertEqual(Flipboard.intervalStart(due: day(10, 28), rule: monWedFri, calendar: utc), day(10, 26), "Wed ← Mon")
        XCTAssertEqual(Flipboard.intervalStart(due: day(10, 26), rule: monWedFri, calendar: utc), day(10, 23), "Mon ← Fri")
        XCTAssertEqual(Flipboard.intervalDays(due: day(10, 26), rule: monWedFri, calendar: utc), 3)
    }

    // MARK: The light bar

    func testElapsedFractionIsClamped() {
        let due = day(10, 31) // every 3 days: the interval runs Oct 28 → Oct 31
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(10, 28), calendar: utc), 0, accuracy: 1e-9)
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(10, 29, 12), calendar: utc), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(10, 31), calendar: utc), 1, accuracy: 1e-9)
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(11, 9), calendar: utc), 1, "overdue clamps to 1")
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(10, 1), calendar: utc), 0, "before the interval clamps to 0")
        XCTAssertEqual(Flipboard.elapsedFraction(due: nil, rule: every3Days, now: day(10, 28), calendar: utc), 1)
    }

    func testElapsedDaysReadsTwoOfThree() {
        let due = day(10, 31)
        XCTAssertEqual(Flipboard.elapsedDays(due: due, rule: every3Days, now: day(10, 28, 9), calendar: utc), 0)
        XCTAssertEqual(Flipboard.elapsedDays(due: due, rule: every3Days, now: day(10, 30, 9), calendar: utc), 2)
        XCTAssertEqual(Flipboard.elapsedDays(due: due, rule: every3Days, now: day(11, 15), calendar: utc), 3, "clamped to the interval")
    }

    // MARK: Order

    func testRedFirstMostOverdueOnTopThenGreenBySoonest() {
        let items: [(due: Date?, title: String)] = [
            (day(11, 4), "Call grandma"),
            (day(10, 28), "Floss"),        // due today
            (day(10, 30), "Shave"),
            (day(10, 20), "Water plants"), // most overdue
            (nil, "New"),                  // never flipped
            (day(10, 30), "Bins"),         // same day as Shave
        ]
        let sorted = items.sorted { Flipboard.isOrderedBefore($0, $1, calendar: utc) }.map(\.title)
        XCTAssertEqual(sorted, ["New", "Water plants", "Floss", "Bins", "Shave", "Call grandma"])
    }

    // MARK: Layout

    func testColumnCount() {
        XCTAssertEqual(FlipboardLayout.columnCount(width: 361, compact: true, spacing: 14), 2)
        XCTAssertEqual(FlipboardLayout.columnCount(width: 300, compact: false, spacing: 14), 3, "never fewer than 3 on Mac/iPad")
        XCTAssertEqual(FlipboardLayout.columnCount(width: 700, compact: false, spacing: 14), 4)
        XCTAssertEqual(FlipboardLayout.columnCount(width: 2000, compact: false, spacing: 14), 5, "never more than 5")
    }

    func testFlipIntervalRoundTrip() {
        XCTAssertEqual(FlipInterval(every3Days), FlipInterval(count: 3, unit: .days))
        XCTAssertEqual(FlipInterval(RecurrenceRule(frequency: .weekly, interval: 2))?.rule, RecurrenceRule(frequency: .weekly, interval: 2))
        XCTAssertNil(FlipInterval(.monthly))
        XCTAssertNil(FlipInterval(.weekdays))
    }

    // MARK: Flipping (model)

    /// A switch due on `due`. `add` would move a past due date to today, so it is set again afterwards.
    private func switchTask(_ title: String = "Shave", due: Date?, rule: RecurrenceRule? = nil) throws -> TaskItem {
        let task = TaskItem(title: title, dueDate: due, recurrence: rule ?? every3Days)
        context.insert(task)
        try Flipboard.add(task, in: context)
        task.dueDate = due
        return task
    }

    func testFlipOnOverdueTaskLandsInTheFuture() throws {
        let task = try switchTask(due: daysFromToday(-2))
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .red)
        Flipboard.flip(task, in: context)
        XCTAssertGreaterThan(task.dueDate!, today)
        XCTAssertEqual(task.dueDate, daysFromToday(3), "a flip restarts the interval from today, not from the old due date")
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .green)
        XCTAssertFalse(task.isCompleted, "a switch rolls forward instead of completing")
        XCTAssertTrue(Flipboard.isMember(task))
    }

    func testFlipOfLongOverdueSwitchRestartsFromToday() throws {
        // toggleCompletion alone would give today (-3 + 3) and leave the switch red.
        let task = try switchTask(due: daysFromToday(-3))
        Flipboard.flip(task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(3))
    }

    func testFlipDueTodayResetsAFullInterval() throws {
        let task = try switchTask(due: today)
        Flipboard.flip(task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(3))
    }

    func testEarlyFlipOfGreenSwitchRestartsFromToday() throws {
        let task = try switchTask("Water plants", due: daysFromToday(4), rule: .weekly)
        Flipboard.flip(task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(7), "watering early restarts the week from today")
    }

    func testFlipWithoutDueDateStartsTheSchedule() throws {
        let task = try switchTask(due: nil)
        task.dueDate = nil
        Flipboard.flip(task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(3))
        XCTAssertFalse(task.isCompleted, "toggleCompletion would complete a dateless recurring task")
    }

    func testDueAfterFlipMatchesFlip() throws {
        for offset in [-10, -3, -2, -1, 0, 1, 2] {
            let task = try switchTask("t\(offset)", due: daysFromToday(offset))
            let expected = Flipboard.dueAfterFlip(due: task.dueDate, rule: every3Days, now: Date())
            Flipboard.flip(task, in: context)
            XCTAssertEqual(task.dueDate, expected, "offset \(offset)")
        }
    }

    // MARK: Joining and leaving

    func testAddCreatesLabelWithStableIdAndFillsInWhatASwitchNeeds() throws {
        let timed = cal.date(bySettingHour: 9, minute: 30, second: 0, of: daysFromToday(2))!
        let task = TaskItem(title: "Trim beard", dueDate: timed, hasDueTime: true)
        context.insert(task)
        try Flipboard.add(task, in: context)

        XCTAssertTrue(Flipboard.isMember(task))
        XCTAssertEqual(task.recurrenceRule, Flipboard.defaultRule)
        XCTAssertFalse(task.hasDueTime)
        XCTAssertEqual(task.dueDate, daysFromToday(2), "time of day dropped")
        let labels = try context.fetch(FetchDescriptor<TaskLabel>())
        XCTAssertEqual(labels.map(\.id), [Flipboard.labelID])
        XCTAssertEqual(Flipboard.labelID, SeedIdentity.uuid(for: "TaskLabel/flipboard"))

        let other = TaskItem(title: "Floss", recurrence: .daily)
        context.insert(other)
        try Flipboard.add(other, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskLabel>()).count, 1, "the label is reused")
        XCTAssertEqual(other.dueDate, today, "a dateless task joins red, due today")
        XCTAssertEqual(Flipboard.side(due: other.dueDate, now: Date()), .red)
        XCTAssertFalse(Flipboard.hasStarted(other))
    }

    func testAddMovesAPastDueDateToTodayAndKeepsAFutureOne() throws {
        let overdue = TaskItem(title: "Bins", dueDate: daysFromToday(-5), recurrence: .weekly)
        let future = TaskItem(title: "Water plants", dueDate: daysFromToday(4), recurrence: .weekly)
        context.insert(overdue)
        context.insert(future)
        try Flipboard.add(overdue, in: context)
        try Flipboard.add(future, in: context)
        XCTAssertEqual(overdue.dueDate, today)
        XCTAssertEqual(Flipboard.side(due: overdue.dueDate, now: Date()), .red)
        XCTAssertEqual(future.dueDate, daysFromToday(4))
        XCTAssertEqual(Flipboard.side(due: future.dueDate, now: Date()), .green)
        XCTAssertTrue(Flipboard.hasStarted(future), "a switch due in the future is running")
    }

    func testAddReusesAnExistingLabelByName() throws {
        let existing = TaskLabel(name: "Flipboard")
        context.insert(existing)
        try context.save()
        let task = try switchTask(due: today)
        XCTAssertEqual(task.labels?.map(\.id), [existing.id])
    }

    func testRemoveKeepsTheRepeat() throws {
        let task = try switchTask(due: daysFromToday(1))
        Flipboard.remove(task, in: context)
        XCTAssertFalse(Flipboard.isMember(task))
        XCTAssertEqual(task.recurrenceRule, every3Days)
        XCTAssertEqual(task.dueDate, daysFromToday(1))
    }

    func testCreateSwitchStartsRed() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: every3Days, in: context)
        XCTAssertTrue(Flipboard.isMember(task))
        XCTAssertEqual(task.dueDate, today)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .red)
        XCTAssertFalse(Flipboard.hasStarted(task))
        XCTAssertEqual(Flipboard.caption(due: task.dueDate, rule: every3Days, started: false, now: Date()), "Flip to start")
    }

    /// George's example: "Shave" every two weeks starts red, a flip makes it green for 14 days, then it
    /// is red until shaved again.
    func testTwoWeekSwitchStartsRedFlipsGreenAndTurnsRedAfterTwoWeeks() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2)
        let now = Date()
        let task = try Flipboard.createSwitch(title: "Shave", rule: rule, in: context, now: now)
        func caption(at date: Date) -> String {
            Flipboard.caption(due: task.dueDate, rule: rule, started: Flipboard.hasStarted(task), now: date)
        }

        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: now), .red)
        XCTAssertEqual(caption(at: now), "Flip to start")

        Flipboard.flip(task, in: context, now: now)
        XCTAssertEqual(task.dueDate, daysFromToday(14))
        XCTAssertTrue(Flipboard.hasStarted(task))
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: now), .green)
        XCTAssertEqual(caption(at: now), "0 of 14 days")
        XCTAssertEqual(Flipboard.elapsedFraction(due: task.dueDate, rule: rule, now: today), 0, accuracy: 1e-9)

        let day13 = cal.date(byAdding: .day, value: 13, to: now)!
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: day13), .green)
        XCTAssertEqual(caption(at: day13), "13 of 14 days")

        let day14 = cal.date(byAdding: .day, value: 14, to: now)!
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: day14), .red)
        XCTAssertEqual(caption(at: day14), "Due today")
        XCTAssertEqual(Flipboard.elapsedFraction(due: task.dueDate, rule: rule, now: day14), 1, accuracy: 1e-9)

        let day15 = cal.date(byAdding: .day, value: 15, to: now)!
        XCTAssertEqual(caption(at: day15), "1 day overdue")
    }

    func testCaptionForSwitchWithoutDueDate() {
        XCTAssertEqual(Flipboard.caption(due: nil, rule: every3Days, started: true, now: day(10, 28), calendar: utc), "Flip to start")
    }

    func testHasStartedComparesDueDayWithCreationDay() {
        XCTAssertFalse(Flipboard.hasStarted(due: day(10, 28), createdAt: day(10, 28, 15), calendar: utc), "created and due today")
        XCTAssertTrue(Flipboard.hasStarted(due: day(10, 31), createdAt: day(10, 28, 15), calendar: utc))
        XCTAssertFalse(Flipboard.hasStarted(due: nil, createdAt: day(10, 28), calendar: utc))
    }

    func testSetRuleOnANewSwitchKeepsItRed() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: every3Days, in: context)
        Flipboard.setRule(RecurrenceRule(frequency: .weekly, interval: 2), for: task, in: context)
        XCTAssertEqual(task.dueDate, today)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .red)
    }

    func testSetRuleKeepsWhenTheIntervalBegan() throws {
        let task = try switchTask(due: daysFromToday(2)) // started yesterday
        Flipboard.setRule(RecurrenceRule(frequency: .daily, interval: 2), for: task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(1))
        XCTAssertEqual(task.recurrenceRule, RecurrenceRule(frequency: .daily, interval: 2))
    }
}
