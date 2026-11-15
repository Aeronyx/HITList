import Foundation

// Finding what changed on the device (`dev/SYNC-ENGINE.md` section 4) and what to send for it. Nothing is journalled:
// the device's items are compared with the ledger's bases, whatever wrote them and whether or not `updatedAt` moved.

extension SyncCore {
    /// What the compare found for one key.
    struct Finding {
        /// The change the transport's list should hold for it; nil: nothing to send.
        var change: PendingChange?
        /// The ledger entry to write (a deletion noticed, or one put right); nil: as it is.
        var entry: LedgerEntry?
        /// The entry holds nothing worth keeping and goes.
        var drop = false
    }

    /// Compares `keys` (nil: everything) and makes the transport's list match. Writes the ledger first (a deletion
    /// noticed here), then the list: a crash in between leaves a list the next compare puts right. While held,
    /// nothing is compared (a full iCloud excepted: then the count is kept, and nothing is added; and a mass
    /// deletion, which a whole compare outside an event looks at again, to lift it when the items are back).
    ///
    /// This is the one place a deletion here is noticed, so it is the one place guarded against a store that reads
    /// wrong: a whole compare that finds the store empty while iCloud holds items, or more items gone than `limits`
    /// allows at once, notices nothing and holds (`massDeletion`). A compare of a few keys that finds many gone
    /// decides on everything instead. `confirmedAt`: the person confirmed, the deletions carry that moment.
    func compare(_ keys: Set<SyncKey>?, confirmedAt: Date? = nil) async {
        guard loaded else { return }
        if let hold, hold != .storageFull {
            guard case .massDeletion = hold, keys == nil, !inEvent else { return }
        }
        var here: [SyncKey: SyncRecord]
        var universe: Set<SyncKey>
        let present: Set<SyncKey>
        do {
            let records: [SyncRecord]
            if let keys { records = try await store.records(keys) } else { records = try await store.records() }
            here = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            universe = keys ?? Set(here.keys).union(entries.keys)
            if keys != nil {
                // Records waiting for an item among these that is here now are looked at with them (section 8).
                let more = waiters(of: Set(here.keys)).subtracting(universe)
                if !more.isEmpty {
                    here.merge(try await localRecords(more)) { first, _ in first }
                    universe.formUnion(more)
                }
            }
            // Whether the items the bases (and the waits) point at are on the device.
            var targets = Set<SyncKey>()
            for key in universe {
                if let base = entries[key]?.base { targets.formUnion(Self.references(base)) }
                targets.formUnion(Self.targets(of: waitsFor(key), type: key.type))
            }
            let unknown = keys == nil ? Set<SyncKey>() : targets.subtracting(here.keys)
            let found = unknown.isEmpty ? Set<SyncKey>() : Set(try await localRecords(unknown).keys)
            present = keys == nil ? Set(here.keys) : Set(here.keys).union(found)
        } catch let SyncStoreError.duplicates(keys) {
            await enterHold(.duplicates(keys.sorted()))
            return
        } catch {
            await fail("The device's items could not be read: \(error)")
            return
        }
        if keys == nil { universe.insert(Self.metaKey) }
        let isHere: (SyncKey) -> Bool = { present.contains($0) }
        let now = clock()
        var desired: [SyncKey: PendingChange] = [:]
        var write = LedgerWrite()
        var arrivals: [LocalWrite] = []
        var gone = 0
        // In key order: nothing a `Set` happens to iterate first decides what is written or logged (replays).
        for key in universe.sorted() where key != Self.metaKey {
            var local = here[key]
            // A waited-for item that is here now: its reference goes on the device (written below, before the ledger).
            if let device = local, waits[key] != nil,
               let arrived = Self.arrived(device, waiting: waitsFor(key), base: entries[key]?.base, present: isHere) {
                arrivals.append(LocalWrite(key: key, expected: device, record: arrived))
                local = arrived
                here[key] = arrived
            }
            // What it waits for now: its whole record's references to items not on the device.
            let wait = Self.waitFields(local: local, base: entries[key]?.base, current: waitsFor(key), present: isHere)
            if wait != waitsFor(key) {
                if wait.isEmpty { write.deferRemove.append(key) } else { write.deferUpsert.append(Self.waitRecord(key, wait)) }
            }
            let whole = Self.whole(local, waiting: wait)
            let finding = self.finding(key, local: whole, now: confirmedAt ?? now)
            if let change = finding.change { desired[key] = change }
            if let entry = finding.entry {
                write.upsert.append(entry)
                if entry.deletedHereAt != nil, entries[key]?.deletedHereAt == nil { gone += 1 }
            }
            if finding.drop { write.remove.append(key) }
        }
        if universe.contains(Self.metaKey), let change = metaFinding().change { desired[Self.metaKey] = change }

        if confirmedAt == nil {
            if keys != nil, gone >= limits.massDeletionCount {
                // Many gone at once in a save's hint: measured against everything before anything is decided.
                await compare(nil)
                return
            }
            if keys == nil {
                // The supervisor's rule of 2026-11-15 (review finding 2). (a) The store is not the one the ledger
                // describes: no item here has a living base while the ledger holds living bases (one stray row, a
                // seeded filter or the profile, no longer defeats "empty"). (b) Many gone at once: at least the count
                // AND more than the share of the living bases.
                // Living: what iCloud holds alive that this device has not already found deleted here (a deletion
                // noticed before, confirmed or under the numbers, is decided: counting it again would ask again after
                // every "I deleted them", in a loop, until iCloud took the markers; brief 145).
                let living = entries.values.filter {
                    $0.key != Self.metaKey && $0.base?.isDeleted == false && $0.deletedHereAt == nil
                }.count
                let known = here.keys.contains { entries[$0]?.base?.isDeleted == false }
                let empty = living > 0 && !known
                let tooMany = gone >= limits.massDeletionCount && Double(gone) > limits.massDeletionShare * Double(living)
                if empty || tooMany {
                    await holdMassDeletion(empty ? living : gone, of: living, at: now)
                    return
                }
                if case .massDeletion(let count)? = hold {
                    log("The \(count) missing items are back (or few enough now): the hold lifts by itself")
                    await lift(resetTransport: true)
                }
            }
        }

        // The device first (the references that arrived), then the ledger. One the person overtook keeps waiting:
        // its wait is left as it was, and the next compare writes it.
        if !arrivals.isEmpty {
            do {
                let stale = try await store.apply(arrivals)
                if !stale.isEmpty {
                    write.deferUpsert.removeAll { stale.contains($0.key) }
                    write.deferRemove.removeAll { stale.contains($0) }
                }
                let written = Set(arrivals.map(\.key)).subtracting(stale)
                for key in written.sorted() { log("\(key): an item it points at is here now; the reference is written here") }
                if !written.isEmpty { host?.didWrite(written) }
            } catch {
                await storeFailed(error)
                return
            }
        }
        do {
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return
        }
        if keys == nil {
            // Everything was looked at: what waits is exactly what this compare found.
            waiting = Set(desired.keys)
        } else {
            for key in universe { waiting.remove(key) }
            waiting.formUnion(desired.keys)
        }
        if !write.upsert.isEmpty {
            for entry in write.upsert where entry.deletedHereAt != nil {
                log("\(entry.key): deleted here; its marker is waiting to go")
            }
        }
        await matchPending(desired, within: keys == nil ? nil : universe, depth: Self.depths(here))
    }

