import CoreData
import Foundation
import OSLog
import SQLite3
import SwiftData
import HITListCore

/// The sync engine's memory on disk (`SyncLedger`, `dev/SYNC-ENGINE.md` sections 4 and 7): for every record what
/// iCloud last held, fetched records set aside, a few facts, and the transport's own state.
///
/// A store of its own beside the data: its own SwiftData models in its own `ModelContainer`, never synced
/// (`cloudKitDatabase: .none`) and never part of `HITListSchema`, at `<App Group>/<store name>.ledger` (`HITList.ledger`
/// beside `HITList.store`, `HITList-s141.ledger` beside a side store), or in memory for tests and for an app store
/// that runs in memory. It is the engine's scratch memory and **disposable by design, but for one thing**: losing it,
/// resetting it, or starting with an empty one costs nothing of the person's items, because the engine then merges
/// everything afresh (a merge without a memory, section 7); but the deletions this device has taken down and not yet
/// sent live here too, and with them lost those items come back. That is why `reset()` deletes every row of this store,
/// while a file is moved aside only when it is damaged beyond opening (`open(at:)`): one that cannot be opened now is
/// left as it is, and the engine waits for it. COMMON's "never delete as a reset" protects the person's data, which
/// deletes mirror to every device; nothing here leaves the device.
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
    /// store runs in memory or has no file of its own. Throws `NotOpened` as `open(at:)` does.
    static func forAppStore(storeURL: URL?, storeInMemory: Bool) throws -> SyncLedgerStore {
        guard let storeURL, !storeInMemory else { return inMemory() }
        return try open(at: url(forStoreAt: storeURL))
    }

    /// The ledger's file is there (or should be) and cannot be opened now, and was left as it is: the engine holds
    /// `failed` with these words and tries again at the next start or "Try again".
    struct NotOpened: Error, CustomStringConvertible {
        let words: String
        var description: String { words }
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

    /// The ledger at `url`.
    ///
    /// A file **damaged beyond opening** (`classify`: SQLite finds no database or a corrupt one, or a sound file this
    /// build's models cannot open) is moved aside (never deleted: `<name>.unreadable-<time>`, with its `-wal` and
    /// `-shm`) and an empty ledger is made in its place, with a line in the log: a merge without a memory
    /// (`dev/SYNC-ENGINE.md` section 7); the deletions not yet sent go with the file, which nothing could read anyway.
    ///
    /// Anything else (no permission, a full disk, the file's protection on a phone not unlocked since it started, the
    /// file busy, a reason not known) throws `NotOpened` and leaves every file as it was: the deletions this device has
    /// not sent are in it, and moving it aside would bring those items back. Nothing runs in memory in its place (a
    /// ledger in memory would forget those deletions at the next launch just the same).
    static func open(at url: URL) throws -> SyncLedgerStore {
        do {
            return SyncLedgerStore(container: try container(at: url), url: url, movedAside: nil)
        } catch {
            switch classify(error, file: check(url)) {
            case .notNow(let words):
                log.error("Sync ledger at \(url.path, privacy: .public) cannot be opened now (\(words, privacy: .public)); left as it is, the engine waits")
                throw NotOpened(words: "The sync engine's memory could not be opened: \(words)")
            case .damaged(let words):
                let aside: URL?
                do {
                    aside = try moveAside(url)
                } catch {
                    log.fault("Sync ledger at \(url.path, privacy: .public) is damaged (\(words, privacy: .public)) and could not be moved aside (\(error.localizedDescription, privacy: .public))")
                    throw NotOpened(words: "The sync engine's memory is damaged and could not be set aside: \(error.localizedDescription)")
                }
                log.error("Sync ledger at \(url.path, privacy: .public) is damaged (\(words, privacy: .public)); moved to \(aside?.lastPathComponent ?? "nowhere", privacy: .public), starting with an empty ledger")
                do {
                    return SyncLedgerStore(container: try container(at: url), url: url, movedAside: aside)
                } catch {
                    log.fault("Sync ledger: a new file at \(url.path, privacy: .public) could not be made (\(error.localizedDescription, privacy: .public))")
                    throw NotOpened(words: "The sync engine's memory could not be made: \(error.localizedDescription)")
                }
            }
        }
    }

    /// What a failure to open the ledger is.
    enum OpenFailure: Equatable {
        /// Damaged beyond opening: moved aside, an empty ledger in its place.
        case damaged(String)
        /// Cannot be opened now: left alone; the engine holds and tries again later.
        case notNow(String)
    }

    /// What SQLite itself makes of the ledger's file, read-only (`check`): SwiftData's own error does not always carry
    /// the cause.
    enum FileCheck: Equatable {
        case missing
        /// Not a database, or a damaged one (`SQLITE_NOTADB`, `SQLITE_CORRUPT`, or a quick check that is not "ok").
        case damaged(String)
        /// SQLite could not read it now (no permission, the file's protection, locked or busy, an I/O error).
        case unreadable(String)
        /// A sound SQLite database.
        case sound
    }

    /// Damage is only what SQLite itself calls damage, or a sound file whose models this build cannot open (Core
    /// Data's incompatible-model codes in the error's chain: a newer build's ledger after a tester went back; the
    /// ledger's models carry no migration plan, so this build could never open it). Everything else, a reason not
    /// known included, is "not now": holding wrongly costs sync until the next try, moving aside wrongly costs the
    /// deletions not yet sent. A full disk or a refused permission named in the chain is never damage.
    static func classify(_ error: Error, file: FileCheck) -> OpenFailure {
        let chain = errorChain(error)
        let cause = chain.last?.localizedDescription ?? error.localizedDescription
        switch file {
        case .damaged(let words):
            return .damaged(words)
        case .missing:
            return .notNow(cause)
        case .unreadable(let words):
            return .notNow(words)
        case .sound:
            if let named = chain.first(where: { $0.domain == NSCocoaErrorDomain && notNowCodes.contains($0.code) }) {
                return .notNow(named.localizedDescription)
            }
            if let model = chain.first(where: { $0.domain == NSCocoaErrorDomain && incompatibleModelCodes.contains($0.code) }) {
                return .damaged(model.localizedDescription)
            }
            return .notNow(cause)
        }
    }

    /// Foundation's codes for a disk that is full or read-only, or a permission refused.
    static let notNowCodes: Set<Int> = [NSFileWriteOutOfSpaceError, NSFileReadNoPermissionError, NSFileWriteNoPermissionError,
                                        NSFileWriteVolumeReadOnlyError]

    /// Core Data: the store's model is not this build's and cannot be brought to it.
    static let incompatibleModelCodes: Set<Int> = [NSPersistentStoreIncompatibleVersionHashError, NSMigrationMissingSourceModelError,
                                                   NSPersistentStoreIncompatibleSchemaError, NSMigrationError,
                                                   NSMigrationMissingMappingModelError]

    private static func errorChain(_ error: Error) -> [NSError] {
        var out: [NSError] = []
        var next: NSError? = error as NSError
        while let current = next, out.count < 8 {
            out.append(current)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return out
    }

    /// Opens the file read-only with SQLite and runs `PRAGMA quick_check(1)`. Never writes, never makes a file.
    static func check(_ url: URL) -> FileCheck {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        func failure(_ code: Int32) -> FileCheck {
            let words = "\(String(cString: sqlite3_errstr(code))) (\(code))"
            switch code & 0xff {
            case SQLITE_NOTADB, SQLITE_CORRUPT: return .damaged(words)
            default: return .unreadable(words)
            }
        }
        let opened = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK else { return failure(opened) }
        // A writer that holds the file for a moment (this process's own container, just closing) is waited out:
        // "busy" is no answer about the file. Half a second at most; a lock that outlasts it reads as unreadable,
        // which holds and never moves the file aside. (Seen in round 32: the check right after a save answered
        // "database is locked" on the iPhone simulator.)
        sqlite3_busy_timeout(db, 500)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check(1)", -1, &statement, nil) == SQLITE_OK else {
            return failure(sqlite3_extended_errcode(db))
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return failure(sqlite3_extended_errcode(db)) }
        let answer = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        return answer == "ok" ? .sound : .damaged("quick check: \(answer)")
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
        if dropped {
            // The record of a forgotten entry must be settled afresh, and an item that is not on this device is only
            // ever settled when iCloud's record arrives: the bookmark is still past it. So everything is asked for
            // again, once (the brain's own fact for it: `SyncCore` resets the transport at its start when it is set).
            // Without this the device would lack an item iCloud holds, for good (the review, under finding 6).
            let name = Self.refetchFact
            var descriptor = FetchDescriptor<LedgerFactRow>(predicate: #Predicate { $0.name == name })
            descriptor.fetchLimit = 1
            if let row = (try? context.fetch(descriptor))?.first {
                row.value = Data([1])
            } else {
                context.insert(LedgerFactRow(name: name, value: Data([1])))
            }
            try? context.save()
        }
        return out.sorted { $0.key < $1.key }
    }

    /// The brain's fact that asks for everything to be fetched again at its next start (`SyncCore.refetchFact`).
    static let refetchFact = "refetch"

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

    func facts(prefix: String) async throws -> [String: Data] {
        let rows = try makeContext().fetch(FetchDescriptor<LedgerFactRow>(predicate: #Predicate { $0.name.starts(with: prefix) }))
        return Dictionary(rows.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
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
