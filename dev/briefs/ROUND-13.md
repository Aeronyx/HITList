# Round 13: the friends' first week (2026-11-07)

Written by Fable after the first friend's day on a Mac (George's message of 2026-11-07, quoted in each brief). Read
`dev/SUPERVISOR.md` §4 for how a round runs; this file says what the round is about and what was already done.

## What the Mac session showed, and what is already fixed on master

**He had the iPad build, not the Mac app.** His sync log starts `iOS 15.5 (Build 24F74) · iPad8,6 · platform=iOS`
(24F74 is macOS 15.5; `iPad8,6` is what an iPad app reports on an Apple silicon Mac) and its store sits in the iOS
app group (`group.com.trammells.hitlist`; the Mac app's group is team-prefixed). TestFlight on an Apple silicon Mac
lists "iPhone and iPad apps" for any group whose "Test iPhone and iPad apps on Macs with Apple silicon" setting is
on, and it was on for Friends (read through the App Store Connect API, which also shows both the iOS and the macOS
build 17 in the group). That is the grey title bar (the system's window around an iPad app), the iPad layout in a Mac
window, the sidebar's "Preview" badge wrapping one letter per line, the cut-off tip. Fixed: the iOS build opts out
(`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO` and the visionOS twin in `project.yml`), so the next upload cannot be
installed on a Mac as an iPad app; the badge yields in a narrow sidebar; George turns the group setting off for build
17 (in the hand-over message).

**His sync stopped** at 14:49:33 with `CKErrorDomain 2` (partial failure) and never exported again. Three `TaskItem`
fields (`deadline`, `locationName`, `flipPeriodStart`, all from 0.4.0) were in neither CloudKit environment:
`-seedSampleData`, which teaches Development every field, never set them, sessions run with sync off, and
`release.sh`'s drift check compares Development with Production only, so nothing noticed. Production rejects a record
carrying an unknown field and the mirroring retries that record first, so one flip of a switch (every flip writes
`flipPeriodStart`) ended exports for the session. Fixed on master: the seed sets every optional field
(`CloudKitSchemaTests.testSampleDataCarriesEveryOptionalField` fails when a model field is left out), and `release.sh`
hands the Production export to the preflight, where `testProductionSchemaCarriesEveryModelField` fails while
Production lacks a field (`CloudKitSchemaCheck`). **George deploys the three fields** (a schema push run, then the
console) before anyone flips a switch again; no build is needed for that.

**The "Export overdue" errors** at 14:44 were false: the saved entities (`CoreRuleRecord`, `CoreEventRecord`,
`CoreTipRecord`) belong to TipKit's own SwiftData store in the same process. `CloudSyncMonitor` now counts only the
task store's entities (`syncedEntityNames`). The 21 s first screen is the system's first launch of a newly installed
app (every launch mark starts at 21 s; nothing of ours ran before), not a HITList cost.

**"Deleting a Flipboard switch doesn't delete it everywhere"**: with his Mac not exporting, no delete made there
reached his iPhone, so this may have been the sync. Brief 59 reproduces it with sync working before chasing it.

Also on master: `-seedDemoData` (a believable week on a side store, for screenshots and sessions; `TaskActions.demoLines`)
and the README's screenshots (`docs/images/`).

## The round: four briefs, all four in parallel

| Brief | Session | Effort | Owns, in short |
|---|---|---|---|
| 57 | `groups` | xhigh | Group-by and filters for Inbox and Today, Groups one tap away on iPhone, Group-vs-label guidance: `TaskListView`, `InboxView`, `BrowseView`, `SidebarView`, `ProjectEditorView`, new `Views/Groups/*`, new core `GroupedOrdering` |
| 58 | `tab-motion` | high | The island's moving pill, the haptic, the crossfade: `MobileTabBar`, `MobileShell`, `TapHaptic`, `HITMotion` |
| 59 | `flipboard-intervals` | xhigh | Switches leave the lists while green and come back red; long-press menu; delete everywhere: `Views/Flipboard/*`, `TaskRow`, core `TaskOrdering`/`FilterQuery`, the Upcoming models, the Flipboard tip |
| 60 | `review-inbox` | high | Review only undated and ungrouped tasks, swipe left/right, three buttons: `Views/Inbox/InboxProcess*`, `InboxZeroView`, `InboxText`, `InboxPicker`, new core `InboxReview` |

Merge order: 59 (core rules) first, then 57, 58, 60; 59's report lists the one-line calls the list views need, which
you apply after 57 merges. `HITTips.swift` is shared three ways (one tip each) and `dev/ROADMAP.md` by all: expect
small conflicts there, keep every side.

Version: `## 0.7.2` already holds Fable's fixes (CHANGELOG, What's New, the `SettingsTests` pin). If George released
0.7.2 before this round, the round is 0.8.0 (new section, entry and pin); if not, rename 0.7.2 to 0.8.0 and add the
round's notes to it.

## What to check yourself after the merge
- Inbox and Today grouped by Group on iPhone and Mac; a Group reached from the Today title in one tap.
- The island pill slides on every tab change with a haptic; the screen crossfades; Reduce Motion is plain.
- A green switch is in no list; flip it back to red (its menu) and it is in Today as a today task; delete a switch
  from the Flipboard and from the task editor: gone from Today, Spotlight and the other device.
- Review Inbox on iPhone: swipe both ways, undo a delete, the count on the menu item, the empty state.
- `scripts/test.sh` (all three), then the hand-over message with the schema deploy in bold if any session changed a
  model (none of these briefs should).
