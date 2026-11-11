import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 92: brief 82's day anchor attacked in the app, before the first-run pass rewrites real data: the passes against
/// values no device can vouch for, older builds and other zones; the one place against every writer; the first-run pass
/// against a failing backup, a kill and a big store. The task store is in memory unless a test says otherwise, the save
/// hook watches only this test's container, and the process's zone is New York for every test (`NSTimeZone.default`,
/// which `Calendar.current` follows; restored after), so each means the same on this Mac and on CI.
@MainActor
final class DayAnchorReviewStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var hook: DayAnchoring.SaveHook?
    private var hookZone = DayAnchorReviewStoreTests.newYork
    private var savedZone: TimeZone!
    private var defaults: UserDefaults!
    private var suiteName = ""

    static let newYork = TimeZoneStoreTests.calendar("America/New_York")
    static let chicago = TimeZoneStoreTests.chicago
    static let losAngeles = TimeZoneStoreTests.losAngeles
    static let tokyo = TimeZoneStoreTests.tokyo

    override func setUp() async throws {
        savedZone = NSTimeZone.default
        NSTimeZone.default = Self.newYork.timeZone
        container = ModelContainerFactory.preview()
        context = container.mainContext
        suiteName = "DayAnchorReviewStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        hook?.stop()
        hook = nil
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        context = nil
        NSTimeZone.default = savedZone
    }

    static func day(_ y: Int, _ m: Int, _ d: Int) -> DayAnchor.Day { DayAnchor.Day(year: y, month: m, day: d) }

    static func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Starts the app's one place, reading old values in `zone` (the zone the saving device is in).
    private func watch(in zone: Calendar) {
        hookZone = zone
        if hook == nil { hook = DayAnchoring.SaveHook(container: container, calendar: { [unowned self] in self.hookZone }) }
    }

    /// The task as the store keeps it, fetched in a context of its own.
    private func stored(_ id: UUID) throws -> TaskItem {
        let fresh = ModelContext(container)
        return try XCTUnwrap(try fresh.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
    }

    /// Inserts a task with these values and saves it with no hook watching: what an older build left in the store, or
    /// what an import brought.
    private func olderBuildTask(_ title: String, due: Date?, hasTime: Bool = false, deadline: Date? = nil,
                                recurrence: RecurrenceRule? = nil) throws -> TaskItem {
        let wasWatching = hook
        hook?.stop()
        hook = nil
        let task = TaskItem(title: title, dueDate: due, hasDueTime: hasTime, recurrence: recurrence)
        task.deadline = deadline
        context.insert(task)
        try context.save()
        if wasWatching != nil { watch(in: hookZone) }
        return task
    }

    private func shown(_ date: Date?, in zone: Calendar = newYork) -> DayAnchor.Day? {
        date.map { DayAnchor.localDay(of: $0, calendar: zone) }
    }

    /// The import pass on a store whose first-run pass has run (marked in this test's own defaults, never the app group's).
    private func importPass(calendar: Calendar, syncLog: ProfileStore.Log) -> DayAnchoring.Count? {
        defaults.set(DayAnchoring.firstRunVersion, forKey: DayAnchoring.firstRunKey())
        return DayAnchoring.importPass(in: context, calendar: calendar, defaults: defaults, syncLog: syncLog)
    }

    /// The stored bits of a date: "byte for byte" means these are equal.
    private func bits(_ date: Date?) -> UInt64? { date?.timeIntervalSinceReferenceDate.bitPattern }

    // MARK: - Never rewritten on a guess (the supervisor's finding)

    /// Values a device in Chicago can't vouch for: Thursday 09:00 there (15:00 UTC, which is also Tokyo's Friday midnight),
    /// Thursday's UTC midnight (Wednesday 18:00 there) from a tool or an import, Kolkata's Friday midnight, an anchor a
    /// 0.9.2 device carried across the autumn change (11:00 UTC), and a stray moment with seconds; and a deadline at
    /// Tokyo's midnight. Saved for another reason, passed over after an import and by the first-run pass: every one is
    /// kept byte for byte and counted by why; Chicago's own midnight beside them is anchored. The first-run pass, with
    /// nothing it can anchor, takes no backup and says what it left.
    func testAStrayValueSurvivesEveryPassByteForByte() throws {
        let strays: [(String, Date)] = [
            ("Chicago's Thursday 09:00", Self.utc("2026-11-12T15:00:00Z")),
            ("Thursday's UTC midnight", Self.utc("2026-11-12T00:00:00Z")),
            ("Kolkata's Friday midnight", Self.utc("2026-11-12T18:30:00Z")),
            ("an anchor carried across the change", Self.utc("2026-11-11T11:00:00Z")),
            ("a stray moment", Self.utc("2026-11-12T15:07:13Z").addingTimeInterval(0.25)),
        ]
        var tasks: [(String, TaskItem, UInt64?)] = []
        for (name, value) in strays {
            let task = try olderBuildTask(name, due: value)
            tasks.append((name, task, bits(value)))
        }
        let tokyosMidnight = DayAnchor.start(of: Self.day(2026, 11, 13), calendar: Self.tokyo)
        let withDeadline = try olderBuildTask("Deadline at Tokyo's midnight", due: nil, deadline: tokyosMidnight)

        func assertKept(_ when: String) throws {
            for (name, task, original) in tasks {
                XCTAssertEqual(bits(try stored(task.id).dueDate), original, "\(name), \(when)")
            }
            XCTAssertEqual(bits(try stored(withDeadline.id).deadline), bits(tokyosMidnight), "the deadline, \(when)")
        }

        // The first-run pass: nothing it can vouch for, so no backup and nothing written; one line says what it left.
        var backedUp = false
        var lines: [(String, [String: String])] = []
        let outcome = DayAnchoring.firstRunPass(context: context, defaults: defaults, key: "review.firstRun", calendar: Self.chicago,
                                                backUp: { _ in backedUp = true; return nil }, syncLog: { lines.append(($0, $2)) })
        XCTAssertEqual(outcome, .nothingToDo)
        XCTAssertFalse(backedUp)
        XCTAssertEqual(lines.map(\.0), ["Days on the first run of this build: none to anchor here; 6 left as they were (5 not a midnight here, 1 a moment rather than a midnight)"])
        XCTAssertEqual(lines.first?.1["leftNotAMidnightHere"], "5")
        XCTAssertEqual(lines.first?.1["leftAMoment"], "1")
        try assertKept("after the first-run pass")

        // The import pass, with Chicago's own midnight beside them: that one is anchored, the rest kept and counted.
        let thursday = Self.day(2026, 11, 12)
        let own = try olderBuildTask("Chicago's Thursday", due: DayAnchor.start(of: thursday, calendar: Self.chicago))
        let count = try XCTUnwrap(importPass(calendar: Self.chicago, syncLog: { lines.append(($0, $2)) }))
        XCTAssertEqual(count, DayAnchoring.Count(dueDates: 1, leftAlone: .init(notThisZonesMidnight: 5, notAMidnight: 1)))
        XCTAssertEqual(try stored(own.id).dueDate, DayAnchor.anchor(of: thursday))
        try assertKept("after the import pass")

        // The one place: each saved again for another reason, in Chicago.
        watch(in: Self.chicago)
        for (name, task, _) in tasks { task.notes = "edited: \(name)" }
        withDeadline.notes = "edited"
        try context.save()
        try assertKept("after a save")
        XCTAssertEqual(shown(try stored(tasks[0].1.id).dueDate, in: Self.chicago), thursday, "Thursday 09:00 still shows Thursday")
    }

    /// Brief 82's worry, the other way round: a phone that flew to Los Angeles before it updated finds Chicago's midnights,
    /// which it shows as the evening before (as 0.9.2 did there). It can't vouch for them, so its first-run pass and its
    /// import pass keep them byte for byte; the Mac at home in Chicago anchors them, and then the phone shows Thursday.
    func testAPhoneThatFlewWestBeforeItUpdatedLeavesHomesDaysForHome() throws {
        let thursday = Self.day(2026, 11, 12)
        let fromHome = DayAnchor.start(of: thursday, calendar: Self.chicago)
        let task = try olderBuildTask("Call Sam", due: fromHome)
        XCTAssertEqual(shown(fromHome, in: Self.losAngeles), Self.day(2026, 11, 11), "Wednesday 22:00 in Los Angeles")

        var backedUp = false
        let outcome = DayAnchoring.firstRunPass(context: context, defaults: defaults, key: "review.firstRun", calendar: Self.losAngeles,
                                                backUp: { _ in backedUp = true; return nil }, syncLog: { _, _, _ in })
        XCTAssertEqual(outcome, .nothingToDo)
        XCTAssertFalse(backedUp)
        XCTAssertEqual(importPass(calendar: Self.losAngeles, syncLog: { _, _, _ in }),
                       DayAnchoring.Count(leftAlone: .init(notThisZonesMidnight: 1)))
        XCTAssertEqual(bits(try stored(task.id).dueDate), bits(fromHome))

        // Home anchors it; the anchor syncs to the phone, which shows Thursday.
        XCTAssertEqual(importPass(calendar: Self.chicago, syncLog: { _, _, _ in }),
                       DayAnchoring.Count(dueDates: 1))
        XCTAssertEqual(shown(try stored(task.id).dueDate, in: Self.losAngeles), thursday)
    }

    /// A device still on 0.9.2 completed a daily repeat 0.9.3 had anchored on Oct 30: its roll-over stepped the anchor's
    /// own 06:00 EDT to Nov 11 at 06:00 EST, 11:00 UTC, and synced it. 0.9.3's import pass in New York keeps it, so both
    /// devices show Nov 11; before brief 92 it read 11:00 UTC as UTC+13's Nov 12 midnight and stored Nov 12.
    func testAnOlderBuildsRollOfAnAnchoredRepeatKeepsItsDayThroughTheImportPass() throws {
        let rolled = Self.newYork.date(byAdding: .day, value: 12, to: DayAnchor.anchor(of: Self.day(2026, 10, 30)))!
        XCTAssertEqual(rolled, Self.utc("2026-11-11T11:00:00Z"))
        let task = try olderBuildTask("Stretch", due: rolled, recurrence: .daily)
        XCTAssertEqual(importPass(calendar: Self.newYork, syncLog: { _, _, _ in }),
                       DayAnchoring.Count(leftAlone: .init(notThisZonesMidnight: 1)))
        XCTAssertEqual(bits(try stored(task.id).dueDate), bits(rolled))
        XCTAssertEqual(shown(try stored(task.id).dueDate), Self.day(2026, 11, 11))
    }

    // MARK: - The one place: repeats rolling on

    /// The rules brief 92 names, each completed in New York at noon on Nov 11, 2026 from an anchor before the autumn change
    /// (Nov 1). The next day is the rule's, stored as that day's anchor. `RecurrenceRule` steps a date keeping its time of
    /// day, and an anchor's is 06:00 EDT: stepped past Nov 1 it is 06:00 EST, 11:00 UTC, which the one place can't vouch
    /// for, so it stayed unanchored (and before brief 92's first finding, was stored a day late).
    static let rollCases: [(String, RecurrenceRule, DayAnchor.Day, DayAnchor.Day)] = [
        ("every day", .daily, day(2026, 10, 30), day(2026, 11, 11)),
        ("every week", .weekly, day(2026, 10, 28), day(2026, 11, 11)),
        ("every Wednesday", RecurrenceRule(frequency: .weekly, weekdays: [4]), day(2026, 10, 28), day(2026, 11, 11)),
        ("every weekday", .weekdays, day(2026, 10, 30), day(2026, 11, 11)),
        ("every month on the 15th", RecurrenceRule(frequency: .monthly, anchorDay: 15), day(2026, 10, 15), day(2026, 11, 15)),
        ("every month from the 31st", RecurrenceRule(frequency: .monthly, anchorDay: 31), day(2026, 10, 31), day(2026, 11, 30)),
        ("every first Monday", RecurrenceRule(frequency: .monthly, place: .weekday(2, ordinal: 1)), day(2026, 10, 5),
         day(2026, 12, 7)),
        ("every year on Feb 29", RecurrenceRule(frequency: .yearly, anchorDay: 29, place: .date(month: 2, day: 29)),
         day(2024, 2, 29), day(2027, 2, 28)),
    ]

    func testCompletingARepeatAcrossTheAutumnChangeStoresTheNextDaysAnchor() throws {
        watch(in: Self.newYork)
        let noon = TimeZoneStoreTests.local(2026, 11, 11, 12, in: Self.newYork)
        for (name, rule, from, expected) in Self.rollCases {
            let task = TaskItem(title: name, dueDate: DayAnchor.anchor(of: from), recurrence: rule)
            context.insert(task)
            try context.save()
            TaskActions.toggleCompletion(task, in: context, now: noon)
            let kept = try stored(task.id)
            XCTAssertFalse(kept.isCompleted, name)
            XCTAssertEqual(shown(kept.dueDate), expected, "\(name): the rule's day")
            XCTAssertEqual(kept.dueDate, DayAnchor.anchor(of: expected), "\(name): stored as that day's anchor")
        }
    }

    /// A monthly repeat on the 15th, completed twice across the change, keeps the 15th (its rule's day of the month never
    /// moves), and a timed daily repeat keeps its 09:00 where the person is, untouched by the one place.
    func testARepeatKeepsItsDayOfTheMonthAndATimedOneItsHour() throws {
        watch(in: Self.newYork)
        let monthly = TaskItem(title: "Rent", dueDate: DayAnchor.anchor(of: Self.day(2026, 10, 15)),
                               recurrence: RecurrenceRule(frequency: .monthly, anchorDay: 15))
        let nine = TimeZoneStoreTests.local(2026, 10, 30, 9, in: Self.newYork)
        let timed = TaskItem(title: "Pills", dueDate: nine, hasDueTime: true, recurrence: RecurrenceRule.daily.withTime(hour: 9, minute: 0))
        context.insert(monthly)
        context.insert(timed)
        try context.save()
        TaskActions.toggleCompletion(monthly, in: context, now: TimeZoneStoreTests.local(2026, 11, 11, 12, in: Self.newYork))
        TaskActions.toggleCompletion(monthly, in: context, now: TimeZoneStoreTests.local(2026, 11, 16, 12, in: Self.newYork))
        XCTAssertEqual(try stored(monthly.id).dueDate, DayAnchor.anchor(of: Self.day(2026, 12, 15)))
        XCTAssertEqual(try stored(monthly.id).recurrenceRule?.anchorDay, 15)
        TaskActions.toggleCompletion(timed, in: context, now: TimeZoneStoreTests.local(2026, 11, 11, 12, in: Self.newYork))
        XCTAssertEqual(try stored(timed.id).dueDate, TimeZoneStoreTests.local(2026, 11, 11, 9, in: Self.newYork),
                       "the first 09:00 on a day not yet past (today's), in EST: 14:00 UTC, not 13:00")
    }

    /// Undo of a completion (the toast, the Completed list) puts a repeating day back where it was, byte for byte.
    func testUndoingACompletionPutsTheDayBack() throws {
        watch(in: Self.newYork)
        let before = DayAnchor.anchor(of: Self.day(2026, 10, 30))
        let task = TaskItem(title: "Stretch", dueDate: before, recurrence: .daily)
        context.insert(task)
        try context.save()
        TaskActions.toggleCompletion(task, in: context, now: TimeZoneStoreTests.local(2026, 11, 11, 12, in: Self.newYork))
        TaskActions.reschedule(task, to: before, keepTime: false, in: context)
        XCTAssertEqual(bits(try stored(task.id).dueDate), bits(before))
    }

    // MARK: - The one place: picking a day

    /// Upcoming's Pick Date hands back the picked day at the time of day of the date it opened on (a graphical DatePicker
    /// keeps the time): a task due Jul 1, 2027 (its anchor, 06:00 EDT) picked onto Dec 1, 2027 arrives as Dec 1 at 06:00
    /// EST, 11:00 UTC. It is stored as Dec 1's anchor. The other way (Dec 1 onto Jul 1) lands at 05:00 EDT, 09:00 UTC.
    func testPickingADayForAnAnchoredTaskStoresThePickedDaysAnchor() throws {
        watch(in: Self.newYork)
        for (from, to) in [(Self.day(2027, 7, 1), Self.day(2027, 12, 1)), (Self.day(2027, 12, 1), Self.day(2027, 7, 1))] {
            let task = TaskItem(title: "Renew passport", dueDate: DayAnchor.anchor(of: from))
            context.insert(task)
            try context.save()
            let opened = try XCTUnwrap(task.dueDate)
            let clock = Self.newYork.dateComponents([.hour, .minute, .second], from: opened)
            let pickedDay = TimeZoneStoreTests.local(to.year, to.month, to.day, in: Self.newYork)
            let picked = try XCTUnwrap(Self.newYork.date(bySettingHour: clock.hour!, minute: clock.minute!, second: clock.second!,
                                                         of: pickedDay))
            XCTAssertFalse(DayAnchor.isAnchor(picked), "\(from) → \(to): the picker's value is no anchor")
            TaskActions.reschedule(task, to: picked, in: context)
            XCTAssertEqual(try stored(task.id).dueDate, DayAnchor.anchor(of: to), "\(from) → \(to)")
        }
    }

    /// A date with a time is never touched: a reschedule keeps a timed task's 09:00 on the new day, and the reminder's
    /// Snooze moves it to exactly an hour from now (`keepTime: false`).
    func testReschedulingATimedTaskKeepsItsTimeAndASnoozeItsMoment() throws {
        watch(in: Self.newYork)
        let task = TaskItem(title: "Dentist", dueDate: TimeZoneStoreTests.local(2026, 11, 12, 9, in: Self.newYork), hasDueTime: true)
        context.insert(task)
        try context.save()
        TaskActions.reschedule(task, to: TimeZoneStoreTests.local(2026, 11, 20, in: Self.newYork), in: context)
        XCTAssertEqual(try stored(task.id).dueDate, TimeZoneStoreTests.local(2026, 11, 20, 9, in: Self.newYork))
        let snoozedTo = TimeZoneStoreTests.local(2026, 11, 20, 9, 2, in: Self.newYork).addingTimeInterval(3600 + 0.25)
        TaskActions.reschedule(task, to: snoozedTo, keepTime: false, in: context)
        XCTAssertEqual(bits(try stored(task.id).dueDate), bits(snoozedTo))
        XCTAssertTrue(try stored(task.id).hasDueTime)
    }

    // MARK: - The first-run pass

    static let firstRunKey = "review.firstRun"

    private func firstRun(in zone: Calendar = newYork, backUp: @escaping @MainActor (ModelContext) throws -> URL?,
                          syncLog: @escaping ProfileStore.Log = { _, _, _ in }) -> DayAnchoring.FirstRunOutcome {
        DayAnchoring.firstRunPass(context: context, defaults: defaults, key: Self.firstRunKey, calendar: zone, backUp: backUp,
                                  syncLog: syncLog)
    }

    /// A folder of this test's own in the temporary directory, removed after the test.
    private func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "DayAnchorReview-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// No backup, no pass, and no pass behind its back: while the first-run pass waits for a backup (the disk full), an
    /// import's pass rewrites nothing either. Before brief 92 the first import of that launch rewrote the whole store with
    /// no backup taken. The next launch's backup works, its first pass anchors, and imports anchor again.
    func testTheImportPassWaitsWhileTheFirstRunPassHasNoBackup() throws {
        let thursday = Self.day(2026, 11, 12)
        let midnight = DayAnchor.start(of: thursday, calendar: Self.newYork)
        let task = try olderBuildTask("Call Sam", due: midnight)
        let outcome = firstRun(backUp: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        guard case .noBackup = outcome else { return XCTFail("expected noBackup, got \(outcome)") }
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.newYork, defaults: defaults, firstRunKey: Self.firstRunKey,
                                               syncLog: { _, _, _ in }), DayAnchoring.Count())
        XCTAssertEqual(bits(try stored(task.id).dueDate), bits(midnight), "nothing rewritten without a backup")

        let backup = try scratchFolder().appending(path: "HITList-2026-11-11.json")
        let next = firstRun(backUp: { _ in try Data("{}".utf8).write(to: backup); return backup })
        XCTAssertEqual(next, .rewrote(DayAnchoring.Count(dueDates: 1), backup: backup))
        let later = try olderBuildTask("From the Mac on 0.9.2", due: DayAnchor.start(of: Self.day(2026, 11, 13), calendar: Self.newYork))
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.newYork, defaults: defaults, firstRunKey: Self.firstRunKey,
                                               syncLog: { _, _, _ in }), DayAnchoring.Count(dueDates: 1))
        XCTAssertEqual(try stored(later.id).dueDate, DayAnchor.anchor(of: Self.day(2026, 11, 13)))
    }
}
