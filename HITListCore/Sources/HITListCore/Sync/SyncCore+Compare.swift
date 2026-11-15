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
    /// nothing is compared (a full iCloud excepted: then the count is kept, and nothing is added).
    func compare(_ keys: Set<SyncKey>?) async {
        guard loaded else { return }
        if let hold, hold != .storageFull { return }
        let here: [SyncKey: SyncRecord]
        do {
            let records: [SyncRecord]
            if let keys { records = try await store.records(keys) } else { records = try await store.records() }
            here = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        } catch let SyncStoreError.duplicates(keys) {
            await enterHold(.duplicates(keys.sorted()))
            return
        } catch {
            await fail("The device's items could not be read: \(error)")
            return
        }

        var universe = keys ?? Set(here.keys).union(entries.keys)
        if keys == nil { universe.insert(Self.metaKey) }
        let now = clock()
        var desired: [SyncKey: PendingChange] = [:]
        var write = LedgerWrite()
        for key in universe {
            let finding = key == Self.metaKey ? metaFinding() : self.finding(key, local: here[key], now: now)
            if let change = finding.change { desired[key] = change }
            if let entry = finding.entry { write.upsert.append(entry) }
            if finding.drop { write.remove.append(key) }
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
        await matchPending(desired, within: keys == nil ? nil : universe)
    }

    /// Makes the transport's list hold exactly `desired` for the keys in `within` (nil: for every key). Nothing is
    /// added before the first whole fetch has finished (section 7) or while iCloud is full.
    func matchPending(_ desired: [SyncKey: PendingChange], within: Set<SyncKey>?) async {
        let pending = await transport.pending()
        let listed = Set(pending)
        var remove: [PendingChange] = []
        for change in pending where within?.contains(change.key) ?? true {
            if desired[change.key] != change { remove.append(change) }
        }
        var add: [PendingChange] = []
        if firstFetchDone, hold == nil {
            for key in desired.keys.sorted(by: Self.sendOrder) {
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
            } else if firstFetchDone {
                // New here. Before the first whole fetch it may well be in iCloud already: not counted, not sent.
                finding.change = .save(key)
            }
        } else if let entry {
            guard let base = entry.base else {
                finding.drop = true
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
                    noticed.deletedHereAt = now
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
            local = try await store.records([key]).first
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
            if entry?.base == nil, SyncSchema.type(key.type) == nil { return nil }
            return OutgoingRecord(record: local, system: entry?.system)
        }
        guard var entry, let base = entry.base else { return nil }
        if base.isDeleted {
            // A marker later than iCloud's (M10), or nothing: iCloud already holds the marker.
            guard let at = entry.deletedHereAt, !RecordMerge.same(.marker(key, deletedAt: at), base) else { return nil }
            return OutgoingRecord(record: .marker(key, deletedAt: at), system: entry.system)
        }
        if entry.deletedHereAt == nil {
            // Not noticed yet: noticed now, and kept, so the marker carries the same time if it is asked for again.
            entry.deletedHereAt = clock()
            var write = LedgerWrite()
            write.upsert = [entry]
            do {
                try await commit(write)
            } catch {
                await fail("The engine's memory could not be written: \(error)")
                return nil
            }
        }
        return OutgoingRecord(record: .marker(key, deletedAt: entry.deletedHereAt ?? clock()), system: entry.system)
    }
}
