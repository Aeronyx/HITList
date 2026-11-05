import Foundation

// The Shared Tasks model (brief 51): plain Codable values, kept by `SharedTasksStore` in a JSON file of its own
// and mapped to CloudKit records by `SharedTasksRecords`. Nothing here touches SwiftData or the task store.

/// Who someone is in Shared Tasks: their user record name in the shared container (`CKContainer.userRecordID`).
/// It is the Apple account, as this app's container sees it; there is no login.
typealias SharedMemberID = String

/// A value and when it was last set on some device: the unit of last-writer-wins (`SharedTasksMerge`).
/// Times are whole milliseconds (`SharedClock.stamp`), which is what CloudKit keeps of a date, so a value read
/// back from the server compares equal to the one that was sent.
struct Stamped<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var value: Value
    var changedAt: Date

    init(_ value: Value, at changedAt: Date) {
        self.value = value
        self.changedAt = changedAt
    }

    /// A value nobody has set yet (a list known only by its zone): any real value wins over it.
    static func unset(_ value: Value) -> Stamped { Stamped(value, at: SharedClock.unset) }
}

/// Times for Shared Tasks: whole milliseconds since 1970, the precision CloudKit stores a date with.
enum SharedClock {
    /// The time of a value nobody has set: 1970, which CloudKit stores as it stores any date.
    static let unset = Date(timeIntervalSince1970: 0)

    static func stamp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// Milliseconds, for comparing two stamps without floating-point noise.
    static func millis(_ date: Date) -> Int64 {
        let ms = (date.timeIntervalSince1970 * 1000).rounded()
        guard ms.isFinite else { return ms < 0 ? .min : .max }
        return Int64(max(min(ms, Double(Int64.max / 2)), Double(Int64.min / 2)))
    }
}

/// A due date: the day, or the day and time.
struct SharedDue: Codable, Equatable, Hashable, Sendable {
    var date: Date
    var hasTime: Bool
}

/// A completed task's who and when. They always move together (`SharedTasksMerge.completion`).
struct SharedCompletion: Codable, Equatable, Sendable {
    var at: Date
    /// The member who completed it.
    var by: SharedMemberID
    /// Their name at the time, for a member whose record is gone or not fetched yet.
    var byName: String
}

struct SharedTask: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: Stamped<String>
    var notes: Stamped<String>
    /// 1 = most urgent ... 4 = none, as `TaskItem.priority`.
    var priority: Stamped<Int>
    var due: Stamped<SharedDue?>
    /// Nil while open.
    var completion: Stamped<SharedCompletion?>
    var createdAt: Date
    var createdBy: SharedMemberID?
    var createdByName: String?
    /// The CKRecord's system fields (change tag) as last saved or fetched; nil before the first save.
    var systemFields: Data?

    var isCompleted: Bool { completion.value != nil }
}

/// A person's HITList profile, copied by them into each list they are in (record type `SharedMember`).
struct SharedMember: Codable, Equatable, Identifiable, Sendable {
    var id: SharedMemberID
    var name: Stamped<String>
    /// A small JPEG (`SharedTasksRecords.avatarPixels` on its long side).
    var avatar: Stamped<Data?>
    var joinedAt: Date
    var systemFields: Data?
}

/// One person on a list's CKShare, as last fetched (`SharedTasksRecords.shareInfo`).
struct SharedParticipant: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case owner, participant }
    enum Status: String, Codable, Sendable { case pending, accepted, removed, unknown }

    /// Their user record name; nil for an invitation nobody has accepted yet.
    var userID: SharedMemberID?
    /// The name iCloud gives for them, when it gives one.
    var name: String?
    /// The email address or phone number an invitation went to (only the owner sees these).
    var contact: String?
    var role: Role
    var status: Status
    var canWrite: Bool
    var isCurrentUser: Bool
}

/// A list's CKShare, as last fetched or saved.
struct SharedShareInfo: Codable, Equatable, Sendable {
    var participants: [SharedParticipant]
    var url: URL?
    /// The CKShare itself (keyed archive), for the share sheet and for removing someone.
    var archive: Data?

    var currentUser: SharedParticipant? { participants.first(where: \.isCurrentUser) }
    /// People other than the owner who accepted.
    var acceptedGuests: [SharedParticipant] { participants.filter { $0.role != .owner && $0.status == .accepted } }
    var pendingGuests: [SharedParticipant] { participants.filter { $0.role != .owner && $0.status == .pending } }
}

/// Where a list lives for this account: lists I made sit in my private database, lists I joined in my shared one.
enum SharedListScope: String, Codable, Sendable, CaseIterable {
    case owned, joined
}

/// The list record's own fields (record type `SharedList`).
struct SharedListFields: Codable, Equatable, Sendable {
    var title: Stamped<String>
    var colorHex: Stamped<String>
    var createdAt: Date
}

struct SharedList: Codable, Equatable, Identifiable, Sendable {
    /// Also the zone's name (`SharedTasksSchema.zoneName(for:)`).
    var id: UUID
    var scope: SharedListScope
    /// The zone's owner as this device names it: `CKCurrentUserDefaultName` for my lists, the owner's user record
    /// name for lists I joined.
    var ownerName: String
    var fields: SharedListFields
    var systemFields: Data?
    var tasks: [SharedTask] = []
    var members: [SharedMember] = []
    /// Nil until the list is shared (mine) or its share is fetched (joined).
    var share: SharedShareInfo?
    /// Tasks deleted here whose deletion CloudKit hasn't confirmed: a fetched edit of one is ignored, so a delete
    /// wins over an edit made at the same time.
    var deletedTaskIDs: Set<UUID> = []

    var title: String { fields.title.value }
    var colorHex: String { fields.colorHex.value }
    var isOwned: Bool { scope == .owned }
    var isShared: Bool { share != nil || scope == .joined }

    func task(_ id: UUID) -> SharedTask? { tasks.first { $0.id == id } }
    func member(_ id: SharedMemberID?) -> SharedMember? { id.flatMap { id in members.first { $0.id == id } } }
}

/// What this person shows others: their HITList profile name and picture, with the times they last changed
/// (`Profile.nameUpdatedAt` / `avatarUpdatedAt`).
struct SharedProfile: Codable, Equatable, Sendable {
    var name: String
    var nameChangedAt: Date
    var avatar: Data?
    var avatarChangedAt: Date
}

/// Everything `SharedTasksStore` keeps on disk.
struct SharedTasksState: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version = SharedTasksState.currentVersion
    /// This account's user record name in the shared container, once known.
    var me: SharedMemberID?
    var lists: [SharedList] = []
    /// `CKSyncEngine.State.Serialization` per database, JSON-encoded, opaque here.
    var engineStates: [String: Data] = [:]
    /// The profile last copied into my member records.
    var profile: SharedProfile?
}
