import Foundation

// A device's items and the engine's memory, held in memory: what the engine's tests and the pretend iCloud's
// simulated devices run on, and the reference for what the app's own implementations must do (`SyncStorage.swift`).

/// The device's items in memory. Behaves as `SyncLocalStore` asks of the app's store: required fields filled in,
/// a reference to an item that isn't here written as none, deleting a task deletes its sub-tasks (the one cascade
/// the app's models have), and deleting anything else clears the references to it.
public actor MemoryLocalStore: SyncLocalStore {
    private var items: [SyncKey: SyncRecord] = [:]
    /// How many times `apply` wrote something, for tests.
    public private(set) var applyCount = 0

    public init(_ records: [SyncRecord] = []) {
        for record in records { items[record.key] = SyncSchema.filled(record) }
    }

    public func records() async throws -> [SyncRecord] {
        items.values.sorted { $0.key < $1.key }
    }

    public func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord] {
        keys.compactMap { items[$0] }.sorted { $0.key < $1.key }
    }

    public func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey> {
        var stale = Set<SyncKey>()
        var saves: [SyncRecord] = []
        var deletes: [SyncKey] = []
        for write in writes {
            guard RecordMerge.same(items[write.key], write.expected) else {
                stale.insert(write.key)
                continue
            }
            if let record = write.record { saves.append(record) } else { deletes.append(write.key) }
        }
        // Those pointed at before those that point at them: by type, then a task after its parent.
        let order = Dictionary(uniqueKeysWithValues: SyncSchema.types.enumerated().map { ($1.name, $0) })
        saves.sort { (order[$0.key.type] ?? .max, $0.fields["parent"] == nil ? 0 : 1) < (order[$1.key.type] ?? .max, $1.fields["parent"] == nil ? 0 : 1) }
        for record in saves { items[record.key] = SyncSchema.filled(record) }
        for record in saves { items[record.key] = whole(items[record.key] ?? record) }
        for key in deletes { remove(key) }
        if !saves.isEmpty || !deletes.isEmpty { applyCount += 1 }
        return stale
    }

    // MARK: What a person does on the device (tests)

    /// Adds or changes an item, as the app would save it.
    public func put(_ record: SyncRecord) {
        items[record.key] = whole(SyncSchema.filled(record))
    }

    /// Changes fields of an item that is here (a nil value empties the field).
    public func edit(_ key: SyncKey, _ changes: [String: SyncValue?]) {
        guard var record = items[key] else { return }
        for (field, value) in changes { record.fields[field] = value }
        items[key] = whole(SyncSchema.filled(record))
    }

    /// Deletes an item, as the app would: a task's sub-tasks with it, and references to it cleared.
    public func delete(_ key: SyncKey) { remove(key) }

    public func record(_ key: SyncKey) -> SyncRecord? { items[key] }

    public var count: Int { items.count }

    // MARK: -

    private func remove(_ key: SyncKey) {
        guard items.removeValue(forKey: key) != nil else { return }
        // Its sub-tasks first, each with its own (SwiftData's cascade goes all the way down); then what is left drops
        // its references to whatever went. Walking a copy taken before the recursion would put back what the
        // recursion removed (brief 138: a grandchild came back).
        if key.type == "TaskItem" {
            let children = items.values.filter { $0.key.type == "TaskItem" && $0.fields["parent"] == .reference(key.name) }
            for child in children { remove(child.key) }
        }
        for other in Array(items.keys) {
            if let record = items[other] { items[other] = whole(record) }
        }
    }

    /// `record` with every reference to an item that isn't here taken out.
    private func whole(_ record: SyncRecord) -> SyncRecord {
        guard let type = SyncSchema.type(record.key.type) else { return record }
        var out = record
        for field in type.fields {
            switch (field.kind, record.fields[field.key]) {
            case (.reference(let target), .reference(let name)?):
                if items[SyncKey(type: target, name: name)] == nil { out.fields[field.key] = nil }
            case (.references(let target), .referenceList(let names)?):
                let here = names.filter { items[SyncKey(type: target, name: $0)] != nil }
                out.fields[field.key] = here.isEmpty ? nil : .references(here)
            default: break
            }
        }
        return out
    }
}

/// The engine's memory in memory. `fail` makes the next write throw, for tests of a write that doesn't land.
public actor MemoryLedger: SyncLedger {
    public struct WriteFailed: Error {}

    private var byKey: [SyncKey: LedgerEntry] = [:]
    private var waiting: [SyncKey: CloudRecord] = [:]
    private var facts: [String: Data] = [:]
    private var failNextWrite = false
    public private(set) var writeCount = 0

    public init() {}

    public func entries() async throws -> [LedgerEntry] { byKey.values.sorted { $0.key < $1.key } }

    public func deferred() async throws -> [CloudRecord] { waiting.values.sorted { $0.key < $1.key } }

    public func fact(_ name: String) async throws -> Data? { facts[name] }

    public func write(_ write: LedgerWrite) async throws {
        if failNextWrite {
            failNextWrite = false
            throw WriteFailed()
        }
        for entry in write.upsert { byKey[entry.key] = entry }
        for key in write.remove { byKey[key] = nil }
        for record in write.deferUpsert { waiting[record.key] = record }
        for key in write.deferRemove { waiting[key] = nil }
        for (name, value) in write.facts { facts[name] = value }
        writeCount += 1
    }

    public func reset() async throws {
        byKey = [:]
        waiting = [:]
        facts = [:]
    }

    public func loadTransportState() async -> Data? { facts[LedgerFact.transport] }

    public func saveTransportState(_ state: Data?) async { facts[LedgerFact.transport] = state }

    public func failNext() { failNextWrite = true }

    public func entry(_ key: SyncKey) -> LedgerEntry? { byKey[key] }
}
