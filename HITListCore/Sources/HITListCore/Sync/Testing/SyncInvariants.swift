import Foundation

// What must always be true once every device has synced (`dev/SYNC-ENGINE.md`, section 9, I1 to I8), as functions over
// what the devices and iCloud hold. Each returns findings in plain words, empty when the invariant holds. They read
// only values (records, ledgers, a model of what people did), so they run as well on states a test builds by hand as
// at the end of a simulation, and in wave 2 on the app's own stores.

public enum SyncInvariant: String, Hashable, Sendable, CaseIterable, Comparable {
    /// Same everywhere: every device holds the same items with the same fields, and iCloud holds exactly those.
    case sameEverywhere = "I1"
    /// No lost edit: a field one device changed and no other did has that value everywhere.
    case noLostEdit = "I2"
    /// Nothing comes back: an item deleted on one device and not changed elsewhere afterwards is gone everywhere.
    case nothingComesBack = "I3"
    /// Twice is once: an event delivered twice, a crash, changes nothing in the end.
    case twiceIsOnce = "I4"
    /// One of each: never two items with one key.
    case oneOfEach = "I5"
    /// Whole: no item points at one that is not there.
    case whole = "I6"
    /// Quiet: when nothing is waiting, another sync sends nothing.
    case quiet = "I7"
    /// A newer build's fields survive an older build's edit.
    case newerFieldsSurvive = "I8"

    public static func < (a: SyncInvariant, b: SyncInvariant) -> Bool { a.rawValue < b.rawValue }
}

/// One thing found wrong, in words a person can act on.
public struct SyncFinding: Hashable, Sendable, CustomStringConvertible {
    public var invariant: SyncInvariant
    public var words: String

    public init(_ invariant: SyncInvariant, _ words: String) {
        self.invariant = invariant
        self.words = words
    }

    public var description: String { "\(invariant.rawValue) \(words)" }
}

/// What one device holds, for the invariants: its items, and what its transport still has to send.
public struct DeviceHoldings: Sendable {
    public var name: String
    public var records: [SyncRecord]
    public var pending: [PendingChange]

    public init(name: String, records: [SyncRecord], pending: [PendingChange] = []) {
        self.name = name
        self.records = records
        self.pending = pending
    }
}

/// One device's store and memory at a moment, for I4 (compared before and after an event is delivered again).
public struct DeviceSnapshot: Equatable, Sendable {
    public var records: [SyncRecord]
    public var entries: [LedgerEntry]
    public var deferred: [CloudRecord]
    /// The ledger's facts, the transport's own state left out (its bookmark moves on purpose).
    public var facts: [String: Data]
    public var pending: [PendingChange]

    public init(records: [SyncRecord], entries: [LedgerEntry], deferred: [CloudRecord], facts: [String: Data],
                pending: [PendingChange]) {
        self.records = records
        self.entries = entries
        self.deferred = deferred
        self.facts = facts
        self.pending = pending
    }

    /// The snapshot of a simulated device. The fact names it reads are `LedgerFact`'s and `extraFacts`.
    public static func of(store: MemoryLocalStore, ledger: MemoryLedger, transport: FakeTransport,
                          extraFacts: [String] = []) async -> DeviceSnapshot {
        var facts: [String: Data] = [:]
        for name in [LedgerFact.account, LedgerFact.firstFetchDone, LedgerFact.hold] + extraFacts {
            if let value = try? await ledger.fact(name) { facts[name] = value }
        }
        return DeviceSnapshot(records: (try? await store.records()) ?? [],
                              entries: (try? await ledger.entries()) ?? [],
                              deferred: (try? await ledger.deferred()) ?? [],
                              facts: facts,
                              pending: await transport.pending())
    }
}

/// What people did, device by device, step by step: the model I2 and I3 are checked against. The simulation keeps it
/// from what each person's action changed on the device (`record(step:device:before:after:)`), so a deletion's
/// cascade and the references it clears are in it as the device made them.
public struct SimIntent: Sendable {
    public enum Change: Sendable, Equatable {
        /// The item was made (or made again: an undo) with these fields.
        case made(SyncRecord)
        /// These fields were changed to these values (nil: emptied).
        case changed([String: SyncValue?])
        case deleted
    }