    /// How deep each task is under its parents, as far as `records` tell: the order sub-tasks are added in.
    static func depths(_ records: [SyncKey: SyncRecord]) -> [SyncKey: Int] {
        var out: [SyncKey: Int] = [:]
        for (key, record) in records where key.type == "TaskItem" {
            var depth = 0
            var current = record
            while depth < 64, case .reference(let parent)? = current.fields["parent"],
                  let next = records[SyncKey(type: "TaskItem", name: parent)] {
                depth += 1
                current = next
            }
            out[key] = depth
        }
        return out
    }

    /// Makes the transport's list hold exactly `desired` for the keys in `within` (nil: for every key). Nothing is
    /// added before the first whole fetch has finished (section 7) or while iCloud is full. Added with the items
    /// pointed at before those that point at them (`SyncSchema.types`, a task after its parent), so iCloud rarely
    /// holds a record ahead of its target.
    func matchPending(_ desired: [SyncKey: PendingChange], within: Set<SyncKey>?, depth: [SyncKey: Int] = [:]) async {
        let pending = await transport.pending()
        let listed = Set(pending)
        var remove: [PendingChange] = []
        for change in pending where within?.contains(change.key) ?? true {
            if desired[change.key] != change { remove.append(change) }
        }
        var add: [PendingChange] = []
        if firstFetchDone, hold == nil {
            let ordered = desired.keys.sorted { a, b in
                let ra = Self.rank(a.type), rb = Self.rank(b.type)
                if ra != rb { return ra < rb }
                let da = depth[a] ?? 0, db = depth[b] ?? 0
                if da != db { return da < db }
                return a.name < b.name
            }
            for key in ordered {
                if let change = desired[key], !listed.contains(change) { add.append(change) }
            }
        }
        if !remove.isEmpty { await transport.remove(remove) }
        if !add.isEmpty { await transport.add(add) }
        if !add.isEmpty || !remove.isEmpty {
            log("Waiting to go: \(waiting.count) (\(add.count) added to the list, \(remove.count) taken off)")
        }
    }

