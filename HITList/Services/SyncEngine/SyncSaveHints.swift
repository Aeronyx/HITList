import Foundation
import SwiftData
import HITListCore

/// What one save of a `ModelContext` tells the sync engine's brain to look at (`dev/SYNC-ENGINE.md` section 4: "for
/// the keys a save touched (the app passes them on `ModelContext.didSave`; a hint, never the truth)"). The brain finds
/// every change by comparing records, whether or not a hint came, so a hint may name too much but must never be the
/// only way a change is found; when in doubt it says "everything".
enum SyncSaveHint: Equatable, Sendable {
    /// The save touched none of the six synced models, or it was another container's (TipKit keeps a SwiftData store
    /// of its own in the app's process and posts the same notification: DATA-LAYER section 0, point 12). Nothing to do.
    case unrelated
    /// Look at these records: the rows the save inserted or changed.
    case keys(Set<SyncKey>)
    /// Look at everything: the save deleted a row (which can no longer say its `id`), or a row could not be named.
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

    /// The hint of one `ModelContext.didSave` notification for `container`'s store.
    ///
    /// Call it from an observer registered with `queue: nil`: it runs synchronously on the saving context's own thread
    /// inside `save()`, where the saved rows can be read from that context to learn their ids (a
    /// `PersistentIdentifier` does not carry the model's `id`). Read on any other thread, the context is not
    /// safe to touch, so the hint would have to be `.everything`.
    ///
    /// The notification's `userInfo`, as observed on macOS 26.7.1 (`round-28/SDK-SwiftData-History.md` section 8):
    /// `"inserted"`, `"updated"`, `"deleted"`, each an `Array<PersistentIdentifier>` and present on every save, even
    /// empty; `"invalidatedAll"` when a context's rows were all invalidated. `object` is the context that saved.
    static func hint(for note: Notification, container: ModelContainer) -> SyncSaveHint {
        let context = note.object as? ModelContext
        if let context, context.container !== container { return .unrelated }
        return hint(userInfo: note.userInfo, context: context)
    }

    /// The hint of a `didSave` `userInfo`; `context` is the context that saved (nil when unknown: then nothing can be
    /// named, and a save of a synced model is `.everything`).
    static func hint(userInfo: [AnyHashable: Any]?, context: ModelContext?) -> SyncSaveHint {
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
        if !deleted.isEmpty || !invalidated.isEmpty { return .everything }
        if inserted.isEmpty, updated.isEmpty { return .unrelated }
        guard let context else { return .everything }

        var keys = Set<SyncKey>()
        for id in inserted + updated {
            guard let model = SyncRecordMapping.models[id.entityName], let key = key(of: id, as: model, in: context) else {
                return .everything
            }
            keys.insert(key)
        }
        return keys.isEmpty ? .unrelated : .keys(keys)
    }

    private static func key<M: SyncMappedModel>(of id: PersistentIdentifier, as model: M.Type,
                                                in context: ModelContext) -> SyncKey? {
        // The row the context just saved is registered in it: no fetch, nothing faulted from the store.
        guard let row: M = context.registeredModel(for: id) else { return nil }
        return SyncSchema.key(M.syncType, id: row.id)
    }
}

/// Watches every save on `container`'s contexts and hands the brain its hint (nothing for an unrelated save). The
/// handler runs on the saving thread, inside the save: it must only pass the hint on (to the engine's own actor), never
/// wait or touch the store.
final class SyncSaveHintObserver {
    private var token: NSObjectProtocol?
    private let center: NotificationCenter

    init(container: ModelContainer, center: NotificationCenter = .default,
         handler: @escaping @Sendable (_ keys: Set<SyncKey>?) -> Void) {
        self.center = center
        token = center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak container] note in
            guard let container else { return }
            let hint = SyncSaveHints.hint(for: note, container: container)
            guard hint.isRelated else { return }
            handler(hint.keys)
        }
    }

    deinit { stop() }

    func stop() {
        if let token { center.removeObserver(token) }
        token = nil
    }
}
