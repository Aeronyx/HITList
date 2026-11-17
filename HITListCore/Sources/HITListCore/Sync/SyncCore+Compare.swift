import Foundation

// Finding what changed on the device (`dev/SYNC-ENGINE.md` section 4) and what to send for it.
//
// A change is found by comparing: an item whose record differs from the ledger's base is waiting to go, whatever
// wrote it and whether or not `updatedAt` moved. **A deletion is never found by comparing.** It is known only when
// the store wrote it down as it happened (`SyncLocalStore.deletions`), and an item that is merely not here, with no
// deletion written down, is missing: forgotten by the ledger and fetched again. So a store that reads empty, loses
// rows or is put back from an older copy cannot delete anything in iCloud, and no guard has to guess.

extension SyncCore {
    /// What the compare found for one key.
    struct Finding {
        /// The change the transport's list should hold for it; nil: nothing to send.
        var change: PendingChange?
        /// The ledger entry to write (a deletion noticed, or one put right); nil: as it is.
        var entry: LedgerEntry?
        /// The entry holds nothing worth keeping and goes.
        var drop = false
        /// iCloud holds the item, this device agreed on it, and it is not here with no deletion written down: not a
        /// deletion. The entry goes and every record is asked for again, so iCloud's comes back (M14).
        var missing = false
    }

    /// Takes note of what the store says was deleted here (`SyncLocalStore.deletions`): the one way the brain learns
    /// of a deletion on this device. Each is written to the ledger (`deletedHereAt`) before the store is told to
    /// forget it, so a crash in between tells it again, and one noted twice keeps its first time. An item deleted
    /// before this device and iCloud ever agreed on it is kept too, with no base, until a fetch shows whether iCloud
    /// holds it (a save accepted whose answer was lost, a merge without a memory). Runs while held: a person goes on
    /// deleting things whatever iCloud is doing. False when the store or the ledger failed (the brain is then held).
    ///
    /// A note whose row is still here is kept (148 finding 3): the note is taken at `willSave`, so a second deletion
    /// may be written down while its save is still committing, and forgetting its note then would leave the row,
    /// once the save lands, missing with no deletion written down (M14: it would come back). Such a note is read again
    /// at the next compare; only the launch's whole compare (`clearingLeftovers`), when no save of this process can
    /// be in flight, forgets those left for rows that are here (a save that failed, an undo).
    func noteDeletions(clearingLeftovers: Bool = false) async -> Bool {
        let told: Set<SyncKey>
        let here: Set<SyncKey>
        do {
            told = try await store.deletions()
            guard !told.isEmpty else { return true }
            here = Set(try await store.records(told).map(\.key))
        } catch {
            await storeFailed(error)
            return false
        }
        let now = clock()
        var write = LedgerWrite()
        for key in told.sorted() where !here.contains(key) && SyncSchema.type(key.type) != nil {
            if var entry = entries[key] {
                // A marker iCloud already holds, or a deletion already noted: nothing to add.
                guard entry.deletedHereAt == nil, entry.base?.isDeleted != true else { continue }
                // Never before the version it deletes: a device whose clock runs behind still deletes what it held
                // (a marker stamped earlier would lose to that version on a device merging afresh).
                entry.deletedHereAt = max(now, entry.base?.updatedAt ?? now)
                write.upsert.append(entry)
            } else {
                write.upsert.append(LedgerEntry(key: key, base: nil, system: nil, deletedHereAt: now))
            }
        }
        do {
            try await commit(write)
            try await store.forget(deletions: clearingLeftovers ? told : told.subtracting(here))
        } catch {
            await fail(SyncFailureWords.deletionNotNoted, error)
            return false
        }
        for entry in write.upsert where entry.base != nil { log("\(entry.key): deleted here; its marker is waiting to go") }
        let gone = Set(write.upsert.map(\.key))
        noted.formUnion(gone)
        // The store took the reference off every record that pointed at what went (section 8): those records are
        // looked at with it, so each keeps the reference as one it waits for before anything of it is sent. (A save's
        // hint usually names them too; this does not rest on it.)
        if !gone.isEmpty {
            for (key, entry) in entries {
                guard let base = entry.base, !base.isDeleted, !gone.contains(key) else { continue }
                if Self.references(base).contains(where: gone.contains) { noted.insert(key) }
            }
        }
        return true
    }

    /// Outside an event and when not held: has the transport forget its bookmark if records were let go or found
    /// missing (`refetch`), so the next fetch brings every record again. (A hold that lifts does the same, `lift`.)
    func refetchIfOwed() async {
        guard refetch, hold == nil, !inEvent, transportStarted else { return }
        await transport.reset()
        var write = LedgerWrite()
        write.facts.updateValue(nil, forKey: Self.refetchFact)
        write.facts.updateValue(nil, forKey: Self.unsettledFact)
        try? await commit(write)
        unsettled = [:]
        log("Everything will be fetched again")
        // The transport forgot its list with its bookmark: put back what is waiting.
        await compare(nil)
    }

