import XCTest
import SwiftData
import CoreSpotlight
import HITListCore
@testable import HITList

/// Spotlight (brief 52, item 2): open top-level tasks in the system index, kept in step in batches through a
/// ledger of what was indexed, cleared on an account switch, never from a test or a Debug side-store run,
/// and a tapped result opening its task.
@MainActor
final class SpotlightTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var suite: String!
    private var defaults: UserDefaults!
    private var index: FakeIndex!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
        suite = "SpotlightTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        index = FakeIndex()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        _ = IntentRouter.shared.take()
        _ = IntentRouter.shared.takeTask()
        container = nil
        context = nil
        defaults = nil
        index = nil
    }

    private func sync(batchSize: Int = 100) -> SpotlightSync {
        SpotlightSync(index: index, defaults: defaults, batchSize: batchSize)
    }

    @discardableResult
    private func task(_ title: String, notes: String = "", due: Date? = nil, group: String? = nil,
                      labels: [String] = []) throws -> TaskItem {
        let item = TaskItem(title: title)
        item.notes = notes
        item.dueDate = due
        if let group {
            let project = Project(name: group)
            context.insert(project)
            item.project = project
        }
        context.insert(item)
        for name in labels {
            let label = TaskLabel(name: name)
            context.insert(label)
            item.labels = (item.labels ?? []) + [label]
        }
        try context.save()
        return item
    }

    // MARK: Records and plans

    func testFingerprintChangesWithWhatSpotlightShows() throws {
        let item = try task("Buy milk", notes: "2%", due: Date(timeIntervalSince1970: 1_800_000_000), group: "Home",
                            labels: ["errands"])
        let first = SpotlightRecord(item).fingerprint
        XCTAssertEqual(SpotlightRecord(item).fingerprint, first, "the same task, the same fingerprint")
        XCTAssertEqual(first.count, 32)

        item.title = "Buy oat milk"
        let renamed = SpotlightRecord(item).fingerprint
        XCTAssertNotEqual(renamed, first)
        item.notes = "1 litre"
        XCTAssertNotEqual(SpotlightRecord(item).fingerprint, renamed)
        let noted = SpotlightRecord(item).fingerprint
        item.dueDate = nil
        XCTAssertNotEqual(SpotlightRecord(item).fingerprint, noted)
        let undated = SpotlightRecord(item).fingerprint
        item.project?.name = "Flat"
        XCTAssertNotEqual(SpotlightRecord(item).fingerprint, undated)
        let moved = SpotlightRecord(item).fingerprint
        item.priority = 1
        XCTAssertEqual(SpotlightRecord(item).fingerprint, moved, "priority isn't shown in Spotlight")
    }

    func testPlanIndexesNewAndChangedAndRemovesTheRest() {
        let a = UUID(), b = UUID(), c = UUID(), gone = UUID()
        let plan = SpotlightPlan.make(current: [a: "1", b: "2", c: "3"], ledger: [a: "1", b: "old", gone: "9"])
        XCTAssertEqual(Set(plan.index), [b, c])
        XCTAssertEqual(plan.remove, [gone])
        XCTAssertTrue(SpotlightPlan.make(current: [a: "1"], ledger: [a: "1"]).isEmpty)
    }

    func testLedgerRoundTripsAndIgnoresAnOldVersion() {
        let id = UUID()
        SpotlightLedger.save([id: "abc"], to: defaults)
        XCTAssertEqual(SpotlightLedger.load(from: defaults), [id: "abc"])
        defaults.set(["v": 0, "items": [id.uuidString: "abc"]], forKey: SpotlightLedger.key)
        XCTAssertNil(SpotlightLedger.load(from: defaults), "an older ledger means: index everything again")
        XCTAssertNil(SpotlightLedger.load(from: UserDefaults(suiteName: "\(suite!).empty")!))
    }

    // MARK: Refresh

    func testFirstRefreshClearsTheIndexThenIndexesOpenTopLevelTasksInBatches() async throws {
        for n in 1...5 { try task("Task \(n)") }
        let done = try task("Done already")
        done.isCompleted = true
        let parent = try task("Parent")
        let child = try task("Child")
        child.parent = parent
        try context.save()

        let plan = await sync(batchSize: 2).refresh(in: context)

        XCTAssertEqual(index.removedAll, 1, "no ledger yet: whatever an earlier build left goes first")
        XCTAssertEqual(index.batches.map(\.count), [2, 2, 2], "six open top-level tasks, two at a time")
        XCTAssertEqual(Set(index.indexed.map(\.title)), ["Task 1", "Task 2", "Task 3", "Task 4", "Task 5", "Parent"])
        XCTAssertEqual(plan.index.count, 6)
        XCTAssertEqual(SpotlightLedger.load(from: defaults)?.count, 6)
    }

    func testLaterRefreshesSendOnlyWhatChanged() async throws {
        let milk = try task("Buy milk")
        let bread = try task("Buy bread")
        let sync = sync()
        await sync.refresh(in: context)
        index.reset()

        let quiet = await sync.refresh(in: context)
        XCTAssertTrue(quiet.isEmpty)
        XCTAssertTrue(index.batches.isEmpty, "nothing changed, nothing sent")
        XCTAssertEqual(index.removedAll, 0)

        milk.title = "Buy oat milk"
        try context.save()
        await sync.refresh(in: context)
        XCTAssertEqual(index.indexed.map(\.title), ["Buy oat milk"])
        XCTAssertEqual(index.removed, [])
        _ = bread
    }

    func testCompletingOrDeletingATaskTakesItOutOfSpotlight() async throws {
        let milk = try task("Buy milk")
        let bread = try task("Buy bread")
        let sync = sync()
        await sync.refresh(in: context)
        index.reset()

        TaskActions.toggleCompletion(milk, in: context)
        await sync.refresh(in: context)
        XCTAssertEqual(index.removed, [milk.id])

        index.reset()
        let breadID = bread.id
        TaskActions.delete(bread, in: context)
        try context.save()
        await sync.refresh(in: context)
        XCTAssertEqual(index.removed, [breadID])
        XCTAssertEqual(SpotlightLedger.load(from: defaults), [:])
    }

    func testAFailedBatchIsTriedAgainNextTime() async throws {
        try task("Buy milk")
        index.failing = true
        let sync = sync()
        await sync.refresh(in: context)
        XCTAssertEqual(SpotlightLedger.load(from: defaults) ?? [:], [:], "not recorded as indexed")

        index.failing = false
        index.reset()
        await sync.refresh(in: context)
        XCTAssertEqual(index.indexed.map(\.title), ["Buy milk"])
    }

    func testAccountSwitchClearsTheIndexAndTheLedger() async throws {
        try task("Someone else's task")
        let sync = sync()
        await sync.refresh(in: context)
        index.reset()

        await sync.clearForAccountChange()
        XCTAssertEqual(index.removedAll, 1)
        XCTAssertNil(SpotlightLedger.load(from: defaults))
    }

    // MARK: Who may index

    func testOnlyTheRealStoreIndexesNeverTestsOrSideStores() {
        let main = ModelContainerFactory.mainStoreName
        XCTAssertTrue(SpotlightSync.isAllowed(storeName: main, inMemory: false, testing: false, simulator: false))
        XCTAssertFalse(SpotlightSync.isAllowed(storeName: main, inMemory: false, testing: true, simulator: false))
        XCTAssertFalse(SpotlightSync.isAllowed(storeName: main, inMemory: true, testing: false, simulator: false),
                       "the in-memory fallback is empty: indexing it would take every task out of Spotlight")
        XCTAssertFalse(SpotlightSync.isAllowed(storeName: "HITList-Development.store", inMemory: false, testing: false,
                                               simulator: false),
                       "a Debug build on the Mac shares the TestFlight app's index (one bundle id)")
        XCTAssertTrue(SpotlightSync.isAllowed(storeName: "HITList-Development.store", inMemory: false, testing: false,
                                              simulator: true),
                      "a simulator has no other build to share the index with")
        XCTAssertFalse(SpotlightSync.isAllowed(storeName: "HITList-Development.store", inMemory: true, testing: false,
                                               simulator: true))
    }

    func testAStoppedSyncLeavesTheIndexAlone() async throws {
        try task("Buy milk")
        let sync = SpotlightSync(index: index, defaults: defaults, isAllowed: false)
        await sync.refresh(in: context)
        await sync.clearForAccountChange()
        XCTAssertTrue(index.batches.isEmpty)
        XCTAssertEqual(index.removedAll, 0)
    }

    // MARK: What Spotlight shows, and opening it

    func testEntityCarriesTitleDescriptionAndKeywords() throws {
        let due = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 17))!
        let item = try task("Call mom", notes: "Ask about Sunday", due: due, group: "Home", labels: ["family"])
        item.hasDueTime = true
        let entity = TaskEntity(spotlight: item)
        let set = entity.attributeSet
        XCTAssertEqual(set.title, "Call mom")
        XCTAssertEqual(set.displayName, "Call mom")
        let description = try XCTUnwrap(set.contentDescription)
        XCTAssertTrue(description.contains("Home"), description)
        XCTAssertTrue(description.contains(due.formatted(date: .abbreviated, time: .shortened)),
                      "a fixed date, never “Tomorrow”, which would go stale in the index: \(description)")
        XCTAssertTrue(description.contains("Ask about Sunday"))
        XCTAssertEqual(set.keywords, ["family", "Home"])
        XCTAssertEqual(set.dueDate, due)
    }

    func testOpeningAResultAsksTheShellToOpenTheTask() async throws {
        let item = try task("Call mom")
        IntentStore.register(container)
        defer { IntentStore.reset() }
        let intent = OpenTaskIntent()
        intent.target = TaskEntity(item)
        _ = try await intent.perform()
        XCTAssertEqual(IntentRouter.shared.request?.task, item.id)
        XCTAssertNil(IntentRouter.shared.take(), "a task request is not a screen, and stays for the task route")
        XCTAssertEqual(IntentRouter.shared.takeTask(), item.id)
        XCTAssertNil(IntentRouter.shared.request)
    }

    func testRouterHandsOutATaskOnce() {
        let router = IntentRouter()
        let id = UUID()
        router.open(task: id)
        XCTAssertEqual(router.takeTask(), id)
        XCTAssertNil(router.takeTask())
        router.open(.today)
        XCTAssertNil(router.takeTask(), "a screen request is not a task, and stays for the screen route")
        XCTAssertEqual(router.take(), .today)
    }

    func testASpotlightActivityNamesItsTask() {
        let id = UUID()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: id.uuidString]
        XCTAssertEqual(SpotlightSync.taskID(from: activity), id)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "not-a-uuid"]
        XCTAssertNil(SpotlightSync.taskID(from: activity))
    }
}

/// Records what would reach Core Spotlight.
@MainActor
private final class FakeIndex: SpotlightIndexing {
    var batches: [[TaskEntity]] = []
    var removed: [UUID] = []
    var removedAll = 0
    var failing = false

    var indexed: [TaskEntity] { batches.flatMap { $0 } }

    func reset() {
        batches = []
        removed = []
        removedAll = 0
    }

    func index(_ entities: [TaskEntity]) async throws {
        if failing { throw CocoaError(.featureUnsupported) }
        batches.append(entities)
    }

    func remove(_ ids: [UUID]) async throws {
        if failing { throw CocoaError(.featureUnsupported) }
        removed += ids
    }

    func removeAll() async throws {
        removedAll += 1
    }
}
