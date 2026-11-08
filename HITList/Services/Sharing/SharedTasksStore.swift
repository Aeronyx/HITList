import Foundation
import Observation
import OSLog

/// The shared lists on this device (brief 51): one `SharedTasksState` kept in memory and, outside tests, in one
/// JSON file per task store (`SharedTasksPreference.fileURL`). Never SwiftData: a `ModelContext` save anywhere in
/// the process reaches `CloudSyncMonitor` and its watchdog, which belong to the task store alone.
///
/// Local edits check `SharedTasksPermissions`, stamp each changed field (`SharedClock`), save the file and tell the
/// sync layer what to send (`onChanges`). Server copies come back through the `apply…` calls, which merge them with
/// what is here (`SharedTasksMerge`) and ask for a save again when the merged copy holds something newer.
@MainActor
@Observable
final class SharedTasksStore {
    enum Persistence: Equatable {
        case memory
        case file(URL)
    }

    enum StoreError: Error, Equatable, LocalizedError {
        case notAllowed
        case noSuchList
        case noSuchTask
        case emptyTitle
        /// This account's identity in the shared container isn't known yet (never fetched; offline at first use).
        case notReady

        var errorDescription: String? {
            switch self {
            case .notAllowed: "Only the list's owner can do that."
            case .noSuchList: "That list isn't here any more."
            case .noSuchTask: "That task isn't here any more."
            case .emptyTitle: "Give it a name first."
            case .notReady: "Shared Tasks is still connecting to iCloud. Try again in a moment."
            }
        }
    }

    /// A record in a list's zone.
    struct RecordRef: Hashable, Sendable {
        var listID: UUID
        var scope: SharedListScope
        var ownerName: String
        var recordName: String
    }

    /// What the sync layer has to send after a local edit.
    enum Change: Hashable, Sendable {
        /// A new list of mine: its zone.
        case saveZone(UUID)
        /// My list deleted, for everyone.
        case deleteZone(UUID)
        case saveRecord(RecordRef)
        case deleteRecord(RecordRef)
        /// My list stops being shared: its CKShare is deleted.
        case stopSharing(UUID)
        /// I leave a list I joined: the CKShare is deleted from my shared database.
        case leave(UUID, ownerName: String)
        /// The owner takes someone off the list's CKShare.
        case removeParticipant(UUID, SharedMemberID)
    }

    nonisolated static let defaultColor = "#5E81F4"
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sharing")

    private(set) var state: SharedTasksState
    /// Why the file couldn't be read at launch (it was moved aside and the lists come back from iCloud).
    private(set) var loadProblem: String?
    @ObservationIgnored let persistence: Persistence
    @ObservationIgnored var clock: () -> Date
    /// Told about every local change, in order; the sync layer queues them for CloudKit.
    @ObservationIgnored var onChanges: (([Change]) -> Void)?
    /// Told whenever the state was saved, local changes and fetched ones alike: the badge and the morning summary
    /// count shared tasks (brief 64).
    @ObservationIgnored var onSave: (() -> Void)?
    @ObservationIgnored private var batchDepth = 0
    @ObservationIgnored private var batchedChanges: [Change] = []
    @ObservationIgnored private var batchDirty = false

    init(persistence: Persistence, clock: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.clock = clock
        switch persistence {
        case .memory:
            state = SharedTasksState()
        case .file(let url):
            let loaded = Self.load(from: url)
            state = loaded.state
            loadProblem = loaded.problem
        }
    }

    var lists: [SharedList] { state.lists }
    var me: SharedMemberID? { state.me }
    /// The set of people a task was last added to here (brief 64).
    var lastUsedListID: UUID? { state.lastUsedListID }
    var profile: SharedProfile? { state.profile }

    func list(_ id: UUID) -> SharedList? { state.lists.first { $0.id == id } }

    /// Lists by name, mine and joined together.
    var sortedLists: [SharedList] {
        state.lists.sorted {
            let order = $0.title.localizedCaseInsensitiveCompare($1.title)
            return order != .orderedSame ? order == .orderedAscending : $0.id.uuidString < $1.id.uuidString
        }
    }

    // MARK: - Lists

