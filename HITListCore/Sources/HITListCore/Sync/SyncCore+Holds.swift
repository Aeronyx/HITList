import Foundation

// Holds and their ways out (`dev/SYNC-ENGINE.md` section 10), the account (T12) and a lost zone (T11).
//
// While held (a full iCloud excepted) the brain compares nothing, sends nothing (`recordToSend` answers nil, so the
// transport drops what it had) and lets fetched records go unread. Because the transport moves its bookmark past what
// it delivered, letting a record go is only safe if everything is fetched again later: the brain marks that
// (`refetch`, kept in the ledger) and resets the transport when the hold lifts. The pending list needs no keeping:
// nothing is journalled, so the compare after the hold rebuilds it.

extension SyncCore {
    // MARK: Entering and lifting

    func enterHold(_ next: SyncHold) async {
        if hold != next {
            hold = next
            holdNote = nil
            log("Held: \(next.words)")
        }
        if next.persists {
            // Kept so a relaunch is held too. If the ledger cannot take it, the hold is kept in memory only: a
            // relaunch finds the cause again (no account, the format, a full iCloud) or asks again.
            var write = LedgerWrite()
            write.facts[LedgerFact.hold] = try? JSONEncoder().encode(next)
            try? await commit(write)
        }
        publish()
    }

    /// The device's items or the ledger could not be read or written. Tried again by the next `start()` or
    /// `resume()`; fetched records are let go meanwhile and fetched again then.
    func fail(_ words: String) async {
        await enterHold(.failed(words))
    }

    /// Fetched records were let go unread: everything must be fetched again before the brain trusts its memory.
    func markRefetch() async {
        refetch = true
        var write = LedgerWrite()
        write.facts[Self.refetchFact] = Data([1])
        // Best effort: when the ledger cannot take even this, neither could it take the transport's bookmark.
        try? await commit(write)
    }

    /// Lifts the hold. `resetTransport`: if records were let go while held, the transport forgets its bookmark
    /// first (then its list, which the next compare rebuilds), so everything comes again. Not from inside `handle`
    /// (an account's change has already reset the transport by itself, T12).
    func lift(resetTransport: Bool) async {
        if refetch, resetTransport {
            // The transport first, then the fact: a crash in between resets it once more, which costs a fetch.
            await transport.reset()
            log("Everything will be fetched again: records were let go while held")
        }
        var write = LedgerWrite()
        if hold?.persists == true { write.facts.updateValue(nil, forKey: LedgerFact.hold) }
        if refetch, resetTransport || hold == .noAccount { write.facts.updateValue(nil, forKey: Self.refetchFact) }
        do {
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return
        }
        if let hold { log("Hold lifted: \(hold.words)") }
        hold = nil
        holdNote = nil
    }

    /// What a new start lifts: a failure and duplicates are tried again, a full iCloud is tried again (a launch is
    /// a return to the app), and a format this build now reads lets it read.
    func liftForStart() async {
        switch hold {
        case .failed?, .duplicates?, .storageFull?:
            await lift(resetTransport: true)
        case .needsUpdate?:
            if Self.formatVersion(of: entries[Self.metaKey]?.base) <= SyncSchema.formatVersion {
                await lift(resetTransport: true)
            }
        case nil:
            if refetch {
                // A failure that never became a hold kept in the ledger (a crash during it): fetched again.
                await transport.reset()
                var write = LedgerWrite()
                write.facts.updateValue(nil, forKey: Self.refetchFact)
                try? await commit(write)
            }
        default:
            break
        }
    }

    // MARK: The account (T12)

    func accountChanged(_ change: AccountChange) async {
        switch change {
        case .signedOut(let previous):
            log("Signed out of iCloud (\(previous))")
            _ = await leaveAccount(reason: .signedOut)
        case .switched(let previous, let current):
            log("iCloud account switched (\(previous) to \(current))")
            if await leaveAccount(reason: .accountSwitched) { await joinAccount(current) }
        case .signedIn(let current):
            log("Signed in to iCloud (\(current))")
            if let account, account != current {
                // Another account came while the app was not running: as a switch.
                if await leaveAccount(reason: .accountSwitched) { await joinAccount(current) }
            } else if account == nil, !entries.isEmpty {
                // A memory nobody's account owns: not trusted. Forgotten, every item kept, merged afresh (section 7).
                do {
                    try await ledger.reset()
                    forgetCache(keepAccount: false)
                } catch {
                    await fail("The engine's memory could not be written: \(error)")
                    return
                }
                await joinAccount(current)
            } else {
                await joinAccount(current)
            }
        }
    }

