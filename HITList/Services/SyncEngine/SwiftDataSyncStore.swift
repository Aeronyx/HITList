import Foundation
import OSLog
import SwiftData
import HITListCore

/// The device's items as the sync engine's brain sees them (`SyncLocalStore`, `dev/SYNC-ENGINE.md` sections 2 to 5):
/// the app's six models read as records, and the brain's writes made on the app's own `ModelContainer`.
///
/// **Reads run off the main actor**: an actor (the Swift runtime's own serial executor, on the shared pool, never the
/// main thread), and each read makes a `ModelContext` of its own and lets it go when it returns, so it reads what the
/// store holds at that moment (a context kept between calls returns the values it fetched before). Not a
/// `@ModelActor`: its context is made in its `init` and runs on the main queue when that `init` runs on the main thread.
///
/// **Writes go through the app's main context, on the main actor** (`Writer.mainContext`). Round 28 found
/// (`SwiftDataSyncStoreTests`, on a store file and in memory alike, macOS 26.7.1) that SwiftData's main context never
/// takes in a save made by another context of the same container: a row a view has shown keeps its old values, and
/// the person's next save of that row writes the whole old copy back, reverting what the engine wrote, after which
/// the brain would find the old value "changed here" and send it to iCloud, undoing another device's edit everywhere.
/// SwiftData has no public way to refresh a registered row, so the engine writes where the views read. Then the
/// `expected` check sees the person's unsaved edit too (the key comes back stale and the brain decides again once it is
/// saved), and every view sees the write at once. The cost: the main thread is busy for the length of an apply (5,032
/// inserts ~1.4 s on this Mac, a first sync; a usual apply is a few rows). `Writer.ownContext` keeps the other road for
/// the tests that pin why it is not taken.
///
/// **The person's edit is never lost**: a write goes ahead only when the row still equals the record the brain decided
/// on (`expected`, compared as `SyncRecord.comparable`, unsaved edits on the main context included); otherwise the key
/// comes back and the brain decides again on the newer record.
///
/// The day anchoring (`DayAnchoring.SaveHook`) runs inside every save on the app's container, this one's too: a day
/// written as a local midnight is stored anchored, and the next read says so (the brain then sends the anchored day:
/// one more send at most, `dev/SYNC-ENGINE.md` section 8).
actor SwiftDataSyncStore: SyncLocalStore {
    /// `ModelContext.author` of the engine's saves, so that a `didSave` observer or a history transaction can tell
    /// them. On the main context it is set for the engine's save only (whatever the person had pending, which autosave
    /// would have saved anyway, is in the same save) and put back after.
    static let author = "HITList.syncEngine"

    /// Where `apply` writes.
    enum Writer: Sendable {
        /// The app's main context, on the main actor: what the app uses (see the type's comment for why).
        case mainContext
        /// A context of the engine's own, off the main actor: SwiftData's main context does not take its saves in.
        /// Only for the tests that pin that.
        case ownContext
    }

    nonisolated let container: ModelContainer
    nonisolated let writer: Writer

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    init(container: ModelContainer, writer: Writer = .mainContext) {
        self.container = container
        self.writer = writer
    }

    func records() async throws -> [SyncRecord] {
        try Self.read(nil, in: container)
    }

    func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord] {
        guard !keys.isEmpty else { return [] }
        return try Self.read(keys, in: container)
    }

    func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey> {
        guard !writes.isEmpty else { return [] }
        switch writer {
        case .mainContext:
            let container = container
            return try await MainActor.run { try Self.apply(writes, on: container.mainContext, shared: true) }
        case .ownContext:
            return try Self.apply(writes, in: container)
        }
    }

    // MARK: - The work, on the calling thread (the actor's, or a test's own)

    /// A context of the engine's own: no autosave (a write is saved once, whole, or not at all).
    static func makeContext(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.author = author
        return context
    }

    /// The records of every row (nil) or of the rows with these keys, sorted by key. Throws
    /// `SyncStoreError.duplicates` when two rows share a key (several `Profile` rows among them).
    static func read(_ keys: Set<SyncKey>?, in container: ModelContainer) throws -> [SyncRecord] {
        let context = makeContext(container)
        var out: [SyncKey: SyncRecord] = [:]
        var duplicates = Set<SyncKey>()
        for type in SyncSchema.types {
            guard let model = SyncRecordMapping.models[type.name] else { continue }
            let wanted = keys?.filter { $0.type == type.name }
            if let wanted, wanted.isEmpty { continue }
            for record in try records(of: model, keys: wanted, in: context) {
                if let wanted, !wanted.contains(record.key) { continue }
                if out.updateValue(record, forKey: record.key) != nil { duplicates.insert(record.key) }
            }
        }
        if !duplicates.isEmpty { throw SyncStoreError.duplicates(duplicates.sorted()) }
        return out.values.sorted { $0.key < $1.key }
    }

    private static func records<M: SyncMappedModel>(of model: M.Type, keys: Set<SyncKey>?,
                                                    in context: ModelContext) throws -> [SyncRecord] {
        try rows(of: model, keys: keys, in: context).map { SyncRecordMapping.record(of: $0) }
    }

    /// The rows of one model for these keys (nil: every row). A key whose name is not an id names no row, except the
    /// singleton's own name, whose rows are all of them.
    private static func rows<M: SyncMappedModel>(of model: M.Type, keys: Set<SyncKey>?,
                                                 in context: ModelContext) throws -> [M] {
        guard let keys else { return try M.syncFetch(ids: nil, in: context) }
        if let singleton = M.syncType.singleton {
            return keys.contains(where: { $0.name == singleton }) ? try M.syncFetch(ids: nil, in: context) : []
        }
        let ids = keys.compactMap { UUID(uuidString: $0.name) }
        return ids.isEmpty ? [] : try M.syncFetch(ids: ids, in: context)
    }

    /// `SyncLocalStore.apply`, in one context and one save: every write whose `expected` still holds, none of the
    /// others, all or nothing.
    ///
    /// Order: the rows of every written key are read first, as the context holds them (on the main context: with the
    /// person's unsaved edits), and each write's `expected` is checked against them (all before anything changes, so a
    /// write is never checked against another write of the same call). Then every inserted or updated row gets its values (in `SyncSchema.types` order, a task after its
    /// parent), then its references (so a reference to an item the same call inserts is found, whatever the order),
    /// then the deletions (`context.delete`; SwiftData's own rules then take a task's sub-tasks and clear references to
    /// what went). One `save()`; when it throws, nothing of the call is in the store (a context of its own is rolled
    /// back; the main context is handled as `apply(_:on:shared:)` says).
    /// A call that changes nothing itself (every write stale, or every value already equal) does not save at all.
    ///
    /// `beforeSave` is for tests: it runs with every change made in the context and nothing saved, and a throw there
    /// takes the same road as a save that throws.
    static func apply(_ writes: [LocalWrite], in container: ModelContainer,
                      beforeSave: (() throws -> Void)? = nil) throws -> Set<SyncKey> {
        try apply(writes, on: makeContext(container), shared: false, beforeSave: beforeSave)
    }

    /// `apply` on `context`. `shared`: the context is the app's main context, which may hold the person's unsaved
    /// edits, so a failed save is never answered with `rollback()` (that would drop them too): the engine's own
    /// changes are undone by hand instead (rows it changed are written back to what they were, rows it inserted are
    /// deleted). Rows it deleted cannot be brought back in the context: they stay deleted and go with the next save,
    /// which is what the brain decided for them anyway.
    static func apply(_ writes: [LocalWrite], on context: ModelContext, shared: Bool,
                      beforeSave: (() throws -> Void)? = nil) throws -> Set<SyncKey> {
        guard !writes.isEmpty else { return [] }
        var rows = try existingRows(Set(writes.map(\.key)), in: context)
        let before = rows.mapValues { record(of: $0) }

        var stale = Set<SyncKey>()
        var saves: [(order: Int, key: SyncKey, record: SyncRecord)] = []
        var deletes: [SyncKey] = []
        for write in writes {
            guard before[write.key]?.comparable == write.expected?.comparable else {
                stale.insert(write.key)
                continue
            }
            if let record = write.record, !record.isDeleted {
                saves.append((saves.count, write.key, record))
            } else {
                deletes.append(write.key)
            }
        }

        // Those pointed at before those that point at them: by type, then a task after its parent.
        let typeOrder = Dictionary(uniqueKeysWithValues: SyncSchema.types.enumerated().map { ($1.name, $0) })
        saves.sort { a, b in
            let ta = typeOrder[a.key.type] ?? .max, tb = typeOrder[b.key.type] ?? .max
            if ta != tb { return ta < tb }
            let pa = a.record.fields["parent"] == nil ? 0 : 1, pb = b.record.fields["parent"] == nil ? 0 : 1
            if pa != pb { return pa < pb }
            return a.order < b.order
        }

        // Values: insert the rows that are not here, update the ones that are.
        var insertedKeys = Set<SyncKey>()
        // Whether the engine itself changed anything: the context's own `hasChanges` also counts the person's pending
        // edits on the main context, which are not the engine's to save.
        var changedSomething = false
        var written: [(key: SyncKey, record: SyncRecord)] = []
        for save in saves {
            guard let model = SyncRecordMapping.models[save.key.type] else {
                log.error("Sync engine: no model for \(save.key.description, privacy: .public); nothing written for it")
                continue
            }
            let row: any SyncMappedModel
            if let existing = rows[save.key] {
                row = existing
            } else {
                guard let inserted = insert(model, key: save.key, in: context) else {
                    log.error("Sync engine: \(save.key.description, privacy: .public) names no row id; nothing written for it")
                    continue
                }
                row = inserted
                rows[save.key] = inserted
                insertedKeys.insert(save.key)
                changedSomething = true
            }
            if !writeValues(save.record, to: row).isEmpty { changedSomething = true }
            written.append((save.key, save.record))
        }

        // References: to rows of this call first, then to rows already in the store; none when neither has it.
        var looked: [SyncKey: (any SyncMappedModel)?] = [:]
        let lookup: SyncModelLookup = { key in
            if let row = rows[key] { return row }
            if let known = looked[key] { return known }
            let found = (try? existingRows([key], in: context))?[key]
            looked[key] = .some(found)
            return found
        }
        for item in written {
            guard let row = rows[item.key] else { continue }
            if !writeReferences(item.record, to: row, lookup: lookup).isEmpty { changedSomething = true }
        }

        for key in deletes {
            guard let row = rows[key] else { continue }
            context.delete(row)
            changedSomething = true
        }

        guard changedSomething else { return stale }
        let author = context.author
        context.author = Self.author
        defer { context.author = author }
        do {
            try beforeSave?()
            try context.save()
        } catch {
            if shared {
                undo(written.map(\.key), before: before, inserted: insertedKeys, rows: rows, in: context, lookup: lookup)
            } else {
                context.rollback()
            }
            log.error("Sync engine: a write of \(writes.count) records was not saved, nothing of it is in the store: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        return stale
    }

    /// The engine's changes taken back out of a shared context after its save failed: inserted rows deleted (a row
    /// never saved simply goes), changed rows written back to their records from before the call.
    private static func undo(_ keys: [SyncKey], before: [SyncKey: SyncRecord], inserted: Set<SyncKey>,
                             rows: [SyncKey: any SyncMappedModel], in context: ModelContext, lookup: SyncModelLookup) {
        for key in keys {
            guard let row = rows[key] else { continue }
            if inserted.contains(key) {
                context.delete(row)
            } else if let record = before[key] {
                writeValues(record, to: row)
                writeReferences(record, to: row, lookup: lookup)
            }
        }
    }

    /// The rows saved now for these keys, by key. Throws `SyncStoreError.duplicates` for a key with more than one row.
    private static func existingRows(_ keys: Set<SyncKey>, in context: ModelContext) throws -> [SyncKey: any SyncMappedModel] {
        var out: [SyncKey: any SyncMappedModel] = [:]
        var duplicates = Set<SyncKey>()
        for type in SyncSchema.types {
            let wanted = keys.filter { $0.type == type.name }
            guard !wanted.isEmpty, let model = SyncRecordMapping.models[type.name] else { continue }
            for row in try anyRows(of: model, keys: wanted, in: context) {
                let key = SyncSchema.key(type, id: row.id)
                guard wanted.contains(key) else { continue }
                if out.updateValue(row, forKey: key) != nil { duplicates.insert(key) }
            }
        }
        if !duplicates.isEmpty { throw SyncStoreError.duplicates(duplicates.sorted()) }
        return out
    }

    private static func anyRows<M: SyncMappedModel>(of model: M.Type, keys: Set<SyncKey>,
                                                    in context: ModelContext) throws -> [any SyncMappedModel] {
        try rows(of: model, keys: keys, in: context)
    }

    private static func record<M: SyncMappedModel>(of row: M) -> SyncRecord { SyncRecordMapping.record(of: row) }

    /// A new row for `key`, inserted into `context`: its id is the key's name, or the singleton's own id.
    private static func insert<M: SyncMappedModel>(_ model: M.Type, key: SyncKey,
                                                   in context: ModelContext) -> (any SyncMappedModel)? {
        let id: UUID
        if M.syncType.singleton != nil {
            id = SyncRecordMapping.profileRowID
        } else if let parsed = UUID(uuidString: key.name), parsed.uuidString == key.name {
            id = parsed
        } else {
            return nil
        }
        let row = M.syncInsert(id: id)
        context.insert(row)
        return row
    }

    @discardableResult
    private static func writeValues<M: SyncMappedModel>(_ record: SyncRecord, to row: M) -> [String] {
        SyncRecordMapping.write(record, to: row, pass: .values, lookup: { _ in nil })
    }

    @discardableResult
    private static func writeReferences<M: SyncMappedModel>(_ record: SyncRecord, to row: M,
                                                            lookup: SyncModelLookup) -> [String] {
        SyncRecordMapping.write(record, to: row, pass: .references, lookup: lookup)
    }
}