    @discardableResult
    func createList(title: String, colorHex: String = SharedTasksStore.defaultColor) throws -> SharedList {
        guard let me = state.me else { throw StoreError.notReady }
        let title = Self.clean(title)
        guard !title.isEmpty else { throw StoreError.emptyTitle }
        let t = now()
        var list = SharedList(id: UUID(), scope: .owned, ownerName: SharedTasksSchema.currentUserOwnerName,
                              fields: SharedListFields(title: Stamped(title, at: t), colorHex: Stamped(colorHex, at: t), createdAt: t))
        list.members = [newMember(me, joinedAt: t)]
        state.lists.append(list)
        commit([.saveZone(list.id), .saveRecord(ref(list, SharedTasksSchema.listRecordName)),
                .saveRecord(ref(list, SharedTasksSchema.memberRecordName(for: me)))])
        return list
    }

    func renameList(_ id: UUID, to title: String) throws {
        let i = try index(of: id)
        try require(.renameList, state.lists[i])
        let title = Self.clean(title)
        guard !title.isEmpty else { throw StoreError.emptyTitle }
        guard title != state.lists[i].title else { return }
        state.lists[i].fields.title = Stamped(title, at: now())
        commit([.saveRecord(ref(state.lists[i], SharedTasksSchema.listRecordName))])
    }

    /// The owner deletes the list for everyone (its zone).
    func deleteList(_ id: UUID) throws {
        let i = try index(of: id)
        try require(.deleteList, state.lists[i])
        state.lists.remove(at: i)
        commit([.deleteZone(id)])
    }

    /// A participant leaves; the list goes from this device at once.
    func leave(_ id: UUID) throws {
        let i = try index(of: id)
        try require(.leave, state.lists[i])
        let list = state.lists.remove(at: i)
        commit([.leave(id, ownerName: list.ownerName)])
    }

    /// The owner stops sharing: everyone else loses the list, the owner keeps it, unshared. Their member records
    /// go too.
    func stopSharing(_ id: UUID) throws {
        let i = try index(of: id)
        try require(.stopSharing, state.lists[i])
        var changes: [Change] = [.stopSharing(id)]
        let me = state.me
        let others = state.lists[i].members.filter { $0.id != me }
        for member in others { changes.append(.deleteRecord(ref(state.lists[i], SharedTasksSchema.memberRecordName(for: member.id)))) }
        state.lists[i].members.removeAll { $0.id != me }
        state.lists[i].share = nil
        commit(changes)
    }

    /// The owner takes someone off the list.
    func removeMember(_ memberID: SharedMemberID, from listID: UUID) throws {
        let i = try index(of: listID)
        try require(.removeMember, state.lists[i])
        guard memberID != state.me else { throw StoreError.notAllowed }
        state.lists[i].members.removeAll { $0.id == memberID }
        if var share = state.lists[i].share {
            share.participants.removeAll { $0.userID == memberID }
            state.lists[i].share = share
        }
        commit([.removeParticipant(listID, memberID),
                .deleteRecord(ref(state.lists[i], SharedTasksSchema.memberRecordName(for: memberID)))])
    }

    // MARK: - Tasks

    @discardableResult
    func addTask(to listID: UUID, title: String, notes: String = "", priority: Int = 4, due: SharedDue? = nil) throws -> SharedTask {
        let i = try index(of: listID)
        try require(.addTask, state.lists[i])
        guard let me = state.me else { throw StoreError.notReady }
        let title = Self.clean(title)
        guard !title.isEmpty else { throw StoreError.emptyTitle }
        let t = now()
        let task = SharedTask(id: UUID(), title: Stamped(title, at: t), notes: Stamped(notes, at: t),
                              priority: Stamped(Self.clampPriority(priority), at: t), due: Stamped(due.map(Self.normalized), at: t),
                              completion: Stamped(nil, at: t), createdAt: t, createdBy: me, createdByName: myName)
        state.lists[i].tasks.append(task)
        state.lastUsedListID = listID
        commit([.saveRecord(ref(state.lists[i], SharedTasksSchema.taskRecordName(for: task.id)))])
        return task
    }

