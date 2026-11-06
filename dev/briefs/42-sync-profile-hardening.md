# Brief 42: profiles and sync, robust and lightweight (branch `sync-profile-hardening`, effort xhigh)

Read `briefs/COMMON.md` first. Six sessions run at the same time; see COMMON's "Round 10 ownership". Session 40 is
placing `ProfileBadge`/a profile menu in the sidebar and on Browse using `ProfileStore`'s public API: keep that API
stable (additive changes only) and say in the report what you changed.

George's words, on 0.5.0 (15), 2026-11-04:

> Make profiles/sign-in required if that's what we need to keep everyone's tasks separate and secure.

> Once again ensure profiles and cloud sync are very robust, professional, and lightweight.

The supervisor's answer to the first, which this brief must confirm or refute with evidence: a login is not needed
to keep people apart. Every friend's tasks live in their own Apple account's CloudKit private database, which
nobody else (including the developer) can read; HITList adds no server. What can leak is local: one device used
with two Apple accounts in turn. That is item 2.

## Items (one commit each, failing test first where there is logic)

1. **Review** (read first, write findings into the report): `ProfileStore`, the profile merge in `Deduplicator`,
   `CloudSyncMonitor`, `AccountWatch`, `Services/Sync/*`, `ModelContainerFactory`, `LocalBackup`, the sticky draft
   store, `NotificationScheduler`. Look for: work on the main thread at launch (fetches, image decoding of the
   avatar on every render, JSON encodes), observers or timers that never stop, fetches without limits, the profile
   being re-saved without a change (each save is a CloudKit export), dedupe races with an import in flight, error
   paths that log and carry on silently. Fix what is in your files, one commit each, with a test where it is logic.
2. **One device, two Apple accounts** (`AccountWatch`, `ModelContainerFactory`, `LocalBackup`, the sticky-draft
   store, notification scheduling): when the iCloud account changes on a device, Core Data purges the mirrored
   records, but local things may survive and show the previous person's data to the next: sticky quick-add drafts,
   the last-shown Undo toast, local backups in the app's folder, pending reminders and the badge, Spotlight or widget
   caches if any, `AppGroup.defaults` values that name tasks. Make each of them per account (keyed by a hash of the
   `userRecordID`, never the raw id in logs) or cleared on a detected switch. Never delete iCloud data. Tests with
   two fake account ids.
3. **Profile robustness**: a profile edited on two devices offline converges after both sync (the merge already
   prefers newest per field; prove it with a test that simulates the two imports in either order); the avatar is
   decoded once and cached (`ProfileBadge` and the Account screen must not decode JPEG on every body); saving the
   same name twice writes nothing; a profile record arriving for a different account (should be impossible) is
   ignored and logged. Keep `ProfileStore`'s API additive.
4. **Sync health line**: Settings → iCloud and Settings → Account read the same state words (one source); the sync
   log names account switches ("Account changed: local drafts and reminders cleared"), never with names or ids.
5. **Lightweight**: measure launch to first list frame in a Debug run on the iPhone 17 simulator and the Mac (os_signpost
   or log timestamps) before and after; report the numbers. Do not add dependencies.

## Ownership
`Services/ProfileStore.swift`, `Deduplicator.swift` (profile and dedupe scheduling), `CloudSyncMonitor.swift`,
`AccountWatch.swift`, `Services/Sync/*`, `ModelContainerFactory.swift` (no schema change: if a fix needs one, stop
and report it), `LocalBackup.swift`, `NotificationScheduler.swift` + `Services/Notifications/*` (account switch only),
`Views/Settings/AccountSettingsSection.swift` (its internals; keep `ProfileBadge`'s signature), `ICloudSettingsGroups.swift`,
`Support/SyncStatusViews.swift`; tests `ProfileTests`, `SyncStateTests`, `DedupeTests`, new `AccountSwitchTests`;
ROADMAP row "Profiles and sync hardening (brief 42)". Not yours: `QuickAddDraft.swift` (41) — if the sticky-draft
store lives there, put the per-account key behind a small function in a new file of yours and report the one-line
call 41 or the supervisor should add; `SidebarView`, `BrowseView` (40).

## Done
All three suites green; the review's findings (fixed and not fixed) in the report; launch numbers before/after; a
Debug run on the simulator and the Mac showing the sync log lines for a simulated account switch (a test hook is
fine; never sign the real Mac out of iCloud). Answer George's sign-in question in two sentences in the report.
