import Foundation

// What arrives from iCloud (`dev/SYNC-ENGINE.md` sections 5 and 8) and what comes back from a send. The order of
// writes is the point of this file: **the device first, then the ledger, and only then the transport's list and the
// return from `handle`** (after which the transport moves its bookmark). A crash after the device and before the
// ledger leaves an item that differs from its base: the next compare sends it with the old token, iCloud refuses it
// with a conflict (T6), and the merge finds the two the same. The other order would leave a base that says the device
// holds iCloud's new version while it holds the old one: the next compare would send the old value with the new
// token, and iCloud would take it.

extension SyncCore {
    /// One record's settling: what it was decided on and what it came to.
    struct Settling {
        var key: SyncKey
        /// iCloud's version; nil when iCloud no longer holds the record at all (removed for good, `unknownItem`).
        var server: CloudRecord?
        /// The device's item when the decision was made, as the device holds it (the merge read it whole).
        var local: SyncRecord?
        var outcome: MergeOutcome

        /// What the device should hold, references to items not on it included (`shown` takes those off).
        var target: SyncRecord? { outcome.device }
    }

    // MARK: Fetched

    func fetched(_ changed: [CloudRecord], removed: [SyncKey]) async {
        if let hold, hold.stopsFetching {
            log("\(changed.count + removed.count) fetched records let go unread while held (\(hold.words)); all will be fetched again")
            await markRefetch()
            return
        }
        var records: [CloudRecord] = []
        for record in changed {
            if record.key == Self.metaKey {
                guard await keepMeta(record) else {
                    await markRefetch()
                    return
                }
            } else if SyncSchema.type(record.key.type) == nil {
                log("\(record.key): a type this build does not know; ignored")
            } else {
                records.append(record)
            }
        }
        if removed.contains(Self.metaKey), entries[Self.metaKey] != nil {
            // The zone's meta gone for good: forgotten, so the compare sends it again.
            var forget = LedgerWrite()
            forget.remove = [Self.metaKey]
            do {
                try await commit(forget)
            } catch {
                await fail("The engine's memory could not be written: \(error)")
                await markRefetch()
                return
            }
        }
        let ordered = records.sorted { $0.key < $1.key }
        guard await settle(ordered, removed: removed, why: "fetched") else {
            await markRefetch()
            return
        }
    }

    func didFetch(error: String?) async {
        if let error {
            fetchError = error
            log("A fetch stopped early: \(error). It will be tried again")
            return
        }
        fetchError = nil
        if let hold, hold.stopsFetching { return }
        if !firstFetchDone {
            var write = LedgerWrite()
            write.facts[LedgerFact.firstFetchDone] = Data([1])
            do {
                try await commit(write)
                log("First whole fetch finished: what iCloud lacks can go now")
            } catch {
                await fail("The engine's memory could not be written: \(error)")
                return
            }
        }
        // Deletions kept across a forgotten memory that this whole fetch did not bring: iCloud does not hold the
        // item, so there is nothing to delete there.
        let kept = entries.values.filter { $0.base == nil && $0.deletedHereAt != nil }.map(\.key)
        if !kept.isEmpty {
            do {
                let here = try await localRecords(Set(kept))
                var forget = LedgerWrite()
                forget.remove = kept.filter { here[$0] == nil }.sorted()
                try await commit(forget)
            } catch {
                await storeFailed(error)
                return
            }
        }
        lastFetchEnded = clock()
        await compare(nil)
    }