    func setTitle(_ title: String, task taskID: UUID, in listID: UUID) throws {
        let title = Self.clean(title)
        guard !title.isEmpty else { throw StoreError.emptyTitle }
        try editTask(taskID, in: listID, action: .editTask) { task, t in
            guard task.title.value != title else { return false }
            task.title = Stamped(title, at: t)
            return true
        }
    }

    func setNotes(_ notes: String, task taskID: UUID, in listID: UUID) throws {
        try editTask(taskID, in: listID, action: .editTask) { task, t in
            guard task.notes.value != notes else { return false }
            task.notes = Stamped(notes, at: t)
            return true
        }
    }

    func setPriority(_ priority: Int, task taskID: UUID, in listID: UUID) throws {
        let priority = Self.clampPriority(priority)
        try editTask(taskID, in: listID, action: .editTask) { task, t in
            guard task.priority.value != priority else { return false }
            task.priority = Stamped(priority, at: t)
            return true
        }
    }

    func setDue(_ due: SharedDue?, task taskID: UUID, in listID: UUID) throws {
        let due = due.map(Self.normalized)
        try editTask(taskID, in: listID, action: .editTask) { task, t in
            guard task.due.value != due else { return false }
            task.due = Stamped(due, at: t)
            return true
        }
    }

    /// Completes (who: me, when: now) or reopens a task. Who and when move with the state, never apart.
    func setCompleted(_ completed: Bool, task taskID: UUID, in listID: UUID) throws {
        guard let me = state.me else { throw StoreError.notReady }
        let name = myName
        try editTask(taskID, in: listID, action: .completeTask) { task, t in
            guard task.isCompleted != completed else { return false }
            task.completion = Stamped(completed ? SharedCompletion(at: t, by: me, byName: name) : nil, at: t)
            return true
        }
    }

    func deleteTask(_ taskID: UUID, in listID: UUID) throws {
        let i = try index(of: listID)
        try require(.deleteTask, state.lists[i])
        guard let at = state.lists[i].tasks.firstIndex(where: { $0.id == taskID }) else { throw StoreError.noSuchTask }
        state.lists[i].tasks.remove(at: at)
        state.lists[i].deletedTaskIDs.insert(taskID)
        commit([.deleteRecord(ref(state.lists[i], SharedTasksSchema.taskRecordName(for: taskID)))])
    }

    // MARK: - Me

    /// This account's user record name in the shared container. A different one than before means another Apple
    /// account: everything kept here belonged to the previous one and goes.
    func setMe(_ id: SharedMemberID) {
        guard state.me != id else { return }
        if state.me != nil {
            Self.log.notice("Shared Tasks: another iCloud account; the previous account's shared lists are cleared from this device")
            state = SharedTasksState()
        }
        state.me = id
        save()
    }

    /// The profile this person shows others. When it changed, their member record in every list is written again;
    /// an unchanged profile writes nothing.
    func setProfile(_ profile: SharedProfile) {
        let profile = SharedProfile(name: profile.name, nameChangedAt: SharedClock.stamp(profile.nameChangedAt),
                                    avatar: profile.avatar, avatarChangedAt: SharedClock.stamp(profile.avatarChangedAt))
        guard let me = state.me else {
            if state.profile != profile { state.profile = profile; save() }
            return
        }
        state.profile = profile
        var changes: [Change] = []
        for i in state.lists.indices {
            let current = state.lists[i].member(me)
            var updated = current ?? newMember(me, joinedAt: now())
            updated.name = SharedTasksMerge.pick(updated.name, Stamped(profile.name, at: profile.nameChangedAt))
            updated.avatar = SharedTasksMerge.pick(updated.avatar, Stamped(profile.avatar, at: profile.avatarChangedAt))
            guard current.map({ SharedTasksMerge.differs(updated, from: $0) }) ?? true else { continue }
            if let at = state.lists[i].members.firstIndex(where: { $0.id == me }) {
                state.lists[i].members[at] = updated
            } else {
                state.lists[i].members.append(updated)
            }
            changes.append(.saveRecord(ref(state.lists[i], SharedTasksSchema.memberRecordName(for: me))))
        }
        commit(changes)
    }

