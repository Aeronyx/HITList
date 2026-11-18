# 170: the word that lets every device move: one record in iCloud's public database (code)

George, 2026-11-18: "I also want it to force everyone to move over to the new sync engine so we can settle this
once and for all", and earlier the same day, "I'd even rather the update just automatically move their tasks
after we've confirmed the new engine is working." One build must do both: reach everyone, and move nobody until
George has seen the engine work on his own devices on the live side of iCloud. So the move made by the app itself
(`SyncEngineAutoMove`, round 33) will wait for **a word from George that every device can read**: one record in
the public database of the engine's container. No record: nobody moves (the safe side). The record there: every
device moves when its own rules allow. The record removed or marked paused: devices that have not yet moved wait
again. This reverses `dev/SYNC-ENGINE.md` section 14's "no remote switches" for this one purpose; the supervisor
rewrites the document and wires your type into `SyncEngineAutoMove` himself.

**Yours**: a new file `HITList/Services/SyncEngine/SyncEngineRollout.swift`; `dev/cloudkit/sync-engine.ckdb` and
`HITListTests/SyncEngine/SyncEngineSchemaFileTests.swift` (the file gains one record type; the test that pins the
file to the engine's schema must go on pinning every engine type exactly and learn that this one more type
exists, with a reason in a comment); a new test file `HITListTests/SyncEngine/SyncEngineRolloutTests.swift`; a
Debug hook in `SyncEngineRehearsal.swift` (three small additions, below). **Not yours**:
`SyncEngineAutoMove.swift`, `SyncEngineSwitch.swift`, `SyncEngine+Move.swift`, `SyncEngine.swift`,
`CloudKitTransport.swift`, core, `scripts/release.sh` (its check already compares Production with the file: say in
your report exactly what it will print before George has deployed the new type).

1. **The record.** Type `HLRollout`, in the **public** database's default zone, record name `everyone`. Fields:
   `minBuild` (INT64, optional: only builds with a build number at least this move; absent means every build),
   `paused` (INT64, optional: 1 means wait). In the schema file: readable by the world, and say what the file
   grants for creating and writing (CloudKit's defaults let any signed-in person create a record of a type; no
   released code path creates this one, and the smallest grant that still lets the Debug hook create it in
   Development and George create it in the CloudKit Console is what you want: read Apple's documentation of the
   schema language's `GRANT` lines and of security roles, say what you chose and why, and what a curious tester
   could and could not do).
2. **The question** (`SyncEngineRollout`): `enum Answer { case go, notYet, paused, unknown }` and a protocol with
   one async function, as `SyncEngineZoneLooking` is built, so a stand-in answers in tests. The CloudKit
   implementation fetches that one record by its id (no query, no index), reads the two fields against this
   build's number (`AppInfo`), and maps: record there and this build allowed and not paused → `go`; `paused` → 
   `paused`; no such record (`unknownItem`) or `minBuild` above this build → `notYet`; anything else (offline, a
   schema not yet deployed, a throttle) → `unknown`. It never throws, never retries by itself, writes one line in
   the sync log per answer through a closure it is given, and keeps nothing on disk.
3. **Debug only** (`#if DEBUG`, side stores only, in `SyncEngineRehearsal`): `-rehearsalRollout go|pause|clear`
   writes, pauses or deletes the record in the public database the device's account can reach (Development for a
   Debug build), and `-rehearsalRolloutAsk YES` asks and prints the answer. One line each, as the other hooks
   print.
4. **Tests**: every mapping above with a stand-in for the database call (inject the fetch as a closure returning
   the record's fields or an error); the build comparison at its edges; that the release build has no path that
   writes the record (a test that greps the non-Debug source for a save into the public database is fine).

Nobody talks to iCloud in this brief: the supervisor imports the schema into Development and runs the hooks on the
Mac and George's phone himself. Proof: your tests; `SyncEngineSchemaFileTests`; `HITListTests` whole on the Mac. In
your report: the exact text George types in the CloudKit Console to make the record (the click path as Apple's
console names things, from its documentation, marked as unverified where you could not see it), the grants you
chose, and what `scripts/release.sh` prints until the type is deployed.
