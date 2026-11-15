import Foundation

// How one record is settled between this device and iCloud. Pure: the same four inputs always give the same answer,
// on every device, so two devices that have seen the same things hold the same thing. The rules, M1 to M13, are
// spelled out in `dev/SYNC-ENGINE.md` ("How a record is settled"); each case below names its rule.

/// What is known about one record at the moment of deciding.
public struct MergeInput: Sendable {
    /// The record as iCloud held it when this device and iCloud last agreed (`LedgerEntry.base`: known fields,
    /// `comparable`; a marker when they agreed it was deleted). Nil: they never have.
    public var base: SyncRecord?
    /// The item on this device now; nil when it isn't here.
    public var local: SyncRecord?
    /// When this device noticed the item was deleted here (`LedgerEntry.deletedHereAt`); `now` stands in when the
    /// item is missing and nobody has noticed yet.
    public var deletedHereAt: Date?
    /// The record as iCloud holds it now (a marker when deleted); nil when iCloud holds none.
    public var server: SyncRecord?
    public var now: Date

    public init(base: SyncRecord?, local: SyncRecord?, deletedHereAt: Date? = nil, server: SyncRecord?, now: Date) {
        self.base = base
        self.local = local
        self.deletedHereAt = deletedHereAt
        self.server = server
        self.now = now
    }
}

public struct MergeOutcome: Equatable, Sendable {
    public enum Rule: String, Sendable, CaseIterable {
        /// A key whose type this build does not know: `merged` is the device's record untouched, and the caller
        /// does nothing with it (the brain filters such records out before the merge, `dev/SYNC-ENGINE.md` section 8).
        case unknownType = "M0"
        case nothing = "M1", newHere = "M2", newThere = "M3", deletedThereUnknownHere = "M4",
             firstMeeting = "M5", firstMeetingDeletedThere = "M6", threeWay = "M7", deletedHere = "M8",
             deletedThere = "M9", deletedBoth = "M10", goneForGood = "M11", cameBackHere = "M12",
             cameBackThere = "M13"
    }

    /// What this device and iCloud should both end with: the item's record, a marker (the item deleted), or nil
    /// (nothing at all, not even a marker).
    public var merged: SyncRecord?
    public var rule: Rule

    /// What the device should hold: the item, or nothing.
    public var device: SyncRecord? { merged?.isDeleted == false ? merged : nil }

    public init(merged: SyncRecord?, rule: Rule) {
        self.merged = merged
        self.rule = rule
    }
}

public enum RecordMerge {
    /// Whether two records are the same as far as this build can tell: both absent, or the same key and the same
    /// fields this build knows (`SyncSchema.known`, required fields filled in, `data` by digest). A marker is the
    /// same as another marker with the same time.
    public static func same(_ a: SyncRecord?, _ b: SyncRecord?) -> Bool {
        normal(a)?.comparable == normal(b)?.comparable
    }

    /// `record` as the merge reads it: cut to the fields this build knows, required fields filled in. A type this
    /// build does not know comes back as it is.
    ///
    /// Two readings make records that mean the same compare the same, so that nothing is sent back and forth for
    /// them (round 28, brief 138): a marker is its key and its time and nothing else (content left on one by
    /// mistake, or an `updatedAt` other than its `deletedAt`, does not make a different marker); a set of references
    /// is sorted without repeats, and an empty one is none (as a device holds it).
    public static func normal(_ record: SyncRecord?) -> SyncRecord? {
        guard let record else { return nil }
        guard let known = SyncSchema.known(record) else { return record }
        if case .millis(let deleted)? = known.fields[SyncSchema.deletedAt] {
            return SyncRecord(key: known.key, fields: [SyncSchema.deletedAt: .millis(deleted),
                                                       SyncSchema.updatedAt: .millis(deleted)])
        }
        var out = SyncSchema.filled(known)
        let lists = out.fields.compactMap { field, value -> (String, [String])? in
            if case .referenceList(let names) = value { return (field, names) }
            return nil
        }
        for (field, names) in lists { out.fields[field] = names.isEmpty ? nil : .references(names) }
        return out
    }

