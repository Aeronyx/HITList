import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 149, item 1 (the review's 16c, with 16b's path): a record iCloud holds that this build fetched and could not
/// read (in practice the profile, its picture not downloaded) stays owed until it can be read, and nothing is
/// overwritten or lost meanwhile.
///
/// The SDK lets no test build a `CKSyncEngine` event, so `CloudKitTransport` itself cannot run here. These tests run the
/// app's engine (`SyncEngine`: SwiftData, the ledger, the brain) on the pretend iCloud through `WithholdingTransport`,
/// which does to the brain exactly what `CloudKitTransport` now does with an unreadable record, with the same pieces
/// (`OwedRecords`, `CloudKitTransportRules.fetchEnding`): the record held back from `fetched` and owed; a conflict
/// whose version cannot be read taken off the list untold and owed; at the end of each fetch the owed records asked
/// for by key and delivered once they can be read; the fetch's words saying what is owed. Its `.asBefore` mode is the
/// transport before the fix (the record dropped, the conflict refused), to show what went wrong.
@MainActor
final class UnreadableRecordTests: XCTestCase {
    private var cloud: FakeCloud!
    private var engines: [SyncEngine] = []

    override func setUp() async throws {
        cloud = FakeCloud()
        engines = []
    }

    override func tearDown() async throws {
        for engine in engines { await engine.stop() }
        engines = []
        cloud = nil
    }

    /// `unreadable`: the records the device cannot read from its first fetch (its launch syncs at once).
    private func device(_ name: String, mode: WithholdingTransport.Mode? = nil, unreadable: Set<SyncKey> = []) async -> SyncEngine {
        let cloud = self.cloud!
        let engine = SyncEngine(container: ModelContainerFactory.preview(), ledger: .inMemory(), storeURL: nil,
                                board: SyncEngineBoard(), backUp: { _ in }) { ledger -> any SyncTransport in
            if let mode { return WithholdingTransport(cloud: cloud, device: name, state: ledger, mode: mode, unreadable: unreadable) }
            return FakeTransport(cloud: cloud, device: name, state: ledger)
        }
        engine.echo = { line in print("[\(name)] \(line)") }
        engines.append(engine)
        await engine.start()
        await engine.settle()
        return engine
    }

    private func sync(_ engine: SyncEngine) async throws {
        await engine.settle()
        try await engine.core.syncNow()
        await engine.settle()
    }