    /// Compares `keys` (nil: everything) and makes the transport's list match. Deletions the store wrote down are
    /// noted first (while held too); then, unless held (a full iCloud excepted: the count is kept and nothing is
    /// added), each item is compared with its base. The ledger is written first, then the list: a crash in between
    /// leaves a list the next compare puts right. `launch`: the start's own whole compare, which also clears notes left
    /// for rows that are here (`noteDeletions`).
    func compare(_ asked: Set<SyncKey>?, launch: Bool = false) async {
        guard loaded else { return }
        guard await noteDeletions(clearingLeftovers: launch && asked == nil) else { return }
        if let hold, !hold.triedOnReturn { return }
        // The deletions just noted are looked at too, whatever was asked for.
        let keys = asked.map { $0.union(noted) }
        noted = []
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
            await fail(SyncFailureWords.dataNotRead, error)
            return
        }
        if keys == nil { universe.insert(Self.metaKey) }
        let isHere: (SyncKey) -> Bool = { present.contains($0) }
        let now = clock()
        var desired: [SyncKey: PendingChange] = [:]
        var write = LedgerWrite()
        var arrivals: [LocalWrite] = []
        var missing: [SyncKey] = []
        // In key order: nothing a `Set` happens to iterate first decides what is written or logged (replays).
        for key in universe.sorted() where key != Self.metaKey {
            var local = here[key]
            // A waited-for item that is here now: its reference goes on the device (written below, before the ledger).
            if let device = local, waits[key] != nil,
               let arrived = Self.arrived(device, waiting: waitsFor(key), present: isHere) {
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
            let finding = self.finding(key, local: whole, now: now)
            if let change = finding.change { desired[key] = change }
            if let entry = finding.entry { write.upsert.append(entry) }
            if finding.drop || finding.missing { write.remove.append(key) }
            if finding.missing { missing.append(key) }
            if local != nil, !askedAgain.isEmpty { askedAgain.remove(key) }
        }
        if universe.contains(Self.metaKey), let change = metaFinding().change { desired[Self.metaKey] = change }

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
            await fail(SyncFailureWords.recordsNotSaved, error)
            return
        }
        if !missing.isEmpty {
            // Not deleted by anyone: what iCloud holds of them comes back with the next fetch of everything. Once
            // for an item until it has been seen here again.
            let first = missing.filter { !askedAgain.contains($0) }
            askedAgain.formUnion(missing)
            if first.isEmpty {
                log("\(missing.count) item\(missing.count == 1 ? "" : "s") iCloud holds could not be put back on this device (the first: \(missing[0])); left for the next launch")
            } else {
                log("\(missing.count) item\(missing.count == 1 ? "" : "s") iCloud holds \(missing.count == 1 ? "is" : "are") not on this device and nobody deleted \(missing.count == 1 ? "it" : "them") here (the first: \(missing[0])): fetched again, nothing is deleted in iCloud")
                await markRefetch()
            }
        }
        if keys == nil {
            // Everything was looked at: what waits is exactly what this compare found.
            waiting = Set(desired.keys)
        } else {
            for key in universe { waiting.remove(key) }
            waiting.formUnion(desired.keys)
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
            } else if entry.deletedHereAt != nil {
                // iCloud holds it alive and it was deleted here (`noteDeletions`): its marker waits to go.
                finding.change = .save(key)
            } else {
                // iCloud holds it alive and it is not here, and no deletion of it was written down: missing.
                finding.missing = true
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

    /// The zone's own record: sent once the first fetch has shown iCloud has none. Refused for good, it is kept out
    /// like any other record (until the next launch), not put back at every compare (148 finding 1).
    func metaFinding() -> Finding {
        var finding = Finding()
        if firstFetchDone, entries[Self.metaKey]?.base == nil, refused[Self.metaKey] == nil {
            finding.change = .save(Self.metaKey)
        }
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
            await fail(SyncFailureWords.dataNotRead, error)
            return nil
        }
        if let refusal = refused[key], RecordMerge.same(refusal.local, local) { return nil }
        let entry = entries[key]
        if let local {
            if let base = entry?.base, !base.isDeleted, RecordMerge.same(local, base) { return nil }
            // What goes is written down first (`SyncCore+Sent`), so that an answer that never comes still leaves this
            // device something to settle iCloud's record against.
            guard await rememberSend(local, for: key) else { return nil }
            sentAs[key] = .some(local)
            if entry?.base?.isDeleted == false {
                // Kept until this send is answered: the save may land and its answer be lost (`decide`).
                var sends = unanswered[key] ?? []
                if sends.last.map({ !RecordMerge.same($0, local) }) ?? true { sends.append(Self.base(local)) }
                unanswered[key] = Array(sends.suffix(Self.unansweredKept))
            }
            return OutgoingRecord(record: local, system: entry?.system)
        }
        guard let entry, let base = entry.base else { return nil }
        if base.isDeleted {
            // A marker later than iCloud's (M10), or nothing: iCloud already holds the marker.
            guard let at = entry.deletedHereAt, !RecordMerge.same(.marker(key, deletedAt: at), base) else { return nil }
            sentAs[key] = .some(nil)
            return OutgoingRecord(record: .marker(key, deletedAt: at), system: entry.system)
        }
        // Only a deletion written down is sent (`noteDeletions`): an item that is merely not here is not one.
        guard let at = entry.deletedHereAt else { return nil }
        sentAs[key] = .some(nil)
        return OutgoingRecord(record: .marker(key, deletedAt: at), system: entry.system)
    }
}
