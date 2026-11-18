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
            // A failure over a hold the person or the world must lift (its fact stays in the ledger): when the
            // failure lifts, that hold comes back, not nothing.
            if !next.persists, let current = hold, current.persists { heldUnder = current }
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
    /// `resume()`; fetched records are let go meanwhile and fetched again then. `words` are a person's
    /// (`SyncFailureWords`); the error goes to the log only (brief 160, review 147 F10).
    func fail(_ words: String, _ error: Error) async {
        log("\(words) The error: \(error)")
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
        if let under = heldUnder, hold?.persists == false {
            // The failure goes; the hold it fell on stays (its fact was never cleared).
            log("\(hold?.words ?? ""): tried again; still held: \(under.words)")
            heldUnder = nil
            hold = under
            holdNote = nil
            return
        }
        heldUnder = nil
        if refetch, resetTransport {
            // The transport first, then the fact: a crash in between resets it once more, which costs a fetch.
            await transport.reset()
            unsettled = [:]
            log("Everything will be fetched again: records were let go while held")
        }
        var write = LedgerWrite()
        if hold?.persists == true { write.facts.updateValue(nil, forKey: LedgerFact.hold) }
        if hold == .noAccount { write.facts.updateValue(nil, forKey: Self.switchFact) }
        if refetch, resetTransport || hold == .noAccount {
            write.facts.updateValue(nil, forKey: Self.refetchFact)
            write.facts.updateValue(nil, forKey: Self.unsettledFact)
        }
        do {
            try await commit(write)
        } catch {
            await fail(SyncFailureWords.recordsNotSaved, error)
            return
        }
        if let hold { log("Hold lifted: \(hold.words)") }
        hold = nil
        holdNote = nil
    }

    /// What a new start lifts: a failure and duplicates are tried again, a full iCloud is tried again (a launch is
    /// a return to the app), and a format this build now reads lets it read.
    func liftForStart() async {
        // iCloud's format newer than this build's, whether or not the hold's fact reached the ledger.
        if Self.formatVersion(of: entries[Self.metaKey]?.base) > SyncSchema.formatVersion, hold != .needsUpdate {
            await enterHold(.needsUpdate)
            await markRefetch()
            return
        }
        if hold == .noAccount, let next = switchTo {
            await retrySwitch(to: next)
            return
        }
        switch hold {
        case .failed?, .duplicates?, .storageFull?, .iCloudNotReady?:
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
                write.facts.updateValue(nil, forKey: Self.unsettledFact)
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
            await signOut()
        case .switched(let previous, let current):
            log("iCloud account switched (\(previous) to \(current))")
            await switchAccount(to: current)
        case .signedIn(let current):
            log("Signed in to iCloud (\(current))")
            if let account, account != current {
                // Another account came while the app was not running, or after a sign-out: as a switch.
                await switchAccount(to: current)
            } else if account == current, hold == .noAccount || heldUnder == .noAccount, switchTo == nil, hasMemory {
                // Back to the account it was signed out of (brief 165): the memory carries on. The transport has
                // forgotten its bookmark (T12), so a whole fetch comes first; what changed here and in iCloud meanwhile
                // then settles three ways, as after any time offline.
                log("Signed in again to the account it was signed out of: the memory is kept; a whole fetch first")
                await rejoin(current)
            } else if hasMemory, account == nil || account == current {
                // A sign-in to the ledger's own account means the transport's state was lost (T12): a fresh bookmark
                // never tells of a zone lost meanwhile, so the bases cannot be trusted. (A memory nobody's account
                // owns, likewise.) Nothing of the person's leaves the device; the memory is forgotten but for the
                // deletions not sent yet, the transport reset, and everything merged afresh (section 7). Only when
                // there is a memory: a transport whose `reset()` announces the account again then finds none, and
                // simply joins.
                log("The transport's own memory was lost: the engine's is forgotten too and everything is merged afresh")
                guard await forgetMemory(keepFirstFetch: false) else { return }
                await transport.reset()
                await joinAccount(current)
            } else {
                await joinAccount(current)
            }
        }
    }

    /// A sign-out (brief 165; George, 2026-11-18: "definitely keep tasks on the device after sign-out if possible").
    /// Nothing leaves the device and nothing is forgotten: the ledger keeps its bases, the account it was signed out of
    /// and the deletions not sent yet. Held, so nothing is sent or fetched; the device is still compared, so what
    /// changes waits and is counted. A switch that was waiting on a failed backup is dropped: the next sign-in says
    /// which account comes, and a different one is a switch again.
    func signOut() async {
        joinTo = nil
        if switchTo != nil {
            var write = LedgerWrite()
            write.facts.updateValue(nil, forKey: Self.switchFact)
            do {
                try await commit(write)
            } catch {
                await fail(SyncFailureWords.recordsNotSaved, error)
                return
            }
        }
        await enterHold(.noAccount)
        log("Nothing leaves this device while signed out; changes wait for the sign-in")
        await compare(nil)
    }

    /// The sign-in to the account the device was signed out of: the hold lifted, the memory kept, but nothing sent
    /// before a whole fetch has finished (`firstFetchDone` cleared, `rejoinFact` kept), because iCloud may have lost
    /// the zone meanwhile and a bookmark that starts afresh never says so. At the end of that fetch a base whose record
    /// it did not bring is forgotten (`checkRejoin`): the item goes again as new, never deleted here.
    func rejoin(_ current: String) async {
        var write = LedgerWrite()
        write.facts.updateValue(nil, forKey: LedgerFact.firstFetchDone)
        write.facts[Self.rejoinFact] = Data([1])
        do {
            try await commit(write)
        } catch {
            joinTo = current
            await fail(SyncFailureWords.recordsNotSaved, error)
            return
        }
        rejoinSeen = []
        await joinAccount(current)
    }

    /// The end of the whole fetch after a sign-in to the same account (`rejoin`), added to the write that marks the
    /// first fetch done: every entry with a base whose record that fetch did not bring, and that the transport does not
    /// owe, is forgotten. iCloud does not hold it: an item here goes again as new (M2), one not here is nothing (M11).
    /// Absence never deletes anything. The keys forgotten.
    func checkRejoin(into write: inout LedgerWrite) -> [SyncKey] {
        guard rejoining else { return [] }
        let stale = entries.values.filter { $0.base != nil && !rejoinSeen.contains($0.key) && !owedKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
        // A deletion made here (signed out, or before) stays a deletion: kept with no base, so that when another
        // device sends the item to iCloud again it settles against it (M3 with a deletion of its own) and its marker
        // goes, instead of the item coming back (the `all` set, seeds 13 and 26).
        write.upsert += stale.filter { $0.deletedHereAt != nil }
            .map { LedgerEntry(key: $0.key, base: nil, system: nil, deletedHereAt: $0.deletedHereAt) }
        write.remove += stale.filter { $0.deletedHereAt == nil }.map(\.key)
        write.facts.updateValue(nil, forKey: Self.rejoinFact)
        return stale.map(\.key)
    }

    /// At a switch to another account every item leaves the device, those iCloud never held too, after a backup
    /// that names both accounts (so the host sets the previous account's backups aside itself, 147 F6): they are the
    /// previous account's, what was changed while signed out among them, and would otherwise go to the next account's
    /// iCloud (brief 160, review 147 F11). In this order: held (nothing is sent from now on, a missing item is not
    /// read as a deletion), the backup, the memory forgotten, and only then the items removed. A crash before the
    /// removal leaves items with no memory of them; the other order would leave a memory of items that are gone. False
    /// when the backup failed: nothing was removed.
    func leaveAccount(joining current: String) async -> Bool {
        await enterHold(.noAccount)
        let leaving: Set<SyncKey>
        do {
            leaving = Set(entries.values.filter { $0.base?.isDeleted == false }.map(\.key))
                .union(try await store.records().map(\.key))
        } catch {
            await storeFailed(error)
            return false
        }
        guard await backup(.accountSwitched, from: account, to: current) else { return false }
        do {
            try await ledger.reset()
            forgetCache(keepAccount: false)
        } catch {
            await fail(SyncFailureWords.recordsNotSaved, error)
            return false
        }
        await enterHold(.noAccount)
        await removeHere(leaving, why: SyncRemovalReason.accountSwitched.rawValue)
        return true
    }

    /// Another account: the previous one's items leave (after a backup), then this one is joined. If the backup
    /// fails, the brain stays held with the account it is to join remembered (`switchFact`), and `resume()` or the
    /// next start tries again: the transport has moved on and will not say it twice.
    func switchAccount(to current: String) async {
        if await leaveAccount(joining: current) {
            await joinAccount(current)
        } else {
            var write = LedgerWrite()
            write.facts[Self.switchFact] = Data(current.utf8)
            try? await commit(write)
            switchTo = current
        }
    }

    func retrySwitch(to current: String) async {
        log("Trying the switch to \(current) again")
        await switchAccount(to: current)
    }

    /// The account the memory now belongs to, and the sign-in's lift of `noAccount`, in one write: a crash or a
    /// failure leaves both or neither.
    func joinAccount(_ current: String) async {
        let lifting = hold == .noAccount || heldUnder == .noAccount
        var write = LedgerWrite()
        write.facts[LedgerFact.account] = Data(current.utf8)
        write.facts.updateValue(nil, forKey: Self.switchFact)
        if lifting {
            write.facts.updateValue(nil, forKey: LedgerFact.hold)
            // The transport has forgotten its bookmark and its list by now (T12): the next fetch brings everything.
            write.facts.updateValue(nil, forKey: Self.refetchFact)
        }
        do {
            try await commit(write)
        } catch {
            joinTo = current
            await fail(SyncFailureWords.recordsNotSaved, error)
            return
        }
        switchTo = nil
        joinTo = nil
        if lifting {
            log("Hold lifted: signed in")
            if hold == .noAccount { hold = nil; holdNote = nil }
            if heldUnder == .noAccount { heldUnder = nil }
        }
        // The compare puts back what is waiting.
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
            guard await forgetMemory(keepFirstFetch: true) else { return }
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
                holdNote = "Nothing was removed from this device: no backup could be written."
                publish()
                throw SyncCoreError.noBackup
            }
            do {
                try await host.willRemoveLocalData(reason: .zonePurged)
            } catch {
                holdNote = "Nothing was removed from this device: the backup failed."
                log("\(holdNote ?? "") The error: \(error)")
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
            await fail(SyncFailureWords.recordsNotSaved, error)
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

    /// Whether the brain remembers anything of iCloud's.
    var hasMemory: Bool {
        // Not what records wait for: that is the device's own, kept across a forgetting (`forgetMemory`).
        firstFetchDone || entries.values.contains { $0.base != nil }
    }

    /// Forgets what the brain knows of iCloud's records (every base and token, and unless `keepFirstFetch` the first
    /// fetch) in one write, keeping what records wait for and the deletions made here and not sent yet: each stays
    /// as an entry with no base and its `deletedHereAt`, settled against iCloud's record when the next whole fetch
    /// brings it (M3/M4 with an explicit deletion), and dropped if that fetch does not.
    func forgetMemory(keepFirstFetch: Bool) async -> Bool {
        var write = LedgerWrite()
        for key in entries.keys.sorted() {
            guard let entry = entries[key] else { continue }
            if let at = entry.deletedHereAt {
                write.upsert.append(LedgerEntry(key: key, base: nil, system: nil, deletedHereAt: at))
            } else {
                write.remove.append(key)
            }
        }
        // What records wait for is kept too (round 32, zone seed 724): it is the device's own (the references it
        // cannot show), not a memory of iCloud's, and only it can say that a record points at an item that is not
        // here. The next compare reads it against no base: what no longer applies goes there.
        if !keepFirstFetch { write.facts.updateValue(nil, forKey: LedgerFact.firstFetchDone) }
        // What was remembered of sends with no answer belongs to the memory forgotten: a new epoch makes it worth
        // nothing without naming every fact (M5's amendment, `SyncCore+Sent`).
        write.facts[Self.epochFact] = Data(String(sentEpoch + 1).utf8)
        do {
            try await commit(write)
        } catch {
            await fail(SyncFailureWords.recordsNotSaved, error)
            return false
        }
        remembered = [:]
        refused = [:]
        sentAs = [:]
        unanswered = [:]
        unsettled = [:]
        if !keepFirstFetch { waiting = [] }
        return true
    }

    // MARK: Removing the person's items

    /// The host's backup. False (and the reason kept for the status) when there is no host or it throws.
    func backup(_ reason: SyncRemovalReason, from previous: String? = nil, to current: String? = nil) async -> Bool {
        guard let host else {
            holdNote = "Nothing was removed from this device: no backup could be written."
            log(holdNote ?? "")
            return false
        }
        do {
            try await host.willRemoveLocalData(reason: reason, switchingFrom: previous, to: current)
            return true
        } catch {
            // Plain words for the person; the error in the log only (brief 160).
            holdNote = "Nothing was removed from this device: the backup failed."
            log("\(holdNote ?? "") The error: \(error)")
            publish()
            return false
        }
    }

    /// Removes `keys` from the device, each only if it is still as it was read (a newer edit is kept).
    func removeHere(_ keys: Set<SyncKey>, why: String) async {
        guard !keys.isEmpty else { return }
        do {
            let here = try await localRecords(keys)
            // A sub-task iCloud never held stays, as every such item does: written out from under a parent that goes
            // (the store deletes no row a write does not name).
            var free: [LocalWrite] = []
            for record in try await store.records() where record.key.type == "TaskItem" && here[record.key] == nil {
                guard case .reference(let parent)? = record.fields["parent"],
                      here[SyncKey(type: "TaskItem", name: parent)] != nil else { continue }
                var out = record
                out.fields["parent"] = nil
                free.append(LocalWrite(key: record.key, expected: record, record: out))
            }
            let writes = free + here.values.sorted { $0.key < $1.key }.map { LocalWrite(key: $0.key, expected: $0, record: nil) }
            let kept = try await store.apply(writes).intersection(here.keys)
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
        waits = [:]
        firstFetchDone = false
        if !keepAccount { account = nil }
        refetch = false
        waiting = []
        refused = [:]
        sentAs = [:]
        unanswered = [:]
        unsettled = [:]
        switchTo = nil
        rejoining = false
        rejoinSeen = []
        // A ledger reset takes every fact with it, the remembered sends and their epoch among them.
        remembered = [:]
        sentEpoch = 0
    }
}