    /// Settles one record (rules M1 to M13). For a key whose type this build does not know the answer is
    /// `.unknownType` with the device's record untouched: the caller must not act on it (not write, not send, not
    /// remove), because nothing of such a record is this build's to decide.
    public static func merge(_ input: MergeInput) -> MergeOutcome {
        let base = normal(input.base), local = normal(input.local), server = normal(input.server)
        guard let key = (local ?? server ?? base)?.key else {
            return MergeOutcome(merged: nil, rule: .nothing)
        }
        guard let type = SyncSchema.type(key.type) else {
            return MergeOutcome(merged: input.local, rule: .unknownType)
        }
        let deletedHere: Date = input.deletedHereAt ?? input.now

        switch (base, local, server) {
        case (_, nil, nil):
            // M1: nothing here, nothing there. (With a base: gone for good there and already gone here.)
            return MergeOutcome(merged: nil, rule: base == nil ? .nothing : .goneForGood)

        case (nil, let local?, nil):
            // M2: made here, iCloud has never held it.
            return MergeOutcome(merged: local, rule: .newHere)

        case (nil, nil, let server?):
            // M3 and M4: iCloud's, new to this device (alive: it arrives; a marker: there is nothing to delete).
            // Unless this device holds a deletion of its own still to send, kept as an entry with no base when the
            // ledger was forgotten (section 7; an explicit `deletedHereAt`, never `now`): against a live record it
            // is settled as M8 (iCloud's stands only if changed after the deletion, else the marker goes), against
            // a marker as M10 (the later of the two times).
            if let at = input.deletedHereAt {
                if server.isDeleted {
                    let later = isLater(.date(at), than: server[SyncSchema.deletedAt])
                    return MergeOutcome(merged: later ? .marker(key, deletedAt: at) : server, rule: .deletedBoth)
                }
                let changedAfter = (server.updatedAt ?? .distantPast) > at
                return MergeOutcome(merged: changedAfter ? server : .marker(key, deletedAt: at), rule: .deletedHere)
            }
            return MergeOutcome(merged: server, rule: server.isDeleted ? .deletedThereUnknownHere : .newThere)

        case (nil, let local?, let server?):
            if server.isDeleted {
                // M6: here without a memory of it, deleted there. The later of the edit and the deletion wins.
                let revived = (local.updatedAt ?? .distantPast) > (server.deletedAt ?? .distantPast)
                return MergeOutcome(merged: revived ? local : server, rule: .firstMeetingDeletedThere)
            }
            // M5: both hold it and have never agreed: the record changed last, whole.
            return MergeOutcome(merged: firstMeeting(type, local: local, server: server), rule: .firstMeeting)

        case (let base?, let local?, nil):
            // M11: iCloud removed it for good (a marker past its lifetime, or a change sent to a record it no longer
            // holds). Unchanged here since they agreed: it goes here too. Changed here: it is new again.
            _ = base
            return MergeOutcome(merged: same(local, base) ? nil : local, rule: .goneForGood)

        case (let base?, nil, let server?):
            if server.isDeleted {
                // M10: deleted there, not here either. Deleted on both sides apart: the marker carries the later of
                // the two deletions, whichever device reached iCloud first (round 28, brief 138: with iCloud's time
                // alone, the order of arrival decided the marker's time, and a deletion here after an edit elsewhere
                // was forgotten). With the base a marker too, only an explicit `deletedHereAt` is a deletion here:
                // a later marker this device still has to send over iCloud's earlier one, kept when that earlier
                // marker is delivered again (T2; session 139). `now` never stands in for it, or two devices would
                // send each other fresher markers at every sync.
                let stillToGo: Date? = base.isDeleted ? input.deletedHereAt : deletedHere
                if let at = stillToGo, isLater(.date(at), than: server[SyncSchema.deletedAt]) {
                    return MergeOutcome(merged: .marker(key, deletedAt: at), rule: .deletedBoth)
                }
                return MergeOutcome(merged: server, rule: .deletedBoth)
            }
            if base.isDeleted {
                // M13: deleted as far as this device knew, made again on another: it arrives. Unless this device
                // still has a later deletion of its own to send (an explicit `deletedHereAt`, never `now`): then the
                // revival is ordered against that time as in M8 (it arrives only if changed after it).
                if let at = input.deletedHereAt, (server.updatedAt ?? .distantPast) <= at {
                    return MergeOutcome(merged: .marker(key, deletedAt: at), rule: .cameBackThere)
                }
                return MergeOutcome(merged: server, rule: .cameBackThere)
            }
            // M8: deleted here while iCloud holds it. Untouched there since: the deletion stands. Changed there
            // after the deletion: the change wins and the item comes back here.
            if !same(server, base), (server.updatedAt ?? .distantPast) > deletedHere {
                return MergeOutcome(merged: server, rule: .deletedHere)
            }
            return MergeOutcome(merged: .marker(key, deletedAt: deletedHere), rule: .deletedHere)

        case (let base?, let local?, let server?):
            if base.isDeleted {
                // M12: the device knew it deleted and holds it again: made again here (an undo, an import). Against
                // the marker this device knew, it stands whatever its dates. Against a newer marker (deleted again
                // elsewhere since), it is ordered as M6: it stands only if changed after that deletion (the app moves
                // `updatedAt` when it puts a deleted item back, so an undo beats an older deletion and loses to a
                // later one). If another device made it again too, the two meet for the first time.
                if server.isDeleted {
                    guard isLater(server[SyncSchema.deletedAt], than: base[SyncSchema.deletedAt]) else {
                        return MergeOutcome(merged: local, rule: .cameBackHere)
                    }
                    let revived = (local.updatedAt ?? .distantPast) > (server.deletedAt ?? .distantPast)
                    return MergeOutcome(merged: revived ? local : server, rule: .cameBackHere)
                }
                return MergeOutcome(merged: firstMeeting(type, local: local, server: server), rule: .cameBackHere)
            }
            if server.isDeleted {
                // M9: deleted there. Unchanged here: it goes. Changed here after the deletion: it stays, and comes
                // back there.
                if !same(local, base), (local.updatedAt ?? .distantPast) > (server.deletedAt ?? .distantPast) {
                    return MergeOutcome(merged: local, rule: .deletedThere)
                }
                return MergeOutcome(merged: server, rule: .deletedThere)
            }
            // M7: both hold it and have agreed before: field by field.
            return MergeOutcome(merged: threeWay(type, base: base, local: local, server: server), rule: .threeWay)

        case (nil, nil, nil):
            return MergeOutcome(merged: nil, rule: .nothing)
        }
    }

