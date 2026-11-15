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
    /// References kept (section 8): no device sends a record that takes away a reference iCloud holds, unless a person
    /// on that device changed that field.
    case referencesKept = "I9"
    /// Accounts apart (section 10, brief 145): each account's iCloud holds only items that belong to it (made there,
    /// made signed out, or carried there by a device that left another account holding items iCloud never held).
    case accountsApart = "I10"

    public static func < (a: SyncInvariant, b: SyncInvariant) -> Bool {
        (Int(a.rawValue.dropFirst()) ?? 0) < (Int(b.rawValue.dropFirst()) ?? 0)
    }
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
        /// For `changed`: what the changed fields held on the device just before (nil: empty). A set of references is
        /// judged by the names the person added and removed (section 5's `union`), not by the whole list.
        public var previous: [String: SyncValue?] = [:]
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
    /// Who lost their memory and when.
    public private(set) var amnesia: [(step: Int, device: String)] = []
    /// When the zone was lost (deleted, purged, reset): what only iCloud held (a newer build's fields) went with it.
    public private(set) var zoneLosses: [Int] = []
    /// Saves iCloud accepted that took a reference away, and when (I9).
    public private(set) var drops: [(step: Int, drop: FakeCloud.ReferenceDrop)] = []

    public mutating func recordDrops(step: Int, _ drops: [FakeCloud.ReferenceDrop]) {
        for drop in drops { self.drops.append((step, drop)) }
    }

    // MARK: Refusals for good (T9, brief 145)
    //
    // A record iCloud refused for good (too large, rejected) is kept out of the list until a person changes it again
    // (section 6 T9, `SyncStatus.refused`, shown to the person): until then its device holds a version iCloud and the
    // other devices do not. I1, I2 and I3 do not judge such a key; once a person changes it after the refusal, they do.

    /// When each key was last refused for good.
    public private(set) var refusals: [SyncKey: Int] = [:]

    public mutating func recordRefusals(step: Int, _ keys: [SyncKey]) {
        for key in keys { refusals[key] = step }
    }

    /// Keys held back on a device by a refusal for good that no person has changed since.
    public var heldBack: Set<SyncKey> {
        Set(refusals.keys.filter { key in
            guard let at = refusals[key] else { return false }
            return !events(of: key).contains { $0.step > at }
        })
    }

    // MARK: Accounts (section 10, brief 145)
    //
    // What the design says of a sign-out and an account switched (section 10, decision 2): what was synced leaves the
    // device at sign-out, after a backup; it returns at sign-in; an account switched is a sign-out then a sign-in;
    // items iCloud never held stay on the device (so they go to whichever account it joins next); nothing of one
    // account reaches another. The model: every item has the account it belongs to: the one its device was signed in
    // to when a person made it (none: signed out, it goes where the device signs in next), moved to the next account
    // when its device leaves an account holding it while iCloud never held it ("travelling", read from the device's
    // ledger at the moment: no living base). I2 and I3 judge only the run's account's own items (`foreign` skips the
    // rest); `accountsApart` (I10) checks that each account's iCloud holds only items that belong to it.

    /// The run's account (every device starts and ends signed in to it).
    public var account: String = FakeCloud.defaultAccount
    /// Each device's sign-ins and sign-outs, in order (nil: signed out).
    public private(set) var accountChanges: [(step: Int, device: String, account: String?)] = []
    /// Items that left an account with their device because iCloud had never held them, and where they went.
    public private(set) var travels: [SyncKey: [(step: Int, from: String?, to: String?)]] = [:]

    /// Device `device` signs in to `to` (nil: signs out) at `step`; `travelling` are the items on it that its ledger
    /// holds no living base for: they stay on the device, and go to `to`.
    public mutating func recordAccount(step: Int, device: String, to: String?, travelling: [SyncKey]) {
        let from = accountOf(device, at: step)
        accountChanges.append((step, device, to))
        for key in travelling { travels[key, default: []].append((step, from, to)) }
    }

    /// The account `device` was signed in to at `step` (nil: signed out).
    public func accountOf(_ device: String, at step: Int) -> String? {
        var current: String? = account
        for change in accountChanges where change.device == device && change.step <= step { current = change.account }
        return current
    }

    /// Whether `key` was ever anything but the run's account's own: a person touched it on a device signed in to
    /// another account or signed out, or it travelled with its device. I2 and I3 judge only the run's own items.
    func foreign(_ key: SyncKey) -> Bool {
        if travels[key] != nil { return true }
        return events(of: key).contains { accountOf($0.device, at: $0.step) != account }
    }

    /// Whether `key` may be in `owner`'s iCloud: a person made it on a device signed in to `owner` or signed out, or
    /// it travelled to `owner` (or to no account, then on to wherever its device signed in).
    func belongs(_ key: SyncKey, to owner: String) -> Bool {
        let made = events(of: key).contains { event in
            guard case .made = event.change else { return false }
            let at = accountOf(event.device, at: event.step)
            return at == nil || at == owner
        }
        return made || (travels[key] ?? []).contains { $0.to == nil || $0.to == owner }
    }

    /// Whether a person on `device` made the item or changed `field` of it at `step` or before.
    func personChanged(_ key: SyncKey, _ field: String, on device: String, by step: Int) -> Bool {
        events(of: key).contains { event in
            guard event.device == device, event.step <= step else { return false }
            switch event.change {
            case .made: return true
            case .changed(let fields): return fields[field] != nil
            case .deleted: return false
            }
        }
    }
    /// The last step at which a person (on any device) gave `key` a reference in `field` to any of `names`: made it so,
    /// or changed the field to hold one. Nil when nobody did.
    func lastGiven(_ key: SyncKey, _ field: String, names: [String]) -> Int? {
        func holds(_ value: SyncValue?) -> Bool {
            switch value {
            case .reference(let name)?: return names.contains(name)
            case .referenceList(let list)?: return list.contains(where: names.contains)
            default: return false
            }
        }
        var last: Int?
        for event in events(of: key) {
            switch event.change {
            case .made(let record): if holds(record.fields[field]) { last = event.step }
            case .changed(let fields): if let value = fields[field], holds(value) { last = event.step }
            case .deleted: break
            }
        }
        return last
    }

    /// Deletions a device made of items its ledger held no living base for ("step|device|key"): section 4 finds a
    /// deletion only by its base, so nothing can tell iCloud (an item never agreed on, or one a lost memory or a lost
    /// zone left without a base).
    private var blind: Set<String> = []

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
                var previous: [String: SyncValue?] = [:]
                for name in Set(old.fields.keys).union(new.fields.keys).sorted()
                where old.fields[name]?.comparable != new.fields[name]?.comparable {
                    changes[name] = .some(new.fields[name])
                    previous[name] = .some(old.fields[name])
                }
                if !changes.isEmpty {
                    add(Event(step: step, device: device, key: key, change: .changed(changes), previous: previous))
                }
            case (nil, nil):
                break
            }
        }
    }

    /// Another build wrote a key into iCloud's record (`FakeCloud.poke`).
    public mutating func recordPoke(step: Int, key: SyncKey, fields: [String: SyncValue?]) {
        for name in fields.keys.sorted() { pokes.append(Poke(step: step, key: key, field: name, value: fields[name] ?? nil)) }
    }

    /// A device lost its memory at this step, or (recorded again) finished the first whole fetch after it: until
    /// then a merge without a memory may settle anything changed meanwhile, anywhere.
    public mutating func recordAmnesia(step: Int, device: String) {
        exposedThrough = max(exposedThrough, step)
        amnesia.append((step, device))
    }

    /// The zone was lost at this step.
    public mutating func recordZoneLoss(step: Int) { zoneLosses.append(step) }

    /// Whether a deletion can have been forgotten: the device that made it lost its memory at that step or later
    /// (a deletion is known only from the base its ledger kept; section 4), before or without sending the marker.
    func forgotten(_ deletion: Event) -> Bool {
        if blind.contains("\(deletion.step)|\(deletion.device)|\(deletion.key)") { return true }
        return amnesia.contains { $0.device == deletion.device && $0.step >= deletion.step }
    }

    /// The person on `device` deleted these items while its ledger held no living base for them.
    public mutating func recordBlindDeletions(step: Int, device: String, keys: [SyncKey]) {
        for key in keys { blind.insert("\(step)|\(device)|\(key)") }
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

    /// Whether a task goes with a parent a person deleted: any parent any person ever gave it, or gave that parent,
    /// and so on up, deleted by a person somewhere. The one cascade the models have takes a sub-task with its parent
    /// on whichever device the deletion reaches, whatever the task's own history (section 5 does not save it).
    func underDeletedParent(_ key: SyncKey) -> Bool {
        var seen: Set<String> = []
        var next = parentsEverSet(key)
        while let name = next.popFirst() {
            guard seen.insert(name).inserted else { continue }
            let parent = SyncKey(type: key.type, name: name)
            if everDeleted(parent) { return true }
            next.formUnion(parentsEverSet(parent))
        }
        return false
    }

    private func parentsEverSet(_ key: SyncKey) -> Set<String> {
        var out = Set<String>()
        for event in events(of: key) {
            switch event.change {
            case .made(let record):
                if case .reference(let name)? = record.fields["parent"] { out.insert(name) }
            case .changed(let fields):
                if case .reference(let name)?? = fields["parent"] { out.insert(name) }
            case .deleted: break
            }
        }
        return out
    }

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
    /// `except`: keys held back on a device by a refusal for good (`SimIntent.heldBack`), not judged.
    public static func sameEverywhere(devices: [DeviceHoldings], cloud: [CloudRecord],
                                      except: Set<SyncKey> = []) -> [SyncFinding] {
        // A held-back item is on its device and not in iCloud: the references to it are not judged either.
        let devices = devices.map { device -> DeviceHoldings in
            guard !except.isEmpty else { return device }
            let allowed = Set(device.records.map(\.key)).subtracting(except)
            let records = device.records.filter { !except.contains($0.key) }.map { shown($0, allowed) }
            return DeviceHoldings(name: device.name, records: records, pending: device.pending)
        }
        let cloud = cloud.filter { !except.contains($0.key) }
        var findings: [SyncFinding] = []
        var there: [SyncKey: SyncRecord] = [:]
        var markers = Set<SyncKey>()
        let alive = livingKeys(cloud)
        for record in cloud where SyncSchema.type(record.key.type) != nil {
            if record.record.isDeleted { markers.insert(record.key) } else { there[record.key] = normal(shown(record.record, alive)) }
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
    /// the clocks (`updatedAt` and the fields a clock field times), and a sub-task under a parent a person deleted, at
    /// any depth and through any parent anyone gave it (it goes with its parent, whenever it was made).
    public static func noLostEdit(devices: [DeviceHoldings], cloud: [CloudRecord], intent: SimIntent) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        let holders: [(String, [SyncKey: SyncRecord])] = devices.sorted(by: { $0.name < $1.name }).map { device in
            (device.name, Dictionary(device.records.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        let alive = livingKeys(cloud)
        let iCloud = Dictionary(cloud.map { ($0.key, shown($0.record, alive)) }, uniquingKeysWith: { a, _ in a })
        let heldBack = intent.heldBack
        for key in intent.keys {
            guard let type = SyncSchema.type(key.type), !intent.everDeleted(key), !intent.foreign(key),
                  !heldBack.contains(key) else { continue }
            if key.type == SyncSchema.taskItem.name, intent.underDeletedParent(key) { continue }
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
            // Likewise one made twice on one device without a deletion between (the profile made again on a device
            // whose synced copy left it at a sign-out, before the sign-in brought it back: brief 145, account seed 19).
            let madeCount = events.filter { if case .made = $0.change { return true } else { return false } }.count
            guard makers.count == 1, madeCount == 1 else { continue }
            let skip = clockFields(type).union([SyncSchema.updatedAt])
            for field in type.fields where !skip.contains(field.key) {
                if field.merge == .union, case .references(let target) = field.kind {
                    findings += unionField(key, field: field.key, target: target, made: made, events: events,
                                           holders: holders, iCloud: iCloud, intent: intent)
                    continue
                }
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

    /// I2 for a set of references (`labels`, merged as a `union`, section 5 M7: "S plus what L added less what L
    /// removed"): judged name by name. A name one device added or removed, and no other did, is in the set everywhere
    /// or nowhere as that device last left it; a name nobody touched is as the maker made it. A name the store took off
    /// because its item went is not a person's removal (section 8: it is waited for, and comes back with the item), so
    /// a person's later save of the set does not remove it: only the names that person added or took away count.
    /// A name whose item a person deleted is expected gone (and not judged when that deletion may be forgotten, or the
    /// item was deleted and made again).
    private static func unionField(_ key: SyncKey, field: String, target: String, made: SimIntent.Event,
                                   events: [SimIntent.Event], holders: [(String, [SyncKey: SyncRecord])],
                                   iCloud: [SyncKey: SyncRecord], intent: SimIntent) -> [SyncFinding] {
        func names(_ value: SyncValue??) -> Set<String> {
            if case .referenceList(let list)?? = value { return Set(list) }
            return []
        }
        var initial: Set<String> = []
        if case .made(let record) = made.change { initial = names(.some(record.fields[field])) }
        // Each name's toggles: (device, step, in the set after it).
        var toggles: [String: [(device: String, step: Int, present: Bool)]] = [:]
        for event in events {
            guard case .changed(let fields) = event.change, let new = fields[field] else { continue }
            let after = names(.some(new))
            let before = names(event.previous[field])
            for name in after.subtracting(before) { toggles[name, default: []].append((event.device, event.step, true)) }
            for name in before.subtracting(after) { toggles[name, default: []].append((event.device, event.step, false)) }
        }
        var findings: [SyncFinding] = []
        for name in initial.union(toggles.keys).sorted() {
            let touched = toggles[name] ?? []
            let present: Bool
            let because: String
            if touched.isEmpty {
                present = initial.contains(name)
                because = "device \(made.device) made it so at step \(made.step) and nobody changed it"
            } else {
                guard Set(touched.map(\.device)).count == 1, let last = touched.last, last.step > intent.exposedThrough else { continue }
                present = last.present
                because = "device \(last.device) \(last.present ? "added" : "removed") it at step \(last.step) and no other device changed it"
            }
            let item = SyncKey(type: target, name: name)
            var expected = present
            if let deletion = intent.gone(item) {
                if intent.forgotten(deletion) { continue }
                expected = false
            } else if intent.everDeleted(item) {
                continue
            }
            var wrong: [String] = []
            for (device, items) in holders {
                let held = names(.some(items[key]?.fields[field])).contains(name)
                if held != expected { wrong.append("device \(device) \(held ? "holds it" : "does not")") }
            }
            let inCloud = names(.some(iCloud[key]?.fields[field])).contains(name)
            if inCloud != expected { wrong.append("iCloud \(inCloud ? "holds it" : "does not")") }
            if !wrong.isEmpty {
                findings.append(SyncFinding(.noLostEdit, "\(key) \(field) should \(expected ? "" : "not ")hold →\(short(name)): \(because); \(wrong.joined(separator: "; "))"))
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
        // A reference to an item a refusal holds back on its device cannot show anywhere else (T9): not judged.
        let heldBack = intent.heldBack
        if case .reference(let target) = field.kind, case .reference(let name)? = value,
           heldBack.contains(SyncKey(type: target, name: name)) { return .skip }
        if case .references(let target) = field.kind, case .referenceList(let names)? = value,
           names.contains(where: { heldBack.contains(SyncKey(type: target, name: $0)) }) { return .skip }
        switch (field.kind, value) {
        case (.reference(let target), .reference(let name)?):
            let key = SyncKey(type: target, name: name)
            if let deletion = intent.gone(key) { return intent.forgotten(deletion) ? .skip : .check(nil) }
            return intent.everDeleted(key) ? .skip : .check(value)
        case (.references(let target), .referenceList(let names)?):
            var kept: [String] = []
            for name in names {
                let key = SyncKey(type: target, name: name)
                if let deletion = intent.gone(key) {
                    if intent.forgotten(deletion) { return .skip }
                    continue
                }
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
    /// holds at most its marker. Not held to account: a deletion the deleting device may have forgotten (it lost its
    /// memory at that step or later: section 4 knows a deletion only from the base the ledger kept). Another
    /// device's loss of memory is no excuse: it merges with the marker (M6).
    public static func nothingComesBack(devices: [DeviceHoldings], cloud: [CloudRecord], intent: SimIntent) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        let iCloud = Dictionary(cloud.map { ($0.key, $0.record) }, uniquingKeysWith: { a, _ in a })
        let heldBack = intent.heldBack
        for key in intent.keys {
            guard let deletion = intent.gone(key), !intent.forgotten(deletion), !intent.foreign(key),
                  !heldBack.contains(key) else { continue }
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

    /// I6: every reference on a device points at an item the device holds. (iCloud may keep a reference to an item
    /// that is not there, section 8: it may only be late, or come back by an undo, and devices honour it then.
    /// `cloud` is kept in the signature for the callers; it is not judged.)
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
        _ = cloud
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
    /// build has sent since; unless the record was removed for good, or the zone was lost after (it went with it).
    public static func newerFieldsSurvive(cloud: [CloudRecord], intent: SimIntent) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        let iCloud = Dictionary(cloud.map { ($0.key, $0.record) }, uniquingKeysWith: { a, _ in a })
        var last: [String: SimIntent.Poke] = [:]
        for poke in intent.pokes { last["\(poke.key)|\(poke.field)"] = poke }
        for id in last.keys.sorted() {
            let poke = last[id]!
            guard let record = iCloud[poke.key], !intent.zoneLosses.contains(where: { $0 >= poke.step }) else { continue }
            if record.fields[poke.field] != poke.value {
                findings.append(SyncFinding(.newerFieldsSurvive, "\(poke.key) \(poke.field) was written by a newer build at step \(poke.step) as \(say(poke.value)); iCloud now holds \(say(record.fields[poke.field]))"))
            }
        }
        return findings
    }

    // MARK: I9

    /// I9: every save iCloud accepted that took a reference away (`FakeCloud.ReferenceDrop`) was a person's own change on
    /// the device that sent it: they made the item there (an undo too: M12) or changed that field there. Not held to
    /// account: a save up to a device's loss of memory (M5 keeps the record changed last, whole).
    ///
    /// Nor a reference a person gave up to then (brief 145, seed 100 with sends that skip the fetch): the merge without
    /// a memory is decided during the device's first whole fetch after the loss, but what it decided may be sent a step
    /// or two later, after the exposure has ended. I2 does not judge such an edit (`exposedThrough`); I9 likewise.
    public static func referencesKept(intent: SimIntent) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        for (step, drop) in intent.drops {
            guard step > intent.exposedThrough,
                  !intent.personChanged(drop.key, drop.field, on: drop.device, by: step) else { continue }
            if let given = intent.lastGiven(drop.key, drop.field, names: drop.removed), given <= intent.exposedThrough {
                continue
            }
            let names = drop.removed.map(short).joined(separator: ", ")
            findings.append(SyncFinding(.referencesKept, "device \(drop.device) sent \(drop.key) without \(drop.field) →\(names) at step \(step), which iCloud held; no person on \(drop.device) changed \(drop.field)"))
        }
        return findings
    }

    // MARK: I10

    /// I10: nothing of one account reaches another. Every item `owner`'s iCloud holds alive belongs to `owner` by the
    /// model (`SimIntent.belongs`): a person made it on a device signed in to it or signed out, or a device carried it
    /// there from another account whose iCloud had never held it (section 10: those items stay on the device).
    public static func accountsApart(owner: String, cloud: [CloudRecord], intent: SimIntent) -> [SyncFinding] {
        var findings: [SyncFinding] = []
        for record in cloud.sorted(by: { $0.key < $1.key })
        where !record.record.isDeleted && SyncSchema.type(record.key.type) != nil && !intent.belongs(record.key, to: owner) {
            findings.append(SyncFinding(.accountsApart, "\(owner)'s iCloud holds \(record.key) (\(sketch(record.record))), which no person made there, signed out, or carried there"))
        }
        return findings
    }

    // MARK: Words

    /// The keys of the records iCloud holds alive.
    static func livingKeys(_ cloud: [CloudRecord]) -> Set<SyncKey> {
        Set(cloud.filter { !$0.record.isDeleted }.map(\.key))
    }

    /// A record of iCloud's as a device shows it: references to records iCloud does not hold alive left out (section 8
    /// lets iCloud keep them).
    static func shown(_ record: SyncRecord, _ alive: Set<SyncKey>) -> SyncRecord {
        guard let type = SyncSchema.type(record.key.type), !record.isDeleted else { return record }
        var out = record
        for field in type.fields {
            switch (field.kind, record.fields[field.key]) {
            case (.reference(let target), .reference(let name)?):
                if !alive.contains(SyncKey(type: target, name: name)) { out.fields[field.key] = nil }
            case (.references(let target), .referenceList(let names)?):
                let kept = names.filter { alive.contains(SyncKey(type: target, name: $0)) }
                out.fields[field.key] = kept.isEmpty ? nil : .references(kept)
            default: break
            }
        }
        return out
    }

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
