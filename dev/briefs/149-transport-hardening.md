# 149: three ways the engine's app side can lose or hide a change (code)

`dev/SYNC-ENGINE.md` section 14, stage 2, items 1 to 3 (section 13 names each). A worktree of your own; Mac hosted
tests are your proof (`xcodebuild test -project HITList.xcodeproj -scheme HITList -destination 'platform=macOS'
-allowProvisioningUpdates -derivedDataPath build.noindex/149 -only-testing:HITListTests/<Class>`, with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

**Yours**: `HITList/Services/SyncEngine/CloudKitTransport.swift`, `SyncLedgerStore.swift`, `CloudRecordCodec.swift`,
their test files in `HITListTests/SyncEngine/` (`CloudKitTransportTests`, `SyncLedgerStoreTests`,
`CloudRecordCodecTests`; new test files beside them are fine, then `xcodegen generate`). In
`HITList/Services/SyncEngine/SyncEngine.swift` only the few lines of `launchIfSwitchedOn` that make the ledger and
speak of `movedAside`: the supervisor is editing the rest of that file. **Not yours**: anything under
`HITListCore/Sources/HITListCore/Sync/` except doc comments in `SyncTransport.swift` (agent 150 is changing the
brain); `dev/SYNC-ENGINE.md` (put the words a changed rule needs in your report and the supervisor writes them in).

Read first: `dev/SYNC-ENGINE.md` sections 4, 6, 7, 10, 13; in the notes folder (one level above `round-32/`)
`round-28/SDK-CKSyncEngine.md` and `146-sync-review/FINDINGS.md` (findings 16b, 16c, 16e and the ledger's opening).

## 1. A fetched record this build cannot read must stay owed (16c)

Today a record whose decoding throws (`CloudRecordCodec.DecodeProblem`: in practice an asset that did not download
or is too large, so nearly always `Profile.profile` with its avatar) is dropped while `CKSyncEngine` moves its
bookmark on: the device never hears of that record again unless it changes in iCloud. Make it owed:

- The transport remembers the record's name in its own saved state and asks iCloud for exactly those records again
  (by name, not by resetting the bookmark) at each later fetch and at each start, and delivers one as fetched when
  it can be read. Never on a timer.
- One unreadable record must not stop anything else from syncing, and must never make the brain take the record for
  absent from iCloud in a way that overwrites it: trace what the brain does today for a key iCloud holds and the
  transport has not delivered (a local row with no base is sent without a token, iCloud refuses with its own
  version, which is unreadable too: 16b's path), prove with a test that nothing in iCloud is overwritten and nothing
  here is lost, and that when the record becomes readable both sides settle.
- The person can see it: while a record is owed the fetch's words say so (how many, and the first one's name and
  reason), so the bolt is not filled and Settings → iCloud shows the line. Use the road that exists
  (`didFetch(error:)`'s words, the status's `lastError`); if no road fits without a change to the brain, say what
  the smallest change would be and stop there.

## 2. An expired change token (16e)

Find out first what `CKSyncEngine` itself does when iCloud answers `changeTokenExpired` (Apple's documentation, the
SDK notes): if it resets and refetches by itself, prove that our transport's handling of what follows is right (a
whole fetch arrives: is `fetchedWhole` true to it? does the brain's ledger stay?) and say so with a test on the
rules. If it does not, the transport does what T13 says: forgets the bookmark and its list, keeps the account and
what it knew of the zone, tells the brain nothing that reads as "the transport lost its state" (that costs the
brain its ledger, T12), and fetches everything; once per fetch, never in a loop.

## 3. The ledger's file is moved aside for any error at opening

`SyncLedgerStore.open(at:)` moves the file aside whenever the container cannot be made. Losing the ledger is safe
for items (a merge without memory) **but it takes the deletions this device has not yet sent with it, and those
items then come back**. So the file is moved aside only when it is damaged beyond opening (say exactly which errors
you take for that, and why). Anything else (the disk full, no permission, a phone locked before its first unlock so
that the file's protection refuses the open: check which protection the App Group's files have and whether the app
can be launched in the background in that state, by a push or a background refresh) leaves the file untouched, and
the engine holds `failed` with the words, to be tried again at the next start or "Try again". Check the same for
the main store's opening (`ModelContainerFactory.open` falls back to an empty in-memory store, on which the engine
never runs: is that path safe when the phone is locked?) and report; the main store's code is not yours to change.

## Proof

Hosted tests for each item, written first and seen to fail. The whole of `HITListTests/SyncEngine` green at the end,
and the counts before and after. If you have time left: run the transport's probe once against CloudKit Development
(`dev/SYNC-ENGINE.md` section 9, item 4: the command with `HITLIST_STORE_SUFFIX=p149`, the built Debug app in your
derived-data folder; quit it afterwards) and report its lines.