    // MARK: -

    /// M7. A field only one side changed since `base` is that side's. A field both changed: by its `SyncField.Merge`.
    /// `updatedAt` and every clock field end as the later of the two, so the record is never older than either.
    static func threeWay(_ type: SyncType, base: SyncRecord, local: SyncRecord, server: SyncRecord) -> SyncRecord {
        let serverLast = (server.updatedAt ?? .distantPast) >= (local.updatedAt ?? .distantPast)
        let clocks = clockKeys(type)
        var out = SyncRecord(key: local.key)
        for field in type.fields {
            let l = local.fields[field.key], s = server.fields[field.key], b = base.fields[field.key]
            let lc = l?.comparable, sc = s?.comparable, bc = b?.comparable
            let value: SyncValue?
            if field.key == SyncSchema.updatedAt || clocks.contains(field.key) {
                value = later(l, s)
            } else if lc == sc {
                value = s
            } else if lc == bc {
                value = s
            } else if sc == bc {
                value = l
            } else {
                switch field.merge {
                case .lastWriter: value = serverLast ? s : l
                case .clock(let clock): value = isLater(local.fields[clock], than: server.fields[clock]) ? l : s
                case .union: value = union(l, s, base: b)
                }
            }
            out.fields[field.key] = value
        }
        return SyncSchema.filled(out)
    }

    /// M5. With nothing to tell who changed what: the record changed last, whole (a tie goes to iCloud's), except a
    /// field with a clock of its own, which goes by its clock.
    static func firstMeeting(_ type: SyncType, local: SyncRecord, server: SyncRecord) -> SyncRecord {
        if same(local, server) { return server }
        let serverLast = (server.updatedAt ?? .distantPast) >= (local.updatedAt ?? .distantPast)
        var out = serverLast ? server : local
        let clocks = clockKeys(type)
        for field in type.fields {
            if case .clock(let clock) = field.merge {
                let fromLocal = isLater(local.fields[clock], than: server.fields[clock])
                out.fields[field.key] = fromLocal ? local.fields[field.key] : server.fields[field.key]
            }
        }
        for key in clocks.union([SyncSchema.updatedAt]) {
            out.fields[key] = later(local.fields[key], server.fields[key])
        }
        return SyncSchema.filled(out)
    }

    static func clockKeys(_ type: SyncType) -> Set<String> {
        var out = Set<String>()
        for field in type.fields {
            if case .clock(let key) = field.merge { out.insert(key) }
        }
        return out
    }

    /// The later of two dates; a side without one loses.
    static func later(_ a: SyncValue?, _ b: SyncValue?) -> SyncValue? {
        guard case .millis(let x)? = a else { return b }
        guard case .millis(let y)? = b else { return a }
        return x > y ? a : b
    }

    /// Whether `a` is strictly later than `b`; no date is earlier than any date.
    static func isLater(_ a: SyncValue?, than b: SyncValue?) -> Bool {
        guard case .millis(let x)? = a else { return false }
        guard case .millis(let y)? = b else { return true }
        return x > y
    }

    /// A set both sides changed: iCloud's, plus what the device added, less what the device removed.
    static func union(_ local: SyncValue?, _ server: SyncValue?, base: SyncValue?) -> SyncValue? {
        func names(_ value: SyncValue?) -> Set<String> {
            if case .referenceList(let list)? = value { return Set(list) }
            return []
        }
        let l = names(local), s = names(server), b = names(base)
        let merged = s.union(l.subtracting(b)).subtracting(b.subtracting(l))
        return merged.isEmpty ? nil : .references(merged)
    }
}
