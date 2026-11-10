import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Settings → Export JSON / Import JSON: `SnapshotBuilder.build` → `jsonData` → `Snapshot.from(json:)` →
/// `SnapshotBuilder.restore`, the same calls `SettingsView` makes.
@MainActor
final class SnapshotRoundTripTests: XCTestCase {
    private var source: ModelContainer!
    private var target: ModelContainer!

    override func setUp() async throws {
        source = ModelContainerFactory.preview()
        target = ModelContainerFactory.preview()
    }

    override func tearDown() async throws {
        source = nil
        target = nil
    }

    // Whole seconds: the JSON uses ISO 8601 without fractions.
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A store with every field set to a non-default value and every relationship shape.
    private func populate(_ context: ModelContext) throws {
        let work = Project(name: "Work", colorHex: "#E5484D", sortOrder: 3)
        let home = Project(name: "Home", colorHex: "#30A46C", sortOrder: 1)
        let urgent = TaskLabel(name: "urgent", colorHex: "#FF0000")
        let phone = TaskLabel(name: "phone", colorHex: "#00FF00")
        for (i, p) in [work, home].enumerated() {
            p.createdAt = t0.addingTimeInterval(Double(i)); p.updatedAt = t0.addingTimeInterval(100 + Double(i))
            context.insert(p)
        }
        for (i, l) in [urgent, phone].enumerated() {
            l.createdAt = t0.addingTimeInterval(10 + Double(i)); l.updatedAt = t0.addingTimeInterval(110 + Double(i))
            context.insert(l)
        }

        let full = TaskItem(title: "Standup", notes: "Zoom link in calendar", priority: 2, dueDate: t0.addingTimeInterval(9 * 3600),
                            hasDueTime: true, project: work, labels: [urgent, phone], recurrence: .weekdays)
        full.sortOrder = 7
        let done = TaskItem(title: "Taxes", priority: 1, dueDate: t0, project: home, labels: [urgent])
        done.isCompleted = true
        done.completedAt = t0.addingTimeInterval(3600)
        let biweekly = TaskItem(title: "Gym", recurrence: RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 4, 6]))
        let bare = TaskItem(title: "Loose end")
        for (i, t) in [full, done, biweekly, bare].enumerated() {
            t.createdAt = t0.addingTimeInterval(20 + Double(i)); t.updatedAt = t0.addingTimeInterval(120 + Double(i))
            context.insert(t)
        }

        let filter = SavedFilter(name: "Focus", query: "(p1 | p2) & today", colorHex: "#123456", sortOrder: 2)
        filter.createdAt = t0.addingTimeInterval(30); filter.updatedAt = t0.addingTimeInterval(130)
        context.insert(filter)
        try context.save()
    }

    /// Order-independent form for comparison: SwiftData fetch order and to-many order are not stable.
    private func normalized(_ s: Snapshot) -> Snapshot {
        var s = s
        s.exportedAt = t0
        s.projects.sort { $0.id.uuidString < $1.id.uuidString }
        s.labels.sort { $0.id.uuidString < $1.id.uuidString }
        s.filters.sort { $0.id.uuidString < $1.id.uuidString }
        s.switchboards?.sort { $0.id.uuidString < $1.id.uuidString }
        s.tasks = s.tasks.map { var t = $0; t.labelIDs.sort { $0.uuidString < $1.uuidString }; return t }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return s
    }

    private func roundTrip(_ snapshot: Snapshot) throws -> Snapshot { try Snapshot.from(json: snapshot.jsonData()) }

    func testExportImportIntoEmptyStorePreservesEverything() throws {
        try populate(source.mainContext)
        let exported = try SnapshotBuilder.build(from: source.mainContext)

        let summary = try SnapshotBuilder.restore(try roundTrip(exported), into: target.mainContext)

        XCTAssertEqual(summary.inserted, 9)
        XCTAssertEqual(summary.updated + summary.skipped, 0)
        let reexported = try SnapshotBuilder.build(from: target.mainContext)
        XCTAssertEqual(normalized(reexported), normalized(exported))
    }

    func testRelationshipsAndRecurrenceSurviveAsModels() throws {
        try populate(source.mainContext)
        try SnapshotBuilder.restore(try roundTrip(SnapshotBuilder.build(from: source.mainContext)), into: target.mainContext)

        let tasks = try target.mainContext.fetch(FetchDescriptor<TaskItem>())
        let byTitle = Dictionary(uniqueKeysWithValues: tasks.map { ($0.title, $0) })
        let standup = try XCTUnwrap(byTitle["Standup"])
        XCTAssertEqual(standup.project?.name, "Work")
        XCTAssertEqual(standup.labelList.map(\.name), ["phone", "urgent"])
        XCTAssertEqual(standup.recurrenceRule, .weekdays)
        XCTAssertEqual(byTitle["Gym"]?.recurrence, "weekly;2;2,4,6")
        XCTAssertEqual(byTitle["Taxes"]?.completedAt, t0.addingTimeInterval(3600))
        XCTAssertNil(byTitle["Loose end"]?.project)
        XCTAssertEqual(byTitle["Loose end"]?.labels ?? [], [])

        let work = try XCTUnwrap(try target.mainContext.fetch(FetchDescriptor<Project>()).first { $0.name == "Work" })
        XCTAssertEqual(work.tasks?.map(\.title), ["Standup"], "inverse relationship is rebuilt")
        let urgent = try XCTUnwrap(try target.mainContext.fetch(FetchDescriptor<TaskLabel>()).first { $0.name == "urgent" })
        XCTAssertEqual(Set(urgent.tasks?.map(\.title) ?? []), ["Standup", "Taxes"])
    }

    func testJSONEncodingIsLosslessForRecordDates() throws {
        try populate(source.mainContext)
        let exported = try SnapshotBuilder.build(from: source.mainContext)
        // Only `exportedAt` (taken from `Date()`) loses its fractional seconds.
        XCTAssertEqual(normalized(try roundTrip(exported)), normalized(exported))
    }

    func testImportingTheSameExportTwiceChangesNothing() throws {
        try populate(source.mainContext)
        let snapshot = try roundTrip(SnapshotBuilder.build(from: source.mainContext))
        try SnapshotBuilder.restore(snapshot, into: target.mainContext)
        let second = try SnapshotBuilder.restore(snapshot, into: target.mainContext)
        XCTAssertEqual(second.inserted + second.updated, 0)
        XCTAssertEqual(second.skipped, 9)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<TaskItem>()), 4)
    }

    func testOlderBackupDoesNotClobberNewerEdits() throws {
        try populate(source.mainContext)
        let snapshot = try roundTrip(SnapshotBuilder.build(from: source.mainContext))
        try SnapshotBuilder.restore(snapshot, into: target.mainContext)
        let local = try XCTUnwrap(try target.mainContext.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Standup" })
        local.title = "Standup (moved)"
        local.updatedAt = t0.addingTimeInterval(10_000)
        try target.mainContext.save()

        try SnapshotBuilder.restore(snapshot, into: target.mainContext)
        XCTAssertEqual(local.title, "Standup (moved)")

        try SnapshotBuilder.restore(snapshot, into: target.mainContext, overwriteNewer: true)
        XCTAssertEqual(local.title, "Standup")
    }

    func testNewerBackupUpdatesExistingRecords() throws {
        try populate(source.mainContext)
        try SnapshotBuilder.restore(try roundTrip(SnapshotBuilder.build(from: source.mainContext)), into: target.mainContext)

        let gym = try XCTUnwrap(try source.mainContext.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Gym" })
        let home = try XCTUnwrap(try source.mainContext.fetch(FetchDescriptor<Project>()).first { $0.name == "Home" })
        gym.project = home
        gym.recurrenceRule = .monthly
        gym.updatedAt = t0.addingTimeInterval(5_000)
        try source.mainContext.save()

        let summary = try SnapshotBuilder.restore(try roundTrip(SnapshotBuilder.build(from: source.mainContext)), into: target.mainContext)
        XCTAssertEqual(summary.updated, 1)
        let restored = try XCTUnwrap(try target.mainContext.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Gym" })
        XCTAssertEqual(restored.project?.name, "Home")
        XCTAssertEqual(restored.recurrence, "monthly;1")
    }

    // MARK: - Schema V2 fields (beta review)

    private func setV2Fields(on task: TaskItem) {
        task.reminderOffsetMinutes = 15
        task.deadline = t0.addingTimeInterval(3 * 86_400)
        task.locationName = "Office"
        task.flipTarget = 3
        task.flipCount = 1
        task.flipPeriodStart = t0
    }

    /// The daily backup and Export JSON wrote none of schema V2's fields, so restoring one (the way back
    /// after losing a device's data) dropped every reminder offset, deadline, location and Flipboard charge.
    func testReminderDeadlineLocationAndFlipboardSurviveABackup() throws {
        try populate(source.mainContext)
        let standup = try XCTUnwrap(try source.mainContext.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Standup" })
        setV2Fields(on: standup)
        try source.mainContext.save()

        try SnapshotBuilder.restore(try roundTrip(SnapshotBuilder.build(from: source.mainContext)), into: target.mainContext)

        let tasks = try target.mainContext.fetch(FetchDescriptor<TaskItem>())
        let restored = try XCTUnwrap(tasks.first { $0.title == "Standup" })
        XCTAssertEqual(restored.reminderOffsetMinutes, 15)
        XCTAssertEqual(restored.deadline, t0.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(restored.locationName, "Office")
        XCTAssertEqual(restored.flipTarget, 3)
        XCTAssertEqual(restored.flipCount, 1)
        XCTAssertEqual(restored.flipPeriodStart, t0)
        let bare = try XCTUnwrap(tasks.first { $0.title == "Loose end" })
        XCTAssertNil(bare.reminderOffsetMinutes)
        XCTAssertNil(bare.deadline)
        XCTAssertNil(bare.locationName)
        XCTAssertEqual(bare.flipTarget, 1)
        XCTAssertEqual(bare.flipCount, 0)
    }

    /// A newer backup clears a field the backup says is empty...
    func testANewerBackupClearsAV2FieldItHasNoValueFor() throws {
        try populate(source.mainContext)
        try SnapshotBuilder.restore(try roundTrip(SnapshotBuilder.build(from: source.mainContext)), into: target.mainContext)
        let local = try XCTUnwrap(try target.mainContext.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Standup" })
        setV2Fields(on: local)
        try target.mainContext.save()

        let source = try XCTUnwrap(try self.source.mainContext.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Standup" })
        source.updatedAt = t0.addingTimeInterval(9_000)
        try self.source.mainContext.save()
        try SnapshotBuilder.restore(try roundTrip(SnapshotBuilder.build(from: self.source.mainContext)), into: target.mainContext)

        XCTAssertNil(local.locationName, "the newer backup says there is no location")
        XCTAssertNil(local.deadline)
        XCTAssertEqual(local.flipTarget, 1)
    }

    /// ...but a backup from before 0.3.6 can't say, so it leaves them as they are.
    func testABackupFromBeforeTheV2FieldsLeavesThemAlone() throws {
        try populate(target.mainContext)
        let local = try XCTUnwrap(try target.mainContext.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Standup" })
        setV2Fields(on: local)
        try target.mainContext.save()

        var old = try SnapshotBuilder.build(from: target.mainContext)
        old.tasks = old.tasks.map { record in
            var r = Snapshot.TaskRecord(id: record.id, title: record.title + " (renamed)", notes: record.notes, priority: record.priority,
                                        dueDate: record.dueDate, hasDueTime: record.hasDueTime, isCompleted: record.isCompleted,
                                        completedAt: record.completedAt, recurrence: record.recurrence, sortOrder: record.sortOrder,
                                        projectID: record.projectID, labelIDs: record.labelIDs, createdAt: record.createdAt,
                                        updatedAt: record.updatedAt.addingTimeInterval(9_000))
            r.reminderOffsetMinutes = nil  // what a 0.3.5 backup holds: no V2 keys at all
            return r
        }
        try SnapshotBuilder.restore(try roundTrip(old), into: target.mainContext)

        XCTAssertEqual(local.title, "Standup (renamed)", "the old backup is newer, so its fields win")
        XCTAssertEqual(local.reminderOffsetMinutes, 15)
        XCTAssertEqual(local.locationName, "Office")
        XCTAssertEqual(local.flipTarget, 3)
    }

    // MARK: - Schema V3: subtasks

    func testSubtasksSurviveABackupUnderTheirParent() throws {
        let context = source.mainContext
        let trip = TaskItem(title: "Pack for trip")
        let socks = TaskItem(title: "Socks"), charger = TaskItem(title: "Charger")
        for task in [trip, socks, charger] { context.insert(task) }
        socks.parent = trip; socks.sortOrder = 1
        charger.parent = trip; charger.sortOrder = 0
        charger.isCompleted = true
        try context.save()

        let exported = try roundTrip(SnapshotBuilder.build(from: context))
        XCTAssertEqual(exported.tasks.first { $0.title == "Socks" }?.parentID, trip.id)
        XCTAssertNil(exported.tasks.first { $0.title == "Pack for trip" }?.parentID)
        try SnapshotBuilder.restore(exported, into: target.mainContext)

        let tasks = try target.mainContext.fetch(FetchDescriptor<TaskItem>())
        let restored = try XCTUnwrap(tasks.first { $0.title == "Pack for trip" })
        XCTAssertNil(restored.parent)
        XCTAssertEqual(restored.orderedSubtasks.map(\.title), ["Charger", "Socks"])
        XCTAssertEqual(restored.orderedSubtasks.map(\.isCompleted), [true, false])
        XCTAssertEqual(normalized(try SnapshotBuilder.build(from: target.mainContext)), normalized(exported))
    }

    /// A child listed before its parent (the store's fetch order is arbitrary) still finds it.
    func testASubtaskListedBeforeItsParentIsReattached() throws {
        let parentID = UUID(), childID = UUID()
        let child = Snapshot.TaskRecord(id: childID, title: "Socks", notes: "", priority: 4, dueDate: nil, hasDueTime: false,
                                        isCompleted: false, completedAt: nil, recurrence: nil, sortOrder: 0, projectID: nil,
                                        labelIDs: [], createdAt: t0, updatedAt: t0, parentID: parentID)
        let parent = Snapshot.TaskRecord(id: parentID, title: "Pack", notes: "", priority: 4, dueDate: nil, hasDueTime: false,
                                         isCompleted: false, completedAt: nil, recurrence: nil, sortOrder: 0, projectID: nil,
                                         labelIDs: [], createdAt: t0, updatedAt: t0)
        let snapshot = Snapshot(deviceName: "test", projects: [], labels: [], tasks: [child, parent], filters: [])
        try SnapshotBuilder.restore(try roundTrip(snapshot), into: target.mainContext)
        let tasks = try target.mainContext.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.first { $0.id == childID }?.parent?.id, parentID)
    }

    /// A backup from before 0.4.1 has no `parentID` key at all and still decodes.
    func testABackupWithoutParentIDsDecodes() throws {
        try populate(source.mainContext)
        let json = try SnapshotBuilder.build(from: source.mainContext).jsonData()
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        object["tasks"] = (object["tasks"] as? [[String: Any]])?.map { var t = $0; t.removeValue(forKey: "parentID"); return t }
        let old = try Snapshot.from(json: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.tasks.count, 4)
        XCTAssertTrue(old.tasks.allSatisfy { $0.parentID == nil })
    }

    /// The rule is one level: a damaged backup that nests deeper attaches the grandchild to the top task.
    func testABackupNestingDeeperThanOneLevelIsFlattened() throws {
        let a = UUID(), b = UUID(), c = UUID()
        func record(_ id: UUID, _ title: String, parent: UUID?) -> Snapshot.TaskRecord {
            Snapshot.TaskRecord(id: id, title: title, notes: "", priority: 4, dueDate: nil, hasDueTime: false, isCompleted: false,
                                completedAt: nil, recurrence: nil, sortOrder: 0, projectID: nil, labelIDs: [], createdAt: t0,
                                updatedAt: t0, parentID: parent)
        }
        let snapshot = Snapshot(deviceName: "test", projects: [], labels: [],
                                tasks: [record(c, "C", parent: b), record(b, "B", parent: a), record(a, "A", parent: nil)], filters: [])
        try SnapshotBuilder.restore(snapshot, into: target.mainContext)
        let byTitle = Dictionary(uniqueKeysWithValues: try target.mainContext.fetch(FetchDescriptor<TaskItem>()).map { ($0.title, $0) })
        XCTAssertEqual(byTitle["B"]?.parent?.title, "A")
        XCTAssertEqual(byTitle["C"]?.parent?.title, "A")
    }

    // MARK: - Schema V6: Switchboards (brief 72)

    /// A Switchboard with its cadence, reset and opt-in, and its switches (one opted in itself), come back as they were.
    func testASwitchboardAndItsSwitchesSurviveABackup() throws {
        let context = source.mainContext
        let board = Switchboard(name: "Deep Clean")
        board.sortOrder = 2
        board.cadence = "weekly"
        board.resetMinutes = 9 * 60 + 30
        board.resetWeekday = 7
        board.overdueBecomesTask = true
        board.createdAt = t0
        board.updatedAt = t0.addingTimeInterval(60)
        context.insert(board)
        let vacuum = TaskItem(title: "Vacuum", dueDate: t0, recurrence: .weekly)
        let windows = TaskItem(title: "Windows", dueDate: t0.addingTimeInterval(10 * 3600), hasDueTime: true, recurrence: .weekly)
        let loose = TaskItem(title: "Shave", recurrence: RecurrenceRule(frequency: .daily, interval: 3))
        for task in [vacuum, windows, loose] { context.insert(task) }
        vacuum.switchboard = board
        windows.switchboard = board
        windows.overdueBecomesTask = true
        loose.overdueBecomesTask = true
        try context.save()

        let exported = try roundTrip(SnapshotBuilder.build(from: context))
        XCTAssertEqual(exported.switchboards?.map(\.name), ["Deep Clean"])
        XCTAssertEqual(exported.tasks.first { $0.title == "Vacuum" }?.switchboardID, board.id)
        XCTAssertNil(exported.tasks.first { $0.title == "Shave" }?.switchboardID)
        XCTAssertTrue(exported.tasks.allSatisfy(\.hasV6Fields))
        let summary = try SnapshotBuilder.restore(exported, into: target.mainContext)
        XCTAssertEqual(summary.inserted, 4)

        let boards = try target.mainContext.fetch(FetchDescriptor<Switchboard>())
        let restored = try XCTUnwrap(boards.first)
        XCTAssertEqual(boards.count, 1)
        XCTAssertEqual(restored.id, board.id)
        XCTAssertEqual(restored.sortOrder, 2)
        XCTAssertEqual(restored.cadence, "weekly")
        XCTAssertEqual(restored.resetMinutes, 570)
        XCTAssertEqual(restored.resetWeekday, 7)
        XCTAssertTrue(restored.overdueBecomesTask)
        XCTAssertEqual(restored.createdAt, t0)
        XCTAssertEqual(restored.updatedAt, t0.addingTimeInterval(60))
        XCTAssertEqual(Set(restored.switches?.map(\.title) ?? []), ["Vacuum", "Windows"])
        let tasks = try target.mainContext.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.first { $0.title == "Windows" }?.overdueBecomesTask, true)
        XCTAssertEqual(tasks.first { $0.title == "Vacuum" }?.overdueBecomesTask, false)
        XCTAssertEqual(tasks.first { $0.title == "Shave" }?.overdueBecomesTask, true)
        XCTAssertNil(tasks.first { $0.title == "Shave" }?.switchboard)
        XCTAssertEqual(normalized(try SnapshotBuilder.build(from: target.mainContext)), normalized(exported))
    }

    /// A newer backup moves a switch out of its board (its record says no board) and renames the board.
    func testANewerBackupMovesASwitchOffItsBoard() throws {
        let context = source.mainContext
        let board = Switchboard(name: "Before Bed")
        let floss = TaskItem(title: "Floss", recurrence: .daily)
        context.insert(board)
        context.insert(floss)
        floss.switchboard = board
        try context.save()
        try SnapshotBuilder.restore(try roundTrip(SnapshotBuilder.build(from: context)), into: target.mainContext)

        board.name = "Bedtime"
        board.updatedAt = Date().addingTimeInterval(60)
        floss.switchboard = nil
        floss.updatedAt = Date().addingTimeInterval(60)
        try context.save()
        try SnapshotBuilder.restore(try roundTrip(SnapshotBuilder.build(from: context)), into: target.mainContext)

        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<Switchboard>()).map(\.name), ["Bedtime"])
        XCTAssertNil(try target.mainContext.fetch(FetchDescriptor<TaskItem>()).first?.switchboard)
    }

    /// A backup written by 0.9.0 (20) has no Switchboards and no V6 task fields: it still restores, and leaves a
    /// switch's board and opt-in as they are here.
    func testABackupFromBeforeSwitchboardsStillRestores() throws {
        let local = TaskItem(title: "Floss", recurrence: .daily)
        let board = Switchboard(name: "Before Bed")
        target.mainContext.insert(local)
        target.mainContext.insert(board)
        local.switchboard = board
        local.overdueBecomesTask = true
        local.updatedAt = t0
        try target.mainContext.save()

        let record = Snapshot.TaskRecord(id: local.id, title: "Floss (from the backup)", notes: "", priority: 4, dueDate: nil,
                                         hasDueTime: false, isCompleted: false, completedAt: nil, recurrence: "daily;1",
                                         sortOrder: 0, projectID: nil, labelIDs: [], createdAt: t0,
                                         updatedAt: t0.addingTimeInterval(3600), flipTarget: 1, flipCount: 0,
                                         schemaVersion: 5)
        let older = Snapshot(deviceName: "0.9.0 (20)", projects: [], labels: [], tasks: [record], filters: [])
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: older.jsonData()) as? [String: Any])
        XCTAssertNil(object["switchboards"], "0.9.0 (20) wrote no such key")
        object["tasks"] = (object["tasks"] as? [[String: Any]])?.map {
            var t = $0; t.removeValue(forKey: "switchboardID"); t.removeValue(forKey: "overdueBecomesTask"); return t
        }
        let decoded = try Snapshot.from(json: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.switchboards)
        XCTAssertFalse(decoded.tasks[0].hasV6Fields)
        try SnapshotBuilder.restore(decoded, into: target.mainContext)

        XCTAssertEqual(local.title, "Floss (from the backup)", "the backup is newer, so its fields win")
        XCTAssertEqual(local.switchboard?.name, "Before Bed", "a backup too old to say leaves the board alone")
        XCTAssertTrue(local.overdueBecomesTask)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<Switchboard>()), 1)
    }
}
