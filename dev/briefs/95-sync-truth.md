# Brief 95: the bolt tells the truth (session `sync-truth`, effort max)

George, 2026-11-11, after 0.9.3 (`dev/briefs/ROUND-20.md` has the whole message, the two pictures in words and the
Mac's log):

> The bolt should never, ever display as full/filled in unless it actually successfully synced within the last
> real-time 30 seconds. I just saw it filled in for a long time when it wasn't successfully synced before it finally
> realized and started flashing again. This time, it was because I accidentally got signed out of my iCloud account,
> but it still shouldn't happen. Concerningly, even after I signed back into iCloud, both the iOS and Mac apps
> showed a synced bolt, but their Inboxes were not consistent (screenshots attached, you can see Mac is missing the
> "Shave" task). What is going wrong here?

and his principle for anything that holds data: **slow is fine, wrong is not.**

This is the round's most important brief. Two devices on 0.9.3 (24), Production, both showing a filled bolt, held
different tasks: the iPhone's Inbox had "call mom" (repeats, Friday) and "Shave" (repeats, Nov 24); the Mac's had
only "call mom". A to-do app that silently disagrees with itself cannot be trusted with a day.

Read `dev/briefs/COMMON.md` (Round 20 block first), `dev/SUPERVISOR.md` §3 and §7, then the code: `Services/Sync/*`,
`Services/CloudSyncMonitor.swift`, `Support/SyncStatusViews.swift`, the store's factory (`ModelContainerFactory`),
`Deduplicator.swift`, `Services/Sync/AccountSwitch.swift` (its header says what Core Data does at a sign-out),
`Views/Settings/ICloudCheck.swift`, and Apple's TN3163 and TN3164 (how `NSPersistentCloudKitContainer` syncs and how
to debug it) and "Reading CloudKit Records for Core Data".

## Part 1. The rule (George's words are the test)
Today `SyncBolt.look` draws `.synced(at)` filled for 24 hours (`staleAfter`), and the mirror only syncs when
something changed, so a filled bolt says "nothing has gone wrong that I heard of". From now on:

