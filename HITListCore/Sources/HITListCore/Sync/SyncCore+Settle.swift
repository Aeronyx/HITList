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
        /// The device's item when the decision was made.
        var local: SyncRecord?
        var outcome: MergeOutcome

        /// What the device should hold.
        var target: SyncRecord? { outcome.device }
        var writesDevice: Bool { !RecordMerge.same(local, target) }
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
        // What an earlier batch set aside is looked at again with this one: what it pointed at may have come.
        var incoming = deferred
        for record in records { incoming[record.key] = record }
        guard await settle(Array(incoming.values), removed: removed, final: false, why: "fetched") else {
            await markRefetch()
            return
        }
    }

    func didFetch(error: String?) async {
        if let error {
            fetchError = error
            log("A fetch stopped early: \(error). It will be tried again; what was set aside stays aside")
            return
        }
        fetchError = nil
        if let hold, hold.stopsFetching { return }
        // The fetch is whole: what is still set aside waits no longer. A reference to what never came is written as
        // none, and because that differs from iCloud's record, the reference is cleared there by the next send.
        if !deferred.isEmpty {
            log("\(deferred.count) set-aside records written; what they point at never came")
            guard await settle(Array(deferred.values), removed: [], final: true, why: "set aside") else {
                await markRefetch()
                return
            }
        }
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
    /// and the ledger: the device first, then the ledger, then the transport's list. `final`: nothing is set aside
    /// (the end of a fetch, a conflict after a send). False when a write failed: the brain is then held (`failed`)
    /// and nothing after the failed write was done.
    func settle(_ incoming: [CloudRecord], removed: [SyncKey], final: Bool, why: String) async -> Bool {
        var byKey: [SyncKey: CloudRecord] = [:]
        for record in incoming where SyncSchema.type(record.key.type) != nil { byKey[record.key] = record }
        // A record removed for good after it changed, in one event: removed.
        let gone = Set(removed.filter { $0 != Self.metaKey })
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
        var settling: [SyncKey: Settling] = [:]
        for key in keys { settling[key] = decide(key, server: byKey[key], local: local[key], now: now) }

        var setAside = Set<SyncKey>()
        if !final {
            do {
                setAside = try await unresolved(settling)
            } catch {
                await storeFailed(error)
                return false
            }
        }

        // 1. The device. A write the person overtook (its `expected` no longer holds) is decided again on what the
        //    device holds now, a few times; then it is set aside for the next event.
        var unsettled = Set<SyncKey>()
        var written = Set<SyncKey>()
        var round = 0
        var toWrite = settling.values.filter { !setAside.contains($0.key) && $0.writesDevice }
        while !toWrite.isEmpty {
            let writes = toWrite.sorted { $0.key < $1.key }.map {
                LocalWrite(key: $0.key, expected: $0.local, record: $0.target)
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
                if decision.writesDevice { again.append(decision) }
            }
            if round >= Self.staleRounds, !again.isEmpty {
                for decision in again {
                    if decision.server != nil { setAside.insert(decision.key) } else { unsettled.insert(decision.key) }
                    log("\(decision.key): changed here \(round) times while it was being written; settled again later")
                }
                break
            }
            if !again.isEmpty { log("\(again.count) records changed here between the read and the write; decided again") }
            toWrite = again
        }

        // 2. The ledger: iCloud's version becomes the base (`deletedHereAt` kept while a marker still has to go).
        var write = LedgerWrite()
        for key in keys.sorted() {
            guard let decision = settling[key] else { continue }
            if setAside.contains(key) {
                if let server = byKey[key], deferred[key] != server { write.deferUpsert.append(server) }
                continue
            }
            if deferred[key] != nil { write.deferRemove.append(key) }
            if unsettled.contains(key) { continue }
            guard let server = decision.server else {
                // Gone from iCloud for good: nothing to remember. An item still here is new again (M11).
                if entries[key] != nil { write.remove.append(key) }
                continue
            }
            let markerToGo = decision.outcome.merged?.isDeleted == true && !server.record.isDeleted
            let deletedHereAt = markerToGo ? (entries[key]?.deletedHereAt ?? now) : nil
            let entry = LedgerEntry(key: key, base: Self.base(server.record), system: server.system,
                                    deletedHereAt: deletedHereAt)
            if entries[key] != entry { write.upsert.append(entry) }
        }
        do {
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return false
        }

        // 3. The transport's list, from what each key now is.
        await compare(keys)
        for key in keys.sorted() {
            guard let decision = settling[key] else { continue }
            log(describe(decision, why: why, written: written.contains(key), setAside: setAside.contains(key)))
        }
        if !written.isEmpty { host?.didWrite(written) }
        return true
    }

    /// The rule for one record, on what the device and the ledger hold now.
    func decide(_ key: SyncKey, server: CloudRecord?, local: SyncRecord?, now: Date) -> Settling {
        let entry = entries[key]
        let input = MergeInput(base: entry?.base, local: local, deletedHereAt: entry?.deletedHereAt,
                               server: server?.record, now: now)
        return Settling(key: key, server: server, local: local, outcome: RecordMerge.merge(input))
    }

    /// The records to be written that point at an item that will be neither on the device nor written with them:
    /// set aside until the fetch ends (section 8). Setting one aside can leave another pointing at nothing, so this
    /// runs until nothing more is set aside.
    func unresolved(_ settling: [SyncKey: Settling]) async throws -> Set<SyncKey> {
        var pointers: [SyncKey: [SyncKey]] = [:]
        for (key, decision) in settling where decision.server != nil && decision.writesDevice {
            if let target = decision.target {
                let refs = Self.references(target)
                if !refs.isEmpty { pointers[key] = refs }
            }
        }
        guard !pointers.isEmpty else { return [] }
        let outside = Set(pointers.values.joined()).subtracting(settling.keys)
        let here = outside.isEmpty ? Set<SyncKey>() : Set(try await localRecords(outside).keys)
        var setAside = Set<SyncKey>()
        func present(_ key: SyncKey) -> Bool {
            guard let decision = settling[key] else { return here.contains(key) }
            // One set aside stays as the device holds it; the others become what they were settled to.
            return setAside.contains(key) ? decision.local != nil : decision.target != nil
        }
        var changed = true
        while changed {
            changed = false
            for (key, refs) in pointers where !setAside.contains(key) && refs.contains(where: { !present($0) }) {
                setAside.insert(key)
                changed = true
            }
        }
        return setAside
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

    private func describe(_ decision: Settling, why: String, written: Bool, setAside: Bool) -> String {
        let rule = "\(decision.outcome.rule.rawValue) \(decision.outcome.rule)"
        let device: String
        if setAside {
            device = "set aside: it points at something not here yet"
        } else if written {
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
            // A version fetched and set aside earlier is older than the one iCloud just accepted.
            if deferred[record.key] != nil { write.deferRemove.append(record.key) }
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
            // No fetch is waiting to bring what a conflict points at: settled whole now.
            guard await settle(conflicts, removed: gone, final: true, why: "sent back") else { return }
        }
        if full {
            log("iCloud is full: what is waiting stays waiting, and is tried again on return to the app")
            await enterHold(.storageFull)
        }
        // A change made here while its save was on the way: the transport took it off the list with the save.
        let looked = accepted.union(failed.keys).subtracting([Self.metaKey])
        if !looked.isEmpty { await compare(looked) }
    }

    /// iCloud refused the record for good (T9): logged, kept out of the list until the item changes, shown.
    func refuse(_ key: SyncKey, words: String) async {
        let local = try? await store.records([key]).first
        refused[key] = Refusal(local: local, words: words)
        log("\(key): \(words). Kept out of the list until it changes")
    }
}
