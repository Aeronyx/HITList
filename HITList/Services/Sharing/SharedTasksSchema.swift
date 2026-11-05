import Foundation

// MARK: - Shared Tasks (brief 51): the design, read before touching anything in Services/Sharing
//
// Shared lists live apart from the task store, in every way that could change how the task store syncs:
//
// - Their own CloudKit container, `iCloud.com.trammells.hitlist.shared`. An owner's shared lists have to live
//   in the owner's private database; in the main container that is the database the SwiftData mirror owns
//   (`com.apple.coredata.cloudkit.zone`), whose database subscription fires for a change in any zone and whose
//   handling of another zone's deletion is undocumented. A second container rules both out.
// - `CKSyncEngine`, never `NSPersistentCloudKitContainer` or a SwiftData CloudKit configuration: SwiftData (27.2
//   SDK) has no shared database, and every NSPersistentCloudKitContainer in the process posts
//   `eventChangedNotification`, which `CloudSyncMonitor` reads as the task store's own sync state.
// - Their own local store: Codable values in one JSON file per task store (`SharedTasksStore`), never SwiftData,
//   whose every `ModelContext.save()` reaches `CloudSyncMonitor` (`ModelContext.didSave`) and its watchdog.
// - Pushes for this container go to Shared Tasks (`SharedTasksPush`), never to `CloudSyncMonitor.pushReceived`.
// - Off by default (`SharedTasksPreference`): off, nothing here creates a CKContainer, an engine or a file.
//
// One CloudKit zone per shared list (`list-<UUID>`), shared whole with a zone-wide `CKShare`. Lists I own sit in
// the private database (one engine), lists I joined in the shared database (a second engine).
//
// Record types (this container only; additive forever once deployed to Production, like the task store's):
// - `SharedList` (record name `list`): title, colour, each with its own change time; createdAt.
// - `SharedTask` (record name `task-<UUID>`): title, notes, priority, due (date + has-time), each with a change
//   time; the completion as one unit (isCompleted, completedAt, completedBy, completedByName,
//   completionChangedAt); who created it.
// - `SharedMember` (record name `member-<userRecordName>`): a person's HITList profile name and picture, copied in
//   by that person; joinedAt.
// - `cloudkit.share` (CloudKit's own): the list's title, participants and permissions.
//
// Rules: last writer wins per field (`SharedTasksMerge`); the completion moves as one unit and, when both sides
// completed, the earlier completion is kept; a delete wins over a concurrent edit. Owner and participants add,
// edit, complete, uncomplete and delete tasks; only the owner renames the list, removes members, stops sharing
// or deletes the list; a participant leaves (`SharedTasksPermissions`).
//
// A new record type or field reaches the Development schema only on a saved record that has a value for it:
// the Debug launch argument `-sharedTasksSchemaPush YES` (with its own `HITLIST_STORE_SUFFIX`) saves one of each,
// every field set. Deploy this container's schema to Production in the CloudKit dashboard before a TestFlight
// build with Shared Tasks switched on reaches anyone; `scripts/release.sh` checks only the main container.

enum SharedTasksSchema {
    static let containerID = "iCloud.com.trammells.hitlist.shared"

    /// Zone names: `list-<UUID>`. Anything else in a database is not a shared list and is left alone.
    static let zonePrefix = "list-"
    static let listRecordName = "list"
    static let taskRecordPrefix = "task-"
    static let memberRecordPrefix = "member-"

    static func zoneName(for listID: UUID) -> String { zonePrefix + listID.uuidString }

    static func listID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix(zonePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(zonePrefix.count)))
    }

    static func taskRecordName(for taskID: UUID) -> String { taskRecordPrefix + taskID.uuidString }

    static func taskID(fromRecordName name: String) -> UUID? {
        guard name.hasPrefix(taskRecordPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(taskRecordPrefix.count)))
    }

    static func memberRecordName(for userID: String) -> String { memberRecordPrefix + userID }

    static func memberID(fromRecordName name: String) -> String? {
        guard name.hasPrefix(memberRecordPrefix), name.count > memberRecordPrefix.count else { return nil }
        return String(name.dropFirst(memberRecordPrefix.count))
    }

    enum RecordType {
        static let list = "SharedList"
        static let task = "SharedTask"
        static let member = "SharedMember"
    }

    /// Field names. Never rename one once it is in Production.
    enum ListField {
        static let title = "title"
        static let titleChangedAt = "titleChangedAt"
        static let colorHex = "colorHex"
        static let colorChangedAt = "colorChangedAt"
        static let createdAt = "createdAt"
    }

    enum TaskField {
        static let title = "title"
        static let titleChangedAt = "titleChangedAt"
        static let notes = "notes"
        static let notesChangedAt = "notesChangedAt"
        static let priority = "priority"
        static let priorityChangedAt = "priorityChangedAt"
        static let dueDate = "dueDate"
        static let hasDueTime = "hasDueTime"
        static let dueChangedAt = "dueChangedAt"
        static let isCompleted = "isCompleted"
        static let completedAt = "completedAt"
        static let completedBy = "completedBy"
        static let completedByName = "completedByName"
        static let completionChangedAt = "completionChangedAt"
        static let createdAt = "createdAt"
        static let createdBy = "createdBy"
        static let createdByName = "createdByName"
    }

    enum MemberField {
        static let userID = "userID"
        static let name = "name"
        static let nameChangedAt = "nameChangedAt"
        static let avatar = "avatar"
        static let avatarChangedAt = "avatarChangedAt"
        static let joinedAt = "joinedAt"
    }
}
