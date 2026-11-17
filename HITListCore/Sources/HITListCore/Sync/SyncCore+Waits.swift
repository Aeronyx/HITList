import Foundation

// References to items that are not on this device (`dev/SYNC-ENGINE.md` section 8). **A reference to an item that is
// not on this device is never cleared by this device**: an item that is absent may only be late (a label sent a batch
// after its task), or deleted here (the store took the reference off the rows that pointed at it, which is not the
// person removing a label).
//
// So a record that iCloud holds pointing at an item the device lacks *waits* for it: the ledger's `deferred` list
// holds, per record, its key and the reference fields it is waiting for (a to-one: the name; a set: the names
// missing here). The brain reasons about the **whole** record, the device's record plus what it waits for: that is
// what is compared with `base`, what goes into the merge, and what is sent. The device is written with what it can
// show. When a waited-for item appears on the device, the reference is written there (the device first) and the
// record stops waiting (then the ledger): a crash in between leaves the reference both on the device and listed as
// waited for, and the whole record is the same either way.
//
// The memory is what tells "the item arrived" from "the person removed the reference": both look like a base that
// points at an item that is here while the device's record does not.

extension SyncCore {
    /// The references `key` is waiting for, by field.
    func waitsFor(_ key: SyncKey) -> [String: SyncValue] {
        waits[key]?.record.fields ?? [:]
    }

    /// A to-one field the person cleared while the base still points at an item: no reference is waited for there.
    static let clearedMark = SyncValue.referenceList([])

    /// Where a wait keeps, beside a set field, the names the person took off it while the base still holds them: none
    /// of them is waited for (the set's twin of `clearedMark`). Not a field of any type: nothing reads it as one.
    static func removedKey(_ field: String) -> String { field + ".removed" }

    /// The device's record with every reference it waits for honoured: a set gets the names it waits for, a to-one
    /// gets the one it waits for only while the device's field is empty (a value there is the person's choice).
    static func whole(_ local: SyncRecord?, waiting: [String: SyncValue]) -> SyncRecord? {
        guard var out = local, !waiting.isEmpty else { return local }
        let type = SyncSchema.type(out.key.type)
        for field in waiting.keys.sorted() {
            let kind = type?.fields.first(where: { $0.key == field })?.kind
            // A set's removed names are a note, not a field.
            if type != nil, kind == nil { continue }
            // A to-one's `clearedMark` (an empty list) is a note, not a reference.
            if case .reference? = kind { if case .referenceList? = waiting[field] { continue } }
            switch waiting[field] {
            case .reference?:
                if out.fields[field] == nil { out.fields[field] = waiting[field] }
            case .referenceList(let names)?:
                var all = Set(names)
                if case .referenceList(let have)? = out.fields[field] { all.formUnion(have) }
                out.fields[field] = .references(all)
            default:
                break
            }
        }
        return out
    }

    /// `record` as the device can show it: without the references to items that will not be on it.
    static func shown(_ record: SyncRecord?, present: (SyncKey) -> Bool) -> SyncRecord? {
        guard var out = record, let type = SyncSchema.type(out.key.type) else { return record }
        for field in type.fields {
            switch (field.kind, out.fields[field.key]) {
            case (.reference(let target), .reference(let name)?):
                if !present(SyncKey(type: target, name: name)) { out.fields[field.key] = nil }
            case (.references(let target), .referenceList(let names)?):
                let here = names.filter { present(SyncKey(type: target, name: $0)) }
                out.fields[field.key] = here.isEmpty ? nil : .references(here)
            default:
                break
            }
        }
        return out
    }

    /// What a record waits for: the references of its whole record to items that are not on the device (a to-one
    /// only while the device's field is empty). The whole record is what the record waited for until now (`current`:
    /// what the last settle decided, or what a deletion here took off it) and, beside it, `base`. A to-one the record
    /// already waits for keeps its name over the base's (brief 145, seed 93: a person's unsent move to a Group whose
    /// deletion then arrived was dropped, and the base's older Group honoured instead); a set waits for the names of
    /// both. Nothing for an item that is not here itself.
    static func waitFields(local: SyncRecord?, base: SyncRecord?, current: [String: SyncValue] = [:],
                           present: (SyncKey) -> Bool) -> [String: SyncValue] {
        guard let local, let type = SyncSchema.type(local.key.type) else { return [:] }
        let base = base?.isDeleted == false ? base : nil
        var out: [String: SyncValue] = [:]
        for field in type.fields {
            switch field.kind {
            case .reference(let target):
                if let held = local.fields[field.key] {
                    // The device holds another item than the base names: the person's choice (or the merge's), so the
                    // base's reference is no longer one this record waits for. Remembered, so that this item's
                    // deletion here before the change went leaves the field empty and does not bring the base's
                    // older reference back (everyday seeds 210, 261; round 32).
                    if case .reference? = base?.fields[field.key], base?.fields[field.key] != held {
                        out[field.key] = Self.clearedMark
                    }
                    continue
                }
                if case .reference(let name)? = current[field.key], !present(SyncKey(type: target, name: name)) {
                    out[field.key] = .reference(name)
                } else if case .reference(let name)? = base?.fields[field.key] {
                    if present(SyncKey(type: target, name: name)) {
                        // The base points at an item that is here and the field is empty: the person cleared it.
                        // Remembered (an empty list, `clearedMark`), so that a deletion of that item here before the
                        // change went does not bring the old reference back as one waited for (brief 145, everyday
                        // seeds 166, 210, 261). It ends when the base no longer holds the reference, or a settle.
                        out[field.key] = Self.clearedMark
                    } else if current[field.key] == Self.clearedMark {
                        out[field.key] = Self.clearedMark
                    } else {
                        out[field.key] = .reference(name)
                    }
                }
            case .references(let target):
                func names(_ value: SyncValue?) -> Set<String> {
                    if case .referenceList(let list)? = value { return Set(list) }
                    return []
                }
                func isHere(_ name: String) -> Bool { present(SyncKey(type: target, name: name)) }
                let held = names(local.fields[field.key]), noted = names(current[Self.removedKey(field.key)])
                var missing = names(current[field.key]).filter { !isHere($0) }
                var removed = Set<String>()
                for name in names(base?.fields[field.key]) where !held.contains(name) && !missing.contains(name) {
                    // A name the base holds and the device does not: taken off by the person while its item was here
                    // (now, or noted before that item went), else by the store because the item is not here.
                    if isHere(name) || noted.contains(name) { removed.insert(name) } else { missing.insert(name) }
                }
                if !missing.isEmpty { out[field.key] = .references(missing) }
                if !removed.isEmpty { out[Self.removedKey(field.key)] = .references(removed) }
            default:
                break
            }
        }
        return out
    }