    /// Forgets everything: the account signed out or changed.
    func forgetAll() {
        state = SharedTasksState()
        save()
    }

    // MARK: - CloudKit state

    func engineState(for scope: SharedListScope) -> Data? { state.engineStates[scope.rawValue] }

    func setEngineState(_ data: Data?, for scope: SharedListScope) {
        guard state.engineStates[scope.rawValue] != data else { return }
        state.engineStates[scope.rawValue] = data
        save()
    }

    // MARK: - Server copies

    /// Applies a run of server changes with one file write and one change notice at the end.
    func batch(_ body: () -> Void) {
        batchDepth += 1
        body()
        batchDepth -= 1
        if batchDepth == 0 { flushBatch() }
    }

    /// A list known from its zone (fetched, or a share just accepted) before its record arrives. Returns whether it
    /// was new here.
    @discardableResult
    func ensureList(_ id: UUID, scope: SharedListScope, ownerName: String, title: String? = nil) -> Bool {
        guard list(id) == nil else { return false }
        let fields = SharedListFields(title: .unset(title ?? ""), colorHex: .unset(Self.defaultColor), createdAt: now())
        state.lists.append(SharedList(id: id, scope: scope, ownerName: ownerName, fields: fields))
        save()
        return true
    }

    /// The list record as the server has it. Returns whether the merged copy has to be saved again.
    @discardableResult
    func applyServerList(_ server: SharedListFields, systemFields: Data?, listID: UUID, scope: SharedListScope, ownerName: String) -> Bool {
        ensureList(listID, scope: scope, ownerName: ownerName)
        guard let i = state.lists.firstIndex(where: { $0.id == listID }) else { return false }
        let merged = SharedTasksMerge.list(local: state.lists[i].fields, server: server)
        state.lists[i].fields = merged
        state.lists[i].systemFields = systemFields
        let resave = SharedTasksMerge.differs(merged, from: server)
        if resave { queue(.saveRecord(ref(state.lists[i], SharedTasksSchema.listRecordName))) } else { save() }
        return resave
    }

    /// A task as the server has it, fetched or returned by a failed save. A task deleted here and not yet confirmed
    /// gone stays deleted. Returns whether the merged copy has to be saved again.
    @discardableResult
    func applyServerTask(_ server: SharedTask, listID: UUID, scope: SharedListScope, ownerName: String) -> Bool {
        ensureList(listID, scope: scope, ownerName: ownerName)
        guard let i = state.lists.firstIndex(where: { $0.id == listID }),
              !state.lists[i].deletedTaskIDs.contains(server.id) else { return false }
        if let at = state.lists[i].tasks.firstIndex(where: { $0.id == server.id }) {
            var merged = SharedTasksMerge.task(local: state.lists[i].tasks[at], server: server)
            merged.systemFields = server.systemFields
            state.lists[i].tasks[at] = merged
            if SharedTasksMerge.differs(merged, from: server) {
                queue(.saveRecord(ref(state.lists[i], SharedTasksSchema.taskRecordName(for: server.id))))
                return true
            }
        } else {
            state.lists[i].tasks.append(server)
        }
        save()
        return false
    }

    /// A member record as the server has it. Returns whether the merged copy has to be saved again (only ever
    /// my own record: someone else's is theirs to write).
    @discardableResult
    func applyServerMember(_ server: SharedMember, listID: UUID, scope: SharedListScope, ownerName: String) -> Bool {
        ensureList(listID, scope: scope, ownerName: ownerName)
        guard let i = state.lists.firstIndex(where: { $0.id == listID }) else { return false }
        if let at = state.lists[i].members.firstIndex(where: { $0.id == server.id }) {
            var merged = server.id == state.me ? SharedTasksMerge.member(local: state.lists[i].members[at], server: server) : server
            merged.systemFields = server.systemFields
            state.lists[i].members[at] = merged
            if server.id == state.me, SharedTasksMerge.differs(merged, from: server) {
                queue(.saveRecord(ref(state.lists[i], SharedTasksSchema.memberRecordName(for: server.id))))
                return true
            }
        } else {
            state.lists[i].members.append(server)
        }
        save()
        return false
    }