1. **Filled means confirmed within the last 30 s of real time.** A confirmation is all of: the iCloud account is
   available; **iCloud itself answered a request** that needs the account and the network (the account-status call
   alone is not an answer); nothing on this device is waiting to be sent (no save newer than the last export that
   finished well, after a few seconds' grace for the export to start); nothing known to be in iCloud is waiting to
   come in.
2. **So the app asks.** While a bolt can be seen (the scene in front on iPhone and iPad; on the Mac while a window
   is visible, front app or not), one small CloudKit request to the tasks container's private database every 15 to
   20 s (you choose, so that one lost answer does not drop a good state and two do; a timeout well under the gap).
   Never in the background, never from an extension. Say in the report what it costs (bytes, requests per hour in
   front) and what it does under Low Power Mode and with no network (it must not spin or queue).
3. **At 30 s without a confirmation the bolt is not filled**, whatever brief 78's steadying (`SyncSteadiness`) would
   hold: leaving filled is immediate, returning needs a confirmation. What it shows instead keeps today's
   vocabulary: hollow and breathing while it is working or asking again (this is what George calls "flashing"),
   struck through once trouble has stayed, with today's colours. Coming back to the app: hollow until the first
   answer (usually under a second), never a flash of trouble for having been away. The rare "good to go" strike
   keeps its rule (`BoltStrikeGate`).
4. **Signed out, restricted, "verify your Apple Account", no network, a request that fails**: each reaches the bolt
   within 30 s, with its words in the bolt's label, in Settings' status line and in the sync log ("Marks show…").
   The log records changes of state and one line per failure kind with a count, not every beat.
5. Every line in Settings that speaks of sync follows the same truth ("Up to date, checked 12 s ago", "Last synced
   3 min ago, checking…"): no words anywhere that claim more than the bolt.
6. Tests with an injected clock and transport: filled at 29 s, not at 31; a lost beat, two lost beats; a save with
   no export after it; an answer that says iCloud has changes and an import that follows, and one that never does;
   sign-out mid-session; back from the background; a hidden Mac window; Reduce Motion.

## Part 2. What went wrong (find it; a finding without a failing test or a reproduction is a suspicion, say so)
Nobody may open George's stores or sign any device in or out of iCloud. Work from the code, from Apple's notes,
from two Debug instances with side stores (`HITLIST_STORE_SUFFIX=s95a`, `s95b`: read how a side store syncs before
relying on it; Debug builds use the Development environment), and from the logs: the supervisor has asked George
for both devices' whole sync logs and will put them in `build.noindex/logs/` in the main checkout
(`/Users/gtrammell/Desktop/HITList/build.noindex/logs/`) and tell you when they arrive. Leads, none of them a
conclusion:
- What Core Data does to the store at a sign-out and at the sign-in after it, on a device that was running, and on
  one that was not. What happens to a row written while signed out, or between the purge and the first import
  after signing in. What the app does when the store is opened with the account unavailable (with the mirror or
  without? `SyncState.localOnly`?), and whether rows written then ever reach iCloud.
- A change the mirror never heard of: history trimmed, a save from another process, a store opened once without
  history tracking, an export that "finished" and sent nothing.
- An import reported finished while records were still to come ("Import finished in 0.13 s" right after a purge).
- A repeating task rolls on in place (`TaskActions.toggleCompletion`); 0.9.3's day passes rewrite dates at first
  launch and after each import (`DayAnchor`), on both devices, after a sign-in too. Any order of those on two
  devices that ends with a task on one and not the other?
- Anything that removes or hides a task on one device without sending a deletion: `Deduplicator`, `SyncRecovery`,
  `SyncStoreGuard`, the account-switch clean-up, a query or filter that differs between the Mac's Inbox and the
  iPhone's for the same store.
Write what each lead came to. If you find the cause, fix it (failing test first). If you cannot reach it from
here, say which evidence would settle it and make sure Part 3 collects exactly that.

## Part 3. A check that can prove it (so the next disagreement names itself)
"Check iCloud…" (Settings → iCloud & data → If something doesn't sync) today makes one round trip. Make it an
audit: read the private database's Core Data zone with CloudKit directly, independently of the mirror (Apple
documents the record names: type `CD_<Entity>`, fields `CD_<attribute>`; read one real record in Development to see
them), keeping only each record's type, id and last-changed stamp; compare with this device's store, record by
record, for every synced kind (tasks, Groups, labels, filters, switches, Switchboards, profiles, whatever the
schema holds).
- It answers in words, on the device only: "This device and iCloud agree: 412 tasks, 9 Groups, …", or "2 tasks on
  this device are not in iCloud: Shave, Call the bank" and "1 task in iCloud is not on this device", each list
  openable. The sync log gets counts and short hashes, never a title.
- **It repairs nothing by itself.** A task here and not in iCloud was either never sent or was deleted elsewhere and
  the deletion never arrived; only the person knows. Offer both, in plain words, after a backup (`LocalBackup`):
  "Send to iCloud" (an ordinary edit and save that the mirror exports; then check again and say whether it
  arrived) and "Remove from this device". For what is in iCloud and not here: say so, and point at "Reset local
  cache…" only once nothing local is missing from iCloud (it would be lost).
- If your beat (Part 1) can be this same read, kept current with a change token of your own, then "nothing waiting
  either way" is exact and cheap, and the bolt can show trouble when the two have differed for two beats with
  nothing in flight. Decide whether that is safe for 0.9.4 (false alarms are their own lie); if not, the audit runs
  on demand, once after each sign-in, and at most once a day.
- First read of a large zone: slow is fine; show progress; never block launch or the first frame.
- No new record type, no schema change, nothing written to iCloud by the audit. If you need one, stop and say so.
- Verify it for real, read-only, from your Debug Mac app against Development (a side store; George's account on
  this Mac). If a system dialog appears, leave it and say so.

## Ownership
`HITList/Services/Sync/*`, `Services/CloudSyncMonitor.swift`, `Support/SyncStatusViews.swift` (the bolt's states and
look; not its place in the toolbar, which is brief 99's), `Views/Settings/ICloudCheck.swift`,
`Views/Settings/ICloudSettingsGroups.swift` and the sync rows of the Mac's iCloud section, the store's factory only
for a finding, `Deduplicator.swift` only for a finding, new files under `Services/Sync/`, tests named `Sync*Tests`
and `BoltTruth*Tests`. Not yours: the Sync log's filter control (99), every other view, the models' shape,
`DayAnchor` (report a finding; do not change it), `scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`.

## Done
The rule's table: each state, what the bolt shows, how long until it shows it. Part 2: each lead, what you tried,
what happened; the cause, or the evidence still needed. Part 3: the audit's words for each outcome, and its real
run against Development. What George does on each device after 0.9.4 to learn why "Shave" was missing, as click
paths. All three suites green, your UI test (if any) on a fresh simulator; the branch; changelog lines in plain
words; every decision of yours George might reverse.
