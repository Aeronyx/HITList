import Foundation
import CryptoKit

/// What iCloud holds in the Core Data zone, as Check iCloud… reads it (`SyncAudit`): one entry per record (its kind,
/// `CD_id` and change stamps, never a title). Built afresh in memory each time the audit is asked for; nothing keeps
/// it between launches and nothing reads iCloud for it unasked (brief 95's beats did both until 0.9.9). Pure.
struct ICloudZoneIndex: Codable, Equatable {
    struct Entry: Codable, Equatable, Sendable {
        /// The CloudKit record type: "CD_TaskItem", or "CDMR" for a many-to-many link.
        var type: String
        /// `CD_entityName`, else the record type without "CD_".
        var entity: String
        /// `CD_id`; nil for a record that has none (a link).
        var id: UUID?
        /// `CD_updatedAt`.
        var updatedAt: Date?
        /// CloudKit's own last-changed time of the record.
        var modifiedAt: Date?
    }

    /// Format of the file; a different one starts afresh.
    static let version = 1

    var version = ICloudZoneIndex.version
    /// The account the records belong to (`AccountIdentity.key`); nil until it was known.
    var accountKey: String?
    /// By CloudKit record name.
    var entries: [String: Entry] = [:]
    /// The archived `CKServerChangeToken` of the private database (which zones changed).
    var databaseToken: Data?
    /// The archived `CKServerChangeToken` of the Core Data zone (which records changed).
    var zoneToken: Data?
    /// A read reached the zone's end: `entries` is everything iCloud held when it finished.
    var complete = false
    /// When the last read of the whole zone finished.
    var lastFullRead: Date?
    /// The zone wasn't there when last read (a new account, or iCloud data deleted in Settings).
    var zoneMissing = false

    /// Changes from one fetch of the zone (`ICloudZoneReading.zoneChanges`).
    struct ZoneChanges: Equatable, Sendable {
        var changed: [String: Entry] = [:]
        var deleted: [String] = []
        var token: Data?
        /// The fetch started without a token: `changed` is the whole zone and replaces what was kept.
        var isFullRead = false
        /// The zone doesn't exist in iCloud.
        var zoneMissing = false
        /// The fetch reached the zone's end. False for a read cut short (a timeout, a dropped network) that still brought
        /// records and a token to go on from: the first read of a large zone then finishes over several beats.
        var reachedEnd = true
    }

    mutating func apply(_ changes: ZoneChanges, at now: Date) {
        if changes.zoneMissing {
            entries = [:]
            zoneToken = nil
            zoneMissing = true
            complete = true
            lastFullRead = now
            return
        }
        zoneMissing = false
        if changes.isFullRead {
            entries = [:]
            complete = false
        }
        for (name, entry) in changes.changed { entries[name] = entry }
        for name in changes.deleted { entries[name] = nil }
        zoneToken = changes.token
        // A whole read, or the last part of a first read that was cut short, makes the index complete.
        if changes.reachedEnd, changes.isFullRead || !complete {
            complete = true
            lastFullRead = now
        }
    }

    /// Forgets the records and tokens (another account, a token iCloud no longer knows): the next beat reads afresh.
    mutating func reset(accountKey: String?) {
        self = ICloudZoneIndex()
        self.accountKey = accountKey
    }

    /// The records of the kinds in `entities` that carry an id, for the comparison.
    func remoteRecords(entities: Set<String>) -> [SyncComparison.Remote] {
        entries.compactMap { name, entry in
            guard let id = entry.id, entities.contains(entry.entity) else { return nil }
            return SyncComparison.Remote(entity: entry.entity, id: id, updatedAt: entry.updatedAt, recordName: name,
                                         modifiedAt: entry.modifiedAt)
        }
    }

    /// Records the comparison leaves out: many-to-many links and kinds this build doesn't sync.
    func otherRecords(entities: Set<String>) -> Int {
        entries.values.filter { $0.id == nil || !entities.contains($0.entity) }.count
    }

    // MARK: The file 0.9.4 to 0.9.9 kept

    /// `<Application Support>/Sync/iCloud index <store name>.json`: where brief 95's beats kept this index between
    /// launches. Nothing keeps it now (the audit reads iCloud afresh each time it is asked); `CloudSyncMonitor` removes
    /// the file once.
    static func retiredFileURL(storeName: String = ModelContainerFactory.storeName,
                               folder: URL = URL.applicationSupportDirectory.appending(path: "Sync", directoryHint: .isDirectory)) -> URL {
        folder.appending(path: "iCloud index \(storeName).json")
    }
}

/// Eight hex digits of a one-way hash: how the sync log names a record (brief 95: "counts and short hashes, never a
/// title"). The same id gives the same hash on every device.
enum SyncShortHash {
    static func of(_ text: String) -> String {
        let digest = SHA256.hash(data: Data("HITList record \(text)".utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
