import Foundation
import CloudKit
import HITListCore

/// The engine's records as CloudKit holds them (brief 142, `dev/SYNC-ENGINE.md` sections 3 and 6): `SyncRecord` to
/// `CKRecord` and back, driven by `SyncSchema`.
///
/// - **Names.** A record is named `"<type>.<name>"` (`TaskItem.6B1F…`, `Profile.profile`, `Meta.meta`) in one zone of
///   the private database. A pending change in `CKSyncEngine` names a record by its `CKRecord.ID` alone, so the id
///   has to say the type. Parsed back strictly (`key(forRecordName:)`): a name that does not parse is not ours.
/// - **Record types** are `HL` + the type (`HLTaskItem`, `HLProfile`, `HLMeta`; `recordType(for:)`), never the
///   model's own name: SwiftData's mirror, still on in released builds, imports every zone of the database and maps a
///   record whose type is an entity's name onto that entity (probe, 2026-11-15: it turned the engine's records into
///   empty items and deleted its profile). `SyncKey.type` stays the model's name; only CloudKit sees the prefix. A
///   record whose type is not exactly `HL` + the type its name says is not ours.
/// - **Out** (`record(for:in:assets:)`, T4): every field of the type is written, set or emptied, and `deletedAt`
///   likewise; a key the type does not list is never touched, so a newer build's fields survive this build's save.
///   The record is rebuilt from the archived system fields when there are some, so iCloud sees the change tag the
///   save is based on; made new otherwise. Never a `CKRecord.Reference`: a reference is the other record's key name
///   as a string, so iCloud never deletes or refuses anything on its own account.
/// - **In** (`cloudRecord(from:)`): every key that maps onto a `SyncValue`, known to this build or not (the brain cuts
///   it down with `SyncSchema.known`), dates rounded to whole milliseconds, an asset read into bytes, and the system
///   fields archived.
enum CloudRecordCodec {
    /// An asset larger than this is not read into memory: the record carrying it is not delivered (`DecodeProblem`).
    /// HITList's only asset is the profile picture, which `ProfileStore` makes small; 16 MB is far past anything a
    /// build of HITList writes, so a record over it was written by something else and is left alone rather than
    /// read whole into memory (or, worse, delivered without the field, which the brain would read as "emptied").
    static let assetByteLimit = 16 * 1024 * 1024

    // MARK: - Zones and names

    static func zoneID(_ zoneName: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    static func recordName(for key: SyncKey) -> String { key.type + "." + key.name }

    static func recordID(for key: SyncKey, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName(for: key), zoneID: zoneID)
    }

    /// The key a record name stands for, or nil when the name is not one the engine makes: a type (a letter, then
    /// letters, digits or underscores: CloudKit's rule for record types), one dot, then a name of letters, digits,
    /// hyphens or underscores (a `UUID.uuidString`, `profile`, `meta`); at most 255 characters in all.
    static func key(forRecordName recordName: String) -> SyncKey? {
        guard recordName.utf8.count <= 255, let dot = recordName.firstIndex(of: ".") else { return nil }
        let type = String(recordName[..<dot])
        let name = String(recordName[recordName.index(after: dot)...])
        guard isRecordType(type), isRecordKeyName(name) else { return nil }
        return SyncKey(type: type, name: name)
    }

    static func key(for recordID: CKRecord.ID) -> SyncKey? { key(forRecordName: recordID.recordName) }

    /// The prefix of every record type the engine writes (`dev/SYNC-ENGINE.md` section 3): a name SwiftData's mirror
    /// cannot map onto one of its entities.
    static let recordTypePrefix = "HL"

    /// CloudKit's record type for a `SyncKey.type`: `TaskItem` → `HLTaskItem`.
    static func recordType(for type: String) -> String { recordTypePrefix + type }

    /// The `SyncKey.type` a CloudKit record type stands for, or nil when it is not one the engine writes.
    static func type(forRecordType recordType: String) -> String? {
        guard recordType.hasPrefix(recordTypePrefix) else { return nil }
        let type = String(recordType.dropFirst(recordTypePrefix.count))
        return isRecordType(type) ? type : nil
    }

    static func isRecordType(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, isASCIILetter(first) else { return false }
        return text.unicodeScalars.allSatisfy { isASCIILetter($0) || isASCIIDigit($0) || $0 == "_" }
    }

    static func isRecordKeyName(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { isASCIILetter($0) || isASCIIDigit($0) || $0 == "-" || $0 == "_" }
    }

    private static func isASCIILetter(_ s: Unicode.Scalar) -> Bool { ("a"..."z").contains(s) || ("A"..."Z").contains(s) }
    private static func isASCIIDigit(_ s: Unicode.Scalar) -> Bool { ("0"..."9").contains(s) }

    // MARK: - The fields of a type

    /// The fields a record of `type` is written with: the schema's (`SyncSchema.types`), or, for the zone's own
    /// `Meta` record (which the schema names but does not list among the synced types), its format version and the
    /// stamp. `deletedAt` belongs to every type and is added by the callers. Nil for a type this build does not know:
    /// such a record is never sent.
    static func fields(ofType type: String) -> [SyncField]? {
        if let known = SyncSchema.type(type) { return known.fields }
        if type == SyncSchema.metaType { return metaFields }
        return nil
    }