    public struct Event: Sendable {
        public var step: Int
        public var device: String
        public var key: SyncKey
        public var change: Change
    }

    public struct Poke: Sendable {
        public var step: Int
        public var key: SyncKey
        public var field: String
        public var value: SyncValue?
    }

    public private(set) var events: [Event] = []
    private var byKey: [SyncKey: [Event]] = [:]
    public private(set) var pokes: [Poke] = []
    /// The last step at which a device lost its memory (its ledger forgotten, by a fault, a lost zone or an account
    /// change). Up to then an edit may meet a merge without a memory, which keeps the record changed last whole
    /// (section 5, M5): I2 does not hold such an edit to account.
    public private(set) var exposedThrough: Int = -1
    /// Who lost their memory and when, for the words of a finding.
    public private(set) var amnesia: [(step: Int, device: String)] = []

    public init() {}

    /// What a person's action on `device` changed: the device's items before and after it.
    public mutating func record(step: Int, device: String, before: [SyncKey: SyncRecord], after: [SyncKey: SyncRecord]) {
        for key in Set(before.keys).union(after.keys).sorted() {
            switch (before[key], after[key]) {
            case (nil, let made?):
                add(Event(step: step, device: device, key: key, change: .made(made)))
            case (_?, nil):
                add(Event(step: step, device: device, key: key, change: .deleted))
            case (let old?, let new?):
                var changes: [String: SyncValue?] = [:]
                for name in Set(old.fields.keys).union(new.fields.keys).sorted()
                where old.fields[name]?.comparable != new.fields[name]?.comparable {
                    changes[name] = .some(new.fields[name])
                }
                if !changes.isEmpty { add(Event(step: step, device: device, key: key, change: .changed(changes))) }
            case (nil, nil):
                break
            }
        }
    }

    /// Another build wrote a key into iCloud's record (`FakeCloud.poke`).
    public mutating func recordPoke(step: Int, key: SyncKey, fields: [String: SyncValue?]) {
        for name in fields.keys.sorted() { pokes.append(Poke(step: step, key: key, field: name, value: fields[name] ?? nil)) }
    }

    /// A device lost its memory at this step.
    public mutating func recordAmnesia(step: Int, device: String) {
        exposedThrough = max(exposedThrough, step)
        amnesia.append((step, device))
    }

    private mutating func add(_ event: Event) {
        events.append(event)
        byKey[event.key, default: []].append(event)
    }

    func events(of key: SyncKey) -> [Event] { byKey[key] ?? [] }

    /// Every key a person touched, in order.
    var keys: [SyncKey] { byKey.keys.sorted() }

    /// The step of the last deletion of `key` with nothing made or changed after it; nil when the item is meant to
    /// be alive, or was changed after its deletion (either outcome is then defensible).
    func gone(_ key: SyncKey) -> Event? {
        let all = events(of: key)
        guard let lastDelete = all.last(where: { $0.change == .deleted }) else { return nil }
        let after = all.contains { $0.step > lastDelete.step && $0.change != .deleted }
        return after ? nil : lastDelete
    }

    /// Whether anyone ever deleted `key`.
    func everDeleted(_ key: SyncKey) -> Bool { events(of: key).contains { $0.change == .deleted } }

    /// The last parent a person gave a task (nil: none, or never set).
    func lastParent(_ key: SyncKey) -> String? {
        for event in events(of: key).reversed() {
            switch event.change {
            case .made(let record):
                if case .reference(let name)? = record.fields["parent"] { return name }
                return nil
            case .changed(let fields):
                if let value = fields["parent"] {
                    if case .reference(let name)? = value { return name }
                    return nil
                }
            case .deleted: continue
            }
        }
        return nil
    }
}

public enum SyncInvariants {
    // MARK: I1

