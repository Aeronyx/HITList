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
    public static func normal(_ record: SyncRecord?) -> SyncRecord? {
        guard let record else { return nil }
        guard let known = SyncSchema.known(record) else { return record }
        return SyncSchema.filled(known)
    }

    public static func merge(_ input: MergeInput) -> MergeOutcome {
        let base = normal(input.base), local = normal(input.local), server = normal(input.server)
        guard let key = (local ?? server ?? base)?.key, let type = SyncSchema.type(key.type) else {
            // Nothing anywhere, or a type this build does not know: leave the device as it is.
            return MergeOutcome(merged: local, rule: .nothing)
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
                // M10 (and M13 for a marker both knew): deleted there, not here either.
                return MergeOutcome(merged: server, rule: base.isDeleted ? .cameBackThere : .deletedBoth)
            }
            if base.isDeleted {
                // M13: deleted as far as this device knew, made again on another.
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
                // M12: the device knew it deleted and holds it again: made again here (an undo, an import). It
                // stands, whatever its dates. If another device made it again too, the two meet for the first time.
                if server.isDeleted { return MergeOutcome(merged: local, rule: .cameBackHere) }
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
