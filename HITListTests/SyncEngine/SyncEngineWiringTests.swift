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
        XCTAssertEqual(decide(debug: false), .own, "a released build follows a moved store's preference (0.9.14)")
        SyncEngineSwitch.setPreference(.mirror, storeName: "HITList-s143.store", defaults: defaults)
        XCTAssertNil(defaults.object(forKey: SyncEngineSwitch.preferenceKey(storeName: "HITList-s143.store")),
                     "moving back leaves the store as one that never moved")
        XCTAssertEqual(decide(), .mirror)
    }

    /// From 0.9.14 a released build may run the engine, and nothing moves by itself: only a store whose own
    /// preference says so (the move writes it) opens on the engine. An argument, a pretend iCloud, another store's
    /// preference (a Debug run's leftover on the same device) switch nothing on in a released build.
    func testAReleasedBuildRunsTheEngineOnlyForAStoreThatWasMoved() {
        XCTAssertTrue(SyncEngineSwitch.isAvailable(isDebug: false))
        XCTAssertEqual(decide(["-syncEngine", "own", "-syncEnginePretend", "x"], store: "HITList.store", debug: false), .mirror)
        SyncEngineSwitch.setPreference(.own, storeName: "HITList-s143.store", defaults: defaults)
        XCTAssertEqual(decide(store: "HITList.store", debug: false), .mirror, "a side store's preference is not the real store's")
        SyncEngineSwitch.setPreference(.own, storeName: "HITList.store", defaults: defaults)
        XCTAssertEqual(decide(store: "HITList.store", debug: false), .own)
        XCTAssertEqual(decide(["-syncEngine", "mirror"], store: "HITList.store", debug: false), .own,
                       "no argument takes a released build's store back; the move does")
        SyncEngineSwitch.setPreference(.mirror, storeName: "HITList.store", defaults: defaults)
        XCTAssertEqual(decide(store: "HITList.store", debug: false), .mirror)
    }

    /// The group that moves a store is hidden until revealed on the device; a store on the engine always shows it
    /// (the way back).
    func testTheSwitchIsHiddenUntilRevealedAndAlwaysShownOnTheEngine() {
        XCTAssertFalse(SyncEngineSwitch.isSwitchRevealed(defaults: defaults))
        XCTAssertFalse(SyncEngineSwitchGroup.isShown(revealed: false, engine: .mirror, isDebugSideStore: false))
        XCTAssertTrue(SyncEngineSwitchGroup.isShown(revealed: false, engine: .own, isDebugSideStore: false))
        XCTAssertTrue(SyncEngineSwitchGroup.isShown(revealed: false, engine: .mirror, isDebugSideStore: true))
        SyncEngineSwitch.revealSwitch(defaults: defaults)
        XCTAssertTrue(SyncEngineSwitch.isSwitchRevealed(defaults: defaults))
        XCTAssertTrue(SyncEngineSwitchGroup.isShown(revealed: true, engine: .mirror, isDebugSideStore: false))
    }

    func testSevenTapsInARowRevealAndASlowTapStartsAgain() {
        var taps = SevenTaps()
        let start = Date(timeIntervalSince1970: 1_000)
        for n in 0..<6 { XCTAssertFalse(taps.tap(at: start.addingTimeInterval(Double(n) * 0.3))) }
        XCTAssertTrue(taps.tap(at: start.addingTimeInterval(1.8)), "the seventh")
        // Six quick taps, a pause, then six more: never seven in a row.
        var slow = SevenTaps()
        for n in 0..<6 { XCTAssertFalse(slow.tap(at: start.addingTimeInterval(Double(n) * 0.3))) }
        for n in 0..<6 { XCTAssertFalse(slow.tap(at: start.addingTimeInterval(10 + Double(n) * 0.3))) }
        XCTAssertTrue(slow.tap(at: start.addingTimeInterval(12)))
    }

    /// The engine's records live in a container of their own (round 30): never the one SwiftData's mirror reads (it
    /// imports every zone of its container, `dev/SYNC-ENGINE.md` section 3), nor Shared Tasks'. And this build is
    /// entitled to it: a container missing from the entitlements fails at the first call, on a device.
    func testTheEngineHasAContainerOfItsOwn() async throws {
        XCTAssertEqual(SyncEngineSwitch.containerID, "iCloud.com.trammells.hitlist.sync")
        XCTAssertNotEqual(SyncEngineSwitch.containerID, HITListSchema.cloudKitContainerID, "not the mirror's")
        XCTAssertNotEqual(SyncEngineSwitch.containerID, SharedTasksSchema.containerID)
        #if os(macOS)
        // CI builds unsigned (scripts/test.sh --unsigned): there is no signature to read there.
        try XCTSkipIf(ProcessInfo.processInfo.environment["HITLIST_UNSIGNED"] == "1", "unsigned builds carry no entitlements")
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

    /// How long the engine's writes held the main thread (round 31, measured on an iPhone 16): ordinary small writes
    /// say nothing; a sustained load says a line each quarter of a second it adds up to, with the launch's total (the
    /// first form spoke only of a single slow write and said nothing of 5,005 records written 200 at a time); one slow
    /// write is said at once.
    func testSustainedWritesAreSaidWithTheirTotal() {
        let times = SyncApplyTimes()
        var lines: [String] = []
        times.report = { lines.append($0) }
        for _ in 0..<4 { times.note(200, 0.05) }
        XCTAssertEqual(lines, [], "0.20 s in all, no write slow: not worth a word yet")
        times.note(200, 0.05)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("0.25 s for 1000 records in 5 writes"), lines[0])
        XCTAssertTrue(lines[0].contains("this launch 0.25 s for 1000 records"), lines[0])
        times.note(3, 0.001)
        XCTAssertEqual(lines.count, 1, "a usual write says nothing")
        times.note(5000, 1.4)
        XCTAssertEqual(lines.count, 2, "one slow write is said at once")
        XCTAssertTrue(lines[1].contains("this launch 1.65 s for 6003 records"), lines[1])
        XCTAssertEqual(times.records, 6003)
        XCTAssertEqual(times.longest, 1.4)
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
        XCTAssertEqual(words, "HITList couldn't open the data on this device.", "plain words (brief 160)")
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
            // A Mac's side store is reopened by hand (a relaunch would not reopen it); an iPhone finishes the move
            // itself the next time it is left (`SyncEngineMoveFinish`, round 34), and says so.
            #if os(macOS)
            XCTAssertTrue(error.localizedDescription.contains("open it again"))
            #else
            XCTAssertTrue(error.localizedDescription.contains("the next time you leave it"), error.localizedDescription)
            #endif
        }
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: "HITList-s143t.store", defaults: defaults), .own)
        // The move waits for a reopen; moving to the engine that still runs takes it back, and needs no backup.
        try await SyncEngine.move(to: .mirror, container: container, storeName: "HITList-s143t.store", defaults: defaults,
                                  current: .mirror, backUp: { _ in backedUp += 1; return nil })
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: "HITList-s143t.store", defaults: defaults), .mirror)
        XCTAssertEqual(backedUp, 1)
        // And asked again, it is made again.
        do {
            try await SyncEngine.move(to: .own, container: container, storeName: "HITList-s143t.store", defaults: defaults,
                                      current: .mirror, backUp: { _ in backedUp += 1; return nil })
        } catch let error as SyncEngine.MoveError {
            XCTAssertEqual(error, .reopenToFinish(.own))
        }
        XCTAssertEqual(backedUp, 2)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TaskItem>()), 1, "rows that shared an id merged")
        XCTAssertEqual(SyncEngineSwitch.decide(storeName: "HITList-s143t.store", isTesting: false, isDebug: true,
                                               arguments: [], defaults: defaults), .own, "the next launch opens it on the engine")
    }

    /// The way back for every device but the first: the store is set aside at the next launch (as Reset local cache
    /// does), so the mirror downloads its zone into a new one. A move to the engine never asks for it.
    func testTheWayBackWithAFreshCopyAsksForTheStoreToBeSetAside() async throws {
        let container = ModelContainerFactory.preview()
        let store = "HITList-s143t.store"
        SyncEngineSwitch.setPreference(.own, storeName: store, defaults: defaults)
        do {
            try await SyncEngine.move(to: .mirror, container: container, storeName: store, defaults: defaults,
                                      current: .own, backUp: { _ in nil })
        } catch let error as SyncEngine.MoveError {
            XCTAssertEqual(error, .reopenToFinish(.mirror))
        }
        XCTAssertNil(ModelContainerFactory.requestedReset(in: defaults), "the first device back keeps its file")
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .mirror)

        SyncEngineSwitch.setPreference(.own, storeName: store, defaults: defaults)
        do {
            try await SyncEngine.move(to: .mirror, container: container, storeName: store, defaults: defaults,
                                      current: .own, freshCopy: true, backUp: { _ in nil })
        } catch let error as SyncEngine.MoveError {
            XCTAssertEqual(error, .reopenToFinish(.mirror))
        }
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), store, "set aside at the next launch of this store")
        XCTAssertEqual(SyncEngineSwitch.nextEngine(storeName: store, defaults: defaults), .mirror)

        defaults.removeObject(forKey: ModelContainerFactory.resetLocalStoreKey)
        do {
            try await SyncEngine.move(to: .own, container: container, storeName: store, defaults: defaults,
                                      current: .mirror, freshCopy: true, backUp: { _ in nil })
        } catch let error as SyncEngine.MoveError {
            XCTAssertEqual(error, .reopenToFinish(.own))
        }
        // Brief 167: a fresh copy is taken in either direction; to the engine it is the move made by the app itself
        // for a store with nothing of its own (`SyncEngineAutoMove` R3). The hand move never asks for one.
        XCTAssertEqual(ModelContainerFactory.requestedReset(in: defaults), store, "a fresh copy of the engine's, set aside at the next launch")
    }

    /// A move waits only when the store's preference differs from the engine this launch runs and no Debug argument
    /// chose that engine: the group then offers to cancel it.
    func testAMoveIsWaitingOnlyWhenThePreferenceDiffersFromThisLaunch() {
        XCTAssertNil(SyncEngineSwitch.pendingMove(current: .mirror, preferred: .mirror, byArgument: false))
        XCTAssertNil(SyncEngineSwitch.pendingMove(current: .own, preferred: .own, byArgument: false))
        XCTAssertEqual(SyncEngineSwitch.pendingMove(current: .mirror, preferred: .own, byArgument: false), .own, "moved, not reopened yet")
        XCTAssertEqual(SyncEngineSwitch.pendingMove(current: .own, preferred: .mirror, byArgument: false), .mirror, "moved back, not reopened yet")
        XCTAssertNil(SyncEngineSwitch.pendingMove(current: .own, preferred: .mirror, byArgument: true),
                     "a Debug run on the engine by argument was never moved")
    }

    func testMovingToTheNewSyncWarnsWhileTodaysSyncHasNotFinished() {
        XCTAssertNil(SyncEngineWords.moveBlocker(mirrorRunning: false, isSynced: false), "today's sync is off: nothing to wait for")
        XCTAssertNil(SyncEngineWords.moveBlocker(mirrorRunning: true, isSynced: true))
        XCTAssertNotNil(SyncEngineWords.moveBlocker(mirrorRunning: true, isSynced: false))
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