    /// I1: every device holds the same items with the same fields (as this build knows them), and iCloud's living
    /// records of the types this build syncs are exactly those.
    public static func sameEverywhere(devices: [DeviceHoldings], cloud: [CloudRecord]) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        var there: [SyncKey: SyncRecord] = [:]
        var markers = Set<SyncKey>()
        for record in cloud where SyncSchema.type(record.key.type) != nil {
            if record.record.isDeleted { markers.insert(record.key) } else { there[record.key] = normal(record.record) }
        }
        for device in devices.sorted(by: { $0.name < $1.name }) {
            var here: [SyncKey: SyncRecord] = [:]
            for record in device.records where SyncSchema.type(record.key.type) != nil { here[record.key] = normal(record) }
            for key in Set(here.keys).union(there.keys).sorted() {
                switch (here[key], there[key]) {
                case (let mine?, nil):
                    let state = markers.contains(key) ? "holds it as deleted" : "does not hold it"
                    findings.append(SyncFinding(.sameEverywhere, "device \(device.name) holds \(key) (\(sketch(mine))); iCloud \(state)"))
                case (nil, let theirs?):
                    findings.append(SyncFinding(.sameEverywhere, "iCloud holds \(key) (\(sketch(theirs))); device \(device.name) does not"))
                case (let mine?, let theirs?) where mine != theirs:
                    findings.append(SyncFinding(.sameEverywhere, "device \(device.name) holds \(key) with \(difference(mine, theirs, "iCloud holds"))"))
                default:
                    break
                }
            }
        }
        return findings
    }

    // MARK: I2

    /// I2: a field one device changed and no other did has that value on every device and in iCloud; an item made and
    /// never deleted is on every device and alive in iCloud. Not held to account: a field changed on two devices (the
    /// merge keeps one of the two, section 5), an item made on two devices (they first meet by M5: the record changed
    /// last, whole), an edit up to a device's loss of memory (`SimIntent.exposedThrough`),
    /// the clocks (`updatedAt` and the fields a clock field times), and a sub-task whose parent a person deleted (it
    /// goes with its parent, whenever it was made).
    public static func noLostEdit(devices: [DeviceHoldings], cloud: [CloudRecord], intent: SimIntent) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        let holders: [(String, [SyncKey: SyncRecord])] = devices.sorted(by: { $0.name < $1.name }).map { device in
            (device.name, Dictionary(device.records.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        let iCloud = Dictionary(cloud.map { ($0.key, $0.record) }, uniquingKeysWith: { a, _ in a })
        for key in intent.keys {
            guard let type = SyncSchema.type(key.type), !intent.everDeleted(key) else { continue }
            if key.type == SyncSchema.taskItem.name, let parent = intent.lastParent(key),
               intent.everDeleted(SyncKey(type: key.type, name: parent)) { continue }
            let events = intent.events(of: key)
            guard let made = events.first(where: { if case .made = $0.change { return true } else { return false } }) else { continue }
            // Made and never deleted: everywhere.
            var missing: [String] = []
            for (name, items) in holders where items[key] == nil { missing.append("device \(name) does not hold it") }
            if let record = iCloud[key], record.isDeleted { missing.append("iCloud holds it as deleted") }
            if iCloud[key] == nil { missing.append("iCloud does not hold it") }
            if !missing.isEmpty {
                findings.append(SyncFinding(.noLostEdit, "\(key) was made on device \(made.device) at step \(made.step) and never deleted; \(missing.joined(separator: "; "))"))
                continue
            }
            let makers = Set(events.compactMap { event -> String? in
                if case .made = event.change { return event.device } else { return nil }
            })
            // Made on two devices (the profile: one per account, made wherever a person first named themselves): the
            // two meet without a common base, and the record changed last wins whole (M5). No field is held to account.
            guard makers.count == 1 else { continue }
            let skip = clockFields(type).union([SyncSchema.updatedAt])
            for field in type.fields where !skip.contains(field.key) {
                var setters: [String: SimIntent.Event] = [:]
                var value: SyncValue?? = nil
                for event in events {
                    if case .changed(let fields) = event.change, let new = fields[field.key] {
                        setters[event.device] = event
                        value = .some(new)
                    }
                }
                let expected: SyncValue?
                let because: String
                if setters.count == 1, let only = setters.first, let value {
                    guard only.value.step > intent.exposedThrough else { continue }
                    expected = value
                    because = "device \(only.key) set it at step \(only.value.step) and no other device changed it"
                } else if setters.isEmpty, case .made(let record) = made.change {
                    expected = SyncSchema.filled(record).fields[field.key]
                    because = "device \(made.device) made it so at step \(made.step) and nobody changed it"
                } else {
                    continue
                }
                guard case .check(let wanted) = settle(expected, field: field, intent: intent) else { continue }
                var wrong: [String] = []
                for (name, items) in holders {
                    let held = items[key].map { SyncSchema.filled($0).fields[field.key] } ?? nil
                    if held?.comparable != wanted?.comparable { wrong.append("device \(name) holds \(say(held))") }
                }
                let inCloud = iCloud[key].map { SyncSchema.filled($0).fields[field.key] } ?? nil
                if inCloud?.comparable != wanted?.comparable { wrong.append("iCloud holds \(say(inCloud))") }
                if !wrong.isEmpty {
                    findings.append(SyncFinding(.noLostEdit, "\(key) \(field.key) should be \(say(wanted)): \(because); \(wrong.joined(separator: "; "))"))
                }
            }
        }
        return findings
    }

    private enum Settled {
        case check(SyncValue?)
        case skip
    }

    /// A field's expected value with the references to items people deleted taken out (the device clears them);
    /// `skip` when a reference points at an item whose fate the model does not decide (deleted, then changed again).
    private static func settle(_ value: SyncValue?, field: SyncField, intent: SimIntent) -> Settled {
        switch (field.kind, value) {
        case (.reference(let target), .reference(let name)?):
            let key = SyncKey(type: target, name: name)
            if intent.gone(key) != nil { return .check(nil) }
            return intent.everDeleted(key) ? .skip : .check(value)
        case (.references(let target), .referenceList(let names)?):
            var kept: [String] = []
            for name in names {
                let key = SyncKey(type: target, name: name)
                if intent.gone(key) != nil { continue }
                if intent.everDeleted(key) { return .skip }
                kept.append(name)
            }
            return .check(kept.isEmpty ? nil : .references(kept))
        default:
            return .check(value)
        }
    }

    /// The fields that are another field's clock (`SyncField.Merge.clock`): they move with what they time.
    static func clockFields(_ type: SyncType) -> Set<String> {
        var out = Set<String>()
        for field in type.fields {
            if case .clock(let clock) = field.merge { out.insert(clock) }
        }
        return out
    }

    // MARK: I3

    /// I3: an item deleted on one device and not made or changed anywhere afterwards is on no device, and iCloud
    /// holds at most its marker.
    public static func nothingComesBack(devices: [DeviceHoldings], cloud: [CloudRecord], intent: SimIntent) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        let iCloud = Dictionary(cloud.map { ($0.key, $0.record) }, uniquingKeysWith: { a, _ in a })
        for key in intent.keys {
            guard let deletion = intent.gone(key) else { continue }
            var back: [String] = []
            for device in devices.sorted(by: { $0.name < $1.name }) {
                if let record = device.records.first(where: { $0.key == key }) {
                    back.append("device \(device.name) holds it (\(sketch(record)))")
                }
            }
            if let record = iCloud[key], !record.isDeleted { back.append("iCloud holds it alive (\(sketch(record)))") }
            if !back.isEmpty {
                findings.append(SyncFinding(.nothingComesBack, "\(key) was deleted on device \(deletion.device) at step \(deletion.step) and not changed afterwards; \(back.joined(separator: "; "))"))
            }
        }
        return findings
    }

    // MARK: I4

    /// I4: the device after an event was delivered a second time is the device after the first time.
    public static func twiceIsOnce(device: String, event: String, once: DeviceSnapshot, twice: DeviceSnapshot) -> [SyncFinding] {
        guard once != twice else { return [] }
        var what: [String] = []
        if once.records != twice.records {
            let a = Dictionary(once.records.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
            let b = Dictionary(twice.records.map { ($0.key, $0) }, uniquingKeysWith: { x, _ in x })
            for key in Set(a.keys).union(b.keys).sorted() where a[key] != b[key] {
                what.append("\(key) went from \(a[key].map(sketch) ?? "nothing") to \(b[key].map(sketch) ?? "nothing")")
            }
        }
        if once.entries != twice.entries { what.append("its ledger's entries changed") }
        if once.deferred != twice.deferred { what.append("the records it set aside changed") }
        if once.facts != twice.facts {
            let names = Set(once.facts.keys).union(twice.facts.keys).filter { once.facts[$0] != twice.facts[$0] }.sorted()
            what.append("its ledger's facts \(names.joined(separator: ", ")) changed")
        }
        if once.pending != twice.pending { what.append("its pending list went from \(once.pending.count) to \(twice.pending.count) changes") }
        return [SyncFinding(.twiceIsOnce, "device \(device), \(event) delivered a second time: \(what.joined(separator: "; "))")]
    }

    // MARK: I5

    /// I5: never two items with one key on a device, and a type with one record per account under its one name only.
    public static func oneOfEach(devices: [DeviceHoldings]) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        for device in devices.sorted(by: { $0.name < $1.name }) {
            var seen: [SyncKey: Int] = [:]
            for record in device.records { seen[record.key, default: 0] += 1 }
            for key in seen.keys.sorted() where seen[key]! > 1 {
                findings.append(SyncFinding(.oneOfEach, "device \(device.name) holds \(seen[key]!) items with the key \(key)"))
            }
            for record in device.records {
                if let type = SyncSchema.type(record.key.type), let one = type.singleton, record.key.name != one {
                    findings.append(SyncFinding(.oneOfEach, "device \(device.name) holds a \(type.name) named \(record.key.name); there is one per account, named \(one)"))
                }
            }
        }
        return findings
    }

    // MARK: I6

    /// I6: every reference on a device points at an item the device holds, and every reference in a living record in
    /// iCloud at a living record there.
    public static func whole(devices: [DeviceHoldings], cloud: [CloudRecord]) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        for device in devices.sorted(by: { $0.name < $1.name }) {
            let here = Set(device.records.map(\.key))
            for record in device.records.sorted(by: { $0.key < $1.key }) {
                for missing in dangling(record, in: here) {
                    findings.append(SyncFinding(.whole, "device \(device.name): \(record.key) points at \(missing), which it does not hold"))
                }
            }
        }
        let alive = Set(cloud.filter { !$0.record.isDeleted }.map(\.key))
        for record in cloud.sorted(by: { $0.key < $1.key }) where !record.record.isDeleted {
            for missing in dangling(record.record, in: alive) {
                findings.append(SyncFinding(.whole, "iCloud: \(record.key) points at \(missing), which iCloud does not hold alive"))
            }
        }
        return findings
    }

    private static func dangling(_ record: SyncRecord, in keys: Set<SyncKey>) -> [SyncKey] {
        guard let type = SyncSchema.type(record.key.type) else { return [] }
        var out: [SyncKey] = []
        for field in type.fields {
            switch (field.kind, record.fields[field.key]) {
            case (.reference(let target), .reference(let name)?):
                let key = SyncKey(type: target, name: name)
                if !keys.contains(key) { out.append(key) }
            case (.references(let target), .referenceList(let names)?):
                for name in names where !keys.contains(SyncKey(type: target, name: name)) {
                    out.append(SyncKey(type: target, name: name))
                }
            default: break
            }
        }
        return out
    }

    // MARK: I7

    /// I7: after everyone has synced, nothing is waiting anywhere, and one more sync on every device changed nothing
    /// in iCloud. `savedInExtraRound`: what iCloud accepted during that one more round. `rounds`: how many rounds it
    /// took to become quiet, nil when it did not within `limit`.
    public static func quiet(devices: [DeviceHoldings], savedInExtraRound: [SyncKey], rounds: Int?, limit: Int) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        if rounds == nil {
            findings.append(SyncFinding(.quiet, "not quiet after \(limit) rounds of every device syncing"))
        }
        for device in devices.sorted(by: { $0.name < $1.name }) where !device.pending.isEmpty {
            let some = device.pending.prefix(3).map { "\($0)" }.joined(separator: ", ")
            findings.append(SyncFinding(.quiet, "device \(device.name) still has \(device.pending.count) changes waiting (\(some))"))
        }
        if !savedInExtraRound.isEmpty {
            let some = savedInExtraRound.sorted().prefix(3).map(\.description).joined(separator: ", ")
            findings.append(SyncFinding(.quiet, "one more sync with nothing waiting saved \(savedInExtraRound.count) records in iCloud (\(some)): ping-pong"))
        }
        return findings
    }

    // MARK: I8

    /// I8: a key another build wrote (`FakeCloud.poke`) is still in iCloud's record, as it wrote it, whatever this
    /// build has sent since; unless the record was removed for good.
    public static func newerFieldsSurvive(cloud: [CloudRecord], intent: SimIntent) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        let iCloud = Dictionary(cloud.map { ($0.key, $0.record) }, uniquingKeysWith: { a, _ in a })
        var last: [String: SimIntent.Poke] = [:]
        for poke in intent.pokes { last["\(poke.key)|\(poke.field)"] = poke }
        for id in last.keys.sorted() {
            let poke = last[id]!
            guard let record = iCloud[poke.key] else { continue }
            if record.fields[poke.field] != poke.value {
                findings.append(SyncFinding(.newerFieldsSurvive, "\(poke.key) \(poke.field) was written by a newer build at step \(poke.step) as \(say(poke.value)); iCloud now holds \(say(record.fields[poke.field]))"))
            }
        }
        return findings
    }

    // MARK: Words

    static func normal(_ record: SyncRecord) -> SyncRecord {
        (RecordMerge.normal(record) ?? record).comparable
    }

    /// A value as a person reads it.
    public static func say(_ value: SyncValue?) -> String {
        guard let value else { return "nothing" }
        switch value {
        case .string(let text): return "'\(text.count > 40 ? String(text.prefix(40)) + "…" : text)'"
        case .int(let number): return "\(number)"
        case .bool(let flag): return "\(flag)"
        case .millis(let ms): return "@\(ms)"
        case .data(let bytes): return "\(bytes.count) bytes"
        case .digest(let hex): return "bytes \(hex.prefix(8))"
        case .reference(let name): return "→\(short(name))"
        case .referenceList(let names): return "[\(names.map(short).joined(separator: ", "))]"
        }
    }

    static func short(_ name: String) -> String { name.count > 8 ? String(name.prefix(8)) : name }

    /// A record in a few words: its name or title, or that it is a marker.
    static func sketch(_ record: SyncRecord) -> String {
        if record.isDeleted { return "deleted \(say(record.fields[SyncSchema.deletedAt]))" }
        for name in ["title", "name", "displayName"] {
            if let value = record.fields[name] { return "\(name) \(say(value))" }
        }
        return "\(record.fields.count) fields"
    }

    /// The fields two records differ in, as "title 'x'; <other> 'y'".
    static func difference(_ mine: SyncRecord, _ theirs: SyncRecord, _ them: String) -> String {
        let names = Set(mine.fields.keys).union(theirs.fields.keys).filter { mine.fields[$0] != theirs.fields[$0] }.sorted()
        let parts = names.prefix(4).map { name in "\(name) \(say(mine.fields[name])); \(them) \(say(theirs.fields[name]))" }
        return parts.joined(separator: ", ") + (names.count > 4 ? " (and \(names.count - 4) more)" : "")
    }
}
