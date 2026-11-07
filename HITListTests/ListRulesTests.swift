import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round-3 list rules on real `TaskItem`s: the Inbox rule (list, count, Process queue), Today's
/// sections and day header, and Browse search reaching completed tasks.
@MainActor
final class ListRulesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()
    private let locale = Locale(identifier: "en_US")

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Saturday, Oct 31 2026, 10:00.
    private var now: Date { date(2026, 10, 31, 10) }

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    @discardableResult
    private func task(_ title: String, due: Date? = nil, time: Bool = false, priority: Priority = .p4,
                      project: Project? = nil, notes: String = "", minutesAgo: Double = 0) -> TaskItem {
        let t = TaskItem(title: title, project: project)
        t.dueDate = due
        t.hasDueTime = time
        t.priorityValue = priority
        t.notes = notes
        t.createdAt = now.addingTimeInterval(-minutesAgo * 60)
        context.insert(t)
        return t
    }

    private func allTasks() throws -> [TaskItem] { try context.fetch(FetchDescriptor<TaskItem>()) }

    // MARK: - Inbox

    func testInboxHoldsDatedTasksFromGroupsButNotGroupNotes() throws {
        let work = Project(name: "Work")
        context.insert(work)
        let loose = task("loose", minutesAgo: 40)
        let datedInWork = task("dated in Work", due: date(2026, 11, 3), project: work, minutesAgo: 30)
        let noteInWork = task("note in Work", project: work, minutesAgo: 20)
        let done = task("done", due: date(2026, 10, 31), minutesAgo: 10)
        done.isCompleted = true
        try context.save()

        XCTAssertTrue(loose.isInInbox)
        XCTAssertTrue(datedInWork.isInInbox)
        XCTAssertFalse(noteInWork.isInInbox, "an undated task in a Group is a note")
        XCTAssertFalse(done.isInInbox)

        let tasks = try allTasks()
        XCTAssertEqual(tasks.filter(\.isInInbox).count, 2, "the Inbox count")
        XCTAssertEqual(InboxProcessQueue(reviewOf: tasks).remaining, [loose.id], "Review Inbox: only the unsorted")
        XCTAssertEqual(TaskOrdering.inbox(tasks).map(\.title), ["dated in Work", "loose"], "undated last")
    }

    func testRemovingTheDateOfAGroupTaskTakesItOutOfTheInbox() throws {
        let work = Project(name: "Work")
        context.insert(work)
        let t = task("call", due: date(2026, 11, 1), project: work)
        try context.save()
        XCTAssertTrue(t.isInInbox)

        TaskActions.reschedule(t, to: nil, in: context)
        XCTAssertFalse(t.isInInbox)
        XCTAssertFalse(t.needsReview, "a Group note is never reviewed")
    }

    // MARK: - Today

    func testTodaySectionsSortByPriorityThenTimeAndSkipUndated() throws {
        let home = Project(name: "Home")
        context.insert(home)
        task("overdue p4", due: date(2026, 10, 29))
        task("overdue p1", due: date(2026, 10, 30), priority: .p1)
        task("today 5pm p3", due: date(2026, 10, 31, 17), time: true, priority: .p3)
        task("today all day p3", due: date(2026, 10, 31), priority: .p3)
        task("today p1", due: date(2026, 10, 31, 20), time: true, priority: .p1)
        task("tomorrow", due: date(2026, 11, 1), priority: .p1)
        task("undated", priority: .p1)
        task("note", priority: .p1, project: home)
        try context.save()

        let list = TaskOrdering.today(try allTasks(), now: now, calendar: calendar)
        XCTAssertEqual(list.overdue.map(\.title), ["overdue p1", "overdue p4"])
        XCTAssertEqual(list.today.map(\.title), ["today p1", "today all day p3", "today 5pm p3"])
    }

    func testTodayHeaderTitlesAndColours() {
        XCTAssertEqual(DueFormatter.sectionTitle(for: now, now: now, style: .dated, calendar: calendar, locale: locale),
                       "Oct 31, Saturday")
        XCTAssertEqual(DueFormatter.sectionTitle(for: date(2026, 10, 30), now: now, style: .dated, calendar: calendar, locale: locale),
                       "Overdue")
        XCTAssertEqual(DueFormatter.sectionTitle(for: now, now: now, calendar: calendar, locale: locale), "Today")
        XCTAssertEqual(DueFormatter.dayTitle(for: date(2027, 1, 2), now: now, calendar: calendar, locale: locale),
                       "Jan 2, 2027, Saturday")
        XCTAssertEqual(DueFormatter.sectionColor(for: date(2026, 10, 30), now: now, calendar: calendar), HITColor.dueOverdue)
        XCTAssertEqual(DueFormatter.sectionColor(for: date(2026, 10, 31, 23), now: now, calendar: calendar), HITColor.dueToday)
        XCTAssertEqual(DueFormatter.sectionColor(for: date(2026, 11, 1), now: now, calendar: calendar), Theme.secondaryText)
    }

    func testTimeTextForRowsUnderTheDayHeader() {
        // Foundation puts a narrow no-break space before "PM".
        let text = DueFormatter.timeText(for: date(2026, 10, 31, 17, 30), calendar: calendar, locale: locale)
        XCTAssertEqual(text.replacingOccurrences(of: "\u{202F}", with: " "), "5:30 PM")
    }

    // MARK: - Browse search

    func testBrowseSearchFindsCompletedTasksAndNotes() throws {
        let done = task("Renew passport")
        TaskActions.toggleCompletion(done, in: context)
        task("Call the bank", notes: "passport fee")
        task("Buy milk")
        try context.save()

        let results = TaskOrdering.search(try allTasks(), text: "passport")
        XCTAssertEqual(results.map(\.title), ["Call the bank", "Renew passport"])
        XCTAssertTrue(results.last?.isCompleted == true)
    }
}
