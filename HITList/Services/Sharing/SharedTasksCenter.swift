import Foundation
import CloudKit
import SwiftData
import Observation
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared Tasks for the whole app (brief 51): the switch, the store and the sync, made only once the switch is on.
///
/// Off (the default), `shared` is a few properties and nothing else: no CKContainer, no engine, no file. On, it opens
/// the store (`SharedTasksPreference.fileURL`), starts the two engines (`SharedTasksSync`), learns who this account
/// is in the shared container, and copies the HITList profile into the member records (`refreshProfile`, again
/// whenever the app becomes active). The screens call the actions here; share acceptance arrives from the scene
/// delegate (iOS) and the app delegate (Mac) through `userAccepted`; pushes for the shared container through
/// `handlePush`.
@MainActor
@Observable
final class SharedTasksCenter {
    static let shared = SharedTasksCenter()

    enum Phase: Equatable {
        case off
        case connecting
        case ready
        case noAccount
    }

    /// An invitation opened while the preview was off (or before it was ready), waiting for the person to join.
    struct Invitation: Identifiable {
        let id = UUID()
        let metadata: CKShare.Metadata
        var title: String { (metadata.share[CKShare.SystemFieldKey.title] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "a shared list" }
        var ownerName: String? {
            metadata.ownerIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    private(set) var isOn: Bool
    private(set) var phase: Phase = .off
    private(set) var store: SharedTasksStore?
    private(set) var isSyncing = false
    /// A line for the Shared screen: the last failure, or why the shared lists' file was reset.
    private(set) var problem: String?
    var pendingInvitation: Invitation?

    @ObservationIgnored private var sync: SharedTasksSync?
    /// An invitation opened while on is being joined without asking (`userAccepted`).
    @ObservationIgnored private var joiningAtOnce = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storeName: String
    @ObservationIgnored private let isTesting: Bool
    @ObservationIgnored private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sharing")

    init(defaults: UserDefaults = AppGroup.defaults, storeName: String = ModelContainerFactory.storeName,
         isTesting: Bool = SyncAppDelegateSupport.isTesting) {
        self.defaults = defaults
        self.storeName = storeName
        self.isTesting = isTesting
        isOn = SharedTasksPreference.isOn(in: defaults, storeName: storeName)
        #if DEBUG
        if !isTesting, SharedTasksDebug.forcesOn { isOn = true } // this run only; the switch isn't written
        #endif
    }

    nonisolated static var container: CKContainer { CKContainer(identifier: SharedTasksSchema.containerID) }

    // MARK: - Switch

    /// Starts Shared Tasks when the switch is on and it isn't running yet. Cheap to call often.
    func startIfOn() {
        guard isOn, store == nil, !isTesting else { return }
        #if DEBUG
        if SharedTasksDebug.seedsSample {
            store = SharedTasksDebug.sampleStore()
            phase = .ready
        } else {
            start()
        }
        SharedTasksDebug.runLaunchHooks(self)
        #else
        start()
        #endif
    }

    #if DEBUG
    /// The schema push drives the engines directly.
    var syncForDebug: SharedTasksSync? { sync }
    #endif

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if !isTesting { SharedTasksPreference.set(on, in: defaults, storeName: storeName) }
        if on {
            startIfOn()
        } else {
            stop()
        }
    }

    private func start() {
        let store = SharedTasksStore(persistence: .file(SharedTasksPreference.folder.appending(path: SharedTasksPreference.fileName(storeName: storeName))))
        let container = Self.container
        let sync = SharedTasksSync(container: container, store: store)
        sync.onActivity = { [weak self] in self?.isSyncing = $0 }
        sync.onProblem = { [weak self] in self?.problem = $0 }
        self.store = store
        self.sync = sync
        problem = store.loadProblem
        phase = .connecting
        Self.log.notice("Shared Tasks: started (\(self.storeName, privacy: .public))")
        observeActivation()
        Task { await connect(container, store: store) }
    }

    private func stop() {
        Self.log.notice("Shared Tasks: switched off")
        let sync = self.sync
        self.sync = nil
        store = nil
        phase = .off
        isSyncing = false
        problem = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        Task { await sync?.shutDown() }
    }

    /// Who this account is in the shared container, then the profile into the member records, then a fetch.
    private func connect(_ container: CKContainer, store: SharedTasksStore) async {
        do {
            let status = try await container.accountStatus()
            guard self.store === store else { return }
            guard status == .available else {
                phase = .noAccount
                return
            }
            let me = try await container.userRecordID()
            guard self.store === store else { return }
            store.setMe(me.recordName)
            phase = .ready
            refreshProfile()
            await sync?.fetchNow()
        } catch {
            guard self.store === store else { return }
            // Offline at launch: what is on disk still shows and edits queue up; the engines catch up later.
            phase = store.me == nil ? .connecting : .ready
            problem = SharedTasksSync.describe(error)
            Self.log.error("Shared Tasks: couldn't reach iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeActivation() {
        #if os(macOS)
        let name = NSApplication.didBecomeActiveNotification
        #else
        let name = UIApplication.didBecomeActiveNotification
        #endif
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let store = self.store else { return }
                Task { await self.connect(Self.container, store: store) }
            }
        })
    }

