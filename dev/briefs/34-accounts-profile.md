# Brief 34: account and profile, privacy policy, ready for friends (branch `accounts-profile`, effort xhigh)

Read `briefs/COMMON.md` first. Sessions 37 (quick-add highlights) and 38 (Mac Upcoming board) run at the same
time; 35 (iPhone tabs, Browse) and 36 (task editor) start after them. You are the only session that touches the
data model this round, and you will be merged last.

George's words, from the 0.4.1 (14) feedback on 2026-11-04:

> I would indeed like my friends to have their own full accounts, which I understand requires an extra
> review; let's get on basic account/profile implementation, privacy policy, and app review right away.
> (I say "basic," but I want you to ensure the account/profile system has the same robustness and
> reliability of our cloud sync).

And their answers to the supervisor's questions:

> Apple only sign-in is fine for now. Set up whatever we need to to ensure my friends and I can all use this
> app freely in TestFlight, as we're honestly all expecting it will become our primary todo-list app.

> Privacy Policy at GitHub Pages on the repo; if the repo is Private and that causes a problem, let's either
> make it Public (I don't see why not at this point, might be good to point to as a coding project on my
> profile) or if that's a bad idea let's create a separate public-facing repo just for privacy
> policy/licensing as needed.

## The design (settled; do not re-ask)

- **Identity is the Apple account the device is signed in to iCloud with.** No Sign in with Apple button, no
  email/password, no server. CloudKit's private database is already per Apple ID, so every friend's tasks are
  theirs alone with no code change; what this brief adds is a visible account (who am I signed in as, is it
  healthy), a profile (name and picture), and everything a friend's first launch needs. Because the app has no
  login of its own, App Store Connect's "Sign-in required" stays unchecked and no demo account is needed.
- **Profile = a new `Profile` model in the private store, schema V4** (follow the "How to add V4" header in
  `SchemaVersions.swift` exactly: freeze V3 in a new `SchemaV3Models.swift`, lightweight stage, hashes pinned
  in `SchemaTests`, a `testV4OnlyAddsTheProfileEntity`). Every attribute optional or defaulted, no `.unique`.
  Suggested fields: `displayName: String = ""`, `avatarData: Data?` with `@Attribute(.externalStorage)`
  (a CKAsset; downscale to ≤ 512 px JPEG, ≤ 200 KB, before saving), `avatarSymbol`/`avatarColor` for the
  initials fallback if you want one, `createdAt`, `updatedAt`. One profile per account: two devices that each
  create one before syncing must converge, so `Deduplicator` merges profiles after every import (keep the
  newest `updatedAt` per field, never lose a picture) with a failing test first.
