# 148: the engine's road to iCloud against Apple's documentation, for Production (read-only review)

`dev/SYNC-ENGINE.md` section 14, stage 2 ("no open finding that can lose a person's change"). The engine's
app-side parts have run on CloudKit **Development** only, with at most 5,000 sample records, on one Mac and once on
an iPhone. In the next release they meet **Production**, real data and George's daily use. Review them as a lead
Apple platform engineer who has shipped `CKSyncEngine` would, with Apple's documentation open.

Files: `HITList/Services/SyncEngine/CloudKitTransport.swift`, `CloudRecordCodec.swift`, `SwiftDataSyncStore.swift`,
`SyncLedgerStore.swift`, `SyncDeletionLog.swift`, `SyncSaveHints.swift`, `SyncRecordMapping.swift`, and the contract
they keep: `HITListCore/Sources/HITListCore/Sync/SyncTransport.swift`, `SyncStorage.swift`.

Read first: `dev/SYNC-ENGINE.md` sections 3, 4, 6 (T1 to T14), 7, 8, 13. In the notes folder (one level above
`round-32/`): `round-28/SDK-CKSyncEngine.md` and `round-28/SDK-SwiftData-History.md` (what the SDK was found to do),
`146-sync-review/FINDINGS.md` (the first review: do not report again what section 13 says was fixed; do check its
"still open" list is still true). Apple's documentation for `CKSyncEngine`, its events and `CKError` codes, and
Apple's sample (`sample-cloudkit-sync-engine`) are the references; quote the page when a finding rests on one.

**Agent 149 is fixing three things at this moment; leave them out**: a fetched record this build cannot read
(16c), an expired change token (16e), and the ledger file moved aside for any error at opening.

Answer each with findings or "looked, nothing":

1. **Production's first contact.** The engine's container's Production schema is deployed by George's click before
   the release; suppose it was not, or lacks a field a newer build sends. What does CloudKit answer for each record
   (in Production an unknown record type or field is refused, there is no just-in-time schema), and what does the
   transport make of it? A whole store "refused for good" would be the worst outcome: it must be a hold with words,
   nothing refused, everything still waiting. Then the zone's creation, the subscription `CKSyncEngine` makes, the
   first fetch of an empty zone, and a first send of 2,000 to 5,000 records (batches, `requestRateLimited`,
   `zoneBusy`, `serviceUnavailable`, retry-after, a send interrupted by the app going to the background).
2. **Every `CKError` code that can come back from a send or a fetch**, as a table: the code, per record or for the
   whole operation, what the transport does, whether that is right. Partial failures above all.
3. **State.** When `stateUpdate` is written relative to the events before it (T1); a kill at each point between an
   event's handling and the state's save; `reset()`; the engine object replaced while events are in flight
   (`isCurrent`).
4. **The account**: signed out, switched, iCloud switched off for HITList alone (the per-app toggle), restricted,
   temporarily unavailable, an encrypted-data reset, the person removing HITList's data in iCloud's settings.
5. **Assets** (`Profile.avatarData`): the temporary files written for a send (are they removed, and when), a
   download that fails, size limits.
6. **A deletion taken down at `willSave`** (`SyncSaveHints.swift`, `SyncDeletionLog.swift`): every way a row of a
   synced model is deleted in the app (grep `.delete(`), the models' cascade rules, contexts other than the main
   one, autosave, a save that fails after the note was written (a note for a deletion that never happened: what does
   the brain do with it?), a rollback.
7. **`SwiftDataSyncStore`**: `apply` writes through the app's main context. When the person has unsaved edits there
   (an editor open, a draft), does the engine's save commit them, or lose them? Is the `LocalWrite.expected` check
   atomic with the write? What a save that throws leaves behind. Reads on contexts of its own: staleness against
   the main context's unsaved or just-saved changes; memory with 5,000 records.
8. **`CloudRecordCodec`**: every field kind there and back (dates in whole milliseconds, an empty string against
   nil, an empty list against none, numbers, a `UUID`'s case), a record of an unknown type, a key this build does
   not know (never sent, never cleared), a record over CloudKit's 1 MB.
9. Anything else a person who has run `CKSyncEngine` in production would warn about.

Write `FINDINGS.md` in your notes folder, and report as the Round 32 block of `dev/briefs/COMMON.md` says.
