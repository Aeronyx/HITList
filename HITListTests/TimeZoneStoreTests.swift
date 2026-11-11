import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 82, item 1: the store written in one time zone and read in another, field by field. Tasks are written the way
/// the app's writers do in the writer's zone (quick add's parser, the editor's start of day, a completion), saved into
/// an in-memory store through the app's one place (`DayAnchoring.SaveHook`, in the writer's zone), fetched back in a
/// fresh context, and read with core's rules in the reader's zone. Every clock is injected: nothing here reads the
/// wall clock or this Mac's zone.
@MainActor
final class TimeZoneStoreTests: XCTestCase {
    private var container: ModelContainer!
    /// The app's one place (brief 82): every save anchors its days, read in the zone the device writing is in.
    private var hook: DayAnchoring.SaveHook?
    private var writerZone = TimeZoneStoreTests.chicago

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        hook = DayAnchoring.SaveHook(container: container, calendar: { [unowned self] in self.writerZone })
    }

    override func tearDown() async throws {
        hook?.stop()
        hook = nil
        container = nil
    }

    static func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        c.firstWeekday = 1
        return c
    }

    static let chicago = calendar("America/Chicago")
    static let losAngeles = calendar("America/Los_Angeles")
    static let tokyo = calendar("Asia/Tokyo")
    static let honolulu = calendar("Pacific/Honolulu")
    static let auckland = calendar("Pacific/Auckland")

    static func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func day(of date: Date?, in calendar: Calendar) -> [Int]? {
        guard let date else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return [parts.year!, parts.month!, parts.day!]
    }

    /// Writes one task the way quick add does in `zone` on Wednesday 2026-11-11 at noon there, saves, and returns its id.
    private func write(_ text: String, deadlineDay: Int? = nil, in zone: Calendar) throws -> UUID {
        let context = container.mainContext
        writerZone = zone
        let now = Self.local(2026, 11, 11, 12, in: zone)
        let parsed = QuickAddParser(now: now, calendar: zone).parse(text)
        let task = TaskItem(title: parsed.title, dueDate: parsed.dueDate, hasDueTime: parsed.hasDueTime,
                            recurrence: parsed.recurrence)
        task.reminderDate = parsed.reminderDate
        // The editor's deadline picker: the picked day's start (`TaskPopout.setDeadline`).
        if let deadlineDay { task.deadline = zone.startOfDay(for: Self.local(2026, 11, deadlineDay, 12, in: zone)) }
        context.insert(task)
        try context.save()
        return task.id
    }

    /// The task as the store keeps it, fetched in a context of its own.
    private func read(_ id: UUID) throws -> TaskItem {
        let context = ModelContext(container)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id }))
        return try XCTUnwrap(tasks.first)
    }

    // MARK: - A day is a day: these failed before brief 82

    /// The due date with no time (`dueDate`, `hasDueTime` false): typed "thu" in Chicago, it is Thursday in Los Angeles,
    /// Tokyo, Honolulu and Auckland: on Today on Thursday there, never Wednesday's.
    func testADueDayWrittenInChicagoIsThursdayInEveryZone() throws {
        let id = try write("Call Sam thu", in: Self.chicago)
        let task = try read(id)
        XCTAssertFalse(task.hasDueTime)
        for zone in [Self.chicago, Self.losAngeles, Self.honolulu, Self.tokyo, Self.auckland] {
            let pair = "Chicago → \(zone.timeZone.identifier)"
            XCTAssertEqual(Self.day(of: task.dueDate, in: zone), [2026, 11, 12], pair)
            let thursday = Self.local(2026, 11, 12, 12, in: zone)
            XCTAssertEqual(TaskOrdering.today([task], now: thursday, calendar: zone).today.map(\.id), [id], pair)
            let wednesday = Self.local(2026, 11, 11, 20, in: zone)
            XCTAssertTrue(TaskOrdering.today([task], now: wednesday, calendar: zone).isEmpty, pair)
        }
    }

    /// The same, written in Tokyo and read in Chicago (a shared device, or a friend's list): Thursday, not Wednesday.
    func testADueDayWrittenInTokyoIsThursdayInChicago() throws {
        let id = try write("Call Sam thu", in: Self.tokyo)
        XCTAssertEqual(Self.day(of: try read(id).dueDate, in: Self.chicago), [2026, 11, 12])
    }

    /// The deadline (always a day): picked as Friday in Chicago, Friday everywhere.
    func testADeadlineWrittenInChicagoIsFridayInEveryZone() throws {
        let id = try write("Report", deadlineDay: 13, in: Self.chicago)
        let task = try read(id)
        for zone in [Self.losAngeles, Self.honolulu, Self.tokyo, Self.auckland] {
            XCTAssertEqual(Self.day(of: task.deadline, in: zone), [2026, 11, 13], zone.timeZone.identifier)
        }
    }

    // MARK: - A time is a moment: pins that hold before and after brief 82

    /// The due date with a time is an instant: 09:00 written in Chicago is 07:00 in Los Angeles and 00:00 Friday in Tokyo.
    func testATimedDueDateKeepsItsMoment() throws {
        let id = try write("Call Sam thu 9am", in: Self.chicago)
        let task = try read(id)
        XCTAssertTrue(task.hasDueTime)
        XCTAssertEqual(task.dueDate, Self.local(2026, 11, 12, 9, in: Self.chicago))
        XCTAssertEqual(Self.losAngeles.dateComponents([.day, .hour], from: task.dueDate!), DateComponents(day: 12, hour: 7))
        XCTAssertEqual(Self.tokyo.dateComponents([.day, .hour], from: task.dueDate!), DateComponents(day: 13, hour: 0))
    }

    /// The reminder moment ("!15m", `reminderDate`) is an instant, whatever the zone.
    func testAReminderMomentKeepsItsInstant() throws {
        let id = try write("Call Sam !15m", in: Self.chicago)
        let task = try read(id)
        XCTAssertEqual(task.reminderDate, Self.local(2026, 11, 11, 12, 15, in: Self.chicago))
    }

    /// Completion, creation and the Flipboard's interval start are instants: stored as they were set.
    func testCompletionCreationAndAFlipsIntervalStartAreInstants() throws {
        let context = container.mainContext
        let moment = Self.local(2026, 11, 11, 23, 30, in: Self.chicago)
        let task = TaskItem(title: "Water plants")
        task.createdAt = moment
        task.completedAt = moment
        task.isCompleted = true
        task.flipPeriodStart = moment
        context.insert(task)
        try context.save()
        let stored = try read(task.id)
        XCTAssertEqual(stored.createdAt, moment)
        XCTAssertEqual(stored.completedAt, moment)
        XCTAssertEqual(stored.flipPeriodStart, moment)
    }
}
