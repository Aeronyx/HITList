# Round 31: the engine on George's iPhone, a push proven, and the road to switching on (2026-11-16, evening)

0.9.13 was released on 2026-11-16 (build 30). George's message that evening, verbatim:

> Thanks, 0.9.13 released. Note that the recent few releases have had this warning at the top:
> "iCloud.com.trammells.hitlist: Development also holds record types this release does not sync through, left out
> of the comparison: HLMeta HLProfile HLProject HLSavedFilter HLSwitchboard HLTaskItem HLTaskLabel Meta Profile
> Project SavedFilter Switchboard TaskItem TaskLabel
> They come from round 28's test runs of the sync engine, which has its own container now. Do not press Deploy
> Schema Changes for this container while they are there: it deploys everything. Reset Development first (CloudKit
> Console → iCloud.com.trammells.hitlist → Development → Reset Environment…)."
>
> Please do plan the engine's next steps. You may indeed use my iPhone for a debug build if you wish; I've
> connected it via wire to this laptop if that's helpful.

No sessions: the supervisor alone. No release is prepared: nothing a person can see changed.

## The warning

It is `release.sh` saying what round 28's probes left in the tasks' container's Development side. It goes when that
side is reset, which deletes only what Debug builds on this Mac put there and returns its schema to Production's.
From a terminal it is one command, the same as the console's Reset Environment:

    xcrun cktool reset-schema --team-id UC8N98H3RT --container-id iCloud.com.trammells.hitlist

George was asked whether to run it from here; nobody runs it without his word.

## The engine on a phone, and a push

His iPhone 16 on a Debug build (it replaced the TestFlight build for forty minutes; the real store, the settings,
Spotlight, reminders and backups are out of a Debug build's reach by code, read again before installing), beside a
Debug Mac app, both on the engine in its own container, Development, zone `HITList-r31`.

- **Phone to Mac.** The Mac app was started empty, in the background, and never brought forward. The phone was
  launched with the sample data and sent nine records; the Mac fetched all nine within seconds and said "Sync for a
  push: done".
- **Mac to phone, HITList in front.** A task completed on the Mac was on the phone in about 3 s.
- **Mac to phone, HITList in the background** (Settings in front): about 3 s.
- **Mac to phone, the phone locked and asleep**: not within three minutes; fetched the moment the app came forward.
  iOS delivers silent pushes to a sleeping phone when it chooses; today's sync lives by the same pushes.
- **Why it had never worked**: on a Mac only Core Data's mirror registered for pushes, and the engine runs with the
  mirror off. Round 30 made the engine register at its start; this is the first run in which a second device
  existed to notify. Two apps on one Mac never notified each other.

**A first sync on the phone.** A Mac app seeded with 5,000 tasks (`-seedSyncLoad 5000`, Debug only) sent 5,006
records in 21 batches; the phone, on a fresh side store, fetched and wrote 5,005 in about 28 s end to end. The main
thread was held about 1.2 s in all, in writes of 200 records of 43 to 65 ms each. No change is needed: the store
keeps writing where the views read. `SyncApplyTimes` now says such load in the sync log (a line when the writes
since the last line add up to a quarter of a second, or one write took a tenth), so the number is there on any
device from now on. (Its first form spoke only of a single slow write and said nothing at all on the phone, where
no write was slow: a threshold that hides the total is no measurement.)

How it was run, for the next time:

    xcodebuild build -project HITList.xcodeproj -scheme HITList -configuration Debug \
      -destination 'id=<the phone's UDID>' -derivedDataPath build.noindex/device -allowProvisioningUpdates
    xcrun devicectl device install app --device <UDID> build.noindex/device/Build/Products/Debug-iphoneos/HITList.app
    xcrun devicectl device process launch --device <UDID> --terminate-existing --console \
      --environment-variables '{"HITLIST_STORE_SUFFIX":"<name>"}' com.trammells.hitlist -- \
      -syncEngine own -syncEngineZone <zone> [-seedSampleData]      # stdout carries the SYNCENGINE lines
    xcrun devicectl device info lockState --device <UDID>            # passcodeRequired: false = it can launch
    xcrun devicectl device process launch --device <UDID> com.apple.Preferences   # puts HITList in the background

The phone must be unlocked for a launch (George did it once; it stayed launchable for the whole run). The built
app's build number is the project's (the Info.plist holds it as a literal; a build setting on the command line does
not change it). Afterwards George installs the TestFlight build over it: TestFlight → HITList → Install.

## The road

`dev/SYNC-ENGINE.md` section 14, seven stages with what each needs from him: real devices (done); close what can
lose or hide a change; his remaining decisions (plain fields recommended for the first live release); the move
rehearsed on a copy of his real data; live for him only; everyone; the mirror retires.

## Proof and what is left

- The runs above: `build.noindex/round-31/e2e/` holds both logs of each.
- Hosted engine classes on the Mac with the timer in place; core untouched.
- Left on the phone: the Debug build until he reinstalls; side stores `HITList-r31phone`, `-r31load`, `-r31load2`
  with their ledgers in the app's group container (about 10,000 sample tasks, a few megabytes; no released build
  opens them). Left in the engine's container, Development: zones `HITList-r31` and `HITList-r31load`. On this
  Mac: side stores `HITList-r31*`.
- Not proven: a push that has to launch the app from nothing (it was suspended, not gone, in every case).
