import XCTest
import CloudKit
@testable import HITList

/// Brief 51: Shared Tasks. The merge rules (`SharedTasksMerge`), who may do what (`SharedTasksPermissions`), the
/// store's local edits and server copies on in-memory stores (`SharedTasksStore`), names and order, and the switch
/// that keeps all of it off by default (`SharedTasksPreference`). Nothing here touches CloudKit, the app group's
/// defaults or the task store.
@MainActor
final class SharedTasksTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_793_000_000) // 2026-10-26
    private var changes: [SharedTasksStore.Change] = []
    private let me = "_me000000000000000000000000000000"
    private let sam = "_sam00000000000000000000000000000"

    private func makeStore(me: String? = nil, profile: SharedProfile? = nil) -> SharedTasksStore {
        let store = SharedTasksStore(persistence: .memory, clock: { [unowned self] in now })
        store.onChanges = { [unowned self] in changes += $0 }
        if let me { store.setMe(me) }
        if let profile { store.setProfile(profile) }
        changes = []
        return store
    }

    private func at(_ seconds: TimeInterval) -> Date { SharedClock.stamp(now.addingTimeInterval(seconds)) }

    private func task(_ title: String = "Milk", titleAt: TimeInterval = 0, notes: String = "", notesAt: TimeInterval = 0,
                      completion: SharedCompletion? = nil, completionAt: TimeInterval = 0, id: UUID = UUID()) -> SharedTask {
        SharedTask(id: id, title: Stamped(title, at: at(titleAt)), notes: Stamped(notes, at: at(notesAt)),
                   priority: Stamped(4, at: at(0)), due: Stamped(nil, at: at(0)),
                   completion: Stamped(completion, at: at(completionAt)), createdAt: at(0), createdBy: sam, createdByName: "Sam")
    }

    /// A list someone else owns, joined by me, as fetched.
    private func joinedList(in store: SharedTasksStore, canWrite: Bool = true) -> UUID {
        let id = UUID()
        store.applyServerList(SharedListFields(title: Stamped("Groceries", at: at(0)), colorHex: Stamped("#FF0000", at: at(0)), createdAt: at(0)),
                              systemFields: nil, listID: id, scope: .joined, ownerName: sam)
        store.applyShare(SharedShareInfo(participants: [
            SharedParticipant(userID: sam, name: "Sam Jones", contact: nil, role: .owner, status: .accepted, canWrite: true, isCurrentUser: false),
            SharedParticipant(userID: me, name: "George T", contact: nil, role: .participant, status: .accepted, canWrite: canWrite, isCurrentUser: true),
        ], url: nil, archive: nil), listID: id, scope: .joined, ownerName: sam)
        changes = []
        return id
    }

    // MARK: - Merge

    func testEachFieldKeepsItsLatestValue() {
        let local = task("Oat milk", titleAt: 10, notes: "", notesAt: 0)
        let server = task("Milk", titleAt: 5, notes: "2 litres", notesAt: 20, id: local.id)
        let merged = SharedTasksMerge.task(local: local, server: server)
        XCTAssertEqual(merged.title.value, "Oat milk")
        XCTAssertEqual(merged.notes.value, "2 litres")
        XCTAssertTrue(SharedTasksMerge.differs(merged, from: server))
    }

    func testATieGivesTheSameAnswerWhicheverCopyIsLocal() {
        let a = task("Apples", titleAt: 3)
        let b = task("Bananas", titleAt: 3, id: a.id)
        XCTAssertEqual(SharedTasksMerge.task(local: a, server: b).title, SharedTasksMerge.task(local: b, server: a).title)
    }

    func testCompletionMovesAsOneUnit() {
        let done = SharedCompletion(at: at(10), by: sam, byName: "Sam")
        let completed = task(completion: done, completionAt: 10)
        let reopened = task(completion: nil, completionAt: 20, id: completed.id)
        let merged = SharedTasksMerge.task(local: completed, server: reopened)
        XCTAssertNil(merged.completion.value, "the later reopen wins, and takes who and when with it")
        let mergedBack = SharedTasksMerge.task(local: reopened, server: completed)
        XCTAssertEqual(mergedBack.completion, merged.completion)

        let laterDone = task(completion: SharedCompletion(at: at(30), by: me, byName: "George"), completionAt: 30, id: completed.id)
        XCTAssertEqual(SharedTasksMerge.task(local: laterDone, server: reopened).completion.value?.by, me)
    }

    func testWhenBothCompletedTheFirstCompletionIsKept() {
        let samDone = task(completion: SharedCompletion(at: at(2), by: sam, byName: "Sam"), completionAt: 2)
        let georgeDone = task(completion: SharedCompletion(at: at(5), by: me, byName: "George"), completionAt: 5, id: samDone.id)
        for merged in [SharedTasksMerge.task(local: samDone, server: georgeDone), SharedTasksMerge.task(local: georgeDone, server: samDone)] {
            XCTAssertEqual(merged.completion.value?.by, sam)
            XCTAssertEqual(merged.completion.value?.at, at(2))
        }
    }

    func testStampsAreWholeMillisecondsSoAServerEchoIsNotAChange() {
        let precise = Date(timeIntervalSince1970: 1_793_000_000.123_456_7)
        let stamped = SharedClock.stamp(precise)
        let echoed = Date(timeIntervalSince1970: 1_793_000_000.123) // what CloudKit gives back
        XCTAssertEqual(SharedClock.millis(stamped), SharedClock.millis(echoed))
        XCTAssertTrue(SharedTasksMerge.same(Stamped("a", at: stamped), Stamped("a", at: echoed)))
    }

    // MARK: - Permissions

    func testOwnerAndParticipantsEditButOnlyTheOwnerManagesTheList() {
        typealias P = SharedTasksPermissions
        for action in [P.Action.addTask, .editTask, .completeTask, .deleteTask] {
            XCTAssertTrue(P.allows(action, role: .owner, canWrite: true))
            XCTAssertTrue(P.allows(action, role: .participant, canWrite: true))
            XCTAssertFalse(P.allows(action, role: .participant, canWrite: false))
        }
        for action in [P.Action.renameList, .invite, .removeMember, .stopSharing, .deleteList] {
            XCTAssertTrue(P.allows(action, role: .owner, canWrite: true))
            XCTAssertFalse(P.allows(action, role: .participant, canWrite: true), "\(action)")
        }
        XCTAssertTrue(P.allows(.leave, role: .participant, canWrite: true))
        XCTAssertFalse(P.allows(.leave, role: .owner, canWrite: true))
    }

    func testAParticipantCannotRemoveMembersStopSharingRenameOrDelete() throws {
        let store = makeStore(me: me)
        let id = joinedList(in: store)
        XCTAssertThrowsError(try store.removeMember(sam, from: id)) { XCTAssertEqual($0 as? SharedTasksStore.StoreError, .notAllowed) }
        XCTAssertThrowsError(try store.stopSharing(id)) { XCTAssertEqual($0 as? SharedTasksStore.StoreError, .notAllowed) }
        XCTAssertThrowsError(try store.renameList(id, to: "Mine now")) { XCTAssertEqual($0 as? SharedTasksStore.StoreError, .notAllowed) }
        XCTAssertThrowsError(try store.deleteList(id)) { XCTAssertEqual($0 as? SharedTasksStore.StoreError, .notAllowed) }
        XCTAssertTrue(changes.isEmpty)
        try store.leave(id)
        XCTAssertNil(store.list(id))
        XCTAssertEqual(changes, [.leave(id, ownerName: sam)])
    }

    func testAReadOnlyParticipantCanOnlyLeave() throws {
        let store = makeStore(me: me)
        let id = joinedList(in: store, canWrite: false)
        XCTAssertThrowsError(try store.addTask(to: id, title: "Eggs"))
        XCTAssertNoThrow(try store.leave(id))
    }

    // MARK: - Local edits

    func testANewListSendsItsZoneItsRecordAndMyMemberRecord() throws {
        let store = makeStore(me: me, profile: SharedProfile(name: "George", nameChangedAt: at(-60), avatar: nil, avatarChangedAt: at(-60)))
        let list = try store.createList(title: "  Groceries  ")
        XCTAssertEqual(list.title, "Groceries")
        XCTAssertEqual(list.scope, .owned)
        XCTAssertEqual(list.ownerName, SharedTasksSchema.currentUserOwnerName)
        XCTAssertEqual(list.members.map(\.id), [me])
        XCTAssertEqual(list.members.first?.name.value, "George")
        XCTAssertEqual(changes, [.saveZone(list.id), .saveRecord(store.ref(list, "list")),
                                 .saveRecord(store.ref(list, SharedTasksSchema.memberRecordName(for: me)))])
        XCTAssertThrowsError(try store.createList(title: "   ")) { XCTAssertEqual($0 as? SharedTasksStore.StoreError, .emptyTitle) }
    }

    func testNothingIsWrittenBeforeTheAccountIsKnown() {
        let store = makeStore()
        XCTAssertThrowsError(try store.createList(title: "Groceries")) { XCTAssertEqual($0 as? SharedTasksStore.StoreError, .notReady) }
        XCTAssertTrue(changes.isEmpty)
    }

    func testAParticipantAddsCompletesReopensAndEdits() throws {
        let store = makeStore(me: me, profile: SharedProfile(name: "George", nameChangedAt: at(0), avatar: nil, avatarChangedAt: at(0)))
        let id = joinedList(in: store)
        let added = try store.addTask(to: id, title: "Eggs", priority: 2, due: SharedDue(date: at(86_400), hasTime: false))
        XCTAssertEqual(added.createdBy, me)
        let ref = store.ref(store.list(id)!, SharedTasksSchema.taskRecordName(for: added.id))
        XCTAssertEqual(ref.ownerName, sam)
        XCTAssertEqual(ref.scope, .joined)

        now = now.addingTimeInterval(30)
        try store.setCompleted(true, task: added.id, in: id)
        var done = try XCTUnwrap(store.list(id)?.task(added.id))
        XCTAssertEqual(done.completion.value, SharedCompletion(at: at(0), by: me, byName: "George"))
        XCTAssertEqual(done.completion.changedAt, at(0))

        now = now.addingTimeInterval(30)
        try store.setCompleted(false, task: added.id, in: id)
        done = try XCTUnwrap(store.list(id)?.task(added.id))
        XCTAssertNil(done.completion.value)

        try store.setTitle("Free-range eggs", task: added.id, in: id)
        try store.setTitle("Free-range eggs", task: added.id, in: id) // unchanged: nothing sent
        XCTAssertEqual(store.list(id)?.task(added.id)?.title.value, "Free-range eggs")
        XCTAssertEqual(changes, Array(repeating: .saveRecord(ref), count: 4))
    }

    // MARK: - Server copies

    func testAServerCopyMergesWithAnEditNotSentYetAndAsksToSaveAgain() throws {
        let store = makeStore(me: me)
        let id = joinedList(in: store)
        let original = task("Milk", titleAt: 0)
        store.applyServerTask(original, listID: id, scope: .joined, ownerName: sam)
        now = now.addingTimeInterval(10)
        try store.setTitle("Oat milk", task: original.id, in: id) // mine, at +10, not sent yet
        changes = []
        var server = task("Milk", titleAt: 0, notes: "2 litres", notesAt: 20, id: original.id) // Sam's notes at +20
        server.systemFields = Data([1, 2, 3])
        XCTAssertTrue(store.applyServerTask(server, listID: id, scope: .joined, ownerName: sam))
        let merged = try XCTUnwrap(store.list(id)?.task(original.id))
        XCTAssertEqual(merged.title.value, "Oat milk")
        XCTAssertEqual(merged.notes.value, "2 litres")
        XCTAssertEqual(merged.systemFields, Data([1, 2, 3]), "the next save carries the server's change tag")
        XCTAssertEqual(changes, [.saveRecord(store.ref(store.list(id)!, SharedTasksSchema.taskRecordName(for: original.id)))])

        changes = []
        XCTAssertFalse(store.applyServerTask(merged, listID: id, scope: .joined, ownerName: sam), "the echo of our own save is no change")
        XCTAssertTrue(changes.isEmpty)
    }

    func testADeleteWinsOverAnEditMadeAtTheSameTime() throws {
        let store = makeStore(me: me)
        let id = joinedList(in: store)
        let original = task("Milk")
        store.applyServerTask(original, listID: id, scope: .joined, ownerName: sam)
        try store.deleteTask(original.id, in: id)
        // Sam's edit, made before Sam saw the delete, arrives: it does not bring the task back.
        store.applyServerTask(task("Oat milk", titleAt: 99, id: original.id), listID: id, scope: .joined, ownerName: sam)
        XCTAssertNil(store.list(id)?.task(original.id))
        store.applyDeletionConfirmed(recordName: SharedTasksSchema.taskRecordName(for: original.id), listID: id)
        XCTAssertEqual(store.list(id)?.deletedTaskIDs, [])

        // The other way round: Sam deleted it while I was editing it.
        let second = task("Bread")
        store.applyServerTask(second, listID: id, scope: .joined, ownerName: sam)
        try store.setTitle("Rye bread", task: second.id, in: id)
        store.applyDeletedRecord(named: SharedTasksSchema.taskRecordName(for: second.id), listID: id)
        XCTAssertNil(store.list(id)?.task(second.id))
        // And a save of mine that finds it gone drops it too.
        let third = task("Jam")
        store.applyServerTask(third, listID: id, scope: .joined, ownerName: sam)
        store.applyMissingOnServer(recordName: SharedTasksSchema.taskRecordName(for: third.id), listID: id)
        XCTAssertNil(store.list(id)?.task(third.id))
    }

    func testAListWhoseZoneIsGoneLeavesThisDevice() {
        let store = makeStore(me: me)
        let id = joinedList(in: store)
        store.applyDeletedZone(id)
        XCTAssertNil(store.list(id))
    }

    func testOtherPeoplesMemberRecordsAreTakenAsTheyAre() {
        let store = makeStore(me: me)
        let id = joinedList(in: store)
        let samMember = SharedMember(id: sam, name: Stamped("Sam", at: at(5)), avatar: .unset(nil), joinedAt: at(0))
        XCTAssertFalse(store.applyServerMember(samMember, listID: id, scope: .joined, ownerName: sam))
        var renamed = samMember
        renamed.name = Stamped("Samantha", at: at(1)) // older stamp, but it is Sam's own record
        XCTAssertFalse(store.applyServerMember(renamed, listID: id, scope: .joined, ownerName: sam))
        XCTAssertEqual(store.list(id)?.member(sam)?.name.value, "Samantha")
        XCTAssertTrue(changes.isEmpty)
    }

    // MARK: - Owner actions

    func testTheOwnerRemovesSomeoneAndStopsSharing() throws {
        let store = makeStore(me: me)
        let list = try store.createList(title: "Chores")
        store.applyShare(SharedShareInfo(participants: [
            SharedParticipant(userID: me, name: nil, contact: nil, role: .owner, status: .accepted, canWrite: true, isCurrentUser: true),
            SharedParticipant(userID: sam, name: "Sam", contact: nil, role: .participant, status: .accepted, canWrite: true, isCurrentUser: false),
        ], url: nil, archive: nil), listID: list.id, scope: .owned, ownerName: list.ownerName)
        store.applyServerMember(SharedMember(id: sam, name: Stamped("Sam", at: at(0)), avatar: .unset(nil), joinedAt: at(0)),
                                listID: list.id, scope: .owned, ownerName: list.ownerName)
        changes = []
        XCTAssertThrowsError(try store.removeMember(me, from: list.id), "the owner can't remove themselves")
        try store.removeMember(sam, from: list.id)
        XCTAssertNil(store.list(list.id)?.member(sam))
        XCTAssertEqual(changes, [.removeParticipant(list.id, sam), .deleteRecord(store.ref(list, SharedTasksSchema.memberRecordName(for: sam)))])

        changes = []
        try store.stopSharing(list.id)
        XCTAssertNil(store.list(list.id)?.share)
        XCTAssertEqual(store.list(list.id)?.members.map(\.id), [me], "the owner keeps the list")
        XCTAssertEqual(changes, [.stopSharing(list.id)])
        XCTAssertThrowsError(try store.leave(list.id), "an owner stops sharing or deletes; they don't leave")
        try store.deleteList(list.id)
        XCTAssertEqual(changes.last, .deleteZone(list.id))
    }

    // MARK: - Profile and account

    func testMyMemberRecordsFollowMyProfileAndAnUnchangedProfileWritesNothing() throws {
        let store = makeStore(me: me, profile: SharedProfile(name: "George", nameChangedAt: at(0), avatar: nil, avatarChangedAt: at(0)))
        let mine = try store.createList(title: "Chores")
        let joined = joinedList(in: store)
        // Joined before my member record was written there: the same profile writes it once, then never again.
        store.setProfile(SharedProfile(name: "George", nameChangedAt: at(0), avatar: nil, avatarChangedAt: at(0)))
        XCTAssertEqual(changes, [.saveRecord(store.ref(store.list(joined)!, SharedTasksSchema.memberRecordName(for: me)))])
        changes = []
        store.setProfile(SharedProfile(name: "George", nameChangedAt: at(0), avatar: nil, avatarChangedAt: at(0)))
        XCTAssertTrue(changes.isEmpty)
        store.setProfile(SharedProfile(name: "George T", nameChangedAt: at(100), avatar: Data([9]), avatarChangedAt: at(100)))
        XCTAssertEqual(store.list(mine.id)?.member(me)?.name.value, "George T")
        XCTAssertEqual(store.list(joined)?.member(me)?.avatar.value, Data([9]))
        XCTAssertEqual(Set(changes), [.saveRecord(store.ref(store.list(mine.id)!, SharedTasksSchema.memberRecordName(for: me))),
                                      .saveRecord(store.ref(store.list(joined)!, SharedTasksSchema.memberRecordName(for: me)))])
    }

    func testAnotherAppleAccountStartsFromNothing() throws {
        let store = makeStore(me: me)
        _ = try store.createList(title: "Chores")
        store.setMe(me)
        XCTAssertEqual(store.lists.count, 1)
        store.setMe(sam)
        XCTAssertEqual(store.lists.count, 0)
        XCTAssertEqual(store.me, sam)
    }

    // MARK: - File

    func testTheFileKeepsEverythingAndAnUnreadableOneIsMovedAside() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SharedTasksTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "SharedTasks-test.json")
        let store = SharedTasksStore(persistence: .file(url), clock: { [unowned self] in now })
        store.setMe(me)
        let list = try store.createList(title: "Chores")
        _ = try store.addTask(to: list.id, title: "Bins", due: SharedDue(date: at(3600), hasTime: true))
        store.setEngineState(Data([7, 7]), for: .owned)

        let reopened = SharedTasksStore(persistence: .file(url))
        XCTAssertEqual(reopened.state, store.state)
        XCTAssertNil(reopened.loadProblem)

        try Data("not json".utf8).write(to: url)
        let damaged = SharedTasksStore(persistence: .file(url))
        XCTAssertTrue(damaged.lists.isEmpty)
        XCTAssertNotNil(damaged.loadProblem)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("SharedTasks-test-unreadable-") }, "\(files)")
    }

    // MARK: - Names, faces, order

    func testCompletedByNamesYouAProfileOrTheNameKeptWithIt() throws {
        let store = makeStore(me: me)
        let id = joinedList(in: store)
        store.applyServerMember(SharedMember(id: sam, name: Stamped("Sam", at: at(0)), avatar: .unset(nil), joinedAt: at(0)),
                                listID: id, scope: .joined, ownerName: sam)
        let list = try XCTUnwrap(store.list(id))
        XCTAssertEqual(SharedPeople.completedBy(task(completion: SharedCompletion(at: at(0), by: sam, byName: "Old")), in: list, me: me), "Completed by Sam")
        XCTAssertEqual(SharedPeople.completedBy(task(completion: SharedCompletion(at: at(0), by: me, byName: "George")), in: list, me: me), "Completed by you")
        XCTAssertEqual(SharedPeople.completedBy(task(completion: SharedCompletion(at: at(0), by: "_gone", byName: "Alex")), in: list, me: me), "Completed by Alex")
        XCTAssertNil(SharedPeople.completedBy(task(), in: list, me: me))
    }

    func testPeopleAreOwnerThenMeThenOthersThenInvitations() {
        let store = makeStore(me: me)
        let id = UUID()
        store.applyServerList(SharedListFields(title: Stamped("Trip", at: at(0)), colorHex: Stamped("#00FF00", at: at(0)), createdAt: at(0)),
                              systemFields: nil, listID: id, scope: .joined, ownerName: sam)
        store.applyShare(SharedShareInfo(participants: [
            SharedParticipant(userID: "_zoe", name: "Zoe", contact: nil, role: .participant, status: .accepted, canWrite: true, isCurrentUser: false),
            SharedParticipant(userID: nil, name: nil, contact: "kim@example.com", role: .participant, status: .pending, canWrite: true, isCurrentUser: false),
            SharedParticipant(userID: me, name: "George T", contact: nil, role: .participant, status: .accepted, canWrite: true, isCurrentUser: true),
            SharedParticipant(userID: "_amy", name: "Amy", contact: nil, role: .participant, status: .accepted, canWrite: true, isCurrentUser: false),
            SharedParticipant(userID: sam, name: "Sam Jones", contact: nil, role: .owner, status: .accepted, canWrite: true, isCurrentUser: false),
        ], url: nil, archive: nil), listID: id, scope: .joined, ownerName: sam)
        store.applyServerMember(SharedMember(id: sam, name: Stamped("Sam", at: at(0)), avatar: .unset(Data([1])), joinedAt: at(0)),
                                listID: id, scope: .joined, ownerName: sam)
        let people = SharedPeople.people(in: store.list(id)!, me: me)
        XCTAssertEqual(people.map(\.name), ["Sam", "George T", "Amy", "Zoe", "kim@example.com"])
        XCTAssertEqual(people.map(\.isOwner), [true, false, false, false, false])
        XCTAssertEqual(people.map(\.isMe), [false, true, false, false, false])
        XCTAssertEqual(people.last?.isPending, true)
        XCTAssertEqual(people.first?.avatar, Data([1]))
    }

    func testOpenTasksByPriorityAndDueThenCompletedNewestFirst() {
        func t(_ title: String, p: Int, due: TimeInterval?, done: TimeInterval? = nil, created: TimeInterval = 0) -> SharedTask {
            var x = task(title, completion: done.map { SharedCompletion(at: at($0), by: me, byName: "") })
            x.priority = Stamped(p, at: at(0))
            x.due = Stamped(due.map { SharedDue(date: at($0), hasTime: false) }, at: at(0))
            x.createdAt = at(created)
            return x
        }
        let sorted = SharedTaskOrdering.sorted([
            t("p4 later", p: 4, due: 200), t("done first", p: 1, due: nil, done: 10), t("p1 undated", p: 1, due: nil),
            t("p4 sooner", p: 4, due: 100), t("p1 dated", p: 1, due: 500), t("done last", p: 4, due: nil, done: 20),
            t("p4 undated new", p: 4, due: nil, created: 9), t("p4 undated old", p: 4, due: nil, created: 1),
        ])
        XCTAssertEqual(sorted.map(\.title.value), ["p1 dated", "p1 undated", "p4 sooner", "p4 later", "p4 undated old",
                                                   "p4 undated new", "done last", "done first"])
    }

    // MARK: - Switch, files, names

    func testTheSwitchIsOffByDefaultAndPerStore() throws {
        let suite = "SharedTasksTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(SharedTasksPreference.isOn(in: defaults, storeName: "HITList.store"))
        SharedTasksPreference.set(true, in: defaults, storeName: "HITList-Development.store")
        XCTAssertTrue(SharedTasksPreference.isOn(in: defaults, storeName: "HITList-Development.store"))
        XCTAssertFalse(SharedTasksPreference.isOn(in: defaults, storeName: "HITList.store"), "a Debug build never switches TestFlight's on")
        SharedTasksPreference.set(false, in: defaults, storeName: "HITList-Development.store")
        XCTAssertNil(defaults.object(forKey: SharedTasksPreference.key(storeName: "HITList-Development.store")))
    }

    func testEachTaskStoreHasItsOwnSharedListsFile() {
        XCTAssertEqual(SharedTasksPreference.fileName(storeName: "HITList.store"), "SharedTasks.json")
        XCTAssertEqual(SharedTasksPreference.fileName(storeName: "HITList-Development.store"), "SharedTasks-Development.json")
        XCTAssertEqual(SharedTasksPreference.fileName(storeName: "HITList-s51.store"), "SharedTasks-s51.json")
    }

    func testRecordNamesRoundTripAndMatchCloudKit() {
        let id = UUID()
        XCTAssertEqual(SharedTasksSchema.listID(fromZoneName: SharedTasksSchema.zoneName(for: id)), id)
        XCTAssertNil(SharedTasksSchema.listID(fromZoneName: "com.apple.coredata.cloudkit.zone"))
        XCTAssertEqual(SharedTasksSchema.taskID(fromRecordName: SharedTasksSchema.taskRecordName(for: id)), id)
        XCTAssertEqual(SharedTasksSchema.memberID(fromRecordName: SharedTasksSchema.memberRecordName(for: sam)), sam)
        XCTAssertNil(SharedTasksSchema.memberID(fromRecordName: "member-"))
        XCTAssertEqual(SharedTasksSchema.currentUserOwnerName, CKCurrentUserDefaultName)
        XCTAssertEqual(SharedTasksSchema.zoneWideShareRecordName, CKRecordNameZoneWideShare)
        XCTAssertNotEqual(SharedTasksSchema.containerID, HITListSchema.cloudKitContainerID)
    }
}
