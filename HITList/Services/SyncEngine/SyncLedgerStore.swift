import CoreData
import Foundation
import OSLog
import SwiftData
import HITListCore

/// The sync engine's memory on disk (`SyncLedger`, `dev/SYNC-ENGINE.md` sections 4 and 7): for every record what
/// iCloud last held, fetched records set aside, a few facts, and the transport's own state.
///
/// A store of its own beside the data: its own SwiftData models in its own `ModelContainer`, never synced
/// (`cloudKitDatabase: .none`) and never part of `HITListSchema`, at `<App Group>/<store name>.ledger` (`HITList.ledger`
/// beside `HITList.store`, `HITList-s141.ledger` beside a side store), or in memory for tests and for an app store
/// that runs in memory. It is the engine's scratch memory and **disposable by design**: losing it, resetting it, or
/// starting with an empty one costs nothing of the person's, because the engine then merges everything afresh (a merge
/// without a memory, section 7). That is why `reset()` deletes every row of this store and a file that cannot be
/// opened is replaced by an empty ledger: COMMON's "never delete as a reset" protects the person's data, which deletes
/// mirror to every device; nothing here is the person's or leaves the device.
///
/// One transaction per `write`: one context, one `save()`, all of it or none of it. The transport's state is a fact in
/// the same file, so it is written by the same SQLite log as the entries: a bookmark is never on disk without the
/// entries written before it (T1: what an event brought is kept before the bookmark moves past it).
actor SyncLedgerStore: SyncLedger {
    struct DecodeFailed: Error, CustomStringConvertible {
        let what: String
        var description: String { "The sync ledger's \(what) could not be read" }
    }

    /// A test's way to make the next `write` throw half way: after its entries are in the context, before its
    /// deferred records, facts and the save. The write must then leave nothing behind.
    struct HalfWayFailure: Error {}

    nonisolated let container: ModelContainer
    /// The ledger's file; nil in memory.
    nonisolated let url: URL?
    /// Where an unreadable ledger file was moved when this one was opened (`open(at:)`), for the log and tests.
    nonisolated let movedAside: URL?

    private var failNextWriteHalfWay = false

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    static let schema = Schema([LedgerEntryRow.self, LedgerDeferredRow.self, LedgerFactRow.self])

    private init(container: ModelContainer, url: URL?, movedAside: URL?) {
        self.container = container
        self.url = url
        self.movedAside = movedAside
    }

    // MARK: - Opening

    /// The ledger beside the app's store at `storeURL`: the same folder and name, `.ledger` for `.store`.
    static func url(forStoreAt storeURL: URL) -> URL {
        storeURL.deletingPathExtension().appendingPathExtension("ledger")
    }

    /// The ledger for the app's store as `ModelContainerFactory` opened it: beside its file, or in memory when the
    /// store runs in memory or has no file of its own.
    static func forAppStore(storeURL: URL?, storeInMemory: Bool) -> SyncLedgerStore {
        guard let storeURL, !storeInMemory else { return inMemory() }
        return open(at: url(forStoreAt: storeURL))
    }

    /// An empty ledger in memory, gone with the process.
    static func inMemory() -> SyncLedgerStore {
        // A name of its own, so that two in-memory ledgers in one process (tests) never share anything.
        let config = ModelConfiguration("SyncLedger-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true,
                                        groupContainer: .none, cloudKitDatabase: .none)
        // An in-memory store has no file to be unreadable; failing here is a broken build, not a broken device.
        let container = try! ModelContainer(for: schema, configurations: [config])
        return SyncLedgerStore(container: container, url: nil, movedAside: nil)
    }

    /// The ledger at `url`. A file that cannot be opened is moved aside (never deleted: `<name>.unreadable-<time>`,
    /// with its `-wal` and `-shm`) and an empty ledger is made in its place, with a line in the log, because an empty
    /// ledger is always safe (`dev/SYNC-ENGINE.md` section 7). If even that fails, the ledger runs in memory.
    static func open(at url: URL) -> SyncLedgerStore {
        do {
            return SyncLedgerStore(container: try container(at: url), url: url, movedAside: nil)
        } catch {
            let first = error
            let aside: URL?
            do {
                aside = try moveAside(url)
                log.error("Sync ledger at \(url.path, privacy: .public) could not be opened (\(first.localizedDescription, privacy: .public)); moved to \(aside?.lastPathComponent ?? "nowhere", privacy: .public), starting with an empty ledger")
            } catch {
                log.fault("Sync ledger at \(url.path, privacy: .public) could not be opened (\(first.localizedDescription, privacy: .public)) nor moved aside (\(error.localizedDescription, privacy: .public)); running on an empty ledger in memory")
                return inMemory()
            }
            do {
                return SyncLedgerStore(container: try container(at: url), url: url, movedAside: aside)
            } catch {
                log.fault("Sync ledger: a new file at \(url.path, privacy: .public) could not be made either (\(error.localizedDescription, privacy: .public)); running on an empty ledger in memory")
                let memory = inMemory()
                return SyncLedgerStore(container: memory.container, url: nil, movedAside: aside)
            }
        }
    }

    private static func container(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration("SyncLedger", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        // SwiftData opens a file lazily in places; one read proves it can be read now, not at the engine's first
        // write.
        _ = try ModelContext(container).fetchCount(FetchDescriptor<LedgerFactRow>())
        return container
    }

    /// Moves the ledger's files to `<name>.unreadable-<UTC time>` beside them. The main file goes last, so that a move
    /// interrupted half way leaves it where the next launch tries again. Returns the main file's new place, or nil
    /// when there was no file.
    static func moveAside(_ url: URL, now: Date = .now) throws -> URL? {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        var stamp = formatter.string(from: now)
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        var n = 2
        while fm.fileExists(atPath: folder.appending(path: "\(name).unreadable-\(stamp)").path) {
            stamp = formatter.string(from: now) + "-\(n)"
            n += 1
        }
        var main: URL?
        for suffix in ["-wal", "-shm", ""] {
            let src = folder.appending(path: name + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = folder.appending(path: "\(name).unreadable-\(stamp)\(suffix)")
            try fm.moveItem(at: src, to: dst)
            if suffix.isEmpty { main = dst }
        }
        return main
    }

    // MARK: - SyncLedger

    /// A row this build cannot read (written by a newer build a tester then went back from, or damaged) is forgotten,
    /// not an error: the engine then has no memory of that one record and settles it afresh, which is always safe
    /// (`dev/SYNC-ENGINE.md` section 7). Throwing instead stopped the engine at every launch with no way out (the
    /// review's finding 6). What was dropped is in `unreadable`, for the sync log.
    func entries() async throws -> [LedgerEntry] {
        let context = makeContext()
        let rows = try context.fetch(FetchDescriptor<LedgerEntryRow>(sortBy: [SortDescriptor(\.key)]))
        let decoder = JSONDecoder()
        var out: [LedgerEntry] = []
        var dropped = false
        for row in rows {
            if let entry = try? decoder.decode(LedgerEntry.self, from: row.payload) {
                out.append(entry)
            } else {
                unreadable.append("entry \(row.key)")
                context.delete(row)
                dropped = true
            }
        }
        if dropped { try? context.save() }
        return out.sorted { $0.key < $1.key }
    }

    func deferred() async throws -> [CloudRecord] {
        let context = makeContext()
        let rows = try context.fetch(FetchDescriptor<LedgerDeferredRow>(sortBy: [SortDescriptor(\.key)]))
        let decoder = JSONDecoder()
        var out: [CloudRecord] = []
        var dropped = false
        for row in rows {
            if let record = try? decoder.decode(CloudRecord.self, from: row.payload) {
                out.append(record)
            } else {
                unreadable.append("waiting record \(row.key)")
                context.delete(row)
                dropped = true
            }
        }
        if dropped { try? context.save() }
        return out.sorted { $0.key < $1.key }
    }

    /// Rows that could not be read and were forgotten (`entries`, `deferred`), by key.
    private(set) var unreadable: [String] = []

    /// For tests: makes the stored rows of these keys unreadable, as a newer build's or a damaged one would be.
    func spoilForTests(entry: SyncKey? = nil, deferred: SyncKey? = nil) throws {
        let context = makeContext()
        if let entry, let row = try entryRows([Self.name(entry)], in: context)[Self.name(entry)] {
            row.payload = Data("not a ledger entry".utf8)
        }
        if let deferred, let row = try deferredRows([Self.name(deferred)], in: context)[Self.name(deferred)] {
            row.payload = Data("not a record".utf8)
        }
        try context.save()
    }

    func fact(_ name: String) async throws -> Data? {
        try factValue(name, in: makeContext())
    }

    /// All of `write` or none of it: one context, one save, rolled back when anything throws. Within the write, as
    /// `MemoryLedger` does: upserts, then removals (a key in both is removed); facts with a nil value are forgotten.
    func write(_ write: LedgerWrite) async throws {
        guard !write.isEmpty else { return }
        let context = makeContext()
        do {
            try apply(write, in: context)
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            Self.log.error("Sync ledger: a write was not saved, nothing of it is kept: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Forgets everything (every entry, deferred record and fact, the transport's state among them) by deleting every
    /// row of the ledger's own store: see the type's comment for why deleting is right here and nowhere else.
    func reset() async throws {
        let context = makeContext()
        do {
            try context.delete(model: LedgerEntryRow.self)
            try context.delete(model: LedgerDeferredRow.self)
            try context.delete(model: LedgerFactRow.self)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func loadTransportState() async -> Data? {
        do {
            return try factValue(LedgerFact.transport, in: makeContext())
        } catch {
            Self.log.error("Sync ledger: the transport's state could not be read (\(error.localizedDescription, privacy: .public)); it starts without one")
            return nil
        }
    }

    /// Durable when it returns: saved in the ledger's file before this returns. It cannot throw (the protocol's
    /// shape), so a failure is logged; the transport then starts from the state saved before, and what it brings
    /// again is handled again (T2: handling is idempotent).
    func saveTransportState(_ state: Data?) async {
        var change = LedgerWrite()
        change.facts = [LedgerFact.transport: state]
        do {
            try await write(change)
        } catch {
            Self.log.error("Sync ledger: the transport's state was not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Which store file the ledger belongs to

    /// The ledger's own fact naming the store file it was written for (`storeIdentity(at:)`).
    static let storeFact = "store"

    /// The identity of the store file at `url`: the UUID Core Data gives a SQLite store when the file is made
    /// (`NSStoreUUIDKey` in its metadata, read without opening the store; the same UUID a saved row's
    /// `PersistentIdentifier.storeIdentifier` carries). It survives a move of the file (the App Group move, a
    /// relaunch) and a restore of a backup into it; a new file (Settings → Reset local cache moves the store aside and
    /// starts an empty one) has a new one. Nil when there is no file or its metadata cannot be read (an in-memory store
    /// has no file: its ledger is in memory too). Public Core Data API, on every OS the app runs on.
    static func storeIdentity(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url, options: nil)
        return metadata?[NSStoreUUIDKey] as? String
    }

    /// Binds the ledger to the store file whose identity is `identity`: a ledger written for another file (an old
    /// ledger beside a store made new by Reset local cache would read as "everything deleted here"), or one with
    /// something in it and no store named at all, is reset first. Returns whether it was reset: the transport must
    /// then be reset too (T13), since its state was a fact of the ledger and is gone. Call it before the engine starts.
    @discardableResult
    func bind(toStore identity: String) async throws -> Bool {
        let context = makeContext()
        let bound = try factValue(Self.storeFact, in: context).flatMap { String(data: $0, encoding: .utf8) }
        if bound == identity { return false }
        let entries = try context.fetchCount(FetchDescriptor<LedgerEntryRow>())
        let deferred = try context.fetchCount(FetchDescriptor<LedgerDeferredRow>())
        let facts = try context.fetchCount(FetchDescriptor<LedgerFactRow>())
        let holdsSomething = entries + deferred + facts > 0
        if holdsSomething {
            Self.log.notice("Sync ledger was written for store \(bound ?? "none", privacy: .public), this store is \(identity, privacy: .public): forgetting it, the engine merges afresh")
            try await reset()
        }
        var change = LedgerWrite()
        change.facts = [Self.storeFact: Data(identity.utf8)]
        try await write(change)
        return holdsSomething
    }

    // MARK: - Tests

    func failNextWriteHalfWayThrough() { failNextWriteHalfWay = true }

    // MARK: -

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func factValue(_ name: String, in context: ModelContext) throws -> Data? {
        var descriptor = FetchDescriptor<LedgerFactRow>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.value
    }

    private func apply(_ write: LedgerWrite, in context: ModelContext) throws {
        let encoder = JSONEncoder()

        if !write.upsert.isEmpty || !write.remove.isEmpty {
            let keys = write.upsert.map { Self.name($0.key) } + write.remove.map(Self.name)
            var rows = try entryRows(keys, in: context)
            for entry in write.upsert {
                let key = Self.name(entry.key)
                let payload = try encoder.encode(entry)
                if let row = rows[key] {
                    if row.payload != payload { row.payload = payload }
                } else {
                    let row = LedgerEntryRow(key: key, payload: payload)
                    context.insert(row)
                    rows[key] = row
                }
            }
            for key in write.remove.map(Self.name) {
                guard let row = rows.removeValue(forKey: key) else { continue }
                context.delete(row)
            }
        }

        if failNextWriteHalfWay {
            failNextWriteHalfWay = false
            throw HalfWayFailure()
        }

        if !write.deferUpsert.isEmpty || !write.deferRemove.isEmpty {
            let keys = write.deferUpsert.map { Self.name($0.key) } + write.deferRemove.map(Self.name)
            var rows = try deferredRows(keys, in: context)
            for record in write.deferUpsert {
                let key = Self.name(record.key)
                let payload = try encoder.encode(record)
                if let row = rows[key] {
                    if row.payload != payload { row.payload = payload }
                } else {
                    let row = LedgerDeferredRow(key: key, payload: payload)
                    context.insert(row)
                    rows[key] = row
                }
            }
            for key in write.deferRemove.map(Self.name) {
                guard let row = rows.removeValue(forKey: key) else { continue }
                context.delete(row)
            }
        }

        for (name, value) in write.facts {
            var descriptor = FetchDescriptor<LedgerFactRow>(predicate: #Predicate { $0.name == name })
            descriptor.fetchLimit = 1
            let row = try context.fetch(descriptor).first
            switch (row, value) {
            case (let row?, let value?): if row.value != value { row.value = value }
            case (nil, let value?): context.insert(LedgerFactRow(name: name, value: value))
            case (let row?, nil): context.delete(row)
            case (nil, nil): break
            }
        }
    }

    private func entryRows(_ keys: [String], in context: ModelContext) throws -> [String: LedgerEntryRow] {
        let rows = try context.fetch(FetchDescriptor<LedgerEntryRow>(predicate: #Predicate { keys.contains($0.key) }))
        return Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func deferredRows(_ keys: [String], in context: ModelContext) throws -> [String: LedgerDeferredRow] {
        let rows = try context.fetch(FetchDescriptor<LedgerDeferredRow>(predicate: #Predicate { keys.contains($0.key) }))
        return Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A row's key: `<type>/<name>` (`SyncKey.description`). A type name never holds a `/`.
    private static func name(_ key: SyncKey) -> String { key.description }
}

// MARK: - The ledger's own models (its own schema, never `HITListSchema`, never synced)

/// One `LedgerEntry`, as JSON (`Codable`): the ledger is read whole and written by key, never queried by its fields.
@Model
final class LedgerEntryRow {
    @Attribute(.unique) var key: String = ""
    var payload: Data = Data()

    init(key: String, payload: Data) {
        self.key = key
        self.payload = payload
    }
}

/// One fetched record set aside (`LedgerWrite.deferUpsert`), as JSON.
@Model
final class LedgerDeferredRow {
    @Attribute(.unique) var key: String = ""
    var payload: Data = Data()

    init(key: String, payload: Data) {
        self.key = key
        self.payload = payload
    }
}

/// One named fact (`LedgerFact`).
@Model
final class LedgerFactRow {
    @Attribute(.unique) var name: String = ""
    var value: Data = Data()

    init(name: String, value: Data) {
        self.name = name
        self.value = value
    }
}
