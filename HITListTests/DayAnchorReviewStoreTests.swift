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
        let count = try XCTUnwrap(DayAnchoring.importPass(in: context, calendar: Self.chicago, syncLog: { lines.append(($0, $2)) }))
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
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.losAngeles, syncLog: { _, _, _ in }),
                       DayAnchoring.Count(leftAlone: .init(notThisZonesMidnight: 1)))
        XCTAssertEqual(bits(try stored(task.id).dueDate), bits(fromHome))

        // Home anchors it; the anchor syncs to the phone, which shows Thursday.
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.chicago, syncLog: { _, _, _ in }),
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
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.newYork, syncLog: { _, _, _ in }),
                       DayAnchoring.Count(leftAlone: .init(notThisZonesMidnight: 1)))
        XCTAssertEqual(bits(try stored(task.id).dueDate), bits(rolled))
        XCTAssertEqual(shown(try stored(task.id).dueDate), Self.day(2026, 11, 11))
    }
}