    /// The account's items leave the device, as they did under the mirror: held first (nothing is sent from now
    /// on, and a missing item is not read as a deletion), then the backup, then the memory forgotten, and only then
    /// the items that iCloud held removed. A crash before the removal leaves items with no memory of them, which
    /// merge afresh at the next sign-in; the other order would leave a memory of items that are gone, which the next
    /// compare would read as deletions to send. False when the backup failed: nothing was removed.
    func leaveAccount(reason: SyncRemovalReason) async -> Bool {
        await enterHold(.noAccount)
        let synced = Set(entries.values.filter { $0.base?.isDeleted == false }.map(\.key))
        if !synced.isEmpty {
            guard await backup(reason) else { return false }
        }
        do {
            try await ledger.reset()
            forgetCache(keepAccount: false)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return false
        }
        await enterHold(.noAccount)
        await removeHere(synced, why: reason.rawValue)
        return true
    }

    func joinAccount(_ current: String) async {
        var write = LedgerWrite()
        write.facts[LedgerFact.account] = Data(current.utf8)
        do {
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return
        }
        if hold == .noAccount {
            // The transport has forgotten its bookmark and its list by now (T12): the next fetch brings everything,
            // and the compare puts back what is waiting.
            await lift(resetTransport: false)
        }
        await compare(nil)
    }

    // MARK: The zone (T11)

    func zoneLost(_ reason: ZoneLoss) async {
        switch reason {
        case .purged:
            // The person removed HITList's data in iCloud's settings. Nothing is deleted here by itself: asked.
            log("HITList's zone was removed from iCloud by the person: nothing is deleted here until they answer")
            await enterHold(.zonePurged)
        case .deleted, .encryptedDataReset:
            // The data here is still wanted: the memory of iCloud's records is worth nothing now. Every entry and
            // every set-aside record is forgotten (the account and the transport's state stay), and since the zone is
            // known empty, everything here is new and goes again (M2). A record another device sends meanwhile meets
            // this one as a conflict and merges (M5).
            log("HITList's zone is gone from iCloud (\(reason.rawValue)): everything here goes again")
            var write = LedgerWrite()
            write.remove = Array(entries.keys)
            write.deferRemove = Array(deferred.keys)
            write.facts[LedgerFact.firstFetchDone] = Data([1])
            do {
                try await commit(write)
            } catch {
                await fail("The engine's memory could not be written: \(error)")
                return
            }
            refused = [:]
            await compare(nil)
        }
    }

    /// The person's answer to a purge. Both forget the memory and reset the transport (the zone it knew is gone),
    /// and from then on everything here is new to iCloud. "Remove here" first writes a backup and then removes what
    /// iCloud had held; nothing is removed if the backup throws.
    func answerPurge(_ choice: PurgeAnswer) async throws {
        let synced = Set(entries.values.filter { $0.base?.isDeleted == false }.map(\.key))
        if choice == .removeHere, !synced.isEmpty {
            guard let host else {
                holdNote = "Nothing was removed from this device: no backup could be written"
                publish()
                throw SyncCoreError.noBackup
            }
            do {
                try await host.willRemoveLocalData(reason: .zonePurged)
            } catch {
                holdNote = "The backup before removing HITList's items failed: \(error)"
                log(holdNote ?? "")
                publish()
                throw error
            }
        }
        // The memory first, then the items: a crash in between keeps the items, which then go to iCloud again.
        let owner = account
        do {
            try await ledger.reset()
            forgetCache(keepAccount: false)
            var write = LedgerWrite()
            if let owner { write.facts[LedgerFact.account] = Data(owner.utf8) }
            write.facts[LedgerFact.firstFetchDone] = Data([1])
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return
        }
        await transport.reset()
        hold = nil
        holdNote = nil
        refetch = false
        log("Answered the purge: \(choice.rawValue)")
        if choice == .removeHere { await removeHere(synced, why: "zone purged") }
        await compare(nil)
    }

    // MARK: Removing the person's items

    /// The host's backup. False (and the reason kept for the status) when there is no host or it throws.
    func backup(_ reason: SyncRemovalReason) async -> Bool {
        guard let host else {
            holdNote = "Nothing was removed from this device: no backup could be written"
            log(holdNote ?? "")
            return false
        }
        do {
            try await host.willRemoveLocalData(reason: reason)
            return true
        } catch {
            holdNote = "Nothing was removed from this device: the backup failed (\(error))"
            log(holdNote ?? "")
            publish()
            return false
        }
    }

    /// Removes `keys` from the device, each only if it is still as it was read (a newer edit is kept).
    func removeHere(_ keys: Set<SyncKey>, why: String) async {
        guard !keys.isEmpty else { return }
        do {
            let here = try await localRecords(keys)
            let writes = here.values.sorted { $0.key < $1.key }.map { LocalWrite(key: $0.key, expected: $0, record: nil) }
            let kept = try await store.apply(writes)
            let removed = Set(here.keys).subtracting(kept)
            log("\(removed.count) items iCloud held removed from this device (\(why)); \(kept.count) changed meanwhile and kept")
            if !removed.isEmpty { host?.didWrite(removed) }
        } catch {
            await storeFailed(error)
        }
    }

    /// The brain's copy of a ledger that was just reset.
    func forgetCache(keepAccount: Bool) {
        entries = [:]
        deferred = [:]
        firstFetchDone = false
        if !keepAccount { account = nil }
        refetch = false
        waiting = []
        refused = [:]
    }
}