    /// One key's comparison: the device's item `local` against the ledger's base.
    func finding(_ key: SyncKey, local: SyncRecord?, now: Date) -> Finding {
        let entry = entries[key]
        var finding = Finding()
        if let local {
            if let base = entry?.base {
                if base.isDeleted {
                    // Made again here after iCloud learned it was deleted (an undo, an import): it goes (M12).
                    finding.change = .save(key)
                } else if !RecordMerge.same(local, base) {
                    finding.change = .save(key)
                }
                if var entry, entry.deletedHereAt != nil {
                    // It was deleted here and is back before its marker went: the item, not the marker.
                    entry.deletedHereAt = nil
                    finding.entry = entry
                }
            } else {
                if firstFetchDone {
                    // New here. Before the first whole fetch it may well be in iCloud already: not counted, not sent.
                    finding.change = .save(key)
                }
                // A deletion kept across a forgotten memory, undone: nothing left to remember.
                if entry != nil { finding.drop = true }
            }
        } else if let entry {
            guard let base = entry.base else {
                // A deletion kept across a forgotten memory waits for the next whole fetch to settle it; anything
                // else with no base is nothing.
                if entry.deletedHereAt == nil { finding.drop = true }
                return finding
            }
            if base.isDeleted {
                if let at = entry.deletedHereAt, !RecordMerge.same(.marker(key, deletedAt: at), base) {
                    // Deleted here too, later than iCloud's marker says (M10): the later marker goes.
                    finding.change = .save(key)
                } else if Self.expired(base, now: now) {
                    // A marker both sides know: removed for good once past its lifetime.
                    finding.change = .delete(key)
                }
            } else {
                // iCloud holds it alive and it is gone here: deleted here, its marker waits to go.
                finding.change = .save(key)
                if entry.deletedHereAt == nil {
                    var noticed = entry
                    // Never before the version it deletes: a device whose clock runs behind still deletes what it
                    // held (a marker stamped earlier would lose to that version on a device merging afresh).
                    noticed.deletedHereAt = max(now, base.updatedAt ?? now)
                    finding.entry = noticed
                }
            }
        }
        if let refusal = refused[key] {
            if RecordMerge.same(refusal.local, local), finding.change != nil {
                // Refused for good as it is: kept out until it changes.
                finding.change = nil
            } else {
                refused[key] = nil
            }
        }
        return finding
    }

    /// The zone's own record: sent once the first fetch has shown iCloud has none.
    func metaFinding() -> Finding {
        var finding = Finding()
        if firstFetchDone, entries[Self.metaKey]?.base == nil { finding.change = .save(Self.metaKey) }
        return finding
    }

    static func expired(_ marker: SyncRecord, now: Date) -> Bool {
        guard let at = marker.deletedAt ?? marker.updatedAt else { return false }
        return at.addingTimeInterval(SyncSchema.markerLifetime) < now
    }

    /// The record to send for `key` as it is now (T3): the item with the ledger's token; the marker of an item
    /// deleted here, at the time it was noticed; `Meta/meta` while iCloud has none; nil when there is nothing to
    /// send after all (the transport then drops the change). Nothing goes while held or before the first fetch.
    func outgoing(_ key: SyncKey) async -> OutgoingRecord? {
        guard loaded, firstFetchDone else { return nil }
        if let hold {
            log("\(key): not sent, held: \(hold.words)")
            return nil
        }
        if key == Self.metaKey {
            guard entries[Self.metaKey]?.base == nil else { return nil }
            let meta = SyncRecord(key: key, fields: [SyncSchema.metaFormatVersion: .int(Int64(SyncSchema.formatVersion))])
            return OutgoingRecord(record: meta, system: nil)
        }
        let local: SyncRecord?
        do {
            // The whole record: the device's, with the references it waits for (section 8). A reference to an item
            // that is not on this device is never sent away.
            local = Self.whole(try await store.records([key]).first, waiting: waitsFor(key))
        } catch let SyncStoreError.duplicates(keys) {
            await enterHold(.duplicates(keys.sorted()))
            return nil
        } catch {
            await fail("The device's items could not be read: \(error)")
            return nil
        }
        if let refusal = refused[key], RecordMerge.same(refusal.local, local) { return nil }
        let entry = entries[key]
        if let local {
            if let base = entry?.base, !base.isDeleted, RecordMerge.same(local, base) { return nil }
            // No base: what goes is written down first (M5's amendment, `SyncCore+Sent`), so that an answer that never
            // comes still leaves this device something to settle iCloud's record against.
            if entry?.base == nil, !(await rememberSend(local, for: key)) { return nil }
            sentAs[key] = .some(local)
            return OutgoingRecord(record: local, system: entry?.system)
        }
        guard let entry, let base = entry.base else { return nil }
        if base.isDeleted {
            // A marker later than iCloud's (M10), or nothing: iCloud already holds the marker.
            guard let at = entry.deletedHereAt, !RecordMerge.same(.marker(key, deletedAt: at), base) else { return nil }
            sentAs[key] = .some(nil)
            return OutgoingRecord(record: .marker(key, deletedAt: at), system: entry.system)
        }
        // A deletion is only ever noticed by the compare, which guards against a store that reads wrong: one it has
        // not noticed is not sent (the transport drops the change; the compare adds the marker when it notices).
        guard let at = entry.deletedHereAt else { return nil }
        sentAs[key] = .some(nil)
        return OutgoingRecord(record: .marker(key, deletedAt: at), system: entry.system)
    }
}
