import Foundation
import SwiftData
import HITListCore

/// What one save of a `ModelContext` tells the sync engine's brain to look at (`dev/SYNC-ENGINE.md` section 4). A
/// change is found by comparing records, so a hint may name too much and a missed one is found by the next whole
/// compare (a launch); when in doubt it says "everything". **A deletion is different: it is never found by
/// comparing.** The rows a save deletes are taken down before the save commits them (`SyncDeletionLog`, from
/// `willSave`, while a row can still say its `id`), and the hint names them like any other row.
enum SyncSaveHint: Equatable, Sendable {
    /// The save touched none of the six synced models, or it was another container's (TipKit keeps a SwiftData store
    /// of its own in the app's process and posts the same notification: DATA-LAYER section 0, point 12). Nothing to do.
    case unrelated
    /// Look at these records: the rows the save made, changed or deleted.
    case keys(Set<SyncKey>)
    /// Look at everything: a row could not be named.
    case everything

    /// What the brain is handed: the keys, or nil for everything. Nil also for `unrelated`, so callers check
    /// `isRelated` first.
    var keys: Set<SyncKey>? {
        if case .keys(let keys) = self { return keys }
        return nil
    }

    var isRelated: Bool { self != .unrelated }
}

enum SyncSaveHints {
    /// The entities the engine syncs, by name (`SyncSchema.types`, which are the models' own names).
    static let syncedEntityNames: Set<String> = Set(SyncSchema.types.map(\.name))

    /// The hint of one `ModelContext.didSave` notification for `container`'s store. `deleted`: the keys of the rows
    /// this save deleted, as they were taken down before it (`deletedKeys(in:)`, at `willSave`); nil when nobody did.
    ///
    /// Call it from an observer registered with `queue: nil`: it runs synchronously on the saving context's own thread
    /// inside `save()`, where the saved rows can be read from that context to learn their ids (a
    /// `PersistentIdentifier` does not carry the model's `id`). Read on any other thread, the context is not
    /// safe to touch, so the hint would have to be `.everything`.
    ///
    /// The notification's `userInfo`, as observed on macOS 26.7.1 (`round-28/SDK-SwiftData-History.md` section 8):
    /// `"inserted"`, `"updated"`, `"deleted"`, each an `Array<PersistentIdentifier>` and present on every save, even
    /// empty; `"invalidatedAll"` when a context's rows were all invalidated. `object` is the context that saved.
    static func hint(for note: Notification, container: ModelContainer, deleted: Set<SyncKey>? = nil) -> SyncSaveHint {
        let context = note.object as? ModelContext
        if let context, context.container !== container { return .unrelated }
        if let context, context.author == SwiftDataSyncStore.author {
            // The engine's own save: the brain is not told to look at what it just wrote. On the main context the
            // store has said what the person had pending in the same save; a context of its own holds nothing else.
            if Thread.isMainThread, let saving = SwiftDataSyncStore.savingOnMainContext,
               saving.context == ObjectIdentifier(context) {
                return saving.others
            }
            return .unrelated
        }
        return hint(userInfo: note.userInfo, context: context, deleted: deleted)
    }

    /// The hint of a `didSave` `userInfo`; `context` is the context that saved (nil when unknown: then nothing can be
    /// named, and a save of a synced model is `.everything`).
    static func hint(userInfo: [AnyHashable: Any]?, context: ModelContext?, deleted named: Set<SyncKey>? = nil) -> SyncSaveHint {
        func ids(_ key: ModelContext.NotificationKey) -> [PersistentIdentifier]? {
            guard let value = userInfo?[key.rawValue] else { return [] }
            // Observed as an array; the doc comment says a set. Either is read; anything else is a doubt.
            if let array = value as? [PersistentIdentifier] { return array.filter { syncedEntityNames.contains($0.entityName) } }
            if let set = value as? Set<PersistentIdentifier> { return set.filter { syncedEntityNames.contains($0.entityName) } }
            return nil
        }
        // A value of a shape not seen before is a doubt: everything.
        guard let inserted = ids(.insertedIdentifiers), let updated = ids(.updatedIdentifiers),
              let deleted = ids(.deletedIdentifiers), let invalidated = ids(.invalidatedAllIdentifiers) else {
            return .everything
        }
        if !invalidated.isEmpty { return .everything }
        if inserted.isEmpty, updated.isEmpty, deleted.isEmpty { return .unrelated }
        var keys = Set<SyncKey>()
        if !deleted.isEmpty {
            // A deleted row cannot say its `id` after the save: its key was taken down before it. Fewer keys than
            // rows (nobody was watching `willSave`, or two rows shared a key) is a doubt: everything, and what is
            // then found gone with no deletion taken down comes back from iCloud instead of being deleted there.
            guard let named, named.count >= deleted.count else { return .everything }
            keys.formUnion(named)
        }
        guard let context else { return .everything }
        for id in inserted + updated {
            guard let model = SyncRecordMapping.models[id.entityName], let key = key(of: id, as: model, in: context) else {
                return .everything
            }
            keys.insert(key)
        }
        return keys.isEmpty ? .unrelated : .keys(keys)
    }