    static let metaFields: [SyncField] = [
        SyncField(SyncSchema.metaFormatVersion, .int),
        SyncField(SyncSchema.updatedAt, .date),
    ]

    private static let deletedAtField = SyncField(SyncSchema.deletedAt, .date)

    // MARK: - Out

    enum EncodeError: Error, Equatable, CustomStringConvertible {
        /// The key's type or name would not parse back (`key(forRecordName:)`).
        case invalidKey(SyncKey)
        /// A type this build does not sync.
        case unknownType(String)
        /// A value of another kind than the field's, or a digest where bytes must go (the brain handed over a
        /// record made for comparing, not for sending).
        case wrongKind(field: String)
        /// The picture could not be written to the temporary file `CKAsset` needs.
        case assetNotWritten(field: String, reason: String)

        var description: String {
            switch self {
            case .invalidKey(let key): return "invalid key \(key)"
            case .unknownType(let type): return "unknown type \(type)"
            case .wrongKind(let field): return "wrong kind for \(field)"
            case .assetNotWritten(let field, let reason): return "asset \(field) not written: \(reason)"
            }
        }
    }

    /// The `CKRecord` to save for `outgoing`, in `zoneID`. Asset files are written through `assets`, which keeps
    /// them until the send has ended.
    static func record(for outgoing: OutgoingRecord, in zoneID: CKRecordZone.ID, assets: AssetFiles) throws -> CKRecord {
        let key = outgoing.record.key
        guard self.key(forRecordName: recordName(for: key)) == key else { throw EncodeError.invalidKey(key) }
        guard let fields = fields(ofType: key.type) else { throw EncodeError.unknownType(key.type) }
        let id = recordID(for: key, in: zoneID)
        let record = rebuilt(from: outgoing.system, id: id, type: key.type)
            ?? CKRecord(recordType: recordType(for: key.type), recordID: id)
        for field in fields + [deletedAtField] {
            record[field.key] = try value(outgoing.record.fields[field.key], for: field, recordID: id, assets: assets)
        }
        return record
    }

    /// The record iCloud last gave this device, as its system fields alone (no values): what a save of a change to
    /// that version starts from. Nil when there is no token, or it cannot be read, or it is for another record (a
    /// ledger moved between zones): the record is then made new and iCloud answers with a conflict if it holds one.
    static func rebuilt(from system: Data?, id: CKRecord.ID, type: String) -> CKRecord? {
        guard let system, let record = unarchive(system) else { return nil }
        guard record.recordID == id, record.recordType == recordType(for: type) else { return nil }
        return record
    }

    static func unarchive(_ system: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: system) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func value(_ value: SyncValue?, for field: SyncField, recordID: CKRecord.ID,
                              assets: AssetFiles) throws -> __CKRecordObjCValue? {
        guard let value else { return nil }
        switch (field.kind, value) {
        case (.string, .string(let text)):
            return text as NSString
        case (.int, .int(let number)):
            return NSNumber(value: number)
        case (.bool, .bool(let flag)):
            // Stored as an Int64 0 or 1, as Core Data's mirror stores a Bool, so the dashboard reads the same.
            return NSNumber(value: Int64(flag ? 1 : 0))
        case (.date, .millis(let ms)):
            return Date(timeIntervalSince1970: Double(ms) / 1000) as NSDate
        case (.data(asset: false), .data(let bytes)):
            return bytes as NSData
        case (.data(asset: true), .data(let bytes)):
            do {
                return CKAsset(fileURL: try assets.write(bytes, recordID: recordID, field: field.key))
            } catch {
                throw EncodeError.assetNotWritten(field: field.key, reason: error.localizedDescription)
            }
        case (.reference, .reference(let name)):
            return name as NSString
        case (.references, .referenceList(let names)):
            // An empty set is no value: a record carries only fields with one (`SyncRecord`), so an empty list is
            // sent as the field emptied and comes back absent.
            let set = Array(Set(names)).sorted()
            return set.isEmpty ? nil : set as NSArray
        default:
            throw EncodeError.wrongKind(field: field.key)
        }
    }

    // MARK: - In

    enum DecodeProblem: Error, Equatable, CustomStringConvertible {
        /// The record's name is not one the engine makes, or its type is not `HL` + the type its name says (a record
        /// SwiftData's mirror wrote, or one of the first probe runs' un-prefixed records).
        case notOurs(recordName: String, recordType: String)
        /// An asset over `assetByteLimit`, or one whose file could not be read.
        case assetUnreadable(field: String, reason: String)

        var description: String {
            switch self {
            case .notOurs(let name, let type): return "not an engine record: \(type) \(name)"
            case .assetUnreadable(let field, let reason): return "asset \(field) unreadable: \(reason)"
            }
        }
    }