    private func task(_ id: UUID, on engine: SyncEngine) throws -> TaskItem? {
        try engine.container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    private func key(_ id: UUID) -> SyncKey { SyncKey(type: "TaskItem", name: id.uuidString) }

    private func cloudTitle(_ id: UUID) async -> String? {
        guard case .string(let title)? = await cloud.record(key(id))?.record.fields["title"] else { return nil }
        return title
    }

    private func cloudNotes(_ id: UUID) async -> String? {
        guard case .string(let notes)? = await cloud.record(key(id))?.record.fields["notes"] else { return nil }
        return notes
    }

    private func withholding(_ engine: SyncEngine) -> WithholdingTransport { engine.transport as! WithholdingTransport }

    // MARK: -

    /// A device that has never seen the record and holds one of its own under the same key (a new device's own
    /// profile): the unreadable record is owed, everything else syncs, the device's own save loses to iCloud's
    /// version untold (iCloud refuses a save without its token), iCloud's version is never overwritten, the person's
    /// row here is never lost, the bolt is not filled and the words say what is owed; once it can be read both sides
    /// settle on one record and the words go.
    func testAnUnreadableRecordStaysOwedNothingIsOverwrittenAndBothSidesSettleWhenItCanBeRead() async throws {
        let a = await device("A")
        let ferry = TaskItem(title: "Ferry at nine")
        let other = TaskItem(title: "Other")
        a.container.mainContext.insert(ferry)
        a.container.mainContext.insert(other)
        try a.container.mainContext.save()
        try await sync(a)
        let ferryID = ferry.id, otherID = other.id
        let ferryInICloud = await cloud.record(key(ferryID))
        XCTAssertNotNil(ferryInICloud, "setup: A sent it")

        let b = await device("B", mode: .owed, unreadable: [key(ferryID)])
        try await sync(b)
        XCTAssertNil(try task(ferryID, on: b), "not readable: not on B")
        XCTAssertNotNil(try task(otherID, on: b), "one unreadable record stops nothing else")
        let owed = await withholding(b).owed
        XCTAssertEqual(owed.reasons.keys.sorted(), [CloudRecordCodec.recordName(for: key(ferryID))], "owed, by name")

        // B's own row under the same key, and one more of its own.
        let mine = TaskItem(title: "Mine")
        mine.id = ferryID
        let fresh = TaskItem(title: "Made on B")
        b.container.mainContext.insert(mine)
        b.container.mainContext.insert(fresh)
        try b.container.mainContext.save()
        let freshID = fresh.id
        try await sync(b)
        try await sync(b)
        let held = await b.core.status
        XCTAssertNotNil(held.lastError, "the words say a record is owed")
        XCTAssertTrue(held.lastError?.contains("TaskItem/\(ferryID.uuidString)") == true, "the first one by name: \(held.lastError ?? "")")
        XCTAssertFalse(held.isSynced, "the bolt is not filled while a record is owed")
        XCTAssertTrue(held.firstFetchDone, "the first fetch was whole for everything else: what iCloud lacks went")
        let ferryAfterB = await cloudTitle(ferryID)
        XCTAssertEqual(ferryAfterB, "Ferry at nine", "nothing in iCloud is overwritten")
        let freshInICloud = await cloudTitle(freshID)
        XCTAssertEqual(freshInICloud, "Made on B", "the rest of B's changes go")
        XCTAssertEqual(try task(ferryID, on: b)?.title, "Mine", "and nothing here is lost")
        XCTAssertTrue(held.refused.isEmpty, "not refused for good: a refusal would keep it out until it changes again")

        // Readable now: the next fetch asks for it by name and delivers it.
        await withholding(b).setUnreadable([])
        try await sync(b)
        try await sync(b)
        try await sync(a)
        let settled = await b.core.status
        XCTAssertNil(settled.lastError, "the words go")
        XCTAssertTrue(settled.isSynced, "the bolt fills")
        let owedAfter = await withholding(b).owed
        XCTAssertTrue(owedAfter.isEmpty)
        let ferryNow = await cloudTitle(ferryID)
        XCTAssertEqual(try task(ferryID, on: b)?.title, ferryNow, "both sides hold one record")
        XCTAssertEqual(try task(ferryID, on: a)?.title, ferryNow)
        // B's save was never answered, so what it sent is the base (M5 → M7, `SyncCore+Sent`): B had not changed it
        // since, iCloud had, and iCloud's version stands. (A new device's default profile does not replace the
        // person's.)
        XCTAssertEqual(ferryNow, "Ferry at nine")
        let freshOnA = try task(freshID, on: a)?.title
        XCTAssertEqual(freshOnA, "Made on B")
    }

    /// A record this device knows, changed elsewhere into a version it cannot read, while it changes another field
    /// here: its save loses to that version, the version is owed, and when it can be read both edits survive.
    func testAnEditHereAndAnEditInAVersionThatCouldNotBeReadBothSurvive() async throws {
        let a = await device("A")
        let b = await device("B", mode: .owed)
        let item = TaskItem(title: "Ferry")
        a.container.mainContext.insert(item)
        try a.container.mainContext.save()
        let id = item.id
        try await sync(a)
        try await sync(b)
        XCTAssertEqual(try task(id, on: b)?.title, "Ferry", "setup: B holds it with a base")

        try task(id, on: a)?.notes = "Pier 4"
        try task(id, on: a)?.updatedAt = Date()
        try a.container.mainContext.save()
        try await sync(a)
        await withholding(b).setUnreadable([key(id)])
        try task(id, on: b)?.title = "Ferry at nine"
        try task(id, on: b)?.updatedAt = Date()
        try b.container.mainContext.save()
        try await sync(b)
        try await sync(b)
        let notesThere = await cloudNotes(id)
        let titleThere = await cloudTitle(id)
        XCTAssertEqual(notesThere, "Pier 4", "nothing in iCloud is overwritten")
        XCTAssertEqual(titleThere, "Ferry")
        XCTAssertEqual(try task(id, on: b)?.title, "Ferry at nine", "nothing here is lost")
        let held = await b.core.status
        XCTAssertFalse(held.isSynced)

        await withholding(b).setUnreadable([])
        try await sync(b)
        try await sync(b)
        try await sync(a)
        let notesAfter = await cloudNotes(id)
        let titleAfter = await cloudTitle(id)
        XCTAssertEqual(titleAfter, "Ferry at nine", "B's edit went")
        XCTAssertEqual(notesAfter, "Pier 4", "A's edit stayed")
        XCTAssertEqual(try task(id, on: b)?.notes, "Pier 4")
        XCTAssertEqual(try task(id, on: a)?.title, "Ferry at nine")
        let settled = await b.core.status
        XCTAssertTrue(settled.isSynced)
    }

    /// The transport before the fix, for the record: the unreadable version was dropped while the bookmark moved on,
    /// so the device never heard of it again once it became readable, and nothing said so.
    func testBeforeTheFixAnUnreadableRecordWasNeverHeardOfAgain() async throws {
        let a = await device("A")
        let item = TaskItem(title: "Ferry at nine")
        a.container.mainContext.insert(item)
        try a.container.mainContext.save()
        let id = item.id
        try await sync(a)
        let b = await device("B", mode: .asBefore, unreadable: [key(id)])
        try await sync(b)
        try await sync(b)
        let silent = await b.core.status
        XCTAssertTrue(silent.isSynced, "the bolt was filled with a record missing")
        await withholding(b).setUnreadable([])
        try await sync(b)
        try await sync(b)
        XCTAssertNil(try task(id, on: b), "readable now, and still never arrives")
    }
}

/// `CloudKitTransport`'s handling of unreadable records, on the pretend iCloud (see `UnreadableRecordTests`).
actor WithholdingTransport: SyncTransport, SyncTransportDelegate {
    enum Mode {
        /// As `CloudKitTransport` does now.
        case owed
        /// As it did before brief 149: dropped while the bookmark moved on; a conflict refused.
        case asBefore
    }

    let inner: FakeTransport
    let cloud: FakeCloud
    let mode: Mode
    private(set) var owed = OwedRecords()
    private var unreadable: Set<SyncKey> = []
    private var brain: (any SyncTransportDelegate)?
    private var wholeSeen = false
    private var wholeBefore = false

    init(cloud: FakeCloud, device: String, state: any SyncTransportState, mode: Mode, unreadable: Set<SyncKey> = []) {
        self.cloud = cloud
        self.mode = mode
        self.unreadable = unreadable
        inner = FakeTransport(cloud: cloud, device: device, state: state)
    }

    func setUnreadable(_ keys: Set<SyncKey>) { unreadable = keys }

    private func name(_ key: SyncKey) -> String { CloudRecordCodec.recordName(for: key) }

    // MARK: SyncTransport

    func start(delegate: any SyncTransportDelegate) async {
        brain = delegate
        await inner.start(delegate: self)
    }

    func stop() async {
        await inner.stop()
        brain = nil
    }

    func pending() async -> [PendingChange] { await inner.pending() }
    func add(_ changes: [PendingChange]) async { await inner.add(changes) }
    func remove(_ changes: [PendingChange]) async { await inner.remove(changes) }
    func fetch() async throws { try await inner.fetch() }
    func send() async throws { try await inner.send() }
    func reset() async { await inner.reset() }

    // MARK: SyncTransportDelegate (the inner transport's events, as `CloudKitTransport` would turn them)

    func recordToSend(_ key: SyncKey) async -> OutgoingRecord? { await brain?.recordToSend(key) }

    func handle(_ event: TransportEvent) async {
        guard let brain else { return }
        switch event {
        case .willFetch:
            wholeBefore = wholeSeen
            await brain.handle(event)
        case .fetched(let changed, let removed):
            var readable: [CloudRecord] = []
            for record in changed {
                if unreadable.contains(record.key) {
                    if mode == .owed { owed.reasons[name(record.key)] = "asset avatarData unreadable: no file" }
                } else {
                    readable.append(record)
                }
            }
            if !(readable.isEmpty && removed.isEmpty) {
                await brain.handle(.fetched(changed: readable, removed: removed))
            }
            for key in readable.map(\.key) + removed { owed.reasons[name(key)] = nil }
        case .sent(let saved, let removed, let failed):
            var told = failed
            for (key, failure) in failed {
                guard case .conflict(let server) = failure, unreadable.contains(server.key) else { continue }
                switch mode {
                case .owed:
                    told[key] = nil
                    owed.reasons[name(key)] = "iCloud's version, in a conflict, could not be read"
                case .asBefore:
                    told[key] = .rejected(code: 14, message: "a conflict without iCloud's record")
                }
            }
            if !(saved.isEmpty && removed.isEmpty && told.isEmpty) {
                await brain.handle(.sent(saved: saved, removed: removed, failed: told))
            }
        case .didFetch(let error):
            if error == nil, mode == .owed, !owed.isEmpty {
                var readable: [CloudRecord] = []
                var settled: [String] = []
                for recordName in owed.reasons.keys.sorted() {
                    guard let key = CloudRecordCodec.key(forRecordName: recordName) else { continue }
                    guard let record = await cloud.record(key) else {
                        settled.append(recordName) // no longer in iCloud
                        continue
                    }
                    if !unreadable.contains(key) {
                        readable.append(record)
                        settled.append(recordName)
                    }
                }
                if !readable.isEmpty { await brain.handle(.fetched(changed: readable, removed: [])) }
                for recordName in settled { owed.reasons[recordName] = nil }
            }
            if error == nil { wholeSeen = true }
            await brain.handle(.didFetch(error: CloudKitTransportRules.fetchEnding(error, owed: owed, wholeFetchSeenBefore: wholeBefore)))
        default:
            await brain.handle(event)
        }
    }
}
