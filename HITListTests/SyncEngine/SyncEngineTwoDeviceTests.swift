import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 143, item 8: two whole devices in the app's own process, each the app's engine as it runs (`SyncEngine`: a
/// SwiftData container, `SwiftDataSyncStore` writing through its main context, a `SyncLedgerStore`, `SyncCore`, the
/// host), on one pretend iCloud (`FakeCloud`, each device a `FakeTransport`). Nothing waits on time: `settle()` sends
/// a marker down the engine's two streams, and a sync is the person's "sync now".
@MainActor
final class SyncEngineTwoDeviceTests: XCTestCase {
    /// One device: its store, its ledger, its board, its engine.
    @MainActor
    final class Device {
        let name: String
        let container: ModelContainer
        let ledger: SyncLedgerStore
        let board = SyncEngineBoard()
        let engine: SyncEngine
        let backups = Backups()
        var context: ModelContext { container.mainContext }
        var transport: FakeTransport { engine.transport as! FakeTransport }

        final class Backups: @unchecked Sendable {
            var reasons: [SyncRemovalReason] = []
            var fail = false
        }

        init(_ name: String, cloud: FakeCloud, container: ModelContainer = ModelContainerFactory.preview(),
             ledger: SyncLedgerStore = .inMemory(), storeURL: URL? = nil) {
            self.name = name
            self.container = container
            self.ledger = ledger
            let backups = self.backups
            engine = SyncEngine(container: container, ledger: ledger, storeURL: storeURL, board: board,
                                backUp: { reason in
                                    if backups.fail { throw CocoaError(.fileWriteUnknown) }
                                    backups.reasons.append(reason)
                                }) { ledger in FakeTransport(cloud: cloud, device: name, state: ledger) }
            engine.echo = { line in print("[\(name)] \(line)") }
        }

        func start() async {
            await engine.start()
            await engine.settle()
        }

        /// The person's "sync now", with everything the save hints and the brain said handled before and after.
        func sync() async throws {
            await engine.settle()
            try await engine.core.syncNow()
            await engine.settle()
        }

        func save() throws { try context.save() }

        func tasks() throws -> [TaskItem] {
            try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.title)]))
        }

        func task(_ id: UUID) throws -> TaskItem? {
            try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
        }

        var status: SyncStatus { get async { await engine.core.status } }
    }

    private var cloud: FakeCloud!
    private var devices: [Device] = []

    /// A deletion the person asked for, however large (Undo last import, a Group with its tasks), is so many
    /// deletions taken down as they were saved: they go, and nobody is asked anything. (The first engine read absence
    /// as deletion, had to guard that with numbers, and needed the app to vouch for a bulk deletion.)
    func testABulkDeletionThePersonAskedForSimplyGoes() async throws {
        let device = Device("A", cloud: cloud)
        devices.append(device)
        await device.start()
        var made: [TaskItem] = []
        for i in 0..<30 {
            let task = TaskItem(title: "Imported \(i)")
            device.context.insert(task)
            made.append(task)
        }
        try device.save()
        try await device.sync()

        for task in made.prefix(25) { device.context.delete(task) }
        try device.save()
        try await device.sync()
        let after = await device.status
        XCTAssertNil(after.hold, "the person deleted them: nothing to ask")
        XCTAssertEqual(after.waiting, 0, "the 25 markers went")
        XCTAssertEqual(try device.tasks().count, 5)
        let tasks = await cloud.records().filter { $0.key.type == "TaskItem" }
        XCTAssertEqual(tasks.filter { $0.record.isDeleted }.count, 25)
        XCTAssertEqual(tasks.filter { !$0.record.isDeleted }.count, 5)
    }

    /// Rows that are gone with no deletion taken down (here: deleted while nothing was watching the saves, as a store
    /// that lost them would look) are not deletions. Nothing is deleted in iCloud, nobody is asked, and at the next
    /// launch everything iCloud holds comes back.
    func testRowsGoneWithNoDeletionTakenDownComeBackAndNothingIsDeletedInICloud() async throws {
        let container = ModelContainerFactory.preview()
        let ledger = SyncLedgerStore.inMemory()
        let first = Device("A", cloud: cloud, container: container, ledger: ledger)
        devices.append(first)
        await first.start()
        for i in 0..<20 { first.context.insert(TaskItem(title: "Task \(i)")) }
        try first.save()
        try await first.sync()
        await first.engine.stop()

        // The app is not running the engine: nothing takes these down.
        for task in try first.tasks() { first.context.delete(task) }
        try first.save()
        XCTAssertEqual(try first.tasks().count, 0, "setup: the store reads empty")

        let again = Device("A", cloud: cloud, container: container, ledger: ledger)
        devices.append(again)
        await again.start()
        try await again.sync()
        try await again.sync()
        let after = await again.status
        XCTAssertNil(after.hold, "nobody is asked anything")
        XCTAssertEqual(after.waiting, 0)
        XCTAssertEqual(try again.tasks().count, 20, "everything iCloud held is back on the device")
        let markers = await cloud.records().filter { $0.record.isDeleted }.count
        XCTAssertEqual(markers, 0, "and nothing was deleted in iCloud")
    }

    override func setUp() async throws {
        cloud = FakeCloud()
        devices = []
    }

    override func tearDown() async throws {
        for device in devices { await device.engine.stop() }
        devices = []
        cloud = nil
    }

    private func device(_ name: String, container: ModelContainer = ModelContainerFactory.preview(),
                        ledger: SyncLedgerStore = .inMemory(), storeURL: URL? = nil) async -> Device {
        let device = Device(name, cloud: cloud, container: container, ledger: ledger, storeURL: storeURL)
        devices.append(device)
        await device.start()
        return device
    }

    /// A task with a Group, a label and two sub-tasks, made on `device` and saved.
    @discardableResult
    private func makeErrand(on device: Device) throws -> TaskItem {
        let home = Project(name: "Home")
        let errand = TaskLabel(name: "errand")
        device.context.insert(home)
        device.context.insert(errand)
        let task = TaskItem(title: "Buy milk", priority: 2, project: home, labels: [errand])
        device.context.insert(task)
        for (index, title) in ["Oat", "Whole"].enumerated() {
            let sub = TaskItem(title: title, project: home)
            sub.sortOrder = index
            device.context.insert(sub)
            sub.parent = task
        }
        try device.save()
        return task
    }

    // MARK: - What one device makes, the other has

    func testATaskMadeOnOneAppearsOnTheOtherWithItsGroupLabelsAndSubtasks() async throws {
        let a = await device("A"), b = await device("B")
        let made = try makeErrand(on: a)
        try await a.sync()
        try await b.sync()

        let there = try XCTUnwrap(try b.task(made.id))
        XCTAssertEqual(there.title, "Buy milk")
        XCTAssertEqual(there.priority, 2)
        XCTAssertEqual(there.project?.name, "Home")
        XCTAssertEqual(there.project?.id, made.project?.id)
        XCTAssertEqual((there.labels ?? []).map(\.name), ["errand"])
        XCTAssertEqual((there.subtasks ?? []).map(\.title).sorted(), ["Oat", "Whole"])
        XCTAssertTrue((there.subtasks ?? []).allSatisfy { $0.project?.id == made.project?.id })
        XCTAssertEqual(try b.tasks().count, 3)
        let statusA = await a.status, statusB = await b.status
        XCTAssertTrue(statusA.isSynced, "\(statusA)")
        XCTAssertTrue(statusB.isSynced, "\(statusB)")
        XCTAssertEqual(b.board.status, statusB, "the board shows the brain's status")
    }

    func testAnEditOnEachSideOfDifferentFieldsBothSurvive() async throws {
        let a = await device("A"), b = await device("B")
        let made = try makeErrand(on: a)
        try await a.sync()
        try await b.sync()

        let onA = try XCTUnwrap(try a.task(made.id))
        onA.title = "Buy oat milk"
        onA.touch()
        try a.save()
        let onB = try XCTUnwrap(try b.task(made.id))
        onB.notes = "From the corner shop"
        onB.touch()
        try b.save()

        try await a.sync()
        try await b.sync()
        try await a.sync()
        for device in [a, b] {
            let task = try XCTUnwrap(try device.task(made.id))
            XCTAssertEqual(task.title, "Buy oat milk", device.name)
            XCTAssertEqual(task.notes, "From the corner shop", device.name)
        }
        let quiet = await cloud.lastChange
        try await a.sync()
        try await b.sync()
        let after = await cloud.lastChange
        XCTAssertEqual(after, quiet, "I7: nothing more is sent once both agree")
    }

    func testADeletionOnOneIsGoneOnTheOtherSubtasksWithIt() async throws {
        let a = await device("A"), b = await device("B")
        let made = try makeErrand(on: a)
        try await a.sync()
        try await b.sync()
        XCTAssertEqual(try b.tasks().count, 3)

        TaskActions.delete(try XCTUnwrap(try a.task(made.id)), in: a.context)
        try await a.sync()
        try await b.sync()
        XCTAssertNil(try b.task(made.id))
        XCTAssertEqual(try b.tasks().count, 0, "its sub-tasks went with it")
        let marker = await cloud.record(SyncSchema.key(SyncSchema.taskItem, id: made.id))
        XCTAssertEqual(marker?.record.isDeleted, true, "a marker stays in iCloud")
    }

    func testAnUndoOfADeletedSwitchComesBackEverywhere() async throws {
        let a = await device("A"), b = await device("B")
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, in: a.context)
        try await a.sync()
        try await b.sync()
        XCTAssertNotNil(try b.task(floss.id))

        let deleted = Flipboard.delete(floss, in: a.context)
        try await a.sync()
        try await b.sync()
        XCTAssertNil(try b.task(floss.id), "deleted there")

        let back = try XCTUnwrap(Flipboard.restore(deleted, in: a.context))
        XCTAssertEqual(back.id, floss.id)
        try await a.sync()
        try await b.sync()
        let there = try XCTUnwrap(try b.task(floss.id), "the undo beats the deletion it undoes")
        XCTAssertEqual(there.title, "Floss")
        XCTAssertEqual((there.labels ?? []).map(\.name), (back.labels ?? []).map(\.name), "with its flipboard label")
    }

    func testAnEditInTheMainContextWhileAFetchIsWrittenIsNotLost() async throws {
        let a = await device("A"), b = await device("B")
        let made = try makeErrand(on: a)
        try await a.sync()
        try await b.sync()

        let onA = try XCTUnwrap(try a.task(made.id))
        onA.notes = "Two litres"
        onA.touch()
        try a.save()
        try await a.sync()

        // On B the person is typing a new title, not saved yet, when A's change arrives.
        let onB = try XCTUnwrap(try b.task(made.id))
        onB.title = "Buy milk and bread"
        onB.touch()
        try await b.sync()
        XCTAssertEqual(onB.title, "Buy milk and bread", "the fetch never writes over an unsaved edit")
        try b.save()
        // B's merged version goes after its conflict is settled (a send later on the fake), then A fetches it.
        try await b.sync()
        try await b.sync()
        try await a.sync()
        for device in [a, b] {
            let task = try XCTUnwrap(try device.task(made.id))
            XCTAssertEqual(task.title, "Buy milk and bread", device.name)
            XCTAssertEqual(task.notes, "Two litres", device.name)
        }
    }

    // MARK: - A first sync of two stores that already hold the same things

    func testAFirstSyncOfTwoStoresHoldingTheSame500ItemsDoublesNothingAndSendsNothingTwice() async throws {
        let ids = (0..<500).map { _ in UUID() }
        let stamp = Date(timeIntervalSince1970: 1_763_200_000)
        func seed(_ container: ModelContainer) throws {
            let context = container.mainContext
            for (index, id) in ids.enumerated() {
                let task = TaskItem(title: "Task \(index)", priority: 1 + index % 4)
                task.id = id
                task.sortOrder = index
                task.createdAt = stamp
                task.updatedAt = stamp
                context.insert(task)
            }
            try context.save()
        }
        let storeA = ModelContainerFactory.preview(), storeB = ModelContainerFactory.preview()
        try seed(storeA)
        try seed(storeB)

        let a = await device("A", container: storeA)
        try await a.sync()
        let sentByA = await cloud.acceptedSaves
        XCTAssertEqual(sentByA, 501, "the 500 and the format's record")

        let b = await device("B", container: storeB)
        try await b.sync()
        let afterB = await cloud.acceptedSaves
        XCTAssertEqual(afterB, sentByA, "B found every item already there: nothing sent")
        XCTAssertEqual(try b.tasks().count, 500, "nothing doubled")
        XCTAssertEqual(try a.tasks().count, 500)
        let records = await cloud.records()
        XCTAssertEqual(records.count, 501)
        let statusB = await b.status
        XCTAssertTrue(statusB.isSynced, "\(statusB)")
        XCTAssertEqual(statusB.waiting, 0)
    }

    // MARK: - The account

    func testASignOutRemovesWhatWasSyncedAfterABackupAndASignInBringsItBack() async throws {
        let a = await device("A"), b = await device("B")
        let made = try makeErrand(on: a)
        try await a.sync()
        try await b.sync()
        XCTAssertEqual(try b.tasks().count, 3)

        await cloud.setAccount(nil, for: "B")
        await b.transport.noticeChanges()
        await b.engine.settle()
        XCTAssertEqual(b.backups.reasons, [.signedOut], "a backup before anything left")
        XCTAssertEqual(try b.tasks().count, 0, "what was synced left the device, as with the mirror")
        let held = await b.status
        XCTAssertEqual(held.hold, .noAccount)
        XCTAssertEqual(b.board.status?.hold, .noAccount)

        await cloud.setAccount(FakeCloud.defaultAccount, for: "B")
        await b.transport.noticeChanges()
        try await b.sync()
        XCTAssertNotNil(try b.task(made.id), "back at sign-in")
        XCTAssertEqual(try b.tasks().count, 3)
    }

    func testASignOutWhoseBackupFailsRemovesNothing() async throws {
        let a = await device("A"), b = await device("B")
        try makeErrand(on: a)
        try await a.sync()
        try await b.sync()
        b.backups.fail = true
        await cloud.setAccount(nil, for: "B")
        await b.transport.noticeChanges()
        await b.engine.settle()
        XCTAssertEqual(try b.tasks().count, 3, "no backup, nothing removed")
        let status = await b.status
        XCTAssertNotNil(status.lastError)
    }

    // MARK: - Reset local cache

    func testResetLocalCacheForgetsTheLedgerWithTheStoreAndFetchesEverythingAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SyncEngineReset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appending(path: "HITList-reset.store")
        let ledgerURL = SyncLedgerStore.url(forStoreAt: storeURL)
        func open() throws -> ModelContainer {
            let schema = HITListSchema.schema
            let config = ModelConfiguration("HITList", schema: schema, url: storeURL, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, migrationPlan: HITListMigrationPlan.self, configurations: [config])
        }

        let a = await device("A")
        let made = try makeErrand(on: a)
        try await a.sync()

        // B on a file: it fetches everything, and its ledger is bound to its store file.
        var first: ModelContainer? = try open()
        let b = try await device("B", container: first!, ledger: SyncLedgerStore.open(at: ledgerURL), storeURL: storeURL)
        try await b.sync()
        XCTAssertEqual(try b.tasks().count, 3)
        let identity = try XCTUnwrap(SyncLedgerStore.storeIdentity(at: storeURL))
        let bound = try await b.ledger.fact(SyncLedgerStore.storeFact).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(bound, identity)
        await b.engine.stop()
        devices.removeAll { $0 === b }
        first = nil

        // Reset local cache: the store moved aside as today (`ModelContainerFactory.trashStore`), a new one opened.
        XCTAssertNotNil(try ModelContainerFactory.trashStore(at: storeURL, into: folder.appending(path: "Trash")))
        let fresh = try open()
        let newIdentity = try XCTUnwrap(SyncLedgerStore.storeIdentity(at: storeURL))
        XCTAssertNotEqual(newIdentity, identity, "a new file is a new store")
        let saves = await cloud.acceptedSaves

        let again = try await device("B", container: fresh, ledger: SyncLedgerStore.open(at: ledgerURL), storeURL: storeURL)
        let rebound = try await again.ledger.fact(SyncLedgerStore.storeFact).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(rebound, newIdentity, "the ledger was forgotten and bound to the new file")
        try await again.sync()
        XCTAssertNotNil(try again.task(made.id), "everything fetched again into the empty store")
        XCTAssertEqual(try again.tasks().count, 3)
        let savesAfter = await cloud.acceptedSaves
        XCTAssertEqual(savesAfter, saves, "nothing was deleted or sent: the empty store was not read as deletions")
    }

    // MARK: - The default filters (the review's finding 11)

    func testADefaultFilterDeletedOrEditedOnOneDeviceStaysSoWhenANewDeviceSeedsItsOwn() async throws {
        let suiteA = "SyncEngineSeedA-\(UUID().uuidString)", suiteB = "SyncEngineSeedB-\(UUID().uuidString)"
        let defaultsA = try XCTUnwrap(UserDefaults(suiteName: suiteA)), defaultsB = try XCTUnwrap(UserDefaults(suiteName: suiteB))
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }
        func filters(_ device: Device) throws -> [String: String] {
            let all = try device.context.fetch(FetchDescriptor<SavedFilter>())
            return Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0.query) })
        }

        let storeA = ModelContainerFactory.preview()
        TaskActions.seedDefaultsIfNeeded(in: storeA.mainContext, defaults: defaultsA, engine: .own)
        let a = await device("A", container: storeA)
        try await a.sync()
        let seeded = try a.context.fetch(FetchDescriptor<SavedFilter>())
        XCTAssertEqual(seeded.count, 4)
        XCTAssertTrue(seeded.allSatisfy { $0.updatedAt == TaskActions.engineSeedDate && $0.createdAt == TaskActions.engineSeedDate })

        // On A the person deletes "Waiting" and edits "Focus".
        let waiting = try XCTUnwrap(seeded.first { $0.name == "Waiting" })
        a.context.delete(waiting)
        let focus = try XCTUnwrap(seeded.first { $0.name == "Focus" })
        focus.query = "p1 & today"
        focus.touch()
        try a.save()
        try await a.sync()

        // B is new and seeds its own, then syncs.
        let storeB = ModelContainerFactory.preview()
        TaskActions.seedDefaultsIfNeeded(in: storeB.mainContext, defaults: defaultsB, engine: .own)
        let b = await device("B", container: storeB)
        try await b.sync()
        try await a.sync()
        try await b.sync()

        for device in [a, b] {
            let names = try filters(device)
            XCTAssertNil(names["Waiting"], "\(device.name): the deletion stands against a fresh seed")
            XCTAssertEqual(names["Focus"], "p1 & today", "\(device.name): the edit stands against a fresh seed")
            XCTAssertEqual(names.count, 3, device.name)
        }
    }

    // MARK: - Rows that share an id

    func testRowsThatShareAnIdAreMergedBeforeTheEngineStarts() async throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let id = UUID()
        let old = TaskItem(title: "Old copy")
        old.id = id
        old.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let new = TaskItem(title: "New copy")
        new.id = id
        context.insert(old)
        context.insert(new)
        let sub = TaskItem(title: "Under the old copy")
        context.insert(sub)
        sub.parent = old
        try context.save()

        let a = await device("A", container: container)
        try await a.sync()
        let rows = try a.context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id }))
        XCTAssertEqual(rows.map(\.title), ["New copy"], "the copy changed last stays")
        XCTAssertEqual((rows.first?.subtasks ?? []).map(\.title), ["Under the old copy"], "its sub-task lost nothing")
        let status = await a.status
        XCTAssertTrue(status.isSynced, "\(status)")
    }
}
