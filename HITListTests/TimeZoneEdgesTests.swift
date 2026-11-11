import XCTest
import SwiftData
import CloudKit
import HITListCore
@testable import HITList

/// Brief 82, item 5: the same rule at the edges. The export and import JSON (an older export imports in the old form
/// and is anchored), the widgets' snapshot, Spotlight and Siri, the Claude connector's dates, the Shared Tasks store
/// (a friend abroad), and the Flipboard (a switch flipped today, a Switchboard's reset where the person is). Every zone
/// and clock is injected, except where a test says it holds in any zone the stored form serves.
@MainActor
final class TimeZoneEdgesTests: XCTestCase {
    static let chicago = TimeZoneStoreTests.chicago
    static let losAngeles = TimeZoneStoreTests.losAngeles
    static let tokyo = TimeZoneStoreTests.tokyo
    static let thursday = DayAnchor.Day(year: 2026, month: 11, day: 12)
    static let friday = DayAnchor.Day(year: 2026, month: 11, day: 13)

    private var container: ModelContainer!
    private var context: ModelContext!
    private var hook: DayAnchoring.SaveHook?
    private var zone = TimeZoneEdgesTests.chicago

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
        hook = DayAnchoring.SaveHook(container: container, calendar: { [unowned self] in self.zone })
    }

    override func tearDown() async throws {
        hook?.stop()
        hook = nil
        container = nil
        context = nil
    }

    private func local(_ d: Int, _ h: Int = 0, _ m: Int = 0, in zone: Calendar) -> Date {
        TimeZoneStoreTests.local(2026, 11, d, h, m, in: zone)
    }

    private func midnight(_ day: DayAnchor.Day, in zone: Calendar) -> Date { DayAnchor.start(of: day, calendar: zone) }

    private func day(_ date: Date?, in zone: Calendar) -> DayAnchor.Day? { date.map { DayAnchor.localDay(of: $0, calendar: zone) } }

    /// Runs `body` with the process's zone set to `zone` (`Calendar.current` follows it), for the code that reads the
    /// device's calendar itself (the Shared Tasks store); restored after, so the test means the same on any Mac and on CI.
    private func inZone(_ zone: Calendar, _ body: () throws -> Void) rethrows {
        let saved = NSTimeZone.default
        NSTimeZone.default = zone.timeZone
        defer { NSTimeZone.default = saved }
        try body()
    }

    // MARK: - JSON

    /// An export from a build before 0.9.3, written in Chicago (its days are Chicago's midnights), imported on a device
    /// in Tokyo: kept as they came (brief 92: Tokyo can't vouch for Chicago's midnights; they show there as Thursday and
    /// Friday afternoons, their days). Back home in Chicago the pass anchors them. An export from this build carries
    /// 10:00 UTC for a day, which an older build imports as that day.
    func testAnOlderExportImportsWithItsDaysAnchored() throws {
        let older = ModelContainerFactory.preview()
        let task = TaskItem(title: "Call Sam", dueDate: midnight(Self.thursday, in: Self.chicago))
        task.deadline = midnight(Self.friday, in: Self.chicago)
        let timed = TaskItem(title: "Dentist", dueDate: local(12, 9, in: Self.chicago), hasDueTime: true)
        older.mainContext.insert(task)
        older.mainContext.insert(timed)
        try older.mainContext.save()
        let json = try SnapshotBuilder.build(from: older.mainContext).jsonData()

        zone = Self.tokyo
        _ = try SnapshotBuilder.restore(try Snapshot.from(json: json), into: context)
        try context.save()
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let imported = try XCTUnwrap(tasks.first { $0.title == "Call Sam" })
        XCTAssertEqual(imported.dueDate, midnight(Self.thursday, in: Self.chicago), "kept as it came in Tokyo")
        XCTAssertEqual(day(imported.dueDate, in: Self.tokyo), Self.thursday)
        let suite = "TimeZoneEdgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(DayAnchoring.firstRunVersion, forKey: DayAnchoring.firstRunKey())
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.chicago, defaults: defaults, syncLog: { _, _, _ in }),
                       DayAnchoring.Count(dueDates: 1, deadlines: 1))
        XCTAssertEqual(imported.dueDate, DayAnchor.anchor(of: Self.thursday))
        XCTAssertEqual(imported.deadline, DayAnchor.anchor(of: Self.friday))
        XCTAssertEqual(tasks.first { $0.title == "Dentist" }?.dueDate, local(12, 9, in: Self.chicago))

        let export = String(decoding: try SnapshotBuilder.build(from: context).jsonData(), as: UTF8.self)
        XCTAssertTrue(export.contains("\"dueDate\" : \"2026-11-12T10:00:00Z\""), export)
        XCTAssertTrue(export.contains("\"deadline\" : \"2026-11-13T10:00:00Z\""), export)
    }

    // MARK: - Widgets

    /// The widgets' snapshot carries the anchor, and the widget's Today (core's rules) shows the day's date-only task on
    /// that day, before its timed one, in Tokyo where the anchor is 19:00.
    func testTheWidgetsSnapshotShowsADayOnItsDayAndFirst() throws {
        zone = Self.tokyo
        let allDay = TaskItem(title: "All day", dueDate: midnight(Self.thursday, in: Self.tokyo))
        let nine = TaskItem(title: "Nine", dueDate: local(12, 9, in: Self.tokyo), hasDueTime: true)
        context.insert(nine)
        context.insert(allDay)
        try context.save()
        let snapshot = try WidgetSnapshotBuilder.build(from: context, shared: [], themeID: "slate", weekStart: 1,
                                                       now: local(12, 8, in: Self.tokyo))
        XCTAssertEqual(snapshot.tasks.first { $0.title == "All day" }?.due, DayAnchor.anchor(of: Self.thursday))
        let today = WidgetContent.today(snapshot, at: local(12, 8, in: Self.tokyo), calendar: Self.tokyo)
        XCTAssertEqual(today.today.map(\.title), ["All day", "Nine"])
        let wednesday = WidgetContent.today(snapshot, at: local(11, 23, in: Self.tokyo), calendar: Self.tokyo)
        XCTAssertTrue(wednesday.isEmpty)
    }

    // MARK: - Siri and Spotlight

    /// Shortcuts' "Due" is a day's start where you are, never 10:00 UTC shown as a time; a timed task's is its moment.
    /// Spotlight's line names the day (holds in every zone from Honolulu to Chatham, this Mac's included).
    func testSiriAndSpotlightShowTheDay() throws {
        zone = Self.chicago
        let task = TaskItem(title: "Call Sam", dueDate: midnight(Self.thursday, in: Self.chicago))
        let timed = TaskItem(title: "Dentist", dueDate: local(12, 9, in: Self.chicago), hasDueTime: true)
        context.insert(task)
        context.insert(timed)
        try context.save()
        XCTAssertEqual(task.dueDate, DayAnchor.anchor(of: Self.thursday))
        for zone in [Self.chicago, Self.losAngeles, Self.tokyo] {
            XCTAssertEqual(TaskEntity.shownDue(task, calendar: zone), midnight(Self.thursday, in: zone), zone.timeZone.identifier)
            XCTAssertEqual(TaskEntity.shownDue(timed, calendar: zone), local(12, 9, in: Self.chicago))
        }
        let entity = TaskEntity(spotlight: task)
        XCTAssertEqual(entity.dueDate, Calendar.current.startOfDay(for: DayAnchor.anchor(of: Self.thursday)))
        XCTAssertEqual(DayAnchor.localDay(of: try XCTUnwrap(entity.dueDate), calendar: .current), Self.thursday)
        XCTAssertTrue(entity.detail?.contains("12") ?? false, entity.detail ?? "")
    }

    // MARK: - Claude

    /// The Claude connector's tools name a day as "2026-11-12" wherever the Mac is, and a time with its offset.
    func testClaudesToolsNameTheDayInEveryZone() throws {
        zone = Self.chicago
        let task = TaskItem(title: "Call Sam", dueDate: midnight(Self.thursday, in: Self.chicago))
        let timed = TaskItem(title: "Dentist", dueDate: local(12, 9, in: Self.chicago), hasDueTime: true)
        context.insert(task)
        context.insert(timed)
        try context.save()
        for zone in [Self.losAngeles, Self.chicago, Self.tokyo, TimeZoneStoreTests.honolulu, TimeZoneStoreTests.auckland] {
            var handler = ClaudeToolHandler(context: context, rule: ClaudeAccessRule(mode: .allExceptHidden))
            handler.calendar = zone
            XCTAssertEqual(handler.dueJSON(task), .string("2026-11-12"), zone.timeZone.identifier)
        }
        var inLA = ClaudeToolHandler(context: context, rule: ClaudeAccessRule(mode: .allExceptHidden))
        inLA.calendar = Self.losAngeles
        XCTAssertEqual(inLA.dueJSON(timed), .string("2026-11-12T07:00:00-08:00"))
        XCTAssertTrue(ClaudeExport.schemaNote.contains("the same day wherever I am"))
    }

    // MARK: - Shared Tasks

    /// A day written here in Chicago is stored as its anchor, and the same day arriving in its old form (Chicago's midnight)
    /// is the same value, so a merge writes nothing back. A friend's Friday written in Tokyo by a build before 0.9.3 (Tokyo's
    /// midnight, Thursday 09:00 here) is kept as it came (brief 92: Chicago can't vouch for Tokyo's midnights): Chicago shows
    /// it as 0.9.2 did, a merge with our copy writes nothing to their record, and the friend's own device in Tokyo anchors it
    /// as Friday, which then reads as Friday here too.
    func testAFriendsDayFromTokyoIsThursdayInChicagoAndNeverRewrittenOnTheirRecord() throws {
        try inZone(Self.chicago) {
            let store = SharedTasksStore(persistence: .memory, clock: { [unowned self] in self.local(11, 12, in: Self.chicago) })
            store.setMe("_me000000000000000000000000000000")
            let list = try store.createList(title: "Groceries")
            let mine = try store.addTask(to: list.id, title: "Oat milk", due: SharedDue(date: midnight(Self.thursday, in: Self.chicago), hasTime: false))
            XCTAssertEqual(mine.due.value?.date, DayAnchor.anchor(of: Self.thursday), "a day written here is stored as its anchor")

            let shared = try XCTUnwrap(store.list(list.id))

            // The same day in the old form at the same stamp (a build before 0.9.3 saved the record): the two forms of one
            // day are one value, so the merge writes nothing back to the record.
            var same = mine
            same.due = Stamped(SharedDue(date: midnight(Self.thursday, in: Self.chicago), hasTime: false), at: mine.due.changedAt)
            let sameFetched = try XCTUnwrap(SharedTasksRecords.task(from: SharedTasksRecords.taskRecord(same, in: shared)))
            XCTAssertEqual(sameFetched.due.value?.date, DayAnchor.anchor(of: Self.thursday))
            XCTAssertFalse(store.applyServerTask(sameFetched, listID: list.id, scope: list.scope, ownerName: list.ownerName),
                           "nothing to write to a record only because a day came in its old form")

            // The friend's later change: a build before 0.9.3 in Tokyo set Friday (Tokyo's midnight, Thursday 09:00 here).
            var theirs = mine
            let tokyoFriday = midnight(Self.friday, in: Self.tokyo)
            theirs.due = Stamped(SharedDue(date: tokyoFriday, hasTime: false), at: local(11, 13, in: Self.chicago))
            let fetched = try XCTUnwrap(SharedTasksRecords.task(from: SharedTasksRecords.taskRecord(theirs, in: shared)))
            XCTAssertEqual(fetched.due.value?.date, tokyoFriday, "kept exactly as it came")
            XCTAssertEqual(day(fetched.due.value?.date, in: Self.chicago), Self.thursday, "as 0.9.2 showed it here")
            XCTAssertEqual(day(fetched.due.value?.date, in: Self.tokyo), Self.friday)
            XCTAssertFalse(store.applyServerTask(fetched, listID: list.id, scope: list.scope, ownerName: list.ownerName),
                           "the merged copy is the server's: nothing to write to the friend's record")
            XCTAssertEqual(store.list(list.id)?.tasks.first?.due.value?.date, tokyoFriday)

            // Their device, in Tokyo, vouches for its own midnight: Friday's anchor, Friday here too.
            let atHome = SharedTasksStore.normalized(SharedDue(date: tokyoFriday, hasTime: false), calendar: Self.tokyo)
            XCTAssertEqual(atHome.date, DayAnchor.anchor(of: Self.friday))
            for zone in [Self.chicago, Self.losAngeles, Self.tokyo] {
                XCTAssertEqual(day(atHome.date, in: zone), Self.friday, zone.timeZone.identifier)
            }

            // A timed shared task is a moment, kept to the millisecond.
            let moment = local(12, 9, in: Self.chicago).addingTimeInterval(0.0004)
            XCTAssertEqual(SharedTasksStore.normalized(SharedDue(date: moment, hasTime: true)).date, SharedClock.stamp(moment))
        }
    }

    /// The shared lists' file a build before 0.9.3 saved in Tokyo, reopened there: its days come back anchored, their
    /// stamps unchanged.
    func testTheSharedListsFileFromAnOlderBuildLoadsAnchored() throws {
        try inZone(Self.tokyo) { try sharedListsFileFromAnOlderBuildLoadsAnchored() }
    }

    private func sharedListsFileFromAnOlderBuildLoadsAnchored() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TimeZoneEdges-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "SharedTasks-test.json")
        let stamp = local(11, 12, in: Self.chicago)
        let older = SharedTasksStore(persistence: .memory, clock: { stamp })
        older.setMe("_me000000000000000000000000000000")
        let list = try older.createList(title: "Groceries")
        _ = try older.addTask(to: list.id, title: "Oat milk")
        var state = SharedTasksState()
        state.lists = [try XCTUnwrap(older.list(list.id))]
        state.lists[0].tasks[0].due = Stamped(SharedDue(date: midnight(Self.thursday, in: Self.tokyo), hasTime: false), at: stamp)
        try JSONEncoder().encode(state).write(to: url)

        let reopened = SharedTasksStore(persistence: .file(url))
        let task = try XCTUnwrap(reopened.list(list.id)?.tasks.first)
        XCTAssertEqual(task.due.value?.date, DayAnchor.anchor(of: Self.thursday))
        XCTAssertEqual(SharedClock.millis(task.due.changedAt), SharedClock.millis(stamp))
    }

    // MARK: - The Flipboard

    /// A loose switch flipped on Wednesday evening in Chicago is still done (green) for the rest of that Wednesday
    /// wherever the person is, and red from Thursday's start there.
    func testALooseSwitchFlippedTodayIsStillFlippedAfterAFlight() throws {
        zone = Self.chicago
        let clock = Flipboard.Clock(rule: .daily)
        let flippedAt = local(11, 19, in: Self.chicago)
        let (charge, _) = Flipboard.afterFlip(Flipboard.Charge(due: midnight(DayAnchor.Day(year: 2026, month: 11, day: 11), in: Self.chicago),
                                                               count: 0, periodStart: nil),
                                              target: 1, clock: clock, now: flippedAt, calendar: Self.chicago)
        let task = TaskItem(title: "Water plants", dueDate: charge.due)
        context.insert(task)
        try context.save()
        XCTAssertEqual(task.dueDate, DayAnchor.anchor(of: Self.thursday))
        XCTAssertEqual(clock.side(task.dueDate, now: local(11, 20, in: Self.losAngeles), calendar: Self.losAngeles), .green)
        XCTAssertEqual(clock.side(task.dueDate, now: local(11, 23, 59, in: Self.losAngeles), calendar: Self.losAngeles), .green)
        XCTAssertEqual(clock.side(task.dueDate, now: local(12, 0, 0, in: Self.losAngeles), calendar: Self.losAngeles), .red)
        // The flip's own instant is Thursday 10:00 in Tokyo: Thursday's turn has come there (the travel skipped the night).
        XCTAssertEqual(clock.side(task.dueDate, now: flippedAt.addingTimeInterval(60), calendar: Self.tokyo), .red)
        XCTAssertEqual(clock.side(task.dueDate, now: local(11, 23, 59, in: Self.tokyo), calendar: Self.tokyo), .green)
    }

    /// A Switchboard resetting at 04:00, flown west: done at 05:00 Thursday in Chicago, it stays done through 04:00
    /// Thursday in Los Angeles (no second reset that day) and is due again at 04:00 Friday there, once.
    func testASwitchboardNeverResetsTwiceInADayFlyingWest() throws {
        zone = Self.chicago
        let board = SwitchboardSchedule(cadence: .daily, resetMinutes: 4 * 60)
        let clock = Flipboard.Clock(rule: .daily, board: board)
        let doneAt = local(12, 5, in: Self.chicago)
        let (charge, _) = Flipboard.afterFlip(Flipboard.Charge(due: midnight(Self.thursday, in: Self.chicago), count: 0, periodStart: nil),
                                              target: 1, clock: clock, now: doneAt, calendar: Self.chicago)
        let task = TaskItem(title: "Stretch", dueDate: charge.due)
        context.insert(task)
        try context.save()
        XCTAssertEqual(task.dueDate, DayAnchor.anchor(of: Self.friday))
        let la = Self.losAngeles
        XCTAssertEqual(clock.side(task.dueDate, now: local(12, 4, 0, in: la), calendar: la), .green, "Thursday's reset in LA came after the flip")
        XCTAssertEqual(clock.side(task.dueDate, now: local(12, 22, in: la), calendar: la), .green)
        XCTAssertEqual(clock.side(task.dueDate, now: local(13, 3, 59, in: la), calendar: la), .green)
        XCTAssertEqual(clock.side(task.dueDate, now: local(13, 4, 0, in: la), calendar: la), .red, "due again at Friday's 04:00 there")
    }

    /// Flown east: done on Wednesday evening in Chicago, the same instant is Thursday 11:00 in Tokyo, past Thursday's
    /// reset there, so Thursday's routine is due (the travel skipped Wednesday night, nothing more); flipped there, it
    /// is done until Friday's 04:00 in Tokyo.
    func testASwitchboardSkipsNoMoreThanTheTravelFlyingEast() throws {
        zone = Self.chicago
        let board = SwitchboardSchedule(cadence: .daily, resetMinutes: 4 * 60)
        let clock = Flipboard.Clock(rule: .daily, board: board)
        let doneAt = local(11, 20, in: Self.chicago)
        let (charge, _) = Flipboard.afterFlip(Flipboard.Charge(due: midnight(DayAnchor.Day(year: 2026, month: 11, day: 11), in: Self.chicago),
                                                               count: 0, periodStart: nil),
                                              target: 1, clock: clock, now: doneAt, calendar: Self.chicago)
        let task = TaskItem(title: "Stretch", dueDate: charge.due)
        context.insert(task)
        try context.save()
        XCTAssertEqual(task.dueDate, DayAnchor.anchor(of: Self.thursday))
        let tokyo = Self.tokyo
        XCTAssertEqual(tokyo.dateComponents([.day, .hour], from: doneAt), DateComponents(day: 12, hour: 11))
        XCTAssertEqual(clock.side(task.dueDate, now: doneAt.addingTimeInterval(60), calendar: tokyo), .red)

        zone = tokyo
        let flipAgain = doneAt.addingTimeInterval(3600)
        let (next, _) = Flipboard.afterFlip(Flipboard.Charge(due: task.dueDate, count: 0, periodStart: nil), target: 1,
                                            clock: clock, now: flipAgain, calendar: tokyo)
        task.dueDate = next.due
        try context.save()
        XCTAssertEqual(task.dueDate, DayAnchor.anchor(of: Self.friday))
        XCTAssertEqual(clock.side(task.dueDate, now: local(13, 3, 59, in: tokyo), calendar: tokyo), .green)
        XCTAssertEqual(clock.side(task.dueDate, now: local(13, 4, 0, in: tokyo), calendar: tokyo), .red)
    }
}
