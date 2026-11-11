import Foundation
import CryptoKit
import OSLog

/// Brief 95: what iCloud holds in the Core Data zone, as the beats see it: one entry per record (its kind, `CD_id` and
/// change stamps, never a title), kept current with change tokens of HITList's own, apart from the mirror's. The first
/// read of a zone fetches every record (`complete` false until it finishes); after it, each beat asks only for what
/// changed since the last one, which is usually nothing. Kept per store, so a Debug build's side store keeps its own,
/// and per iCloud account (`accountKey`): another account's records are never compared with this one's.
///
/// Pure but for `load` and `save`, which keep it in Application Support (this app's own container, not the app group:
/// no extension reads it).
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
        if changes.isFullRead { entries = [:] }
        for (name, entry) in changes.changed { entries[name] = entry }
        for name in changes.deleted { entries[name] = nil }
        zoneToken = changes.token
        if changes.isFullRead {
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

    // MARK: Keeping it

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// `<Application Support>/Sync/iCloud index <store name>.json`.
    static func fileURL(storeName: String = ModelContainerFactory.storeName,
                        folder: URL = URL.applicationSupportDirectory.appending(path: "Sync", directoryHint: .isDirectory)) -> URL {
        folder.appending(path: "iCloud index \(storeName).json")
    }

    /// The kept index, or a fresh one when there is none, it can't be read, or it is another format's.
    static func load(from url: URL = fileURL()) -> ICloudZoneIndex {
        guard let data = try? Data(contentsOf: url) else { return ICloudZoneIndex() }
        guard let index = try? JSONDecoder().decode(ICloudZoneIndex.self, from: data), index.version == version else {
            log.notice("iCloud index at \(url.lastPathComponent, privacy: .public) unreadable; reading iCloud afresh")
            return ICloudZoneIndex()
        }
        return index
    }

    func save(to url: URL = ICloudZoneIndex.fileURL()) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        } catch {
            Self.log.error("iCloud index not saved: \(error.localizedDescription, privacy: .public)")
        }
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
