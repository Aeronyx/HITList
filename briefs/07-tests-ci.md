# Brief: ROADMAP item 7, App-layer tests + CI

Effort: Medium. Model: Opus 5.5. Read `briefs/COMMON.md` first.

## Files you own
New test files in `HITListTests/` and `HITListCore/Tests/HITListCoreTests/`, `.github/workflows/`,
`README.md` (a short "Development" section and a CI badge), `scripts/test.sh` (new). Do not touch
`project.yml`, app sources, or `scripts/release.sh`. If a test needs a seam in app code, write the
test against the current API and list the seam you wanted in your final message instead of adding it.

## Task, three commits
1. **App-layer tests** (in-memory container via `ModelContainerFactory.preview()`), covering:
   - `TaskActions.toggleCompletion` on a recurring task creates/rolls the next occurrence with the
     right date for daily, weekly, monthly and "every 3 days" rules, keeps the time-of-day when
     `hasDueTime`, and completing a non-recurring task sets `completedAt`; un-completing clears it.
   - `TaskActions.reschedule` with and without `keepTime`, to nil.
   - `TaskActions.create(from:)` from a parsed quick-add result creates project/label on demand and
     reuses existing ones by case-insensitive name.
   - Snapshot export → import round-trip preserves every field, relationship, and recurrence string
     (`SnapshotBuilder` + the import path used by Settings).
   - Seeding is idempotent across two calls and two "devices" (two contexts with the same stable ids).
   Aim for 25-40 focused tests; no sleeps, no network, no CloudKit.
2. **`scripts/test.sh`**: runs HITListCore `swift test`, then `xcodebuild test` for macOS and the
   iPhone 17 simulator, prints a one-line summary per suite, exits non-zero on any failure. Uses
   `DEVELOPER_DIR` as in COMMON.md. Works when called from any directory.
3. **GitHub Actions** `.github/workflows/tests.yml` on push and pull_request to master, `macos-15`
   (or the newest runner that has Xcode 26+; pick by checking actions/runner-images), selecting the
   newest available Xcode with `sudo xcode-select`. Run `swift test` for HITListCore unconditionally.
   For the app tests use `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` with the macOS
   destination only (tests use the in-memory store and the XCTest guard in `HITListApp.init`, so no
   CloudKit is touched; verify locally that an unsigned `xcodebuild test` passes before relying on it;
   if it cannot pass unsigned, keep only the core tests in CI and say so). Cache SwiftPM.
   Note in README that macOS runner minutes are billed at 10x on private repos and that Xcode Cloud
   is the alternative (George sets that up in App Store Connect if wanted).

## Verify
`scripts/test.sh` passes locally. Commit the workflow; you cannot run it (no push), so lint it with
`actionlint` if available (`brew install actionlint`) and say whether you did. Update ROADMAP.md item 7
to "done <date>". Report per COMMON.md, including the final test counts per suite.
