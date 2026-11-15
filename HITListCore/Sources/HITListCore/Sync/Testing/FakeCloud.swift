import Foundation

// A pretend iCloud, in memory, for the engine's tests (`dev/SYNC-ENGINE.md`, sections 6 and 9). Apple ships no test
// double for CloudKit (`round-28/SDK-CKSyncEngine.md`, section 15), and a sync engine that has only ever met a working
// network is not tested. `FakeCloud` holds what iCloud would hold: for each account, one zone of records with a
// version per record and a log of changes; `FakeTransport` is one device's road to it, keeping the transport's rules
// T1 to T14 exactly. Nothing here runs unless a test calls it, and nothing waits on real time.

/// iCloud as the engine's devices see it: accounts, each with at most one zone (`SyncSchema.zoneName`) of records.
///
/// Every record keeps every key it was ever sent (known to `SyncSchema` or not: a newer build's fields), a change tag
/// that is new on every accepted save, and its place in a log of changes, so that a device's bookmark means
/// "everything after this". Records removed for good are in the log too. A test reads the cloud directly
/// (`records()`, `record(_:)`) and writes it as another build would (`poke`).
public actor FakeCloud {
    /// The account a device the cloud has not heard of is signed in to.
    public static let defaultAccount = "alice"

    struct Stored: Sendable {
        var fields: [String: SyncValue]
        /// iCloud's change tag for this version: unique across the whole cloud, new on every save.
        var tag: Int
        /// The record's place in the log of changes.
        var seq: Int
    }

    struct Zone: Sendable {
        /// Which making of the zone this is. A zone deleted and made again is another zone: a bookmark or a token
        /// from the old one means nothing in the new one.
        let incarnation: Int
        var records: [SyncKey: Stored] = [:]
        /// Records removed for good, and where in the log.
        var removed: [SyncKey: Int] = [:]
    }

    struct Account: Sendable {
        var zone: Zone?
        /// Every zone of this account that was lost, and why: a device that knew one hears of it once (T11).
        var lost: [Int: ZoneLoss] = [:]
        /// The person's iCloud storage is full: every save is refused with `quotaExceeded` (deletes still go).
        var quotaFull = false
    }

    private var accounts: [String: Account] = [:]
    /// Which account each device is signed in to; a device not listed is signed in to `defaultSignIn`, one listed as
    /// nil is signed out.
    private var signIns: [String: String?] = [:]
    private let defaultSignIn: String?
    /// One-shot refusals: the next save of the key, from any device, is refused with this.
    private var refusals: [SyncKey: SendFailure] = [:]
    private var nextSeq = 1
    private var nextTag = 1
    private var nextIncarnation = 1

    /// How many saves and removals iCloud has accepted, all accounts together.
    public private(set) var acceptedSaves = 0
    public private(set) var acceptedRemovals = 0

    /// - Parameter defaultAccount: the account a device the cloud has not heard of is signed in to (nil: signed out).
    public init(defaultAccount: String? = FakeCloud.defaultAccount) {
        self.defaultSignIn = defaultAccount
    }

    // MARK: What a test reads

    /// Every record the account's zone holds, markers among them, in key order. Empty when there is no zone.
    public func records(account: String = FakeCloud.defaultAccount) -> [CloudRecord] {
        guard let zone = accounts[account]?.zone else { return [] }
        return zone.records.keys.sorted().map { cloudRecord($0, zone.records[$0]!, zone: zone.incarnation) }
    }

    public func record(_ key: SyncKey, account: String = FakeCloud.defaultAccount) -> CloudRecord? {
        guard let zone = accounts[account]?.zone, let stored = zone.records[key] else { return nil }
        return cloudRecord(key, stored, zone: zone.incarnation)
    }

    /// Whether the account has a zone now.
    public func hasZone(account: String = FakeCloud.defaultAccount) -> Bool { accounts[account]?.zone != nil }

    /// The position of the newest change in the log, all accounts together. A sync that saved or removed nothing
    /// leaves it where it was (I7).
    public var lastChange: Int { nextSeq - 1 }

    /// Which account a device is signed in to; nil when signed out.
    public func account(of device: String) -> String? {
        if let entry = signIns[device] { return entry }
        return defaultSignIn
    }

    // MARK: What a test does to iCloud

    /// Writes the record as another build of HITList would: the given keys set (or, with nil, emptied), every other
    /// key left as it is, a new version. Makes the record (and the zone) when they are missing. For T4's "neither sent
    /// nor cleared": poke a key no schema lists and see that a device's save leaves it.
    @discardableResult
    public func poke(_ key: SyncKey, _ fields: [String: SyncValue?], account: String = FakeCloud.defaultAccount) -> CloudRecord {
        let incarnation = ensureZone(account: account)
        var zone = accounts[account]!.zone!
        var stored = zone.records[key] ?? Stored(fields: [:], tag: 0, seq: 0)
        for (name, value) in fields { stored.fields[name] = value }
        stored.tag = takeTag()
        stored.seq = takeSeq()
        zone.records[key] = stored
        zone.removed[key] = nil
        accounts[account]!.zone = zone
        return cloudRecord(key, stored, zone: incarnation)
    }

    /// Removes a record for good as another device would (T8); nothing when it is not there.
    public func pokeRemove(_ key: SyncKey, account: String = FakeCloud.defaultAccount) {
        guard var zone = accounts[account]?.zone, zone.records[key] != nil else { return }
        zone.records[key] = nil
        zone.removed[key] = takeSeq()
        accounts[account]!.zone = zone
    }

    /// The zone is gone: removed by the app or a developer (`deleted`), by the person in iCloud's settings
    /// (`purged`), or with their encrypted data at account recovery (`encryptedDataReset`). Every device that knew
    /// the zone hears of it at its next fetch or send (T11); a device that makes it again makes a new, empty zone.
    public func deleteZone(_ reason: ZoneLoss, account: String = FakeCloud.defaultAccount) {
        guard let zone = accounts[account]?.zone else { return }
        accounts[account]!.lost[zone.incarnation] = reason
        accounts[account]!.zone = nil
    }

    /// Signs a device in to an account, out (nil), or over to another. A running transport notices at its next
    /// fetch or send (`FakeTransport.noticeChanges()` makes it notice now); one that is not running, when it starts
    /// (T12).
    public func setAccount(_ account: String?, for device: String) {
        signIns[device] = .some(account)
    }

    /// The person's storage full (every save refused with `quotaExceeded`), or room again.
    public func setQuotaFull(_ full: Bool, account: String = FakeCloud.defaultAccount) {
        accounts[account, default: Account()].quotaFull = full
    }

    /// The next save of `key`, from whichever device, is refused with `failure` (T9: `quotaExceeded`, `tooLarge`,
    /// `rejected`; or `unknownItem`, `conflict` if a test wants them without arranging them).
    public func refuseNextSave(of key: SyncKey, with failure: SendFailure) {
        refusals[key] = failure
    }

    // MARK: What a transport asks (FakeTransport)

    /// The incarnation of the account's zone now, nil when it has none.
    func incarnation(account: String) -> Int? { accounts[account]?.zone?.incarnation }

    /// Why a zone the device knew is gone; nil when it is still there.
    func loss(account: String, incarnation: Int) -> ZoneLoss? {
        guard accounts[account]?.zone?.incarnation != incarnation else { return nil }
        // A zone the cloud never recorded as lost (it cannot happen, but a bookmark from another cloud could say
        // so): treat it as deleted.
        return accounts[account]?.lost[incarnation] ?? .deleted
    }

    /// The zone, made when it is missing. Returns its incarnation.
    func ensureZone(account: String) -> Int {
        if let zone = accounts[account]?.zone { return zone.incarnation }
        let incarnation = nextIncarnation
        nextIncarnation += 1
        accounts[account, default: Account()].zone = Zone(incarnation: incarnation)
        return incarnation
    }

    /// One change in the log since a bookmark.
    struct LogEntry: Sendable {
        var seq: Int
        /// The record as iCloud holds it now; nil when it was removed for good.
        var record: CloudRecord?
        var key: SyncKey
    }

    /// Every change in the zone after `after` (nil: every record the zone holds, and no removals), oldest first
    /// (CloudKit's "typical order"). Only the latest version of a record: an older one is not kept (T2).
    func changes(account: String, incarnation: Int, after: Int?) -> [LogEntry] {
        guard let zone = accounts[account]?.zone, zone.incarnation == incarnation else { return [] }
        var out: [LogEntry] = []
        for (key, stored) in zone.records where after.map({ stored.seq > $0 }) ?? true {
            out.append(LogEntry(seq: stored.seq, record: cloudRecord(key, stored, zone: incarnation), key: key))
        }
        if let after {
            for (key, seq) in zone.removed where seq > after {
                out.append(LogEntry(seq: seq, record: nil, key: key))
            }
        }
        return out.sorted { $0.seq < $1.seq }
    }

    /// One change a device sends: the keys to write (a value, or nil to empty the field) and the token it holds.
    struct WireSave: Sendable {
        var key: SyncKey
        var system: Data?
        var write: [String: SyncValue?]
        /// Which device sent it (for `drops`).
        var device: String = ""
    }

    /// An accepted save that took a reference away from what iCloud held (section 8: a device sends that only as a
    /// person's own change). A marker is not one: a deletion is I3's.
    public struct ReferenceDrop: Hashable, Sendable {
        public var device: String
        public var key: SyncKey
        public var field: String
        /// The names the field pointed at that the save took away.
        public var removed: [String]
    }

    private var drops: [ReferenceDrop] = []

    /// The reference drops since the last call, in the order iCloud accepted them.
    public func takeDrops() -> [ReferenceDrop] {
        defer { drops = [] }
        return drops
    }

    private func noteDrops(_ save: WireSave, before: Stored?) {
        guard let before, let type = SyncSchema.type(save.key.type) else { return }
        if case .some(.some) = save.write[SyncSchema.deletedAt] { return }
        for field in type.fields {
            guard let written = save.write[field.key] else { continue }
            let old = before.fields[field.key]
            var removed: [String] = []
            switch (field.kind, old) {
            case (.reference, .reference(let name)?):
                if written != old { removed = [name] }
            case (.references, .referenceList(let names)?):
                var now: Set<String> = []
                if case .referenceList(let list)?? = written { now = Set(list) }
                removed = names.filter { !now.contains($0) }
            default: break
            }
            if !removed.isEmpty {
                drops.append(ReferenceDrop(device: save.device, key: save.key, field: field.key, removed: removed))
            }
        }
    }

    struct BatchResult: Sendable {
        var saved: [CloudRecord] = []
        var removed: [SyncKey] = []
        var failed: [SyncKey: SendFailure] = [:]
    }

    /// Applies one batch, each change on its own (a batch is not all-or-nothing, T10). Nil when the zone is no longer
    /// `incarnation` (lost since the transport looked): nothing was applied.
    func apply(account: String, incarnation: Int, saves: [WireSave], deletes: [SyncKey]) -> BatchResult? {
        var result = BatchResult()
        guard var zone = accounts[account]?.zone, zone.incarnation == incarnation else { return nil }
        let quotaFull = accounts[account]?.quotaFull ?? false
        for save in saves {
            if let refusal = refusals.removeValue(forKey: save.key) {
                result.failed[save.key] = refusal
                continue
            }
            if quotaFull {
                result.failed[save.key] = .quotaExceeded
                continue
            }
            if let problem = FakeCloud.invalid(save) {
                result.failed[save.key] = problem
                continue
            }
            let current = zone.records[save.key]
            switch (current, save.system) {
            case (let current?, let system):
                // T6: only a save made on the version iCloud holds now is accepted; anything else is refused whole
                // and carries iCloud's version.
                guard let system, FakeCloud.token(system) == Token(zone: incarnation, key: save.key, tag: current.tag) else {
                    result.failed[save.key] = .conflict(server: cloudRecord(save.key, current, zone: incarnation))
                    continue
                }
            case (nil, .some):
                // T7: a change to a version of a record iCloud no longer holds (removed for good, or a token from
                // a zone that was lost and made again).
                result.failed[save.key] = .unknownItem
                continue
            case (nil, nil):
                break
            }
            noteDrops(save, before: current)
            var stored = current ?? Stored(fields: [:], tag: 0, seq: 0)
            for (name, value) in save.write { stored.fields[name] = value }
            stored.tag = takeTag()
            stored.seq = takeSeq()
            zone.records[save.key] = stored
            zone.removed[save.key] = nil
            acceptedSaves += 1
            result.saved.append(cloudRecord(save.key, stored, zone: incarnation))
        }
        for key in deletes {
            if let refusal = refusals.removeValue(forKey: key) {
                result.failed[key] = refusal
                continue
            }
            // T7: removing a record iCloud does not hold counts as done (and changes nothing in the log).
            if zone.records.removeValue(forKey: key) != nil {
                zone.removed[key] = takeSeq()
                acceptedRemovals += 1
            }
            result.removed.append(key)
        }
        accounts[account]!.zone = zone
        return result
    }

    // MARK: Tokens

    /// What `CloudRecord.system` holds: which zone, which record, which version. No field values: nothing a device
    /// could use instead of fetching the record. Written as one line of text (`fc|zone|type|name|tag`): cheap enough
    /// for thousands of runs, and a token from anywhere else does not read as one.
    struct Token: Hashable, Sendable {
        var zone: Int
        var type: String
        var name: String
        var tag: Int

        init(zone: Int, key: SyncKey, tag: Int) {
            self.zone = zone
            self.type = key.type
            self.name = key.name
            self.tag = tag
        }
    }

    static func token(_ data: Data) -> Token? {
        let parts = String(decoding: data, as: UTF8.self).split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 5, parts[0] == "fc", let zone = Int(parts[1]), let tag = Int(parts[parts.count - 1]) else {
            return nil
        }
        let name = parts[3..<(parts.count - 1)].joined(separator: "|")
        return Token(zone: zone, key: SyncKey(type: String(parts[2]), name: name), tag: tag)
    }

    static func system(_ token: Token) -> Data {
        Data("fc|\(token.zone)|\(token.type)|\(token.name)|\(token.tag)".utf8)
    }

    // MARK: -

    private func cloudRecord(_ key: SyncKey, _ stored: Stored, zone: Int) -> CloudRecord {
        CloudRecord(record: SyncRecord(key: key, fields: stored.fields),
                    system: FakeCloud.system(Token(zone: zone, key: key, tag: stored.tag)))
    }

    private func takeSeq() -> Int {
        defer { nextSeq += 1 }
        return nextSeq
    }

    private func takeTag() -> Int {
        defer { nextTag += 1 }
        return nextTag
    }

    /// iCloud's own refusals, from what CloudKit documents: a value of another kind than the field holds (a field's
    /// type never changes), a value iCloud cannot hold (a `digest` stands for bytes only on a device), and a record
    /// of more than 1 MB not counting assets (`CKRecord.h`). Nil when the save is acceptable.
    static func invalid(_ save: WireSave) -> SendFailure? {
        let type = SyncSchema.type(save.key.type)
        var size = 0
        for name in save.write.keys.sorted() {
            guard let value = save.write[name] ?? nil else { continue }
            if case .digest = value {
                return .rejected(code: 12, message: "\(save.key) \(name): a digest is not a value iCloud can hold")
            }
            if name == SyncSchema.deletedAt || name == SyncSchema.updatedAt {
                if case .millis = value { continue }
                return .rejected(code: 12, message: "\(save.key) \(name) must be a date")
            }
            guard let field = type?.field(name) else { continue }
            guard field.accepts(value) else {
                return .rejected(code: 12, message: "\(save.key) \(name): \(value) is not of the field's kind")
            }
            if case .data(asset: true) = field.kind { continue }
            switch value {
            case .string(let text): size += text.utf8.count
            case .data(let bytes): size += bytes.count
            case .referenceList(let names): size += names.reduce(0) { $0 + $1.utf8.count }
            case .reference(let name): size += name.utf8.count
            default: size += 8
            }
        }
        return size > 1_000_000 ? .tooLarge : nil
    }
}

/// A random number generator that is the same on every machine and every Swift version: SplitMix64, with its own
/// bounded draw and shuffle (the standard library's may change between versions, and a seed must replay the same run
/// on this Mac and on the CI runner).
public struct SimRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in `0..<bound` (bound > 0).
    public mutating func below(_ bound: Int) -> Int {
        precondition(bound > 0, "SimRandom.below needs a positive bound")
        return Int(next() % UInt64(bound))
    }

    /// True with probability `percent` in 100.
    public mutating func chance(_ percent: Int) -> Bool { below(100) < percent }

    public mutating func pick<T>(_ items: [T]) -> T? {
        items.isEmpty ? nil : items[below(items.count)]
    }

    public mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            items.swapAt(i, below(i + 1))
        }
    }
}
