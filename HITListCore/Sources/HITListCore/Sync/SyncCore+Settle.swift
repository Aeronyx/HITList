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
        // Sub-tasks the store will take with a task this settle deletes: the deletion that caused it is theirs.
        let cascade: [SyncKey: Date]
        do {
            cascade = try await cascadeOf(settling, now: now)
        } catch {
            await storeFailed(error)
            return false
        }

        // 1. The device. A write the person overtook (its `expected` no longer holds) is decided again on what the
        //    device holds now, a few times; then it is left for the next fetch (`refetch`), the base not moved.
        var unsettled = Set<SyncKey>()
        var written = Set<SyncKey>()
        var round = 0
        var toWrite = settling.values.filter { !RecordMerge.same($0.local, shown($0)) }
        while !toWrite.isEmpty {
            let writes = toWrite.sorted { $0.key < $1.key }.map {
                LocalWrite(key: $0.key, expected: $0.local, record: shown($0))
            }
            let stale: Set<SyncKey>
            do {
                stale = try await store.apply(writes)
            } catch {
                await storeFailed(error)
                return false
            }
            written.formUnion(Set(toWrite.map(\.key)).subtracting(stale))
            guard !stale.isEmpty else { break }
            round += 1
            let fresh: [SyncKey: SyncRecord]
            do {
                fresh = try await localRecords(stale)
            } catch {
                await storeFailed(error)
                return false
            }
            var again: [Settling] = []
            for key in stale.sorted() {
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
        }
        if !cascade.isEmpty {
            let after = (try? await localRecords(Set(cascade.keys))) ?? [:]
            for key in cascade.keys.sorted() where after[key] == nil {
                if var entry = entries[key], entry.deletedHereAt == nil {
                    entry.deletedHereAt = cascade[key]
                    write.upsert.append(entry)
                    log("\(key): went with the task above it, deleted in iCloud; its marker carries that deletion's time")
                }
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
        await compare(keys.union(cascade.keys))
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

    /// The tasks under a task this settle deletes from the device (the store deletes a task's sub-tasks with it), as
    /// far as the bases tell, with the time of the deletion that takes them: theirs is not a deletion by the person
    /// here, and must not be stamped with "now" (it would beat a later change made elsewhere).
    func cascadeOf(_ settling: [SyncKey: Settling], now: Date) async throws -> [SyncKey: Date] {
        var cause: [String: Date] = [:]
        for decision in settling.values where decision.key.type == "TaskItem" && decision.local != nil && decision.target == nil {
            cause[decision.key.name] = decision.outcome.merged?.deletedAt ?? decision.server?.record.deletedAt ?? now
        }
        guard !cause.isEmpty else { return [:] }
        var out: [SyncKey: Date] = [:]
        var grew = true
        while grew {
            grew = false
            for (key, entry) in entries where key.type == "TaskItem" && out[key] == nil && settling[key] == nil {
                guard let base = entry.base, !base.isDeleted, entry.deletedHereAt == nil,
                      case .reference(let parent)? = base.fields["parent"], let at = cause[parent] else { continue }
                out[key] = at
                cause[key.name] = at
                grew = true
            }
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