    /// The keys of the synced rows `context` is about to delete, read while they can still say their `id` (at
    /// `willSave`, or just before a save): each deleted row, and under a task its sub-tasks at any depth, which the
    /// store takes with it. `excluding`: rows that are the engine's own to delete (its `apply`), never a person's.
    static func deletedKeys(in context: ModelContext, excluding engineRows: Set<ObjectIdentifier> = []) -> Set<SyncKey> {
        var keys = Set<SyncKey>()
        func take(_ model: any PersistentModel) {
            guard !engineRows.contains(ObjectIdentifier(model)), let mapped = model as? any SyncMappedModel else { return }
            guard keys.insert(key(of: mapped)).inserted else { return }
            if let task = model as? TaskItem { for sub in task.subtasks ?? [] { take(sub) } }
        }
        for model in context.deletedModelsArray { take(model) }
        return keys
    }

    private static func key<M: SyncMappedModel>(of row: M) -> SyncKey { SyncSchema.key(M.syncType, id: row.id) }

    private static func key<M: SyncMappedModel>(of id: PersistentIdentifier, as model: M.Type,
                                                in context: ModelContext) -> SyncKey? {
        // The row the context just saved is registered in it: no fetch, nothing faulted from the store.
        guard let row: M = context.registeredModel(for: id) else { return nil }
        return SyncSchema.key(M.syncType, id: row.id)
    }
}

/// Watches every save on `container`'s contexts. Before a save commits (`willSave`) it takes down the rows about to be
/// deleted (`SyncDeletionLog`); after it (`didSave`) it hands the brain the save's hint (nothing for an unrelated
/// save). Both handlers run on the saving thread, inside the save: they only write the note and pass the hint on (to
/// the engine's own actor), never wait for the brain.
final class SyncSaveHintObserver {
    private var tokens: [NSObjectProtocol] = []
    private let center: NotificationCenter
    /// The keys taken down at `willSave`, by the context saving, until its `didSave` names them in the hint. A save
    /// that throws leaves an entry behind; the context's next `willSave` replaces it.
    private let pending = PendingDeletions()

    private final class PendingDeletions: @unchecked Sendable {
        private let lock = NSLock()
        private var byContext: [ObjectIdentifier: Set<SyncKey>] = [:]
        func set(_ keys: Set<SyncKey>, for context: ObjectIdentifier) {
            lock.lock(); defer { lock.unlock() }
            byContext[context] = keys.isEmpty ? nil : keys
        }
        func take(_ context: ObjectIdentifier) -> Set<SyncKey>? {
            lock.lock(); defer { lock.unlock() }
            return byContext.removeValue(forKey: context)
        }
    }

    init(container: ModelContainer, deletions: SyncDeletionLog, center: NotificationCenter = .default,
         handler: @escaping @Sendable (_ keys: Set<SyncKey>?) -> Void) {
        self.center = center
        let pending = pending
        tokens.append(center.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { [weak container] note in
            guard let container, let context = note.object as? ModelContext, context.container === container else { return }
            // The engine's own save takes down the person's pending deletions itself (`SwiftDataSyncStore.apply`),
            // and its own are never a person's.
            guard context.author != SwiftDataSyncStore.author else { return }
            let keys = SyncSaveHints.deletedKeys(in: context)
            deletions.record(keys)
            pending.set(keys, for: ObjectIdentifier(context))
        })
        tokens.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak container] note in
            guard let container else { return }
            let deleted = (note.object as? ModelContext).flatMap { pending.take(ObjectIdentifier($0)) }
            let hint = SyncSaveHints.hint(for: note, container: container, deleted: deleted)
            guard hint.isRelated else { return }
            handler(hint.keys)
        })
    }

    deinit { stop() }

    func stop() {
        for token in tokens { center.removeObserver(token) }
        tokens = []
    }
}