    /// The record as the brain sees it: every key that maps onto a `SyncValue`, and the system fields.
    static func cloudRecord(from record: CKRecord) throws -> CloudRecord {
        guard let key = key(for: record.recordID), type(forRecordType: record.recordType) == key.type else {
            throw DecodeProblem.notOurs(recordName: record.recordID.recordName, recordType: record.recordType)
        }
        let known = Dictionary(((fields(ofType: key.type) ?? []) + [deletedAtField]).map { ($0.key, $0) },
                               uniquingKeysWith: { first, _ in first })
        var out = SyncRecord(key: key)
        for name in record.allKeys() {
            guard let raw = record[name] else { continue }
            if let value = try syncValue(raw, field: known[name], key: name) { out.fields[name] = value }
        }
        return CloudRecord(record: out, system: systemFields(of: record))
    }

    /// One stored value as a `SyncValue`: by the field's kind when this build knows the field and the stored value
    /// is of that kind, and otherwise by what CloudKit holds (a string, a whole number, a date, bytes, a list of
    /// strings), so that a key from a newer build reaches the brain for it to cut away. Nil for what no `SyncValue`
    /// can hold (a fractional number, a location, a list of anything but strings).
    static func syncValue(_ raw: __CKRecordObjCValue, field: SyncField?, key: String) throws -> SyncValue? {
        switch raw {
        case let text as String:
            if case .reference(_)? = field?.kind { return .reference(text) }
            return .string(text)
        case let number as NSNumber:
            if CFNumberIsFloatType(number) {
                // CloudKit keeps a Double apart from an Int64; HITList writes none. A whole one is read as the
                // integer it is (a field written by hand in the dashboard), anything else is left out.
                let double = number.doubleValue
                guard double.rounded() == double, abs(double) < 9.0e15 else { return nil }
                return wholeNumber(Int64(double), field: field)
            }
            return wholeNumber(number.int64Value, field: field)
        case let date as Date:
            return .date(date)
        case let data as Data:
            return .data(data)
        case let asset as CKAsset:
            return .data(try read(asset, field: key))
        case let list as [Any]:
            let strings = list.compactMap { $0 as? String }
            guard strings.count == list.count else { return nil }
            if case .reference(_)? = field?.kind { return nil } // a list where one name goes: not of the field's kind
            return strings.isEmpty ? nil : .references(strings)
        default:
            return nil
        }
    }

    private static func wholeNumber(_ number: Int64, field: SyncField?) -> SyncValue {
        // A bool is any whole number but 0 for true: what NSNumber's `boolValue` says, and what Core Data's mirror
        // read. Only HITList writes these fields and it writes 0 or 1.
        if field?.kind == .bool { return .bool(number != 0) }
        return .int(number)
    }

    private static func read(_ asset: CKAsset, field: String) throws -> Data {
        guard let url = asset.fileURL else {
            throw DecodeProblem.assetUnreadable(field: field, reason: "no file")
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= assetByteLimit else {
            throw DecodeProblem.assetUnreadable(field: field, reason: "\(size) bytes, over \(assetByteLimit)")
        }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= assetByteLimit else {
                throw DecodeProblem.assetUnreadable(field: field, reason: "\(data.count) bytes, over \(assetByteLimit)")
            }
            return data
        } catch let problem as DecodeProblem {
            throw problem
        } catch {
            throw DecodeProblem.assetUnreadable(field: field, reason: error.localizedDescription)
        }
    }
}

/// The temporary files a send's assets live in (`CKAsset` uploads from a file). One folder per transport; a record's
/// files are removed when iCloud has answered for it, the rest when the send ends, the folder at `removeAll()`, and
/// leftovers of a process that crashed mid-send the next time a transport starts (`sweepStale`).
final class AssetFiles: @unchecked Sendable {
    let folder: URL
    private let lock = NSLock()
    private var files: [CKRecord.ID: [URL]] = [:]

    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("HITListSyncAssets", isDirectory: true)

    init(folder: URL = AssetFiles.root.appendingPathComponent(UUID().uuidString, isDirectory: true)) {
        self.folder = folder
    }

    /// Writes `bytes` to a new file for one field of one record and remembers it.
    func write(_ bytes: Data, recordID: CKRecord.ID, field: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("asset")
        try bytes.write(to: url, options: .atomic)
        lock.lock()
        files[recordID, default: []].append(url)
        lock.unlock()
        return url
    }

    /// iCloud answered for this record (saved or refused): its files are no longer needed.
    func release(_ recordID: CKRecord.ID) {
        lock.lock()
        let urls = files.removeValue(forKey: recordID) ?? []
        lock.unlock()
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// The send ended, or the transport stopped: every file goes.
    func removeAll() {
        lock.lock()
        files = [:]
        lock.unlock()
        try? FileManager.default.removeItem(at: folder)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return files.values.reduce(0) { $0 + $1.count }
    }

    /// Removes other transports' folders not touched for a day: left by a process that ended mid-send. (A folder of a
    /// transport running now, in this process or another, is younger than that.)
    static func sweepStale(now: Date = Date(), olderThan age: TimeInterval = 24 * 3600) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in entries {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if now.timeIntervalSince(modified) > age { try? manager.removeItem(at: url) }
        }
    }
}