- **Same robustness as sync** means: the profile goes through the same SwiftData + CloudKit container as tasks
  (no separate CKRecord code path), every profile write and merge is logged through `SyncLog` (a `profile`
  category or the existing sync category with a clear message), the watchdog's rules cover it for free, and
  Settings shows the account state honestly (available / signed out / restricted / could not determine /
  switched account, using `CloudSyncMonitor` and `AccountWatch`, which already track this). A sign-out or
  account switch must never delete anything (see `AccountWatch`'s header).
- **Signing out** is done by the system: the Account screen says so and gives the path (iPhone: Settings →
  [your name] → Sign Out; Mac: System Settings → [your name] → Sign Out). **Deleting your data**: the app
  never mass-deletes (COMMON's rule); the Account screen explains the real path, which Apple provides for every
  CloudKit app: iPhone Settings → [your name] → iCloud → Manage Account Storage (wording varies by iOS
  version; check it in the simulator's Settings app or Apple's docs and quote the iOS 18 and iOS 26 wording) →
  HITList → Delete Data, and offers "Delete profile" (deletes only the Profile record, logged, with a
  confirmation) and the existing Export.

## Items (one commit each, failing test first where there is logic)

1. **Schema V4 with `Profile`** (`Models.swift`, `SchemaVersions.swift`, new `SchemaV3Models.swift`,
   `SchemaTests`, `ModelContainerFactory` only if the model list lives there). Push it to CloudKit
   Development with the Debug Mac run described in the `SchemaVersions.swift` header (its own store suffix,
   never the real store), confirm "exporting succeeded" in the log, quit that Debug app, and put the log
   lines in your report. George deploys to Production before the release; say so in your report.
2. **`ProfileStore`** (new `Services/ProfileStore.swift`): fetch-or-create the single profile on the main
   context, update name/picture, merge duplicates (called from `Deduplicator`), delete; every write logged.
   Unit tests in a new `ProfileTests.swift` (in-memory container): create once, two creates converge after
   dedupe, picture survives a merge, delete leaves tasks alone.
3. **Account screen** (new `Views/Settings/AccountSettingsSection.swift`, one line in `SettingsView.swift` to
   put it first, one in the Mac page's section list (`MacSettingsSection`/`MacSettingsPage`) so the Mac shows it
   too): avatar (PhotosPicker on iOS and the Mac; initials in an accent circle when there is no picture),
   name field (design-system field style, saves on commit, not every keystroke), "iCloud: Signed in" (or the
   honest other state, with what to do), "Your tasks are stored in your iCloud account and sync to every
   device signed in to it", the sign-out explanation, Delete profile (confirm), and how to delete all data
   (above). Custom controls only (`Support/DesignSystem/README.md`). Show the name and avatar small at the top of
   Browse? No: session 35 owns Browse; leave a `ProfileBadge` view (avatar + name) that 35 or the supervisor can
   place later, and say so in the report.
4. **A friend's first launch** (audit, then fix inside your ownership, list the rest): erase a fresh simulator
   of your own (see COMMON), install, and go through the first minute as a new tester would: with no iCloud
   account, and (if the simulator lets you sign in, which it usually does not) with one. Check: no sample/seed
   data in a Release-like configuration, no What's New sheet for a brand-new user (it should only show after an
   update; read `WhatsNew.swift`, which the supervisor owns: report, do not edit), the empty Inbox/Today look
   intentional, notification permission is asked at a sensible moment, the signed-out banner does not shout at
   someone who never used iCloud (`AccountWatch.everSignedInKey`), the sync bolt reads sensibly. Report each
   finding with a screenshot path.
5. **Privacy policy page** (new `docs/privacy.md` with Jekyll front matter `title: HITList Privacy Policy` and
   `permalink: /privacy/`, new `docs/index.md` with a two-line landing page linking to it, new `docs/_config.yml`
   with `title: HITList` and the default theme). The supervisor turns on GitHub Pages from `master` `/docs`;
   the URL will be `https://aeronyx.github.io/HITList/privacy/`. Write it from the code, not from assumptions:
   grep for every network call, `URLSession`, analytics, crash reporting, `UNUserNotificationCenter`,
   `LocalBackup`, `Diagnostics` ("Copy diagnostics": list what it contains), the `server/` relic (unused, say
   the app does not contact any server of ours). Plain English, short sections: who we are (HITList, an app by
   George Trammell, beta via TestFlight), what we collect (nothing on our side), where your data lives (your
   iCloud private database, Apple's privacy policy applies), profile name and photo (stored the same way),
   notifications (scheduled on the device), backups and exports (local files you control), diagnostics (only
   what you copy and send yourself), TestFlight (Apple shares crash reports and feedback you send; link Apple's
   TestFlight terms), children, changes to the policy, contact (TestFlight's "Send Beta Feedback" and the
   repository's issues page `https://github.com/Aeronyx/HITList/issues`; no email address, George adds one if
   they want), effective date 2026-11-04. Also add a "Privacy policy" link row to Settings → About
   (`AboutSettingsGroup.swift` and `MacAboutSection.swift`, link only).
6. **Diagnostics and the iCloud screen** (`Diagnostics.swift`, `ICloudSettingsGroups.swift`, account lines
   only): "Copy diagnostics" gains the profile's existence and sync state (never the name or picture), and the
   iCloud screen's environment line names the account state the same way the Account screen does.

## Ownership

`HITList/Models/Models.swift`, `SchemaVersions.swift`, new `SchemaV3Models.swift`, `ModelContainerFactory.swift`
(model list only); new `Services/ProfileStore.swift`; `Services/Deduplicator.swift` (profile merge only);
`Services/Sync/SyncLog.swift` (a category only); `Services/AccountWatch.swift`, `CloudSyncMonitor.swift` (read;
edit only if a state is missing); new `Views/Settings/AccountSettingsSection.swift` (+ `ProfileBadge`);
`SettingsView.swift` (one line), `Views/Settings/Mac/MacSettingsSection.swift` / `MacSettingsPage.swift` (the
Account entry only), `AboutSettingsGroup.swift`, `MacAboutSection.swift` (privacy link), `Diagnostics.swift`,
`ICloudSettingsGroups.swift` (account lines); `docs/` (new); tests `SchemaTests`, new `ProfileTests`, and
`DedupeTests`/`SettingsTests` where they cover these (never the version pin in `SettingsTests`, which the
supervisor owns); `project.yml` only to add files, then `xcodegen generate`; ROADMAP row "Account and profile,
privacy policy (brief 34)".

Not yours: `Views/Tabs/*`, `BrowseView.swift`, `GeneralSettingsSection.swift`, `SettingsPreferences.swift`
(session 35); `TaskPopout.swift`, `Editor/*`, `QuickAddPopout.swift`, `PopoutHost.swift` (36);
HITListCore's parser, `TokenHighlightField.swift`, `QuickAddDraft.swift` (37); `Views/Upcoming/*` (38);
`WhatsNew.swift`, `CHANGELOG.md`, `scripts/`, `briefs/` (supervisor).

## Done

All three suites green with the new tests; schema V4 in CloudKit Development (log lines in the report);
iPhone simulator screenshots of Settings → Account with a name and a picture, with the initials fallback, and
of Settings → About's privacy link; the first-launch audit's findings; the Mac Account section described (the
Mac cannot be screenshotted: list what George should look at). The report also lists, for George, the exact
App Store Connect click path for external TestFlight testing (the supervisor will relay it): Test Information
fields and suggested text (Beta App Description, What to Test, feedback email, privacy policy URL, "Sign-in
required" unchecked and why), App Privacy ("Data Not Collected", and why that is true), creating an external
group with a public link, and that the first build to external testers goes through Beta App Review.