    /// A settle's waits, read against the base the record now has: a to-one the device had marked cleared (the
    /// person emptied it, `clearedMark`) stays marked while the decided record leaves it empty and `base` names an
    /// item, so the base's reference is not waited for. Only a mark the device already held is kept: an empty field
    /// with none may be the store's own clearing (a row it lost), which the next compare reads from the base.
    static func keepCleared(_ wait: inout [String: SyncValue], current: [String: SyncValue], decided: SyncRecord?,
                            base: SyncRecord) {
        guard let decided, !base.isDeleted, let type = SyncSchema.type(decided.key.type) else { return }
        for field in type.fields {
            switch field.kind {
            case .reference:
                guard current[field.key] == Self.clearedMark, decided.fields[field.key] == nil,
                      case .reference? = base.fields[field.key], wait[field.key] == nil else { continue }
                wait[field.key] = Self.clearedMark
            case .references:
                // A set's removed names likewise: those still out of the decided set and still in iCloud's.
                guard case .referenceList(let noted)? = current[Self.removedKey(field.key)],
                      case .referenceList(let there)? = base.fields[field.key] else { continue }
                var kept = Set(noted).intersection(there)
                if case .referenceList(let decidedNames)? = decided.fields[field.key] { kept.subtract(decidedNames) }
                if case .referenceList(let waited)? = wait[field.key] { kept.subtract(waited) }
                if !kept.isEmpty { wait[Self.removedKey(field.key)] = .references(kept) }
            default:
                break
            }
        }
    }

    /// The references a wait names, by the items they point at.
    static func targets(of fields: [String: SyncValue], type name: String) -> [SyncKey] {
        guard let type = SyncSchema.type(name) else { return [] }
        var out: [SyncKey] = []
        for field in type.fields {
            switch (field.kind, fields[field.key]) {
            case (.reference(let target), .reference(let ref)?):
                out.append(SyncKey(type: target, name: ref))
            case (.references(let target), .referenceList(let refs)?):
                out.append(contentsOf: refs.map { SyncKey(type: target, name: $0) })
            default:
                break
            }
        }
        return out
    }

    /// The records waiting for any of `items`.
    func waiters(of items: Set<SyncKey>) -> Set<SyncKey> {
        guard !items.isEmpty else { return [] }
        var out = Set<SyncKey>()
        for (key, wait) in waits where Self.targets(of: wait.record.fields, type: key.type).contains(where: items.contains) {
            out.insert(key)
        }
        return out
    }

    /// The device's record with the waited-for references whose items are here now written in (a to-one only into
    /// an empty field). Nil when there is nothing to write. (What a record waits for is its whole record, kept up to
    /// date by every settle, so it no longer has to be in `base` too: a reference a person gave here and a deletion
    /// then took off is waited for although iCloud has not heard of it yet.)
    static func arrived(_ local: SyncRecord, waiting: [String: SyncValue],
                        present: (SyncKey) -> Bool) -> SyncRecord? {
        guard let type = SyncSchema.type(local.key.type) else { return nil }
        var out = local
        for field in type.fields {
            switch (field.kind, waiting[field.key]) {
            case (.reference(let target), .reference(let name)?):
                if out.fields[field.key] == nil, present(SyncKey(type: target, name: name)) {
                    out.fields[field.key] = .reference(name)
                }
            case (.references(let target), .referenceList(let names)?):
                let come = names.filter { present(SyncKey(type: target, name: $0)) }
                if !come.isEmpty {
                    var all = Set(come)
                    if case .referenceList(let have)? = out.fields[field.key] { all.formUnion(have) }
                    out.fields[field.key] = .references(all)
                }
            default:
                break
            }
        }
        return RecordMerge.same(out, local) ? nil : out
    }

    /// The ledger's entry for what `key` waits for: its key and the reference fields (`system` unused).
    static func waitRecord(_ key: SyncKey, _ fields: [String: SyncValue]) -> CloudRecord {
        CloudRecord(record: SyncRecord(key: key, fields: fields), system: Data())
    }
}
