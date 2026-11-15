import Foundation
import CryptoKit

// HITList's own sync engine (round 28, `dev/SYNC-ENGINE.md`). This file and the three beside it (`SyncSchema`,
// `SyncTransport`, `SyncStorage`) are the contract the engine's parts are built against: the brain (`SyncCore`), the
// pretend iCloud the tests run on, the SwiftData side and the CloudKit side. Nothing here knows CloudKit or SwiftData.

/// One field of a synced record. A field that has no value is absent from the record.
public enum SyncValue: Hashable, Sendable, Codable {
    case string(String)
    case int(Int64)
    case bool(Bool)
    /// A moment, in whole milliseconds since 1970 (`SyncValue.date(_:)`). iCloud keeps milliseconds, a `Date` keeps
    /// more: compared as whole milliseconds, a date is the same before and after it has been to iCloud and back.
    case millis(Int64)
    case data(Data)
    /// Stands for a `data` value where only "is it the same?" matters (`comparable`): the SHA-256 of the bytes, in hex.
    case digest(String)
    /// Another record, by its name.
    case reference(String)
    /// Other records, by name: a set, kept sorted and without repeats (`SyncValue.references(_:)`).
    case referenceList([String])

    public static func date(_ date: Date) -> SyncValue {
        .millis(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    public static func references<S: Sequence>(_ names: S) -> SyncValue where S.Element == String {
        .referenceList(Array(Set(names)).sorted())
    }

    public var dateValue: Date? {
        if case .millis(let ms) = self { return Date(timeIntervalSince1970: Double(ms) / 1000) }
        return nil
    }

    /// The value to compare by: `data` as its `digest`, everything else as it is. Two values are the same field
    /// value exactly when their `comparable`s are equal.
    public var comparable: SyncValue {
        if case .data(let data) = self { return .digest(SyncValue.digest(of: data)) }
        return self
    }

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Which record: its type ("TaskItem") and its name within the zone (the model's `id`, as `UUID.uuidString` prints
/// it; a type with one record per account has a fixed name, `SyncType.singleton`).
public struct SyncKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var type: String
    public var name: String

    public init(type: String, name: String) {
        self.type = type
        self.name = name
    }

    public static func < (a: SyncKey, b: SyncKey) -> Bool { (a.type, a.name) < (b.type, b.name) }

    public var description: String { "\(type)/\(name)" }
}

/// A record as it is synced: what one device holds for one item, or what iCloud holds for it. Only fields with a
/// value are present. The same value type on every side of the engine, so they can be compared.
public struct SyncRecord: Hashable, Sendable, Codable {
    public var key: SyncKey
    public var fields: [String: SyncValue]

    public init(key: SyncKey, fields: [String: SyncValue] = [:]) {
        self.key = key
        self.fields = fields
    }

    public init(type: String, name: String, fields: [String: SyncValue] = [:]) {
        self.init(key: SyncKey(type: type, name: name), fields: fields)
    }

    public subscript(field: String) -> SyncValue? {
        get { fields[field] }
        set { fields[field] = newValue }
    }

    /// When the item was last changed by a person, on whichever device (`SyncSchema.updatedAt`).
    public var updatedAt: Date? { fields[SyncSchema.updatedAt]?.dateValue }

    /// Set on a record that stands for a deleted item (a marker: `SyncSchema.deletedAt` and nothing of the item's
    /// content): when it was deleted.
    public var deletedAt: Date? { fields[SyncSchema.deletedAt]?.dateValue }

    /// Whether this is a marker for a deleted item.
    public var isDeleted: Bool { fields[SyncSchema.deletedAt] != nil }

    /// The record to compare by: every `data` field as its digest (`SyncValue.comparable`). What a ledger keeps as
    /// a base.
    public var comparable: SyncRecord {
        SyncRecord(key: key, fields: fields.mapValues(\.comparable))
    }

    /// The marker left in iCloud for a deleted item: its key, when it was deleted, and nothing else.
    public static func marker(_ key: SyncKey, deletedAt: Date) -> SyncRecord {
        SyncRecord(key: key, fields: [SyncSchema.deletedAt: .date(deletedAt), SyncSchema.updatedAt: .date(deletedAt)])
    }
}
