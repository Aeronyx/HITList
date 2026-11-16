import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 143: the switch (item 1), the store's flags (item 2), the mirror launch that makes nothing, the host's
/// notices (item 4), the merge of rows that share an id (item 5) and the writes that now move `updatedAt` (item 6).
@MainActor
final class SyncEngineWiringTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "SyncEngineWiringTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    // MARK: - Which engine

    private func decide(_ arguments: [String] = [], store: String = "HITList-s143.store", testing: Bool = false,
                        debug: Bool = true) -> SyncEngineBoard.Engine {
        SyncEngineSwitch.decide(storeName: store, isTesting: testing, isDebug: debug, arguments: ["HITList"] + arguments,
                                defaults: defaults)
    }

    func testTheMirrorUnlessAskedAndEveryReleasedBuildWithoutThePreference() {
        XCTAssertEqual(decide(), .mirror)
        XCTAssertEqual(decide(store: "HITList.store"), .mirror)
        XCTAssertEqual(decide(store: "HITList.store", debug: false), .mirror)
        XCTAssertEqual(decide(["-syncEngine", "own"], store: "HITList.store", debug: false), .mirror, "a release build ignores the argument")
    }

    func testADebugArgumentChoosesOnASideStoreOnly() {
        XCTAssertEqual(decide(["-syncEngine", "own"]), .own)
        XCTAssertEqual(decide(["-syncEngine", "own"], store: "HITList.store"), .mirror, "never on the real store")
        XCTAssertEqual(decide(["-syncEngine", "own"], debug: false), .mirror, "never in a release build")
        XCTAssertEqual(decide(["-syncEnginePretend", "two-macs"]), .own, "a pretend iCloud is the engine's")
        XCTAssertEqual(decide(["-syncEngine", "nonsense"]), .mirror)
    }

    func testThePreferenceIsPerStoreAndTheMirrorArgumentWinsOverIt() {
        SyncEngineSwitch.setPreference(.own, storeName: "HITList-s143.store", defaults: defaults)
        XCTAssertEqual(decide(), .own)
        XCTAssertEqual(decide(store: "HITList-other.store"), .mirror, "another store's preference is its own")
        XCTAssertEqual(decide(["-syncEngine", "mirror"]), .mirror)
        XCTAssertEqual(decide(debug: false), .mirror, "a released build runs the mirror whatever the preference says")
        SyncEngineSwitch.setPreference(.mirror, storeName: "HITList-s143.store", defaults: defaults)
        XCTAssertNil(defaults.object(forKey: SyncEngineSwitch.preferenceKey(storeName: "HITList-s143.store")),
                     "moving back leaves the store as one that never moved")
        XCTAssertEqual(decide(), .mirror)
    }

    /// The engine ships switched off: in a released build nothing can switch it on, not the preference a Debug build
    /// on the same device left in the shared defaults, not an argument, not on any store.
    func testAReleasedBuildNeverRunsTheEngine() {
        for store in ["HITList.store", "HITList-s143.store"] {
            SyncEngineSwitch.setPreference(.own, storeName: store, defaults: defaults)
            XCTAssertEqual(decide(["-syncEngine", "own", "-syncEnginePretend", "x"], store: store, debug: false), .mirror, store)
        }
        XCTAssertFalse(SyncEngineSwitch.isAvailable(isDebug: false))
    }

    /// The engine's records live in a container of their own (round 30): never the one SwiftData's mirror reads (it
    /// imports every zone of its container, `dev/SYNC-ENGINE.md` section 3), nor Shared Tasks'. And this build is
    /// entitled to it: a container missing from the entitlements fails at the first call, on a device.
    func testTheEngineHasAContainerOfItsOwn() async throws {
        XCTAssertEqual(SyncEngineSwitch.containerID, "iCloud.com.trammells.hitlist.sync")
        XCTAssertNotEqual(SyncEngineSwitch.containerID, HITListSchema.cloudKitContainerID, "not the mirror's")
        XCTAssertNotEqual(SyncEngineSwitch.containerID, SharedTasksSchema.containerID)
        #if os(macOS)
        // Off the main thread: reading a signature may wait on the disk.
        let containers = await Task.detached { () -> [String]? in
            var code: SecCode?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSRequirementInformation), &info) == errSecSuccess
            else { return nil }
            let entitlements = (info as? [String: Any])?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
            return entitlements?["com.apple.developer.icloud-container-identifiers"] as? [String]
        }.value
        let listed = try XCTUnwrap(containers, "the hosting app's signature lists its iCloud containers")
        XCTAssertTrue(listed.contains(SyncEngineSwitch.containerID), "\(listed)")
        XCTAssertEqual(listed.first, HITListSchema.cloudKitContainerID, "the task store's stays first")
        #endif
    }

    func testNeverUnderHostedTests() {
        SyncEngineSwitch.setPreference(.own, storeName: "HITList-s143.store", defaults: defaults)
        XCTAssertEqual(decide(["-syncEngine", "own"], testing: true), .mirror)
        XCTAssertEqual(SyncEngineSwitch.current, .mirror, "this test process decided nothing")
    }

    func testTheZoneAndThePretendNameAreDebugSideStoreOnly() {
        let side = "HITList-s143.store"
        XCTAssertEqual(SyncEngineSwitch.zoneName(storeName: side, isDebug: true, arguments: ["-syncEngineZone", "HITList-run1"]), "HITList-run1")
        XCTAssertEqual(SyncEngineSwitch.zoneName(storeName: "HITList.store", isDebug: true, arguments: ["-syncEngineZone", "x"]), SyncSchema.zoneName)
        XCTAssertEqual(SyncEngineSwitch.zoneName(storeName: side, isDebug: false, arguments: ["-syncEngineZone", "x"]), SyncSchema.zoneName)
        XCTAssertEqual(SyncEngineSwitch.zoneName(storeName: side, isDebug: true, arguments: ["-syncEngineZone", "a b"]), SyncSchema.zoneName)
        XCTAssertEqual(SyncEngineSwitch.pretendName(storeName: side, isDebug: true, arguments: ["-syncEnginePretend", "two"]), "two")
        XCTAssertNil(SyncEngineSwitch.pretendName(storeName: "HITList.store", isDebug: true, arguments: ["-syncEnginePretend", "two"]))
    }

    // MARK: - With the switch off, nothing of the engine's

    func testAMirrorLaunchMakesNoEngineNoLedgerAndWiresOnlyTheMove() async throws {
        XCTAssertEqual(SyncEngineSwitch.current, .mirror)
        let board = SyncEngineBoard.shared
        defer { board.launched(.mirror, actions: nil) }
        let ledgerFile = ModelContainerFactory.groupStoreURL.map { SyncLedgerStore.url(forStoreAt: $0) }
        let existedBefore = ledgerFile.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        SyncEngine.launchIfSwitchedOn(container: ModelContainerFactory.preview())
        XCTAssertNil(SyncEngine.shared, "no engine object")
        XCTAssertEqual(board.engine, .mirror)
        XCTAssertNil(board.status)
        XCTAssertNotNil(board.actions?.move, "the move is how a device on the mirror moves")
        if let ledgerFile {
            XCTAssertEqual(FileManager.default.fileExists(atPath: ledgerFile.path), existedBefore, "no ledger file made")
        }
        do {
            try await board.actions?.syncNow()
            XCTFail("there is no engine to sync")
        } catch {}
        XCTAssertFalse(ModelContainerFactory.isOwnEngineEnabled)
    }

    func testTheInMemoryFallbackNeverRunsTheEngineAndTheStatusSaysWhy() {
        let board = SyncEngineBoard()
        SyncEngine.launchIfSwitchedOn(container: ModelContainerFactory.preview(), engine: .own, inMemory: true, board: board)
        XCTAssertNil(SyncEngine.shared, "no engine on an empty store that only reads as one")
        XCTAssertEqual(board.engine, .own)
        XCTAssertNil(board.actions)
        guard case .held(.failed(let words))? = board.status?.state else { return XCTFail("\(String(describing: board.status))") }
        XCTAssertTrue(words.contains("couldn't open this device's data"), words)
    }

    func testOnTheMirrorTheSeedKeepsTodaysStamps() throws {
        let container = ModelContainerFactory.preview()
        let before = Date()
        TaskActions.seedDefaultsIfNeeded(in: container.mainContext, defaults: defaults, engine: .mirror)
        let seeded = try container.mainContext.fetch(FetchDescriptor<SavedFilter>())
        XCTAssertEqual(seeded.count, 4)
        XCTAssertTrue(seeded.allSatisfy { $0.createdAt >= before && $0.updatedAt >= before }, "exactly as before the engine")
    }

    // MARK: - The move

    func testTheMoveBacksUpMergesWritesThePreferenceAndAsksToBeReopenedOnASideStore() async throws {
        let container = ModelContainerFactory.preview()
        let id = UUID()
        for title in ["One", "Two"] {
            let task = TaskItem(title: title)
            task.id = id
            container.mainContext.insert(task)
        }
        try container.mainContext.save()
        var backedUp = 0
        do {
            try await SyncEngine.move(to: .own, container: container, storeName: "HITList-s143t.store", defaults: defaults,
                                      backUp: { _ in backedUp += 1; return nil })
            XCTFail("a side store is reopened by hand")
        } catch let error as SyncEngine.MoveError {
            XCTAssertEqual(error, .reopenToFinish(.own))
            XCTAssertTrue(error.localizedDescription.contains("open it again"))
        }
        XCTAssertEqual(backedUp, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TaskItem>()), 1, "rows that shared an id merged")
        XCTAssertEqual(SyncEngineSwitch.decide(storeName: "HITList-s143t.store", isTesting: false, isDebug: true,
                                               arguments: [], defaults: defaults), .own, "the next launch opens it on the engine")
    }

    func testAMoveWhoseBackupFailsChangesNothing() async throws {
        let container = ModelContainerFactory.preview()
        struct NoBackup: Error {}
        do {
            try await SyncEngine.move(to: .own, container: container, storeName: "HITList-s143t.store", defaults: defaults,
                                      backUp: { _ in throw NoBackup() }, relaunch: false)
            XCTFail("no backup, no move")
        } catch is NoBackup {}
        XCTAssertNil(defaults.object(forKey: SyncEngineSwitch.preferenceKey(storeName: "HITList-s143t.store")))
    }

    // MARK: - The host

    func testTheHostPostsWhatTheMirrorsImportAndExportPostedInOrder() async throws {
        let host = SyncEngineHost(backUp: { _ in })
        let key = SyncSchema.key(SyncSchema.taskItem, id: UUID())
        host.didWrite([key])
        host.didAccept([key])
        host.statusDidChange(SyncStatus(state: .idle, firstFetchDone: true))
        host.didWrite([])
        host.finish()
        var seen: [String] = []
        for await event in host.events {
            switch event {
            case .wrote: seen.append("wrote")
            case .accepted: seen.append("accepted")
            case .status: seen.append("status")
            case .log, .barrier: seen.append("other")
            }
        }
        XCTAssertEqual(seen, ["wrote", "accepted", "status"], "in order, nothing for an empty set")
    }

    func testTheWidgetsFinishLineOnTheEngine() {
        let facts = SyncEngineWidgetFacts()
        let id = UUID()
        let applied = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(facts.canTellGone, "before the first whole fetch a missing task may only be late")
        XCTAssertFalse(facts.accepted(id, since: applied))
        facts.accepted([SyncSchema.key(SyncSchema.taskItem, id: id)], at: applied.addingTimeInterval(1))
        XCTAssertTrue(facts.accepted(id, since: applied), "its own record accepted after the tap")
        XCTAssertFalse(facts.accepted(id, since: applied.addingTimeInterval(2)), "an acceptance before the tap is not it")
        facts.update(SyncStatus(state: .held(.noAccount)))
        XCTAssertEqual(facts.finishLine, .save, "signed out: the save is the end")
        XCTAssertEqual(facts.widgetSync, .localOnly)
        facts.update(SyncStatus(state: .idle, firstFetchDone: true))
        XCTAssertEqual(facts.finishLine, .export)
        XCTAssertTrue(facts.canTellGone)
        XCTAssertEqual(facts.widgetSync, .fine)
        XCTAssertNil(facts.lastExportStart)
        facts.quiet(at: applied)
        XCTAssertEqual(facts.lastExportStart, applied)
    }

    // MARK: - Rows that share an id

    func testRowsThatShareAnIdMergeForEveryModelTheNewestStays() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let old = Date(timeIntervalSince1970: 1_700_000_000), new = Date(timeIntervalSince1970: 1_700_000_100)
        func pair<M: SharedIDModel>(_ make: () -> M, id: UUID) -> (M, M) {
            let a = make(), b = make()
            a.updatedAt = old
            b.updatedAt = new
            context.insert(a)
            context.insert(b)
            return (a, b)
        }
        let groupID = UUID(), labelID = UUID(), boardID = UUID(), taskID = UUID(), filterID = UUID()
        let (oldGroup, newGroup) = pair({ let p = Project(name: "Home"); p.id = groupID; return p }, id: groupID)
        newGroup.name = "Home (renamed)"
        let (oldLabel, newLabel) = pair({ let l = TaskLabel(name: "errand"); l.id = labelID; return l }, id: labelID)
        let (oldBoard, newBoard) = pair({ let s = Switchboard(name: "Bed"); s.id = boardID; return s }, id: boardID)
        _ = pair({ let f = SavedFilter(name: "Soon", query: "today"); f.id = filterID; return f }, id: filterID)
        let (oldTask, newTask) = pair({ let t = TaskItem(title: "Copy"); t.id = taskID; return t }, id: taskID)
        newTask.title = "Newest copy"
        let onOld = TaskItem(title: "On the old copies", project: oldGroup, labels: [oldLabel])
        context.insert(onOld)
        onOld.switchboard = oldBoard
        let subOld = TaskItem(title: "Sub of old"), subNew = TaskItem(title: "Sub of new")
        context.insert(subOld)
        context.insert(subNew)
        subOld.parent = oldTask
        subNew.parent = newTask
        try context.save()

        let report = try Deduplicator.mergeSharedIDs(in: context)
        XCTAssertEqual(report.removed, 5, report.description)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).map(\.name), ["Home (renamed)"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskLabel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Switchboard>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedFilter>()), 1)
        XCTAssertEqual(onOld.project?.persistentModelID, newGroup.persistentModelID)
        XCTAssertEqual((onOld.labels ?? []).map(\.persistentModelID), [newLabel.persistentModelID])
        XCTAssertEqual(onOld.switchboard?.persistentModelID, newBoard.persistentModelID)
        let copies = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == taskID }))
        XCTAssertEqual(copies.map(\.title), ["Newest copy"])
        XCTAssertEqual(Set((copies.first?.subtasks ?? []).map(\.title)), ["Sub of old", "Sub of new"],
                       "a sub-task under either copy ends under the survivor")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 4)
        XCTAssertEqual(try Deduplicator.mergeSharedIDs(in: context).removed, 0, "a second pass changes nothing")
        _ = oldTask
    }

    // MARK: - Writes that move `updatedAt`

    private let longAgo = Date(timeIntervalSince1970: 1_600_000_000)

    func testAnUndoneSwitchIsStampedNowSoItBeatsTheDeletionItUndoes() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, in: context)
        let sub = try TaskActions.addSubtask("Mint", to: floss, in: context)
        floss.updatedAt = longAgo
        sub.updatedAt = longAgo
        try context.save()
        let deleted = Flipboard.delete(floss, in: context)
        let before = Date()
        let back = try XCTUnwrap(Flipboard.restore(deleted, in: context))
        XCTAssertGreaterThanOrEqual(back.updatedAt, before)
        XCTAssertTrue((back.subtasks ?? []).allSatisfy { $0.updatedAt >= before })
    }

    func testANewSwitchsFieldsSetAfterTheCreateCarryTheirMoment() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let before = Date()
        let board = try Flipboard.createSwitchboard(name: "Bed", in: context)
        let vacuum = try Flipboard.createSwitch(title: "Vacuum", rule: .daily, flipTarget: 3, board: board,
                                                overdueBecomesTask: true, in: context)
        XCTAssertGreaterThanOrEqual(vacuum.updatedAt, before)
        XCTAssertEqual(vacuum.flipTarget, 3)
    }

    func testABoardsNewClockStampsTheSwitchesItReLands() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let board = try Flipboard.createSwitchboard(name: "Bed", in: context)
        let vacuum = try Flipboard.createSwitch(title: "Vacuum", rule: .daily, board: board, in: context)
        vacuum.updatedAt = longAgo
        try context.save()
        let before = Date()
        Flipboard.update(board, name: "Bed", cadence: .weekly, resetMinutes: 9 * 60, resetWeekday: 7,
                         overdueBecomesTask: false, in: context)
        XCTAssertGreaterThanOrEqual(vacuum.updatedAt, before, "its due date and rule changed: an edit of the switch")
    }

    func testClaudesNotesSetAfterTheCreateCarryTheirMoment() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let before = Date()
        let handler = ClaudeToolHandler(context: context, rule: ClaudeAccessRule(mode: .allExceptHidden), now: Date(),
                                        calendar: .current, weekStart: 2)
        let result = handler.call(ClaudeTools.addTask, ["text": .string("Water the plants"), "description": .string("The fern too")])
        XCTAssertFalse(result.isError)
        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(task.notes, "The fern too")
        XCTAssertGreaterThanOrEqual(task.updatedAt, before)
    }
}
