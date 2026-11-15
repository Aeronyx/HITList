import Foundation

// What this device last sent for a record and has had no answer for (`dev/SYNC-ENGINE.md` M5 and M7, amended
// 2026-11-15). A save iCloud accepted whose answer was lost (the network dropped on the way back, the app died before
// `sent`) leaves this device's base where it was, or leaves none when the record was new here. Then:
//
// - with no base, the next meeting was M5, the record changed last kept whole, so an edit made here after the send and
//   one made elsewhere could not both survive (brief 145: zone seed 270, memory seed 259). Now what was sent is the
//   base, and the two are settled as M7;
// - with a base, a field the person changed back after the send read as never changed, and iCloud's copy of this
//   device's own earlier value won over it (seed 284: a task un-completed that completed itself again). Now, field by
//   field, the value that was sent and that iCloud holds is what the two agreed on (`agreedThroughSends`).
//
// Written to the ledger before `recordToSend` answers (a crash after the save and before its answer finds it on disk),
// one fact per key, the last record sent; forgotten when the send is answered or a base lands for the key, and worth
// nothing once the memory is forgotten (`sentEpoch` moves on: a lost zone, a lost transport state). Read whole at a
// start. Never used for a deletion, never by the compare (a send without an answer is not an agreement).

extension SyncCore {
    /// What is kept per key: the memory it belongs to, and the record sent (as a base keeps it).
    struct RememberedSend: Codable {
        var epoch: Int
        var record: SyncRecord
    }

    static let sentPrefix = "sent|"
    static func sentFact(_ key: SyncKey) -> String { sentPrefix + key.description }

    /// Writes down what is about to be sent for `key`. False when the ledger could not take it: then nothing is sent
    /// (the brain is held, as for every write that fails).
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

    /// What the ledger remembers of sends without an answer, read whole at a start. One written in an earlier memory
    /// (another epoch) is not used.
    func loadRememberedSends() async throws {
        remembered = [:]
        for (name, data) in try await ledger.facts(prefix: Self.sentPrefix) {
            guard let kept = try? JSONDecoder().decode(RememberedSend.self, from: data), kept.epoch == sentEpoch else { continue }
            _ = name
            remembered[kept.record.key] = kept.record
        }
    }

    /// The sends of `key` this device has had no answer for: those of this run (the newest last), or after a relaunch
    /// the last one written down.
    func sendsWithoutAnswer(_ key: SyncKey) -> [SyncRecord] {
        if let sends = unanswered[key], !sends.isEmpty { return sends }
        return remembered[key].map { [$0] } ?? []
    }

    /// Adds to `write` the forgetting of what was remembered for `keys` (answered, or a base landed for them).
    func forgetSends(_ keys: [SyncKey], in write: inout LedgerWrite) {
        for key in keys where remembered[key] != nil {
            write.facts.updateValue(nil, forKey: Self.sentFact(key))
        }
    }
}