    /// The list's CKShare as fetched or saved; nil when the owner stopped sharing.
    func applyShare(_ info: SharedShareInfo?, listID: UUID, scope: SharedListScope, ownerName: String) {
        ensureList(listID, scope: scope, ownerName: ownerName)
        guard let i = state.lists.firstIndex(where: { $0.id == listID }), state.lists[i].share != info else { return }
        state.lists[i].share = info
        save()
    }

    /// A record deleted on the server (fetched): a task or member goes; a deleted share means my list is no longer
    /// shared. A task I was editing goes too: a delete wins.
    func applyDeletedRecord(named recordName: String, listID: UUID) {
        guard let i = state.lists.firstIndex(where: { $0.id == listID }) else { return }
        if let taskID = SharedTasksSchema.taskID(fromRecordName: recordName) {
            state.lists[i].tasks.removeAll { $0.id == taskID }
            state.lists[i].deletedTaskIDs.remove(taskID)
        } else if let memberID = SharedTasksSchema.memberID(fromRecordName: recordName) {
            state.lists[i].members.removeAll { $0.id == memberID }
        } else if recordName == SharedTasksSchema.zoneWideShareRecordName {
            state.lists[i].share = nil
        }
        save()
    }

    /// The list's zone is gone from this account's database: deleted by its owner, or I was removed or left.
    func applyDeletedZone(_ listID: UUID) {
        guard state.lists.contains(where: { $0.id == listID }) else { return }
        state.lists.removeAll { $0.id == listID }
        save()
    }

    /// A record saved: keep the server's system fields for the next save; a confirmed deletion ends its tombstone.
    func applySaved(recordName: String, listID: UUID, systemFields: Data) {
        guard let i = state.lists.firstIndex(where: { $0.id == listID }) else { return }
        if recordName == SharedTasksSchema.listRecordName {
            state.lists[i].systemFields = systemFields
        } else if let taskID = SharedTasksSchema.taskID(fromRecordName: recordName),
                  let at = state.lists[i].tasks.firstIndex(where: { $0.id == taskID }) {
            state.lists[i].tasks[at].systemFields = systemFields
        } else if let memberID = SharedTasksSchema.memberID(fromRecordName: recordName),
                  let at = state.lists[i].members.firstIndex(where: { $0.id == memberID }) {
            state.lists[i].members[at].systemFields = systemFields
        }
        save()
    }

    func applyDeletionConfirmed(recordName: String, listID: UUID) {
        guard let taskID = SharedTasksSchema.taskID(fromRecordName: recordName),
              let i = state.lists.firstIndex(where: { $0.id == listID }),
              state.lists[i].deletedTaskIDs.contains(taskID) else { return }
        state.lists[i].deletedTaskIDs.remove(taskID)
        save()
    }

    /// A save failed because the record no longer exists on the server. A task was deleted by someone else, so it
    /// goes here too (a delete wins). The list record or my member record is written again from scratch.
    func applyMissingOnServer(recordName: String, listID: UUID) {
        guard let i = state.lists.firstIndex(where: { $0.id == listID }) else { return }
        if let taskID = SharedTasksSchema.taskID(fromRecordName: recordName) {
            state.lists[i].tasks.removeAll { $0.id == taskID }
            save()
        } else if recordName == SharedTasksSchema.listRecordName, state.lists[i].isOwned {
            state.lists[i].systemFields = nil
            queue(.saveRecord(ref(state.lists[i], recordName)))
        } else if let memberID = SharedTasksSchema.memberID(fromRecordName: recordName), memberID == state.me,
                  let at = state.lists[i].members.firstIndex(where: { $0.id == memberID }) {
            state.lists[i].members[at].systemFields = nil
            queue(.saveRecord(ref(state.lists[i], recordName)))
        } else {
            save()
        }
    }

    /// What a pending save sends: the current local copy behind `ref`, or nil when it is gone.
    enum RecordValue: Equatable {
        case list(SharedList)
        case task(SharedTask, in: SharedList)
        case member(SharedMember, in: SharedList)
    }