    private func becameActive() {
        guard let store else { return }
        if phase != .ready {
            Task { await connect(Self.container, store: store) }
        } else {
            // What the others changed while this app was away: shared tasks are rows of Today and the Inbox now
            // (brief 62), and a push can go missing, so coming back to the app fetches too (cheap: the engine asks
            // only for what changed since its last fetch).
            Task { await sync?.fetchNow() }
        }
        refreshProfile()
        presentPendingInvitation()
    }

    // MARK: - Profile

    /// Copies this account's HITList profile (name, small picture) into its member records when it changed. Reads
    /// the task store's main context (`IntentStore`, registered at launch); writes nothing there.
    func refreshProfile() {
        guard let store, let context = try? IntentStore.context() else { return }
        let profiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        guard let profile = ProfileStore.shown(profiles) else { return }
        let avatarAt = SharedClock.stamp(profile.avatarUpdatedAt ?? profile.createdAt)
        let avatar: Data?
        if let kept = store.profile, SharedClock.millis(kept.avatarChangedAt) == SharedClock.millis(avatarAt) {
            avatar = kept.avatar
        } else {
            avatar = profile.avatarData.map(SharedTasksRecords.smallAvatar)
        }
        store.setProfile(SharedProfile(name: profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                                       nameChangedAt: profile.nameUpdatedAt ?? profile.createdAt,
                                       avatar: avatar, avatarChangedAt: avatarAt))
    }

    // MARK: - Actions

    /// Fetch now (the Shared screen appearing, pull to refresh).
    func refresh() async {
        startIfOn()
        refreshProfile()
        await sync?.fetchNow()
    }

    @discardableResult
    func createList(title: String) throws -> SharedList {
        guard let store else { throw SharedTasksStore.StoreError.notReady }
        return try store.createList(title: title)
    }

