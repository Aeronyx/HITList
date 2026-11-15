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

    /// The device's record with every reference it waits for honoured: a set gets the names it waits for, a to-one
    /// gets the one it waits for only while the device's field is empty (a value there is the person's choice).
    static func whole(_ local: SyncRecord?, waiting: [String: SyncValue]) -> SyncRecord? {
        guard var out = local, !waiting.isEmpty else { return local }
        for field in waiting.keys.sorted() {
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
                guard local.fields[field.key] == nil else { continue }
                if case .reference(let name)? = current[field.key], !present(SyncKey(type: target, name: name)) {
                    out[field.key] = .reference(name)
                } else if case .reference(let name)? = base?.fields[field.key], !present(SyncKey(type: target, name: name)) {
                    out[field.key] = .reference(name)
                }
            case .references(let target):
                var names = Set<String>()
                if case .referenceList(let list)? = current[field.key] { names.formUnion(list) }
                if case .referenceList(let list)? = base?.fields[field.key] { names.formUnion(list) }
                let missing = names.filter { !present(SyncKey(type: target, name: $0)) }
                if !missing.isEmpty { out[field.key] = .references(missing) }
            default:
                break
            }
        }
        return out
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
    static func arrived(_ local: SyncRecord, waiting: [String: SyncValue], base: SyncRecord?,
                        present: (SyncKey) -> Bool) -> SyncRecord? {
        guard let type = SyncSchema.type(local.key.type) else { return nil }
        _ = base
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