    /// Keeps the zone's `Meta/meta` as iCloud holds it; holds the brain if its format is newer than this build's.
    /// False when the brain must stop reading what arrived.
    func keepMeta(_ record: CloudRecord) async -> Bool {
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: Self.metaKey, base: Self.base(record.record), system: record.system)]
        do {
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return false
        }
        let version = Self.formatVersion(of: record.record)
        if version > SyncSchema.formatVersion {
            log("iCloud's format is \(version), this build reads \(SyncSchema.formatVersion): held until HITList is updated")
            await enterHold(.needsUpdate)
            return false
        }
        return true
    }

    static func formatVersion(of record: SyncRecord?) -> Int {
        if case .int(let version)? = record?.fields[SyncSchema.metaFormatVersion] { return Int(version) }
        return 0
    }

    // MARK: Settling

    /// Settles records iCloud holds (`incoming`) and records it no longer holds at all (`removed`) against the device
    /// and the ledger: the device first, then the ledger, then the waits and the transport's list (`compare`). The
    /// merge reads the whole record (the device's with what it waits for, section 8); the device is written with what
    /// it can show. False when a write failed or a hold began: nothing after that was done.
    func settle(_ incoming: [CloudRecord], removed: [SyncKey], why: String) async -> Bool {
        var byKey: [SyncKey: CloudRecord] = [:]
        var known = 0
        for record in incoming where SyncSchema.type(record.key.type) != nil {
            if let entry = entries[record.key], entry.system == record.system, RecordMerge.same(entry.base, record.record) {
                // Exactly the version this device already settled (an echo, a fetch delivered twice, everything
                // again after a lost bookmark): nothing new to decide (T2). Deciding again could only lose what this
                // device still has to send, such as a later marker (M10).
                known += 1
                continue
            }
            byKey[record.key] = record
        }
        if known > 0 { log("\(known) \(why) record\(known == 1 ? "" : "s") already settled; nothing new") }
        // A record removed for good after it changed, in one event: removed. A type this build does not know never
        // reaches the merge: left alone, nothing kept, nothing sent, nothing deleted.
        let gone = Set(removed.filter { $0 != Self.metaKey && SyncSchema.type($0.type) != nil })
        for key in gone { byKey[key] = nil }
        let keys = Set(byKey.keys).union(gone)
        guard !keys.isEmpty else { return true }
        let now = clock()

        var local: [SyncKey: SyncRecord]
        do {
            local = try await localRecords(keys)
        } catch {
            await storeFailed(error)
            return false
        }
        // Items iCloud holds alive that are gone here and that nobody noticed yet: noticed first, by a whole compare,
        // which guards against a store that reads wrong (one batch at a time could slip under its numbers). If it
        // holds, nothing arriving is read (it comes again).
        if keys.contains(where: { local[$0] == nil && entries[$0]?.base?.isDeleted == false && entries[$0]?.deletedHereAt == nil }) {
            await compare(nil)
            if let hold, hold.stopsFetching { return false }
        }
        var settling: [SyncKey: Settling] = [:]
        for key in keys { settling[key] = decide(key, server: byKey[key], local: local[key], now: now) }
        let present: Set<SyncKey>
        do {
            present = try await presentAfter(settling)
        } catch {
            await storeFailed(error)
            return false
        }
        func shown(_ decision: Settling) -> SyncRecord? { Self.shown(decision.target, present: { present.contains($0) }) }
        // The items outside this settle that what it deletes here reaches (sub-tasks under a deleted task, records
        // pointing at a deleted Group or label), decided each round with the writes that delete.
        var reached = Set<SyncKey>()

        // 1. The device. A write the person overtook (its `expected` no longer holds) is decided again on what the
        //    device holds now, a few times; then it is left for the next fetch (`refetch`), the base not moved.
        var unsettled = Set<SyncKey>()
        var written = Set<SyncKey>()
        var round = 0
        var toWrite = settling.values.filter { !RecordMerge.same($0.local, shown($0)) }
        while !toWrite.isEmpty {
            let under: Underneath
            do {
                under = try await underneath(toWrite, settling: settling, now: now)
            } catch {
                await storeFailed(error)
                return false
            }
            do {
                // The ledger first: a sub-task that goes carries its deletion's time, one that stays and a record that
                // pointed at what goes keep the reference as one they wait for. A crash before the device is written
                // leaves a time on an item still here (cleared by the next compare) and waits for items still here
                // (dropped by it): the same state, settled again by the next fetch.
                try await commit(under.ledgerWrite)
            } catch {
                await fail("The engine's memory could not be written: \(error)")
                return false
            }
            reached.formUnion(under.keys)
            // Sub-tasks written out from under their parent come first: the store deletes no row a write does not name.
            let writes = under.writes + toWrite.sorted { $0.key < $1.key }.map {
                LocalWrite(key: $0.key, expected: $0.local, record: shown($0))
            }
            let stale: Set<SyncKey>
            do {
                stale = try await store.apply(writes)
            } catch {
                await storeFailed(error)
                return false
            }
            written.formUnion(Set(writes.map(\.key)).subtracting(stale))
            // A sub-task the person changed meanwhile keeps its parent's deletion stale too (strict store): the parent
            // is decided again, and what is under it with it, in the next round.
            let staleSettled = stale.intersection(settling.keys)
            guard !staleSettled.isEmpty else { break }
            round += 1
            let fresh: [SyncKey: SyncRecord]
            do {
                fresh = try await localRecords(staleSettled)
            } catch {
                await storeFailed(error)
                return false
            }
            var again: [Settling] = []
            for key in staleSettled.sorted() {
                let decision = decide(key, server: byKey[key], local: fresh[key], now: now)
                settling[key] = decision
                if !RecordMerge.same(decision.local, shown(decision)) { again.append(decision) }
            }
            if round >= Self.staleRounds, !again.isEmpty {
                for decision in again {
                    unsettled.insert(decision.key)
                    log("\(decision.key): changed here \(round) times while it was being written; fetched again later")
                }
                break
            }
            if !again.isEmpty { log("\(again.count) records changed here between the read and the write; decided again") }
            toWrite = again
        }

        // 2. The ledger: iCloud's version becomes the base (`deletedHereAt` kept while a marker still has to go).
        var write = LedgerWrite()
        for key in keys.sorted() where !unsettled.contains(key) {
            guard let decision = settling[key] else { continue }
            guard let server = decision.server else {
                // Gone from iCloud for good: nothing to remember. An item still here is new again (M11).
                if entries[key] != nil { write.remove.append(key) }
                if waits[key] != nil { write.deferRemove.append(key) }
                continue
            }
            // A marker this device must still send (M8: iCloud holds the item alive; M10: iCloud's marker is
            // earlier than the deletion here): its time is kept, and the compare and `recordToSend` send it.
            let merged = decision.outcome.merged
            let markerToGo = merged?.isDeleted == true && decision.target == nil && !RecordMerge.same(merged, server.record)
            let deletedHereAt = markerToGo ? merged?.deletedAt : nil
            let entry = LedgerEntry(key: key, base: Self.base(server.record), system: server.system,
                                    deletedHereAt: deletedHereAt)
            if entries[key] != entry { write.upsert.append(entry) }
            // What it waits for comes from what the merge decided (section 8), not from the base: when this device's
            // version is the one still to go, its references are not iCloud's, and an older wait must not outlive
            // another device's move.
            let wait = Self.waitFields(local: shown(decision), base: decision.target, present: { present.contains($0) })
            if wait != waitsFor(key) {
                if wait.isEmpty { write.deferRemove.append(key) } else { write.deferUpsert.append(Self.waitRecord(key, wait)) }
            }
        }
        do {
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return false
        }
        if !unsettled.isEmpty { await markRefetch() }

        // 3. What each key now waits for, the references that arrived, and the transport's list.
        await compare(keys.union(reached))
        var inStep = 0
        for key in keys.sorted() {
            guard let decision = settling[key] else { continue }
            if written.contains(key) || unsettled.contains(key) || waiting.contains(key) {
                log(describe(decision, why: why, written: written.contains(key)))
            } else {
                inStep += 1
            }
        }
        if inStep > 0 { log("\(inStep) \(why) record\(inStep == 1 ? "" : "s") already as this device holds them") }
        if !written.isEmpty { host?.didWrite(written) }
        return true
    }

    /// The rule for one record, on what the device and the ledger hold now. The merge reads the whole record.
    func decide(_ key: SyncKey, server: CloudRecord?, local: SyncRecord?, now: Date) -> Settling {
        let entry = entries[key]
        let input = MergeInput(base: entry?.base, local: Self.whole(local, waiting: waitsFor(key)),
                               deletedHereAt: entry?.deletedHereAt, server: server?.record, now: now)
        return Settling(key: key, server: server, local: local, outcome: RecordMerge.merge(input))
    }

    /// The items that will be on the device once `settling` is written: those it settles to something, and those
    /// outside it that the device holds.
    func presentAfter(_ settling: [SyncKey: Settling]) async throws -> Set<SyncKey> {
        var targets = Set<SyncKey>()
        for decision in settling.values {
            if let target = decision.target { targets.formUnion(Self.references(target)) }
        }
        var present = Set(settling.values.compactMap { $0.target == nil ? nil : $0.key })
        let outside = targets.subtracting(settling.keys)
        if !outside.isEmpty { present.formUnion(try await localRecords(outside).keys) }
        return present
    }

    /// What deleting items here does to the device's other items, decided before the device is written.
    struct Underneath {
        /// Writes that go first in the same apply: a sub-task that goes with its parent (named, so the strict store
        /// takes it), or one written out from under it (the `parent` reference off).
        var writes: [LocalWrite] = []
        /// The ledger's part, written before the device: the deletion time of a sub-task that goes, and the references
        /// a record keeps waiting for when what it points at is deleted here.
        var ledgerWrite = LedgerWrite()
        /// Every item reached (compared again after the settle).
        var keys = Set<SyncKey>()
    }

    /// The supervisor's rule of 2026-11-15 (review finding 1): **a deletion arriving from iCloud never takes with it
    /// an item that was made or changed here after that deletion.** Before a task's deletion is written, every
    /// sub-task the device holds under it (at any depth) is settled as if its own deletion had arrived at the same
    /// moment D (the parent marker's time): unchanged here since its base, or last changed here at or before D, it goes
    /// with the parent, named in the same apply and stamped with D (not "now": it would beat a later change made
    /// elsewhere); made here (no base), changed here after D, or moved under the parent here (its base says another
    /// parent or none), it stays: written out from under the parent, its whole record keeping the parent as a reference
    /// it waits for (section 8), and then sent like any change.
    ///
    /// And section 8 for a Group, label or board deleted here: the records on the device that point at it keep that
    /// reference in their whole record, as one they wait for, whether iCloud has heard of it or not (brief 145, seed
    /// 93: a person's unsent move to a Group whose deletion arrived was dropped).
    func underneath(_ deciding: [Settling], settling: [SyncKey: Settling], now: Date) async throws -> Underneath {
        var cause: [String: Date] = [:]
        var gone = Set<SyncKey>()
        for decision in deciding where decision.local != nil && decision.target == nil {
            gone.insert(decision.key)
            if decision.key.type == "TaskItem" {
                cause[decision.key.name] = decision.outcome.merged?.deletedAt ?? decision.server?.record.deletedAt ?? now
            }
        }
        var out = Underneath()
        guard !gone.isEmpty else { return out }
        // From the device, not the bases: a sub-task made or moved here is not in the ledger.
        let records = try await store.records()
        var children: [String: [SyncRecord]] = [:]
        for record in records where record.key.type == "TaskItem" {
            if case .reference(let parent)? = record.fields["parent"] { children[parent, default: []].append(record) }
        }
        var newWaits: [SyncKey: [String: SyncValue]] = [:]
        func wait(_ key: SyncKey, _ field: String, _ value: SyncValue) {
            var fields = newWaits[key] ?? waitsFor(key)
            if case .referenceList(let names) = value, case .referenceList(let had)? = fields[field] {
                fields[field] = .references(Set(names).union(had))
            } else {
                fields[field] = value
            }
            newWaits[key] = fields
        }
        var queue = cause.keys.sorted()
        while !queue.isEmpty {
            let parent = queue.removeFirst()
            guard let at = cause[parent] else { continue }
            for child in (children[parent] ?? []).sorted(by: { $0.key < $1.key }) where settling[child.key] == nil {
                guard !out.keys.contains(child.key) else { continue }
                out.keys.insert(child.key)
                let entry = entries[child.key]
                let base = entry?.base
                let sameParent = base?.isDeleted == false && base?.fields["parent"] == .reference(parent)
                let unchanged = base.map { RecordMerge.same(Self.whole(child, waiting: waitsFor(child.key)), $0) } ?? false
                let before = (child.updatedAt ?? .distantPast) <= at
                if sameParent, unchanged || before {
                    out.writes.append(LocalWrite(key: child.key, expected: child, record: nil))
                    if var noticed = entry, noticed.deletedHereAt == nil {
                        noticed.deletedHereAt = at
                        out.ledgerWrite.upsert.append(noticed)
                    }
                    cause[child.key.name] = at
                    queue.append(child.key.name)
                    log("\(child.key): goes with the task above it, deleted in iCloud; its marker carries that deletion's time")
                } else {
                    var free = child
                    free.fields["parent"] = nil
                    out.writes.append(LocalWrite(key: child.key, expected: child, record: free))
                    wait(child.key, "parent", .reference(parent))
                    log("\(child.key): made or changed here after the task above it was deleted in iCloud; it stays")
                }
            }
        }
        // Records pointing at a Group, label or board deleted here (a sub-task's parent is handled above).
        let pointed = gone.filter { $0.type != "TaskItem" }
        if !pointed.isEmpty {
            for record in records where settling[record.key] == nil && !gone.contains(record.key) {
                guard let type = SyncSchema.type(record.key.type) else { continue }
                for field in type.fields {
                    switch (field.kind, record.fields[field.key]) {
                    case (.reference(let target), .reference(let name)?):
                        if pointed.contains(SyncKey(type: target, name: name)) {
                            wait(record.key, field.key, .reference(name))
                            out.keys.insert(record.key)
                        }
                    case (.references(let target), .referenceList(let names)?):
                        let hit = names.filter { pointed.contains(SyncKey(type: target, name: $0)) }
                        if !hit.isEmpty {
                            wait(record.key, field.key, .references(hit))
                            out.keys.insert(record.key)
                        }
                    default:
                        break
                    }
                }
            }
        }
        for key in newWaits.keys.sorted() {
            guard let fields = newWaits[key], fields != waitsFor(key) else { continue }
            out.ledgerWrite.deferUpsert.append(Self.waitRecord(key, fields))
        }
        return out
    }

    func localRecords(_ keys: Set<SyncKey>) async throws -> [SyncKey: SyncRecord] {
        let records = try await store.records(keys)
        return Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func storeFailed(_ error: Error) async {
        if case SyncStoreError.duplicates(let keys) = error {
            await enterHold(.duplicates(keys.sorted()))
        } else {
            await fail("The device's items could not be read or written: \(error)")
        }
    }

    private func describe(_ decision: Settling, why: String, written: Bool) -> String {
        let rule = "\(decision.outcome.rule.rawValue) \(decision.outcome.rule)"
        let device: String
        if written {
            device = decision.target == nil ? "deleted here" : "written here"
        } else {
            device = "nothing to change here"
        }
        let goes = waiting.contains(decision.key) ? "; this device's version waits to go" : ""
        return "\(decision.key): \(why), \(rule): \(device)\(goes)"
    }

    // MARK: Sent

    func sent(_ saved: [CloudRecord], removed: [SyncKey], failed: [SyncKey: SendFailure]) async {
        // iCloud holds these now, as `saved` says: they are the new bases.
        var write = LedgerWrite()
        for record in saved {
            write.upsert.append(LedgerEntry(key: record.key, base: Self.base(record.record), system: record.system))
        }
        write.remove = removed.filter { entries[$0] != nil }
        do {
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return
        }
        let accepted = Set(saved.map(\.key)).union(removed)
        for key in accepted { refused[key] = nil }
        if !accepted.isEmpty {
            lastSendEnded = clock()
            log("iCloud accepted \(saved.count) saved, \(removed.count) removed for good")
            host?.didAccept(accepted)
        }

        var conflicts: [CloudRecord] = []
        var gone: [SyncKey] = []
        var full = false
        for (key, failure) in failed.sorted(by: { $0.key < $1.key }) {
            switch failure {
            case .conflict(let server):
                log("\(key): iCloud holds a version this device had not seen (T6); settled again")
                if key == Self.metaKey {
                    if await keepMeta(server) == false { return }
                } else {
                    conflicts.append(server)
                }
            case .unknownItem:
                log("\(key): iCloud no longer holds it (T7)")
                if key == Self.metaKey {
                    var forget = LedgerWrite()
                    forget.remove = [key]
                    do { try await commit(forget) } catch { await fail("The engine's memory could not be written: \(error)"); return }
                } else {
                    gone.append(key)
                }
            case .quotaExceeded:
                full = true
            case .tooLarge:
                await refuse(key, words: "too large for iCloud")
            case .rejected(let code, let message):
                await refuse(key, words: "refused by iCloud (\(code)): \(message)")
            }
        }
        if !conflicts.isEmpty || !gone.isEmpty {
            guard await settle(conflicts, removed: gone, why: "sent back") else { return }
        }
        if full {
            log("iCloud is full: what is waiting stays waiting, and is tried again on return to the app")
            await enterHold(.storageFull)
        }
        // A change made here while its save was on the way: the transport took it off the list with the save. (The
        // zone's meta among them, so the count drops when iCloud accepts it.)
        let looked = accepted.union(failed.keys)
        if !looked.isEmpty { await compare(looked) }
    }

    /// iCloud refused the record for good (T9): logged, kept out of the list until the item changes, shown.
    func refuse(_ key: SyncKey, words: String) async {
        // The version iCloud refused (what `recordToSend` answered), not whatever the device holds by now: a newer
        // change goes.
        let local: SyncRecord?
        if let sent = sentAs[key] {
            local = sent
        } else {
            local = Self.whole((try? await store.records([key]))?.first, waiting: waitsFor(key))
        }
        refused[key] = Refusal(local: local, words: words)
        log("\(key): \(words). Kept out of the list until it changes")
    }
}