    /// The list's share for the share sheet: made (zone first, then the CKShare) on first use.
    func prepareShare(for listID: UUID) async throws -> CKShare {
        guard let store, let sync, let list = store.list(listID) else { throw SharedTasksStore.StoreError.noSuchList }
        guard SharedTasksPermissions.allows(.invite, in: list) else { throw SharedTasksStore.StoreError.notAllowed }
        let zoneID = SharedTasksRecords.zoneID(of: list)
        // The zone and the list's records reach the server first: a share of a zone that isn't there fails. A record
        // that conflicts on the way is merged by the engine's events; only a missing zone stops the share (below).
        do {
            try await sync.engine(.owned).sendChanges()
        } catch let error as CKError where SharedTasksSync.isHandledPerRecord(error) {
            Self.log.notice("Shared Tasks: sending before sharing had per-record results; sharing anyway")
        }
        let database = sync.container.privateCloudDatabase
        let shareID = SharedTasksRecords.shareRecordID(listID: listID, ownerName: list.ownerName)
        if let existing = try? await database.record(for: shareID) as? CKShare {
            store.applyShare(SharedTasksRecords.shareInfo(from: existing, me: store.me), listID: listID, scope: .owned, ownerName: list.ownerName)
            return existing
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = list.title as CKRecordValue
        share.publicPermission = .none
        let results = try await database.modifyRecords(saving: [share], deleting: [])
        let saved = try results.saveResults[share.recordID]?.get() as? CKShare ?? share
        store.applyShare(SharedTasksRecords.shareInfo(from: saved, me: store.me), listID: listID, scope: .owned, ownerName: list.ownerName)
        Self.log.notice("Shared Tasks: a list was shared")
        return saved
    }

    /// The list's share as last fetched, for inviting more people (`ShareLink` with an existing share).
    func existingShare(for listID: UUID) -> CKShare? {
        SharedTasksRecords.unarchiveShare(store?.list(listID)?.share?.archive)
    }

    /// A participant leaves: the share goes from their shared database first, then the list from this device.
    func leave(_ listID: UUID) async throws {
        guard let store, let sync, let list = store.list(listID) else { throw SharedTasksStore.StoreError.noSuchList }
        guard SharedTasksPermissions.allows(.leave, in: list) else { throw SharedTasksStore.StoreError.notAllowed }
        let database = sync.container.sharedCloudDatabase
        let shareID = SharedTasksRecords.shareRecordID(listID: listID, ownerName: list.ownerName)
        do {
            try await Self.delete(shareID, in: database)
        } catch let error as CKError where error.code == .permissionFailure {
            // Fall back to removing the shared zone from this account's shared database, which also leaves it.
            _ = try await database.modifyRecordZones(saving: [], deleting: [shareID.zoneID])
        }
        try store.leave(listID)
        Self.log.notice("Shared Tasks: left a list")
    }

    /// The owner stops sharing: the CKShare is deleted (everyone else loses the list); the owner keeps it.
    func stopSharing(_ listID: UUID) async throws {
        guard let store, let sync, let list = store.list(listID) else { throw SharedTasksStore.StoreError.noSuchList }
        guard SharedTasksPermissions.allows(.stopSharing, in: list) else { throw SharedTasksStore.StoreError.notAllowed }
        try await Self.delete(SharedTasksRecords.shareRecordID(listID: listID, ownerName: list.ownerName), in: sync.container.privateCloudDatabase)
        try store.stopSharing(listID)
        Self.log.notice("Shared Tasks: stopped sharing a list")
    }

    /// The owner takes someone off the list (or withdraws an invitation nobody accepted).
    func remove(_ person: SharedPerson, from listID: UUID) async throws {
        guard let store, let sync, let list = store.list(listID) else { throw SharedTasksStore.StoreError.noSuchList }
        guard SharedTasksPermissions.allows(.removeMember, in: list), !person.isOwner, !person.isMe else {
            throw SharedTasksStore.StoreError.notAllowed
        }
        let database = sync.container.privateCloudDatabase
        let shareID = SharedTasksRecords.shareRecordID(listID: listID, ownerName: list.ownerName)
        guard let share = try await database.record(for: shareID) as? CKShare else { return }
        let participant = share.participants.first { p in
            if let id = person.memberID, p.userIdentity.userRecordID?.recordName == id { return true }
            let contact = p.userIdentity.lookupInfo?.emailAddress ?? p.userIdentity.lookupInfo?.phoneNumber
            return person.memberID == nil && contact != nil && contact == person.contact
        }
        if let participant {
            share.removeParticipant(participant)
            let results = try await database.modifyRecords(saving: [share], deleting: [])
            if let saved = try results.saveResults[shareID]?.get() as? CKShare {
                store.applyShare(SharedTasksRecords.shareInfo(from: saved, me: store.me), listID: listID, scope: .owned, ownerName: list.ownerName)
            }
        }
        if let memberID = person.memberID { try store.removeMember(memberID, from: listID) }
    }

    func deleteList(_ listID: UUID) throws {
        guard let store else { throw SharedTasksStore.StoreError.noSuchList }
        try store.deleteList(listID)
    }

    private static func delete(_ id: CKRecord.ID, in database: CKDatabase) async throws {
        let results = try await database.modifyRecords(saving: [], deleting: [id])
        if case .failure(let error)? = results.deleteResults[id] {
            if let ck = error as? CKError, ck.code == .unknownItem { return }
            throw error
        }
    }

    // MARK: - Invitations

    /// Someone opened an invitation link and the system handed it to the app. On: join at once and show the list
    /// (the invitation sheet, with the error, if joining fails). Off: keep it and show the explainer, whose Join
    /// switches the preview on.
    func userAccepted(_ metadata: CKShare.Metadata) {
        guard !isTesting else { return }
        guard metadata.containerIdentifier == SharedTasksSchema.containerID else {
            Self.log.error("Shared Tasks: ignored an invitation for \(metadata.containerIdentifier, privacy: .public)")
            return
        }
        Self.log.notice("Shared Tasks: an invitation was opened (preview \(self.isOn ? "on" : "off", privacy: .public))")
        pendingInvitation = Invitation(metadata: metadata)
        guard isOn else {
            presentPendingInvitation()
            return
        }
        joiningAtOnce = true
        Task {
            do {
                let listID = try await joinPendingInvitation()
                joiningAtOnce = false
                if let listID { SharedTasksPresenter.presentScreen(list: listID) }
            } catch {
                joiningAtOnce = false
                problem = SharedTasksSync.describe(error)
                presentPendingInvitation()
            }
        }
    }

    /// Shows the waiting invitation, once there is a window to show it in (not while it is being joined at once).
    func presentPendingInvitation() {
        guard pendingInvitation != nil, !joiningAtOnce else { return }
        SharedTasksPresenter.presentInvitation()
    }

    /// Joins the waiting invitation (switching the preview on if needed). Returns the list's id.
    @discardableResult
    func joinPendingInvitation() async throws -> UUID? {
        guard let invitation = pendingInvitation else { return nil }
        setOn(true)
        guard let store, let sync else { throw SharedTasksStore.StoreError.notReady }
        let metadata = invitation.metadata
        let zoneID = metadata.share.recordID.zoneID
        guard let listID = SharedTasksSchema.listID(fromZoneName: zoneID.zoneName) else { pendingInvitation = nil; return nil }
        if metadata.participantRole != .owner {
            _ = try await CKContainer(identifier: metadata.containerIdentifier).accept(metadata)
            store.ensureList(listID, scope: .joined, ownerName: zoneID.ownerName, title: invitation.title)
            if store.me == nil { store.setMe(try await sync.container.userRecordID().recordName) }
            store.applyShare(SharedTasksRecords.shareInfo(from: metadata.share, me: store.me), listID: listID, scope: .joined, ownerName: zoneID.ownerName)
            refreshProfile()
            if let profile = store.profile { store.setProfile(profile) }
        }
        pendingInvitation = nil
        Self.log.notice("Shared Tasks: joined a list")
        Task { await sync.fetchNow() }
        return listID
    }

    // MARK: - Pushes

    /// A push for the shared container (routed here by `SyncAppDelegate`, never to `CloudSyncMonitor`): fetch.
    /// Returns whether anything ran.
    func handlePush() async -> Bool {
        startIfOn()
        guard let sync else { return false }
        await sync.fetchNow()
        return true
    }
}

/// Which pushes are Shared Tasks' (the shared container's), so `SyncAppDelegate` keeps them away from the task
/// store's sync monitor, whose watchdog expects a task-store import after every CloudKit push.
enum SharedTasksPush {
    static func isForSharedTasks(_ userInfo: [AnyHashable: Any]) -> Bool {
        let push = SyncPush(userInfo: userInfo)
        return push.isCloudKit && push.container == SharedTasksSchema.containerID
    }
}
