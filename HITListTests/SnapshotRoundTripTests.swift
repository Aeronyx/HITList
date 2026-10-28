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
}
