#if DEBUG
import Foundation
import OSLog
import HITListCore

/// Debug only (`-syncEnginePretend <name>`, side stores only): the app's whole engine on a pretend iCloud kept in one
/// file, so that two Debug Mac apps on two side stores sync with each other and never with iCloud (brief 143, item 8).
///
/// `FakeCloud` is the pretend iCloud of the tests, in memory, in one process; this is its rules kept in a file that
/// several processes share: one zone of records, a change tag per version, a log of changes (each record's place, and
/// the records removed for good), read and written whole under an exclusive `flock`. The transport keeps the rules
/// the brain relies on (T1 to T4, T6 to T8, T10, T12's first sign-in, T13, T14): events one at a time, each handled
/// before the bookmark moves; a save refused whole when its token is not iCloud's current one (the conflict carries
/// iCloud's version); a save on a removed record `unknownItem`; every field of the type written, a key it does not list
/// kept; a change off the list before `sent` is delivered. No zone loss, quota or network trouble: those are the
/// tests' (`FakeTransport`).
///
/// Where the file is: the App Group container (`SyncEnginePretend-<name>.json`, `.lock` beside it), the one folder two
/// sandboxed instances of the app share. Nothing waits on time: an accepted send rings a Darwin notification and every
/// other process on the same pretend iCloud fetches (the pretend push); a change added is sent a moment later, once.
actor PretendCloudTransport: SyncTransport {
    static let account = "pretend"

    struct Stored: Codable, Sendable {
        var record: SyncRecord
        var tag: Int
        var seq: Int
    }

    struct Removed: Codable, Sendable {
        var key: SyncKey
        var seq: Int
    }

    /// The file.
    struct Cloud: Codable, Sendable {
        var version = 1
        var nextSeq = 1
        var nextTag = 1
        var records: [String: Stored] = [:]
        var removed: [String: Removed] = [:]
        var lastChange: Int { nextSeq - 1 }
    }

    /// What the transport keeps in the ledger (`SyncTransportState`).
    struct State: Codable, Sendable, Equatable {
        var account: String?
        var bookmark: Int?
        var pending: [PendingChange] = []
    }

    nonisolated let name: String
    nonisolated let device: String
    nonisolated let fileURL: URL
    private let lockURL: URL
    private let store: any SyncTransportState
    private var state = State()
    private var delegate: (any SyncTransportDelegate)?
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var delivering = false
    private var sendScheduled = false
    private nonisolated let bell: PretendBell

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    static func fileURL(name: String) -> URL {
        let folder = AppGroup.containerURL ?? URL.applicationSupportDirectory
        return folder.appending(path: "SyncEnginePretend-\(name).json")
    }

    static func bellName(_ name: String) -> String { "com.trammells.hitlist.syncEnginePretend.\(name)" }

    init(name: String, device: String, state: any SyncTransportState, fileURL: URL? = nil) {
        self.name = name
        self.device = device
        self.fileURL = fileURL ?? Self.fileURL(name: name)
        lockURL = self.fileURL.deletingPathExtension().appendingPathExtension("lock")
        store = state
        bell = PretendBell(name: Self.bellName(name))
    }

    // MARK: SyncTransport

    func start(delegate: any SyncTransportDelegate) async {
        if let data = await store.loadTransportState(), let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
        self.delegate = delegate
        bell.listen { [weak self] in
            Task { await self?.syncByItself() }
        }
        Self.log.notice("pretend iCloud \(self.name, privacy: .public) at \(self.fileURL.path, privacy: .public): started (\(self.state.pending.count) pending, bookmark \(self.state.bookmark.map(String.init) ?? "none", privacy: .public))")
        if !state.pending.isEmpty { scheduleSend() }
    }

    func stop() async {
        bell.stop()
        await acquire()
        delegate = nil
        release()
    }

    func pending() async -> [PendingChange] { state.pending }

    func add(_ changes: [PendingChange]) async {
        var changed = false
        for change in changes {
            if let index = state.pending.firstIndex(where: { $0.key == change.key }) {
                if state.pending[index] == change { continue }
                state.pending.remove(at: index)
            }
            state.pending.append(change)
            changed = true
        }
        guard changed else { return }
        await persist()
        scheduleSend()
    }

    func remove(_ changes: [PendingChange]) async {
        let gone = Set(changes)
        let before = state.pending.count
        state.pending.removeAll { gone.contains($0) }
        if state.pending.count != before { await persist() }
    }

    func fetch() async throws {
        await acquire()
        defer { release() }
        guard delegate != nil else { throw FakeTransportError.notStarted }
        await announceAccount()
        try await runFetch()
    }

    func send() async throws {
        await acquire()
        defer { release() }
        guard delegate != nil else { throw FakeTransportError.notStarted }
        await announceAccount()
        try await runSend()
    }

    func reset() async {
        // T13: the bookmark and the list forgotten; the account too, so the next operation announces the sign-in (T12,
        // as `CloudKitTransport.reset()` does).
        state = State()
        await persist()
    }

    /// The pretend push, or a change added: a fetch and a send, as CKSyncEngine does by itself.
    func syncByItself() async {
        await acquire()
        defer { release() }
        guard delegate != nil else { return }
        await announceAccount()
        try? await runFetch()
        try? await runSend()
    }

    // MARK: The operations

    private func scheduleSend() {
        guard !sendScheduled else { return }
        sendScheduled = true
        Task {
            // A moment, so the changes of one save go in one send; only while something is pending.
            try? await Task.sleep(for: .milliseconds(300))
            await self.sendByItself()
        }
    }

    private func sendByItself() async {
        sendScheduled = false
        await acquire()
        defer { release() }
        guard delegate != nil, !state.pending.isEmpty else { return }
        await announceAccount()
        try? await runSend()
    }

    private func announceAccount() async {
        guard state.account == nil, let delegate else { return }
        await deliver(.account(.signedIn(current: Self.account)), to: delegate)
        state.account = Self.account
        await persist()
    }

    private func runFetch() async throws {
        guard let delegate else { return }
        await deliver(.willFetch, to: delegate)
        let cloud: Cloud
        do {
            cloud = try withFile { $0 }
        } catch {
            await deliver(.didFetch(error: "the pretend iCloud's file could not be read: \(error.localizedDescription)"), to: delegate)
            throw error
        }
        let after = state.bookmark
        var changed: [(Int, CloudRecord)] = []
        for stored in cloud.records.values where after.map({ stored.seq > $0 }) ?? true {
            changed.append((stored.seq, CloudRecord(record: stored.record, system: Self.token(stored.tag))))
        }
        changed.sort { $0.0 < $1.0 }
        let removed: [SyncKey] = after.map { mark in cloud.removed.values.filter { $0.seq > mark }.map(\.key).sorted() } ?? []
        let records = changed.map(\.1)
        var start = 0
        repeat {
            let page = Array(records[start..<min(start + 200, records.count)])
            let last = start + page.count >= records.count
            if !page.isEmpty || (last && !removed.isEmpty) {
                await deliver(.fetched(changed: page, removed: last ? removed : []), to: delegate)
            }
            start += 200
        } while start < records.count
        // T1: everything the fetch brought has been handled; only now does the bookmark move past it.
        state.bookmark = cloud.lastChange
        await persist()
        await deliver(.didFetch(error: nil), to: delegate)
    }

    private func runSend() async throws {
        guard let delegate else { return }
        await deliver(.willSend, to: delegate)
        var accepted = false
        var rounds = 0
        while !state.pending.isEmpty, rounds < 20 {
            rounds += 1
            let batch = Array(state.pending.prefix(250))
            var outgoing: [(PendingChange, OutgoingRecord?)] = []
            var dropped: [PendingChange] = []
            for change in batch {
                switch change {
                case .save(let key):
                    if let record = await delegate.recordToSend(key) { outgoing.append((change, record)) } else { dropped.append(change) }
                case .delete:
                    outgoing.append((change, nil))
                }
            }
            if !dropped.isEmpty {
                // T3: nil drops the change.
                let gone = Set(dropped)
                state.pending.removeAll { gone.contains($0) }
                await persist()
            }
            guard !outgoing.isEmpty else { continue }
            var saved: [CloudRecord] = []
            var removed: [SyncKey] = []
            var failed: [SyncKey: SendFailure] = [:]
            do {
                try withFile { cloud in
                    for (change, record) in outgoing {
                        switch change {
                        case .save(let key):
                            guard let record else { continue }
                            switch Self.save(record, key: key, in: &cloud) {
                            case .success(let stored): saved.append(stored)
                            case .failure(let failure): failed[key] = failure.reason
                            }
                        case .delete(let key):
                            if cloud.records[key.description] != nil {
                                cloud.records[key.description] = nil
                                cloud.removed[key.description] = Removed(key: key, seq: cloud.nextSeq)
                                cloud.nextSeq += 1
                            }
                            removed.append(key)
                        }
                    }
                }
            } catch {
                await deliver(.didSend(error: "the pretend iCloud's file could not be written: \(error.localizedDescription)"), to: delegate)
                throw error
            }
            // T4: what was answered leaves the list before `sent` is delivered, so what the brain adds back stays.
            let answered = Set(outgoing.map(\.0))
            state.pending.removeAll { answered.contains($0) }
            await persist()
            if !saved.isEmpty || !removed.isEmpty { accepted = true }
            await deliver(.sent(saved: saved, removed: removed, failed: failed), to: delegate)
        }
        await deliver(.didSend(error: nil), to: delegate)
        if accepted { bell.ring() }
    }

    private struct Refusal: Error { let reason: SendFailure }

    /// T4, T6, T7 on the file.
    private static func save(_ outgoing: OutgoingRecord, key: SyncKey, in cloud: inout Cloud) -> Result<CloudRecord, Refusal> {
        let current = cloud.records[key.description]
        if let current {
            guard outgoing.system == token(current.tag) else {
                return .failure(Refusal(reason: .conflict(server: CloudRecord(record: current.record, system: token(current.tag)))))
            }
        } else if outgoing.system != nil {
            return .failure(Refusal(reason: .unknownItem))
        }
        var fields = current?.record.fields ?? [:]
        var known = Set(outgoing.record.fields.keys)
        known.formUnion(SyncSchema.type(key.type)?.fields.map(\.key) ?? [])
        known.formUnion([SyncSchema.updatedAt, SyncSchema.deletedAt])
        for name in known { fields[name] = outgoing.record.fields[name] }
        let stored = Stored(record: SyncRecord(key: key, fields: fields), tag: cloud.nextTag, seq: cloud.nextSeq)
        cloud.nextTag += 1
        cloud.nextSeq += 1
        cloud.records[key.description] = stored
        cloud.removed[key.description] = nil
        return .success(CloudRecord(record: stored.record, system: token(stored.tag)))
    }

    private static func token(_ tag: Int) -> Data { Data("pretend \(tag)".utf8) }

    // MARK: The file

    /// Reads the file, lets `body` change it, writes it back if it changed, all under an exclusive lock that every
    /// process on this pretend iCloud takes.
    private func withFile<T>(_ body: (inout Cloud) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        var cloud = Cloud()
        if let data = try? Data(contentsOf: fileURL) { cloud = try JSONDecoder().decode(Cloud.self, from: data) }
        let before = cloud.lastChange
        let result = try body(&cloud)
        if cloud.lastChange != before {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(cloud).write(to: fileURL, options: .atomic)
        }
        return result
    }

    // MARK: One at a time (T1)

    private func deliver(_ event: TransportEvent, to delegate: any SyncTransportDelegate) async {
        delivering = true
        await delegate.handle(event)
        delivering = false
    }

    private func persist() async {
        let data = try? JSONEncoder().encode(state)
        await store.saveTransportState(data)
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}

/// The pretend push: a Darwin notification every process on the same pretend iCloud listens for.
final class PretendBell: @unchecked Sendable {
    let name: String
    private var handler: (@Sendable () -> Void)?
    private var listening = false

    init(name: String) { self.name = name }

    func listen(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        guard !listening else { return }
        listening = true
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, _, _, _ in
            guard let observer else { return }
            Unmanaged<PretendBell>.fromOpaque(observer).takeUnretainedValue().handler?()
        }, name as CFString, nil, .deliverImmediately)
    }

    func ring() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    func stop() {
        guard listening else { return }
        listening = false
        handler = nil
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                           CFNotificationName(name as CFString), nil)
    }

    deinit { stop() }
}
#endif
