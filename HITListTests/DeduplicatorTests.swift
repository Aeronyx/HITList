import XCTest
import SwiftData
import HITListCore
@testable import HITList

@MainActor
final class DeduplicatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
        suiteName = "HITListTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        context = nil
    }

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func project(_ name: String, createdAt offset: TimeInterval) -> Project {
        let p = Project(name: name)
        p.createdAt = t0.addingTimeInterval(offset)
        p.updatedAt = p.createdAt
        context.insert(p)
        return p
    }

    private func label(_ name: String, createdAt offset: TimeInterval) -> TaskLabel {
        let l = TaskLabel(name: name)
        l.createdAt = t0.addingTimeInterval(offset)
        l.updatedAt = l.createdAt
        context.insert(l)
        return l
    }

    private func fetch<M: PersistentModel>(_ type: M.Type) throws -> [M] { try context.fetch(FetchDescriptor<M>()) }

    // MARK: Seeding

    func testTwoSeedPassesCreateExactlyFourFilters() throws {
        TaskActions.seedDefaultsIfNeeded(in: context, defaults: defaults)
        defaults.removeObject(forKey: TaskActions.didSeedDefaultsKey)  // a second device / lost flag
        TaskActions.seedDefaultsIfNeeded(in: context, defaults: defaults)
        let filters = try fetch(SavedFilter.self)
        XCTAssertEqual(filters.count, 4)
        XCTAssertEqual(Set(filters.map(\.id)), Set(TaskActions.defaultFilters.map { SeedIdentity.savedFilter($0.key) }))
    }

    func testSeedingSkipsFiltersThatAlreadyExistByName() throws {
        let legacy = SavedFilter(name: "Focus", query: "p1")  // seeded by build 1 with a random id
        context.insert(legacy)
        TaskActions.seedDefaultsIfNeeded(in: context, defaults: defaults)
        let focus = try fetch(SavedFilter.self).filter { $0.name == "Focus" }
        XCTAssertEqual(focus.map(\.id), [legacy.id])
        XCTAssertEqual(try fetch(SavedFilter.self).count, 4)
    }

    func testTwoDevicesSeedingBeforeImportConvergeOnStableIDs() throws {
        // Device A and device B both seeded before either imported; the import brings B's copies here.
        TaskActions.seedDefaultsIfNeeded(in: context, defaults: defaults)
        for seed in TaskActions.defaultFilters {
            let copy = SavedFilter(name: seed.name, query: seed.query, colorHex: seed.colorHex)
            copy.id = SeedIdentity.savedFilter(seed.key)
            copy.createdAt = Date().addingTimeInterval(5)
            context.insert(copy)
        }
        try context.save()
        let report = try Deduplicator.run(in: context)
        XCTAssertEqual(report.filters, 4)
        XCTAssertEqual(try fetch(SavedFilter.self).count, 4)
    }

    // MARK: Dedupe

    func testProjectsWithSameTrimmedCaseInsensitiveNameCollapse() throws {
        let work = project("Work", createdAt: 0)
        let work2 = project(" work ", createdAt: 10)
        let a = TaskItem(title: "a", project: work)
        let b = TaskItem(title: "b", project: work2)
        let c = TaskItem(title: "c", project: work2)
        [a, b, c].forEach(context.insert)
        try context.save()

        let report = try Deduplicator.run(in: context)

        XCTAssertEqual(report, DedupeReport(projects: 1, labels: 0, filters: 0))
        let projects = try fetch(Project.self)
        XCTAssertEqual(projects.map(\.id), [work.id])
        XCTAssertEqual(Set([a, b, c].compactMap { $0.project?.id }), [work.id])
        XCTAssertEqual(projects[0].tasks?.count, 3)
    }

    func testLabelsMergeIntoTaskWithoutDuplicates() throws {
        let urgent = label("urgent", createdAt: 0)
        let urgent2 = label("Urgent", createdAt: 5)
        let home = label("home", createdAt: 1)
        let both = TaskItem(title: "both", labels: [urgent, urgent2, home])
        let onlyLoser = TaskItem(title: "only loser", labels: [urgent2])
        [both, onlyLoser].forEach(context.insert)
        try context.save()

        let report = try Deduplicator.run(in: context)

        XCTAssertEqual(report.labels, 1)
        XCTAssertEqual(try fetch(TaskLabel.self).count, 2)
        // Split into typed steps: Swift 6.3 (Xcode 26.6, used by CI) cannot type-check the one-liner in time.
        let byIDString: (UUID, UUID) -> Bool = { $0.uuidString < $1.uuidString }
        let bothIDs: [UUID] = (both.labels ?? []).map(\.id).sorted(by: byIDString)
        let expectedIDs: [UUID] = [urgent.id, home.id].sorted(by: byIDString)
        XCTAssertEqual(bothIDs, expectedIDs)
        XCTAssertEqual(both.labels?.count, 2, "winner is not added twice")
        let onlyLoserIDs: [UUID] = (onlyLoser.labels ?? []).map(\.id)
        XCTAssertEqual(onlyLoserIDs, [urgent.id])
    }

    func testWinnerIsEarliestCreatedAtRegardlessOfInsertionOrder() throws {
        let late = project("Errands", createdAt: 100)
        let early = project("errands", createdAt: -100)
        let middle = project("ERRANDS", createdAt: 0)
        late.updatedAt = t0.addingTimeInterval(500)
        try context.save()

        try Deduplicator.run(in: context)

        let projects = try fetch(Project.self)
        XCTAssertEqual(projects.map(\.id), [early.id])
        XCTAssertEqual(projects[0].name, "errands")
        XCTAssertEqual(projects[0].updatedAt, t0.addingTimeInterval(500), "survivor keeps the newest updatedAt")
        _ = middle
    }

    func testTiesOnCreatedAtBreakByIDString() throws {
        let a = project("Same", createdAt: 0)
        let b = project("same", createdAt: 0)
        try context.save()
        let expected = [a.id, b.id].min { $0.uuidString < $1.uuidString }!

        try Deduplicator.run(in: context)

        XCTAssertEqual(try fetch(Project.self).map(\.id), [expected])
    }

    func testSameIDDifferentNamesCollapseByID() throws {
        let original = project("Home", createdAt: 0)
        let copy = project("Home renamed", createdAt: 3)
        copy.id = original.id
        let task = TaskItem(title: "t", project: copy)
        context.insert(task)
        try context.save()

        try Deduplicator.run(in: context)

        XCTAssertEqual(try fetch(Project.self).map(\.name), ["Home"])
        XCTAssertEqual(task.project?.persistentModelID, original.persistentModelID)
    }

    func testUnnamedRecordsAreNotMerged() throws {
        _ = project("", createdAt: 0)
        _ = project("  ", createdAt: 1)
        try context.save()
        XCTAssertEqual(try Deduplicator.run(in: context).removed, 0)
        XCTAssertEqual(try fetch(Project.self).count, 2)
    }

    func testSecondRunChangesNothing() throws {
        let work = project("Work", createdAt: 0)
        let work2 = project("work", createdAt: 1)
        let l1 = label("x", createdAt: 0)
        let l2 = label("X", createdAt: 1)
        context.insert(TaskItem(title: "t", project: work2, labels: [l1, l2]))
        TaskActions.seedDefaultsIfNeeded(in: context, defaults: defaults)
        context.insert(SavedFilter(name: "focus ", query: "p1"))
        try context.save()

        let first = try Deduplicator.run(in: context)
        XCTAssertEqual(first, DedupeReport(projects: 1, labels: 1, filters: 1))
        let snapshot = try state()

        let second = try Deduplicator.run(in: context)
        XCTAssertEqual(second, DedupeReport())
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try state(), snapshot)
        _ = work
    }

    func testLargeInputCollapsesInOnePass() throws {
        for i in 0..<3_000 { _ = project("p\(i % 1_000)", createdAt: TimeInterval(i)) }
        try context.save()
        let start = Date()
        XCTAssertEqual(try Deduplicator.run(in: context).projects, 2_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "dedupe should stay roughly linear")
        XCTAssertEqual(try fetch(Project.self).count, 1_000)
        XCTAssertEqual(try Deduplicator.run(in: context), DedupeReport())
    }

    private func state() throws -> [String] {
        let projects = try fetch(Project.self).map { "P \($0.id) \($0.name) \($0.updatedAt) \($0.tasks?.count ?? 0)" }
        let labels = try fetch(TaskLabel.self).map { "L \($0.id) \($0.name) \($0.updatedAt) \($0.tasks?.count ?? 0)" }
        let filters = try fetch(SavedFilter.self).map { "F \($0.id) \($0.name) \($0.updatedAt)" }
        return (projects + labels + filters).sorted()
    }

    // MARK: Subtasks (schema V3)

    /// Two copies of a Group merge; the parent was in the copy that goes, its subtask in the one that
    /// stays. Both end up in the survivor, together.
    func testSubtasksFollowTheirParentWhenGroupsMerge() throws {
        let keep = project("Trip", createdAt: 0)
        let lose = project("trip", createdAt: 5)
        let parent = TaskItem(title: "Pack", project: lose)
        let child = TaskItem(title: "Socks", project: keep)
        context.insert(parent); context.insert(child)
        child.parent = parent
        try context.save()

        try Deduplicator.run(in: context)

        XCTAssertEqual(try fetch(Project.self).count, 1)
        XCTAssertEqual(parent.project?.persistentModelID, keep.persistentModelID)
        XCTAssertEqual(child.project?.persistentModelID, keep.persistentModelID)
        XCTAssertEqual(child.parent?.persistentModelID, parent.persistentModelID)
    }

    /// Edits from two devices can leave a subtask in another Group than its parent, or nested a level
    /// deeper than the rule allows; the pass puts both right.
    func testSubtasksAreRepairedToOneLevelInTheirParentsGroup() throws {
        let home = project("Home", createdAt: 0)
        let work = project("Work", createdAt: 1)
        let top = TaskItem(title: "Top", project: home)
        let middle = TaskItem(title: "Middle", project: work)
        let bottom = TaskItem(title: "Bottom")
        for task in [top, middle, bottom] { context.insert(task) }
        middle.parent = top
        bottom.parent = middle
        try context.save()

        let report = try Deduplicator.run(in: context)

        XCTAssertEqual(report.subtasks, 2)
        XCTAssertEqual(bottom.parent?.persistentModelID, top.persistentModelID, "a grandchild moves up to the top task")
        XCTAssertEqual(middle.subtasks ?? [], [])
        XCTAssertEqual(middle.project?.name, "Home")
        XCTAssertEqual(bottom.project?.name, "Home")
        XCTAssertEqual(try Deduplicator.run(in: context).removed + (try Deduplicator.run(in: context).subtasks), 0, "a second pass changes nothing")
    }
}
