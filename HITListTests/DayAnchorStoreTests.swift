import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 82, item 3: the app's one place (every save anchors the days it writes), the pass after each import, and the
/// first-run pass behind its backup. Every zone and clock is injected; the hook watches only this test's container.
@MainActor
final class DayAnchorStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var hook: DayAnchoring.SaveHook?
    private var defaults: UserDefaults!
    private var suiteName = ""

    static let chicago = TimeZoneStoreTests.chicago
    static let losAngeles = TimeZoneStoreTests.losAngeles
    static let tokyo = TimeZoneStoreTests.tokyo

    /// Thursday 2026-11-12 and Friday the 13th.
    static let thursday = DayAnchor.Day(year: 2026, month: 11, day: 12)
    static let friday = DayAnchor.Day(year: 2026, month: 11, day: 13)

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
        suiteName = "DayAnchorStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        hook?.stop()
        hook = nil
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        context = nil
    }

    private func midnight(_ day: DayAnchor.Day, in zone: Calendar) -> Date { DayAnchor.start(of: day, calendar: zone) }

    private func stored(_ id: UUID) throws -> TaskItem {
        let fresh = ModelContext(container)
        return try XCTUnwrap(try fresh.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
    }

    /// Inserts a task with these values and saves it with no hook watching: what an older build left in the store.
    private func olderBuildTask(_ title: String, due: Date?, hasTime: Bool = false, deadline: Date? = nil) throws -> TaskItem {
        let task = TaskItem(title: title, dueDate: due, hasDueTime: hasTime)
        task.deadline = deadline
        context.insert(task)
        try context.save()
        return task
    }

    // MARK: - The one place

    /// A task saved in Chicago with Thursday (Chicago's midnight, as quick add writes it) and a Friday deadline is
    /// stored as Thursday's and Friday's anchors.
    func testTheOnePlaceAnchorsTheDaysASaveWrites() throws {
        hook = DayAnchoring.SaveHook(container: container, calendar: { Self.chicago })
        let task = TaskItem(title: "Call Sam", dueDate: midnight(Self.thursday, in: Self.chicago))
        task.deadline = midnight(Self.friday, in: Self.chicago)
        context.insert(task)
        try context.save()
        let kept = try stored(task.id)
        XCTAssertEqual(kept.dueDate, DayAnchor.anchor(of: Self.thursday))
        XCTAssertEqual(kept.deadline, DayAnchor.anchor(of: Self.friday))
        XCTAssertFalse(kept.hasDueTime)
        XCTAssertFalse(context.hasChanges, "the rewrite is part of the save, not a change left over")
    }

    /// An edit to a task already in the store (a reschedule from a row's menu) is anchored too. The device is in Chicago:
    /// the hook and `TaskActions` both read its calendar.
    func testTheOnePlaceAnchorsAnEdit() throws {
        let task = try olderBuildTask("Call Sam", due: nil)
        hook = DayAnchoring.SaveHook(container: container, calendar: { Self.chicago })
        TaskActions.reschedule(task, to: midnight(Self.friday, in: Self.chicago), calendar: Self.chicago, in: context)
        try context.save()
        XCTAssertEqual(try stored(task.id).dueDate, DayAnchor.anchor(of: Self.friday))
    }

    /// A save that changes something else (the title) anchors the task's old day as well.
    func testTheOnePlaceAnchorsAnOldDayWhenItsTaskIsSavedForAnotherReason() throws {
        let task = try olderBuildTask("Call Sam", due: midnight(Self.thursday, in: Self.chicago))
        hook = DayAnchoring.SaveHook(container: container, calendar: { Self.chicago })
        task.title = "Call Sam back"
        try context.save()
        XCTAssertEqual(try stored(task.id).dueDate, DayAnchor.anchor(of: Self.thursday))
    }

    /// A time is a moment: a timed due date, a reminder, a completion and a flip's interval start are saved as set.
    func testTheOnePlaceLeavesMomentsAlone() throws {
        hook = DayAnchoring.SaveHook(container: container, calendar: { Self.chicago })
        let nine = TimeZoneStoreTests.local(2026, 11, 12, 9, in: Self.chicago)
        let task = TaskItem(title: "Call Sam", dueDate: nine, hasDueTime: true)
        task.reminderDate = nine.addingTimeInterval(-900)
        task.completedAt = nine
        task.flipPeriodStart = nine
        context.insert(task)
        try context.save()
        let kept = try stored(task.id)
        XCTAssertEqual(kept.dueDate, nine)
        XCTAssertEqual(kept.reminderDate, nine.addingTimeInterval(-900))
        XCTAssertEqual(kept.completedAt, nine)
        XCTAssertEqual(kept.flipPeriodStart, nine)
    }

    /// Anchoring is not an edit: `updatedAt` stays what the writer set.
    func testTheOnePlaceKeepsUpdatedAt() throws {
        let task = try olderBuildTask("Call Sam", due: midnight(Self.thursday, in: Self.chicago))
        let updated = task.updatedAt
        hook = DayAnchoring.SaveHook(container: container, calendar: { Self.tokyo })
        task.notes = "about Friday"
        try context.save()
        XCTAssertEqual(try stored(task.id).updatedAt, updated)
    }

    /// Idempotent across saves and zones: an anchor saved again in Tokyo, Los Angeles or Pago Pago stays itself, and a
    /// device in Pago Pago (UTC−11) keeps its own midnights, which it would otherwise show as the day before.
    func testSavingAgainInAnyZoneNeverWalksADay() throws {
        let zones = [Self.tokyo, Self.losAngeles, TimeZoneStoreTests.calendar("Pacific/Pago_Pago"), Self.chicago]
        var zone = Self.chicago
        hook = DayAnchoring.SaveHook(container: container, calendar: { zone })
        let task = TaskItem(title: "Call Sam", dueDate: midnight(Self.thursday, in: Self.chicago))
        context.insert(task)
        try context.save()
        for next in zones {
            zone = next
            for i in 0..<3 {
                task.notes = "\(next.timeZone.identifier) \(i)"
                try context.save()
                XCTAssertEqual(try stored(task.id).dueDate, DayAnchor.anchor(of: Self.thursday), next.timeZone.identifier)
            }
        }
        let pagoPago = TimeZoneStoreTests.calendar("Pacific/Pago_Pago")
        zone = pagoPago
        let local = TaskItem(title: "Pago Pago's own", dueDate: midnight(Self.thursday, in: pagoPago))
        context.insert(local)
        try context.save()
        XCTAssertEqual(try stored(local.id).dueDate, midnight(Self.thursday, in: pagoPago))
    }

    /// The hook watches its own container only: another store's saves (TipKit's datastore, a test's) are left alone.
    func testTheOnePlaceLeavesAnotherContainerAlone() throws {
        hook = DayAnchoring.SaveHook(container: container, calendar: { Self.chicago })
        let other = ModelContainerFactory.preview()
        let task = TaskItem(title: "Elsewhere", dueDate: midnight(Self.thursday, in: Self.chicago))
        other.mainContext.insert(task)
        try other.mainContext.save()
        XCTAssertEqual(task.dueDate, midnight(Self.thursday, in: Self.chicago))
    }

    /// The one switch: off, the hook rewrites nothing.
    func testTheSwitchStopsTheOnePlace() throws {
        hook = DayAnchoring.SaveHook(container: container, calendar: { Self.chicago }, enabled: false)
        let task = TaskItem(title: "Call Sam", dueDate: midnight(Self.thursday, in: Self.chicago))
        context.insert(task)
        try context.save()
        XCTAssertEqual(try stored(task.id).dueDate, midnight(Self.thursday, in: Self.chicago))
    }

    /// Quick add's own path (`TaskActions.create`) through the hook: the parser's local midnight is stored as the anchor.
    func testQuickAddIsAnchoredOnItsSave() throws {
        hook = DayAnchoring.SaveHook(container: container, calendar: { Self.tokyo })
        let now = TimeZoneStoreTests.local(2026, 11, 11, 12, in: Self.tokyo)
        let parsed = QuickAddParser(now: now, calendar: Self.tokyo).parse("Call Sam thu")
        let task = try TaskActions.create(from: parsed, defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(try stored(task.id).dueDate, DayAnchor.anchor(of: Self.thursday))
    }

    // MARK: - After an import

    /// Days an older build wrote (local midnights in Chicago, and one in Tokyo from a friend's device) are anchored by
    /// the import pass on a device whose own midnights they are: Chicago's here in Chicago. Tokyo's Friday, which Chicago
    /// shows as Thursday 09:00, is left exactly as stored and counted (brief 92: never rewritten on a guess); one sync-log
    /// line says how many of each.
    func testTheImportPassAnchorsWhatAnOlderBuildWrote() throws {
        let fromChicago = try olderBuildTask("Chicago", due: midnight(Self.thursday, in: Self.chicago),
                                             deadline: midnight(Self.friday, in: Self.chicago))
        let fromTokyo = try olderBuildTask("Tokyo", due: midnight(Self.friday, in: Self.tokyo))
        let timed = try olderBuildTask("Timed", due: TimeZoneStoreTests.local(2026, 11, 12, 9, in: Self.chicago), hasTime: true)
        let anchored = try olderBuildTask("Anchored", due: DayAnchor.anchor(of: Self.thursday))
        var lines: [(String, [String: String])] = []
        let leftTokyo = DayAnchoring.Count.LeftAlone(notThisZonesMidnight: 1)
        let count = DayAnchoring.importPass(in: context, calendar: Self.chicago, syncLog: { lines.append(($0, $2)) })
        XCTAssertEqual(count, DayAnchoring.Count(dueDates: 1, deadlines: 1, leftAlone: leftTokyo))
        XCTAssertEqual(try stored(fromChicago.id).dueDate, DayAnchor.anchor(of: Self.thursday))
        XCTAssertEqual(try stored(fromChicago.id).deadline, DayAnchor.anchor(of: Self.friday))
        XCTAssertEqual(try stored(fromTokyo.id).dueDate, midnight(Self.friday, in: Self.tokyo))
        XCTAssertEqual(try stored(timed.id).dueDate, TimeZoneStoreTests.local(2026, 11, 12, 9, in: Self.chicago))
        XCTAssertEqual(try stored(anchored.id).dueDate, DayAnchor.anchor(of: Self.thursday))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.0, "Days from an older build anchored after an import: 1 due date and 1 deadline; 1 left as it was (1 not a midnight here)")
        XCTAssertEqual(lines.first?.1["zone"], "America/Chicago")
        XCTAssertEqual(lines.first?.1["leftNotAMidnightHere"], "1")
        // Nothing left that Chicago can vouch for: the next import's pass writes nothing and adds no line.
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.chicago, syncLog: { lines.append(($0, $2)) }),
                       DayAnchoring.Count(leftAlone: leftTokyo))
        XCTAssertEqual(lines.count, 1)
        // The friend's device in Tokyo reads its own Friday as written, and anchors it there.
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.tokyo, syncLog: { lines.append(($0, $2)) }),
                       DayAnchoring.Count(dueDates: 1))
        XCTAssertEqual(try stored(fromTokyo.id).dueDate, DayAnchor.anchor(of: Self.friday))
    }

    // MARK: - The first run

    /// The first launch of this build: the backup is written first (and sees the old values), then every day is
    /// anchored, the pass is marked done and logged; the next launch does nothing.
    func testTheFirstRunPassBacksUpThenAnchorsOnce() throws {
        let task = try olderBuildTask("Call Sam", due: midnight(Self.thursday, in: Self.chicago),
                                      deadline: midnight(Self.friday, in: Self.chicago))
        let backupURL = URL(fileURLWithPath: "/tmp/HITList-2026-11-11.json")
        var backedUpDue: Date?
        var lines: [String] = []
        let outcome = DayAnchoring.firstRunPass(context: context, defaults: defaults, calendar: Self.chicago, backUp: { _ in
            backedUpDue = task.dueDate
            return backupURL
        }, syncLog: { message, _, _ in lines.append(message) })
        XCTAssertEqual(outcome, .rewrote(DayAnchoring.Count(dueDates: 1, deadlines: 1), backup: backupURL))
        XCTAssertEqual(backedUpDue, midnight(Self.thursday, in: Self.chicago), "the backup is taken before anything changes")
        XCTAssertEqual(try stored(task.id).dueDate, DayAnchor.anchor(of: Self.thursday))
        XCTAssertEqual(try stored(task.id).deadline, DayAnchor.anchor(of: Self.friday))
        XCTAssertEqual(lines, ["Days anchored on the first run of this build: 1 due date and 1 deadline"])
        XCTAssertEqual(defaults.integer(forKey: DayAnchoring.firstRunKey()), DayAnchoring.firstRunVersion)

        var calledAgain = false
        let again = DayAnchoring.firstRunPass(context: context, defaults: defaults, calendar: Self.chicago,
                                              backUp: { _ in calledAgain = true; return backupURL }, syncLog: { _, _, _ in })
        XCTAssertEqual(again, .alreadyDone)
        XCTAssertFalse(calledAgain)
    }

    /// No backup, no pass: nothing is rewritten, the pass is not marked done, and the next launch tries again.
    func testTheFirstRunPassWaitsForABackup() throws {
        struct Refused: Error {}
        let task = try olderBuildTask("Call Sam", due: midnight(Self.thursday, in: Self.chicago))
        var levels: [SyncLogEntry.Level] = []
        let failed = DayAnchoring.firstRunPass(context: context, defaults: defaults, calendar: Self.chicago,
                                               backUp: { _ in throw Refused() }, syncLog: { _, level, _ in levels.append(level) })
        guard case .noBackup = failed else { return XCTFail("expected noBackup, got \(failed)") }
        let none = DayAnchoring.firstRunPass(context: context, defaults: defaults, calendar: Self.chicago,
                                             backUp: { _ in nil }, syncLog: { _, level, _ in levels.append(level) })
        guard case .noBackup = none else { return XCTFail("a backup that wrote nothing is no backup, got \(none)") }
        XCTAssertEqual(levels, [.error, .error])
        XCTAssertEqual(try stored(task.id).dueDate, midnight(Self.thursday, in: Self.chicago))
        XCTAssertEqual(defaults.integer(forKey: DayAnchoring.firstRunKey()), 0)

        let later = DayAnchoring.firstRunPass(context: context, defaults: defaults, calendar: Self.chicago,
                                              backUp: { _ in URL(fileURLWithPath: "/tmp/b.json") }, syncLog: { _, _, _ in })
        XCTAssertEqual(later, .rewrote(DayAnchoring.Count(dueDates: 1), backup: URL(fileURLWithPath: "/tmp/b.json")))
    }

    /// A store with nothing to anchor needs no backup; the pass is marked done.
    func testTheFirstRunPassWithNothingToDoTakesNoBackup() throws {
        _ = try olderBuildTask("Anchored", due: DayAnchor.anchor(of: Self.thursday))
        _ = try olderBuildTask("Timed", due: TimeZoneStoreTests.local(2026, 11, 12, 9, in: Self.chicago), hasTime: true)
        var called = false
        let outcome = DayAnchoring.firstRunPass(context: context, defaults: defaults, calendar: Self.chicago,
                                                backUp: { _ in called = true; return nil }, syncLog: { _, _, _ in })
        XCTAssertEqual(outcome, .nothingToDo)
        XCTAssertFalse(called)
        XCTAssertEqual(defaults.integer(forKey: DayAnchoring.firstRunKey()), DayAnchoring.firstRunVersion)
    }

    /// The one switch: off, the first-run pass does nothing and is not marked done (it runs on the first launch with
    /// rewriting on); the import pass rewrites nothing.
    func testTheSwitchStopsBothPasses() throws {
        let task = try olderBuildTask("Call Sam", due: midnight(Self.thursday, in: Self.chicago))
        var called = false
        let outcome = DayAnchoring.firstRunPass(context: context, defaults: defaults, calendar: Self.chicago, enabled: false,
                                                backUp: { _ in called = true; return nil }, syncLog: { _, _, _ in })
        XCTAssertEqual(outcome, .disabled)
        XCTAssertFalse(called)
        XCTAssertEqual(defaults.integer(forKey: DayAnchoring.firstRunKey()), 0)
        XCTAssertEqual(DayAnchoring.importPass(in: context, calendar: Self.chicago, enabled: false, syncLog: { _, _, _ in }),
                       DayAnchoring.Count())
        XCTAssertEqual(try stored(task.id).dueDate, midnight(Self.thursday, in: Self.chicago))
    }

    /// A side store's backup goes into a folder of its own, never into HITList.store's backups.
    /// The pass's mark is named after its store, so a Debug run on another store never marks HITList.store's done.
    func testTheFirstRunMarkIsNamedAfterItsStore() {
        XCTAssertEqual(DayAnchoring.firstRunKey(storeName: "HITList.store"), "dates.dayAnchorPass.HITList.store")
        XCTAssertNotEqual(DayAnchoring.firstRunKey(storeName: "HITList-Development.store"),
                          DayAnchoring.firstRunKey(storeName: "HITList.store"))
    }

    func testASideStoresBackupGoesInItsOwnFolder() throws {
        _ = try olderBuildTask("Call Sam", due: midnight(Self.thursday, in: Self.chicago))
        let folder = FileManager.default.temporaryDirectory.appending(path: "DayAnchorStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try XCTUnwrap(try DayAnchoring.backUp(context: context, now: TimeZoneStoreTests.local(2026, 11, 11, 12, in: Self.chicago),
                                                        isMainStore: false, sideFolder: folder))
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(url.lastPathComponent, LocalBackup.fileName(for: TimeZoneStoreTests.local(2026, 11, 11, 12, in: Self.chicago)))
        let snapshot = try Snapshot.from(json: Data(contentsOf: url))
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Call Sam"])
        XCTAssertEqual(snapshot.tasks.first?.dueDate, midnight(Self.thursday, in: Self.chicago), "the old value, as it was")
        XCTAssertTrue(DayAnchoring.sideBackupFolder.path.contains("Backups before day anchors"))
    }
}
