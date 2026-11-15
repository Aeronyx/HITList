import Foundation
import SwiftData
import HITListCore

/// What was deleted on this device and the brain has not written down yet (`SyncLocalStore.deletions`,
/// `dev/SYNC-ENGINE.md` section 4): the only way the engine learns of a deletion here.
///
/// A deletion is taken down **before the store commits it**, from `ModelContext.willSave`, where a deleted row can
/// still say its `id` (`SyncSaveHintObserver`), and it is kept in the ledger's own file (one fact row per key,
/// `deleted|<type>/<name>`), so a crash in the instant after a delete does not lose it. It lives and dies with the
/// ledger: a ledger reset (another store file, a sign-out) forgets it too, so a note made for one store can never
/// delete anything from another. A note for a row that is still here (the save failed, or the row was made again) is
/// ignored by the brain and forgotten.
///
/// Used from the saving thread (`record`) and from the store's actor (`all`, `forget`): each call makes a context of
/// its own on the ledger's container, and the small state here is behind a lock.
final class SyncDeletionLog: @unchecked Sendable {
    static let prefix = "deleted|"

    private let ledger: ModelContainer?
    private let lock = NSLock()
    /// Without a ledger file (tests, a ledger that runs in memory): kept here, gone with the process.
    private var memory = Set<SyncKey>()
    /// Whether the file may hold a note: true until a read finds none, and again after every `record`. Saves a fetch
    /// on every compare, which is nearly always the answer "nothing".
    private var mayHold = true
    private var generation = 0

    /// `ledger`: the ledger's container (`SyncLedgerStore.container`); nil keeps the notes in memory.
    init(ledger: ModelContainer?) {
        self.ledger = ledger
    }

    /// Takes these down, durably when there is a ledger file. Called inside a save, on its thread; never throws (a
    /// note that could not be written leaves the item to come back from iCloud, which is the safe side).
    func record(_ keys: Set<SyncKey>) {
        guard !keys.isEmpty else { return }
        if let ledger {
            let context = ModelContext(ledger)
            context.autosaveEnabled = false
            // The fact's name is unique: one already there is replaced, not doubled.
            for key in keys { context.insert(LedgerFactRow(name: Self.prefix + key.description, value: Data())) }
            try? context.save()
        }
        lock.lock()
        if ledger == nil { memory.formUnion(keys) }
        mayHold = true
        generation += 1
        lock.unlock()
    }

    func all() -> Set<SyncKey> {
        lock.lock()
        let look = mayHold, started = generation, kept = memory
        lock.unlock()
        guard let ledger else { return kept }
        guard look else { return [] }
        let prefix = Self.prefix
        let context = ModelContext(ledger)
        let rows = (try? context.fetch(FetchDescriptor<LedgerFactRow>(predicate: #Predicate { $0.name.starts(with: prefix) }))) ?? []
        let keys = Set(rows.compactMap { Self.key(named: $0.name) })
        if keys.isEmpty {
            lock.lock()
            // Unless one was taken down while this read ran.
            if generation == started { mayHold = false }
            lock.unlock()
        }
        return keys
    }

    func forget(_ keys: Set<SyncKey>) {
        guard !keys.isEmpty else { return }
        lock.lock()
        memory.subtract(keys)
        lock.unlock()
        guard let ledger else { return }
        let names = keys.map { Self.prefix + $0.description }
        let context = ModelContext(ledger)
        context.autosaveEnabled = false
        guard let rows = try? context.fetch(FetchDescriptor<LedgerFactRow>(predicate: #Predicate { names.contains($0.name) })) else { return }
        for row in rows { context.delete(row) }
        try? context.save()
    }

    /// `deleted|TaskItem/6B1F…` back to its key (a type's name never holds a `/`).
    static func key(named name: String) -> SyncKey? {
        guard name.hasPrefix(prefix) else { return nil }
        let rest = name.dropFirst(prefix.count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let type = String(rest[..<slash]), item = String(rest[rest.index(after: slash)...])
        guard !type.isEmpty, !item.isEmpty else { return nil }
        return SyncKey(type: type, name: item)
    }
}
