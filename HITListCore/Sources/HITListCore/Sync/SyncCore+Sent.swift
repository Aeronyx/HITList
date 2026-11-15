import Foundation

// What this device last sent for a record it holds no base for (`dev/SYNC-ENGINE.md` M5, amended 2026-11-15 on brief
// 145's finding: zone seed 270, memory seed 259). A save iCloud accepted whose answer was lost (the network dropped on
// the way back, the app died before `sent`) leaves no base when the record was new here, or when everything was new
// after a lost zone; the next meeting was then M5, the record changed last kept whole, so an edit made here after the
// send and one made elsewhere could not both survive. Now: "unless this device remembers what it last sent for the
// record and has had no answer for it: then that sent record is the base and the two are settled as M7".
//
// The limits, on purpose: used only when the item is here, iCloud's record is alive and there is still no base; never
// for a deletion, never for M11, never by the compare (a remembered send is not an agreement: iCloud may never have
// taken it, so nothing is "the same as the base" because of it). Written to the ledger before `recordToSend` answers
// (a crash after the save and before its answer finds it on disk), one fact per key; forgotten when a base lands for
// the key, and worth nothing once the memory is forgotten (`sentEpoch` moves on: a lost zone, a lost transport state).
// Bounded: only records with no base are remembered.

extension SyncCore {
    /// What is kept per key: the memory it belongs to, and the record sent (as a base keeps it).
    struct RememberedSend: Codable {
        var epoch: Int
        var record: SyncRecord
    }

    /// Writes down what is about to be sent for `key`, which has no base. False when the ledger could not take it:
    /// then nothing is sent (the brain is held, as for every write that fails).
    func rememberSend(_ record: SyncRecord, for key: SyncKey) async -> Bool {
        let kept = Self.base(record)
        if remembered[key] == kept { return true }
        var write = LedgerWrite()
        write.facts[Self.sentFact(key)] = try? JSONEncoder().encode(RememberedSend(epoch: sentEpoch, record: kept))
        do {
            try await commit(write)
        } catch {
            await fail("The engine's memory could not be written: \(error)")
            return false
        }
        remembered[key] = kept
        return true
    }

    /// Reads what was remembered for `keys` (those with no base whose item is here and whose iCloud record arrived
    /// alive), from memory or the ledger. A record of an earlier memory is not used.
    func recallSends(_ keys: [SyncKey]) async {
        for key in keys where remembered[key] == nil {
            guard let data = try? await ledger.fact(Self.sentFact(key)),
                  let kept = try? JSONDecoder().decode(RememberedSend.self, from: data),
                  kept.epoch == sentEpoch else { continue }
            remembered[key] = kept.record
        }
    }

    /// The keys of `incoming` the amended M5 may apply to: no base here, the item here, iCloud's record alive.
    func sendCandidates(_ keys: [SyncKey], local: [SyncKey: SyncRecord], server: [SyncKey: CloudRecord]) -> [SyncKey] {
        keys.filter { key in
            entries[key]?.base == nil && local[key] != nil && server[key].map { !$0.record.isDeleted } == true
        }
    }

    /// Adds to `write` the forgetting of what was remembered for `keys` that get a base now (had none before).
    /// Writing a fact's absence costs nothing when there was none, so the keys need not be known to have one.
    func forgetSends(_ keys: [SyncKey], in write: inout LedgerWrite) {
        for key in keys where entries[key]?.base == nil {
            write.facts.updateValue(nil, forKey: Self.sentFact(key))
        }
    }
}
