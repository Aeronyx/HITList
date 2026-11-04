import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// The board's actions on real tasks (brief 38): dropping a card on a day, the Overdue column's
/// Reschedule, the day column's "+ Add task" context, and (Mac) the board rendered offscreen.
/// `TaskActions` uses `Calendar.current`, so dates here are relative to today in the current calendar.
@MainActor
final class UpcomingBoardTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar.current

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private var now: Date { Date() }
    private var today: Date { cal.startOfDay(for: now) }

    /// `offset` days from today at `hour:minute` (or the start of the day).
    private func day(_ offset: Int, _ hour: Int? = nil, _ minute: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: offset, to: today)!
        guard let hour else { return day }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @discardableResult
    private func task(_ title: String = "t", due: Date?, time: Bool = false, recurrence: RecurrenceRule? = nil,
                      done: Bool = false) throws -> TaskItem {
        let t = TaskItem(title: title, dueDate: due, hasDueTime: time, recurrence: recurrence)
        if done { t.isCompleted = true; t.completedAt = now }
        context.insert(t)
        try context.save()
        return t
    }

    private func payload(_ tasks: TaskItem...) -> [String] { tasks.map { TaskRescheduling.dragPayload(for: $0.id) } }

    private func allTasks() throws -> [TaskItem] { try context.fetch(FetchDescriptor<TaskItem>()) }

    // MARK: - Drag to reschedule

    func testDroppingOnADayKeepsTheTimeAndTheRepeatsTime() throws {
        let t = try task(due: day(1, 9, 30), time: true, recurrence: RecurrenceRule.daily.withTime(hour: 9, minute: 30))
        let moved = TaskRescheduling.drop(payload(t), on: day(4), among: try allTasks(), now: now, in: context)
        XCTAssertEqual(moved.map(\.id), [t.id])
        XCTAssertEqual(t.dueDate, day(4, 9, 30), "the day changes, the time of day stays")
        XCTAssertTrue(t.hasDueTime)
        XCTAssertEqual(t.recurrence, "daily;1;;;09:30", "the repeat keeps its time")
    }

    func testDroppingARepeatWhoseRuleHadNoTimeYetTimesTheRule() throws {
        // A repeat written before 0.4.1 has no time in its rule; the move stores the task's time there,
        // as the editor's time setters do (`TaskActions.syncRepeatTime`).
        let t = try task(due: day(1, 7, 15), time: true, recurrence: .weekly)
        TaskRescheduling.drop(payload(t), on: day(2), among: try allTasks(), now: now, in: context)
        XCTAssertEqual(t.dueDate, day(2, 7, 15))
        XCTAssertEqual(t.recurrenceRule?.time, RecurrenceRule.TimeOfDay(hour: 7, minute: 15))
    }

    func testDroppingAnAllDayTaskKeepsItAllDay() throws {
        let t = try task(due: day(0))
        TaskRescheduling.drop(payload(t), on: day(3), among: try allTasks(), now: now, in: context)
        XCTAssertEqual(t.dueDate, day(3))
        XCTAssertFalse(t.hasDueTime)
    }

    func testAnOverdueTaskDropsOntoToday() throws {
        let t = try task(due: day(-3, 8, 0), time: true)
        TaskRescheduling.drop(payload(t), on: day(0), among: try allTasks(), now: now, in: context)
        XCTAssertEqual(t.dueDate, day(0, 8, 0))
    }

    func testDaysBeforeTodayTakeNoDrops() throws {
        let t = try task(due: day(2))
        let moved = TaskRescheduling.drop(payload(t), on: day(-1), among: try allTasks(), now: now, in: context)
        XCTAssertTrue(moved.isEmpty)
        XCTAssertEqual(t.dueDate, day(2))
    }

    func testCompletedUnknownAndSameDayDropsChangeNothing() throws {
        let done = try task("done", due: day(1), done: true)
        let sameDay = try task("same", due: day(3, 10, 0), time: true)
        let before = sameDay.updatedAt
        let moved = TaskRescheduling.drop(payload(done, sameDay) + ["not an id", UUID().uuidString], on: day(3),
                                          among: try allTasks(), now: now, in: context)
        XCTAssertTrue(moved.isEmpty)
        XCTAssertEqual(done.dueDate, day(1))
        XCTAssertEqual(sameDay.dueDate, day(3, 10, 0))
        XCTAssertEqual(sameDay.updatedAt, before, "a drop on its own day doesn't touch the task (no sync)")
    }

    func testOverdueColumnTakesNoDropsAndDayColumnsDo() throws {
        try task("late", due: day(-2))
        try task("soon", due: day(1))
        let entries = try allTasks().map { UpcomingView.Entry(task: $0, filterDueDate: $0.dueDate, filterIsCompleted: $0.isCompleted) }
        let board = UpcomingBoardModel(items: entries, window: UpcomingWindow(), now: now, showOverdue: true, calendar: cal)
        XCTAssertEqual(board.columns.first?.id, .overdue)
        XCTAssertFalse(board.columns[0].acceptsDrops)
        XCTAssertTrue(board.columns.dropFirst().allSatisfy(\.acceptsDrops))
    }

    // MARK: - Overdue Reschedule

    func testRescheduleMovesEveryOverdueTaskKeepingItsTime() throws {
        let a = try task("a", due: day(-1, 18, 0), time: true)
        let b = try task("b", due: day(-6))
        let later = try task("later", due: day(5))
        TaskRescheduling.reschedule([a, b], to: day(1), in: context)
        XCTAssertEqual(a.dueDate, day(1, 18, 0))
        XCTAssertEqual(b.dueDate, day(1))
        XCTAssertEqual(later.dueDate, day(5), "only the tasks passed move")
    }

    func testRescheduleSkipsCompletedTasks() throws {
        let done = try task("done", due: day(-2), done: true)
        TaskRescheduling.reschedule([done], to: day(0), in: context)
        XCTAssertEqual(done.dueDate, day(-2))
    }

    // MARK: - Add task in a column

    func testADayColumnsAddRowAddsOnThatDay() throws {
        let board = UpcomingBoardModel<PlainTask>(items: [], window: UpcomingWindow(offset: 3), now: now,
                                                  showOverdue: true, calendar: cal)
        let column = try XCTUnwrap(board.columns.first)
        XCTAssertEqual(column.addContext, .day(day(3)))
        let context = try XCTUnwrap(column.addContext)
        XCTAssertEqual(context.defaultDate(now: now, calendar: cal), day(3), "the card's date is the column's day")
        XCTAssertNil(context.defaultProjectName, "and the task goes to the Inbox unless the text names a Group")
        XCTAssertNil(context.defaultLabelName)
    }

    func testTheCardOpenedFromAColumnAddsOnItsDay() throws {
        let board = UpcomingBoardModel<PlainTask>(items: [], window: UpcomingWindow(offset: 2), now: now,
                                                  showOverdue: true, calendar: cal)
        let context = try XCTUnwrap(board.columns.last?.addContext)  // today + 8
        let parser = QuickAddParser(now: now, calendar: cal)
        let plain = QuickAddDraft(context: context, text: "Call Sam").result(parser)
        XCTAssertEqual(plain.dueDate, day(8))
        XCTAssertFalse(plain.hasDueTime, "all day")
        let timed = QuickAddDraft(context: context, text: "Call Sam 3pm").result(parser)
        XCTAssertEqual(timed.dueDate, day(8, 15, 0), "only a time typed: that time on the column's day")
        let dated = QuickAddDraft(context: context, text: "Call Sam tomorrow").result(parser)
        XCTAssertEqual(dated.dueDate, day(1), "a day typed in the card wins")
    }

    func testATimeWithOtherPhrasesStillLandsOnTheColumnsDay() throws {
        let board = UpcomingBoardModel<PlainTask>(items: [], window: UpcomingWindow(offset: 2), now: now,
                                                  showOverdue: true, calendar: cal)
        let context = try XCTUnwrap(board.columns.last?.addContext)  // today + 8
        let parser = QuickAddParser(now: now, calendar: cal)
        for text in ["Call Sam 5pm p1", "Call Sam 5pm @calls", "Call Sam 5pm !15mb"] {
            let result = QuickAddDraft(context: context, text: text).result(parser)
            XCTAssertEqual(result.dueDate, day(8, 17, 0), "\(text): a priority, label or reminder beside the time keeps the day")
        }
    }

    func testTheOverdueColumnHasNoAddRow() throws {
        let late = PlainTask(title: "late", dueDate: day(-1))
        let board = UpcomingBoardModel(items: [late], window: UpcomingWindow(), now: now, showOverdue: true, calendar: cal)
        XCTAssertEqual(board.columns.first?.id, .overdue)
        XCTAssertNil(board.columns.first?.addContext)
    }

    func testTheAddContextSurvivesTheStoredCardRoundTrip() throws {
        // An open card's list is stored with its draft (`QuickAddDraftStore`), so a day must encode.
        let data = try JSONEncoder().encode(QuickAddContext.day(day(2)))
        XCTAssertEqual(try JSONDecoder().decode(QuickAddContext.self, from: data), .day(day(2)))
    }

    // MARK: - Render check (Mac)

    #if os(macOS)
    /// Renders the board with sample tasks across Overdue and three days into a window offscreen, writes
    /// the PNG (the sandboxed test host's temporary folder; its path is printed), and checks the columns
    /// drew. The PNG is for a person to look at; no session can see the Mac's screen.
    func testBoardRendersOffscreen() throws {
        let work = Project(name: "Work", colorHex: "#5E81F4")
        let home = Project(name: "Home", colorHex: "#46A758")
        context.insert(work)
        context.insert(home)
        let samples: [(String, String, Date?, Bool, Int, Project?, RecurrenceRule?)] = [
            ("Renew passport", "Photos are in the desk drawer", day(-3), false, 1, home, nil),
            ("Send invoice #42", "", day(-1, 17, 0), true, 2, work, nil),
            ("Water the plants", "", day(0), false, 4, home, RecurrenceRule(frequency: .daily, interval: 3)),
            ("Standup", "", day(0, 9, 30), true, 3, work, RecurrenceRule.weekdays.withTime(hour: 9, minute: 30)),
            ("Write the quarterly review for the team and the board", "First draft only; numbers come Friday",
             day(0, 14, 0), true, 1, work, nil),
            ("Call Mom", "", day(1, 18, 30), true, 4, nil, nil),
            ("Dentist", "Bring the insurance card", day(3, 10, 0), true, 2, home, nil),
            ("Groceries", "Milk, eggs, coffee", day(3), false, 4, home, nil),
        ]
        for (title, notes, due, timed, priority, project, rule) in samples {
            let t = TaskItem(title: title, notes: notes, priority: priority, dueDate: due, hasDueTime: timed)
            t.project = project
            t.recurrenceRule = rule
            context.insert(t)
        }
        try context.save()

        let entries = try allTasks().map { UpcomingView.Entry(task: $0, filterDueDate: $0.dueDate, filterIsCompleted: $0.isCompleted) }
        let board = UpcomingBoardModel(items: entries, window: UpcomingWindow(), now: now, showOverdue: true, calendar: cal)
        XCTAssertEqual(board.columns.count, 8, "Overdue and seven days")

        let size = CGSize(width: 1280, height: 640)
        let root = UpcomingBoard(board: board, window: .constant(UpcomingWindow()), now: now)
            .frame(width: size.width, height: size.height)
            .environment(PopoutController())
            .modelContainer(container)
            .font(HITType.body)
            .preferredColorScheme(.dark)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        defer { window.close() }
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        host.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("upcoming-board.png")
        try png.write(to: url)
        print("UPCOMING_BOARD_PNG \(url.path)")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "upcoming-board"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Something besides the background drew in the card columns' area: count pixels that differ from
        // the top-left corner (the background) along a row through the cards.
        let background = rep.colorAt(x: 2, y: 2)
        var differing = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            if let c = rep.colorAt(x: x, y: rep.pixelsHigh / 4), c != background { differing += 1 }
        }
        XCTAssertGreaterThan(differing, 40, "the columns drew")
    }
    #endif
}