    func value(for ref: RecordRef) -> RecordValue? {
        guard let list = list(ref.listID) else { return nil }
        if ref.recordName == SharedTasksSchema.listRecordName { return list.isOwned ? .list(list) : nil }
        if let taskID = SharedTasksSchema.taskID(fromRecordName: ref.recordName) {
            return list.task(taskID).map { .task($0, in: list) }
        }
        if let memberID = SharedTasksSchema.memberID(fromRecordName: ref.recordName) {
            // Only my own member record is ever sent from here.
            return memberID == state.me ? list.member(memberID).map { .member($0, in: list) } : nil
        }
        return nil
    }

    func ref(_ list: SharedList, _ recordName: String) -> RecordRef {
        RecordRef(listID: list.id, scope: list.scope, ownerName: list.ownerName, recordName: recordName)
    }

    // MARK: - Helpers

    private var myName: String { state.profile?.name ?? "" }

    private func now() -> Date { SharedClock.stamp(clock()) }

    private func newMember(_ id: SharedMemberID, joinedAt: Date) -> SharedMember {
        let profile = state.profile
        return SharedMember(id: id, name: profile.map { Stamped($0.name, at: $0.nameChangedAt) } ?? .unset(""),
                            avatar: profile.map { Stamped($0.avatar, at: $0.avatarChangedAt) } ?? .unset(nil), joinedAt: joinedAt)
    }

    private func index(of listID: UUID) throws -> Int {
        guard let i = state.lists.firstIndex(where: { $0.id == listID }) else { throw StoreError.noSuchList }
        return i
    }

    private func require(_ action: SharedTasksPermissions.Action, _ list: SharedList) throws {
        guard SharedTasksPermissions.allows(action, in: list) else { throw StoreError.notAllowed }
    }

    private func editTask(_ taskID: UUID, in listID: UUID, action: SharedTasksPermissions.Action,
                          _ change: (inout SharedTask, Date) -> Bool) throws {
        let i = try index(of: listID)
        try require(action, state.lists[i])
        guard let at = state.lists[i].tasks.firstIndex(where: { $0.id == taskID }) else { throw StoreError.noSuchTask }
        guard change(&state.lists[i].tasks[at], now()) else { return }
        commit([.saveRecord(ref(state.lists[i], SharedTasksSchema.taskRecordName(for: taskID)))])
    }

    nonisolated static func clean(_ title: String) -> String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }

    nonisolated static func clampPriority(_ p: Int) -> Int { min(4, max(1, p)) }

    nonisolated static func normalized(_ due: SharedDue) -> SharedDue { SharedDue(date: SharedClock.stamp(due.date), hasTime: due.hasTime) }

    private func queue(_ change: Change) { commit([change]) }

    private func commit(_ changes: [Change]) {
        if batchDepth > 0 {
            batchedChanges += changes
            batchDirty = true
            return
        }
        save()
        if !changes.isEmpty { onChanges?(changes) }
    }

    private func flushBatch() {
        let changes = batchedChanges
        batchedChanges = []
        if batchDirty { batchDirty = false; save() }
        if !changes.isEmpty { onChanges?(changes) }
    }

    // MARK: - File

    private func save() {
        if batchDepth > 0 { batchDirty = true; return }
        onSave?()
        guard case .file(let url) = persistence else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: [.atomic])
        } catch {
            Self.log.error("Shared Tasks: couldn't save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The saved state, or an empty one: a file that can't be read is moved aside (kept for a look) and the lists
    /// come back from iCloud, since the engines start again from no state.
    static func load(from url: URL) -> (state: SharedTasksState, problem: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (SharedTasksState(), nil) }
        do {
            return (try JSONDecoder().decode(SharedTasksState.self, from: Data(contentsOf: url)), nil)
        } catch {
            let base = url.deletingPathExtension().lastPathComponent
            let aside = url.deletingLastPathComponent().appending(path: "\(base)-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            log.error("Shared Tasks: \(url.lastPathComponent, privacy: .public) couldn't be read (\(error.localizedDescription, privacy: .public)); moved aside, starting empty")
            return (SharedTasksState(), "The shared lists on this device couldn't be read, so they're being downloaded again.")
        }
    }
}
