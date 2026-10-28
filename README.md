# HITList — Human-in-the-List

[![Tests](https://github.com/Aeronyx/HITList/actions/workflows/tests.yml/badge.svg?branch=master)](https://github.com/Aeronyx/HITList/actions/workflows/tests.yml)

A small, fast, Todoist-flavored task manager for iPhone, iPad, and Mac. Built around three
things: a real filter query language, natural-language quick add with learned autofill, and
free sync through your own iCloud account, with an optional backup channel to a home server.

See [DESIGN.md](DESIGN.md) for scope, architecture, the filter grammar, and the sync cost analysis.

## Layout

| Path | What |
|------|------|
| `HITListCore/` | Swift package: filter language, date parsing, quick add, autocomplete, recurrence, snapshot format. `swift test` runs 43 tests in under a second. |
| `HITList/` | SwiftUI multiplatform app (iOS 18+, macOS 15+) using SwiftData + CloudKit. |
| `server/` | Optional backup receiver for your home server (Python stdlib + Docker). |
| `project.yml` | XcodeGen spec. Run `xcodegen generate` to (re)create `HITList.xcodeproj`. |

## Build

```bash
brew install xcodegen          # once
xcodegen generate              # creates HITList.xcodeproj
open HITList.xcodeproj         # pick "My Mac" or an iPhone, press Run
```

Core tests without Xcode UI:

```bash
cd HITListCore && swift test
```

Signing is automatic with team `UC8N98H3RT`, bundle id `com.trammells.hitlist`, CloudKit
container `iCloud.com.trammells.hitlist`. The first signed build registers the container.
If `xcodebuild` complains about the active developer directory, prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` or run
`sudo xcode-select -s /Applications/Xcode.app`.

## Development

```bash
scripts/test.sh                    # HITListCore, app tests on macOS, app tests on the iPhone 17 simulator
scripts/test.sh core macos         # any subset
scripts/test.sh --unsigned macos   # the unsigned build CI runs
```

It prints one line per suite (`✔ macos: 60 tests, 0 failures in 12s`) and exits non-zero on any
failure, keeping the full log. App tests (`HITListTests/`) run hosted in the app against an in-memory
store; `HITListApp.init` skips CloudKit under XCTest, so they never touch real data.

CI: `.github/workflows/tests.yml` runs on pushes and pull requests to `master` on the `macos-26`
runner with its newest Xcode: `swift test` for HITListCore, then the app tests on macOS, unsigned.
macOS runner minutes count 10x against the free allowance on private repositories; Xcode Cloud

If a run is cancelled with no steps and the annotation "not acquired by Runner of type hosted", GitHub had no Apple Silicon macOS runner free for 15 minutes; re-run it (`gh run rerun <id>`) rather than changing anything. Entitlement-dependent tests skip on the unsigned CI build (`HITLIST_UNSIGNED=1`).
(set up in App Store Connect → the app → Xcode Cloud) is the alternative, with 25 free hours a month
in the Apple Developer Program.

## Quick add cheat sheet

```
Pay rent tomorrow 5pm p1 #Finance @bills every month
Standup every weekday 9am #Work
Dentist jan 5 at 2:30pm @health
Trash every other week
Read "tomorrow" by Tom Smith        ← quotes keep a word literal
```

## Filter cheat sheet

```
overdue | today
(p1 | p2) & next 7 days & !@waiting
#Work & no date
due before: next mon & priority <= 2
search: dentist | @health
```

## Home server backup (relic, not wired in)

The app syncs through iCloud only. `server/` and `BackupService.swift` are kept as a
design relic; see DESIGN.md section 5. Settings → Export JSON gives a manual backup.

## TestFlight

See [TESTFLIGHT.md](TESTFLIGHT.md). Theme is dark slate only; see `HITList/Support/Theme.swift`.

## Troubleshooting sync

- The app links CloudKit explicitly (`CloudSyncMonitor.container`). Do not remove it: on macOS 26 the
  App Sandbox otherwise denies the `com.apple.cloudd` lookup and sync fails with CKError 6.
- Before deploying the CloudKit schema, run the Mac app once with `-seedSampleData` so every record
  type exists in the Development environment.
- Full sync logging: launch with `-com.apple.CoreData.CloudKitDebug 3` and read it with
  `/usr/bin/log show --predicate 'process == "HITList" AND subsystem == "com.apple.coredata"'`
  (in zsh, plain `log` is a shell builtin).
