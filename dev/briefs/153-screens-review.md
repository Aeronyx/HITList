# 153: every screen through a new person's eyes (review; builds and runs in a worktree of its own, changes no code)

Before a real launch. George has used HITList daily for weeks and no longer sees it as a stranger does; his friends
got it one release at a time. **Walk the whole app as someone who installed it today**, on the phone George's
friends mostly have, and say what would make them stumble, distrust it, or think it unfinished. George judges a
build from its pictures and has called text near a border "lazy and unprofessional" (floors: 12 pt from a card's
edge, 8 pt between a control and text, 6 pt between two controls); dark themes only, by decision.

You have a worktree of your own so that you can build; **commit nothing and change no source file** (a fix is the
supervisor's or another agent's: say what it would be).

How:

1. Make a simulator of your own: `xcrun simctl create HITList-153 "iPhone 16"` (393 × 852 pt, George's phone).
   Build and run the UI test bundle there (`-scheme HITListUITests`, `-derivedDataPath build.noindex/153`,
   `-destination 'platform=iOS Simulator,id=<UDID>'`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).
2. Brief 93's walk photographs every screen: `QASweepUITests` with `TEST_RUNNER_HITLIST_QA=1` (and
   `TEST_RUNNER_PICTURES_DIR=<a folder in your notes folder>`); `ScreenTourUITests` and `FirstRunUITests` cover the
   first launch. Read those test files first to see what they capture and how they are switched on. Then drive
   what they miss yourself with the iOS Simulator tool (launch arguments are in `HITList/HITListApp.swift` and
   `HITList/Services/TaskActions.swift`: `-seedSampleData`, the demo week): the first launch with an empty store and
   no iCloud account; every sheet from the "+"; a task's card with every field filled; Flipboard; Settings to its
   last page; Help; an empty Inbox, an empty filter, an empty search; a very long title; the largest Dynamic Type
   size; VoiceOver labels on the controls that are only icons (the accessibility audit test lists them).
3. Look at every picture at full size, one by one. That is the review; do not skim a contact sheet.

Report, with the picture's path for each finding:

- **First minute**: what a new person sees and can do before they have made anything; whether the first thing they
  will want (add a task, see it, check it off) is obvious; whether anything asks for a permission before its reason
  is plain.
- **Glaring issues**: clipped or truncated text, text against an edge, misaligned rows, a control with no label, a
  state with no way out, an empty screen that says nothing, words only George would understand (names of internal
  things), inconsistent names for one thing, a destructive button beside a harmless one.
- **Objective upgrades**: small changes that would plainly make it better for everyone, each in one line with what
  it costs. Not taste, not new features for their own sake.
- **Settings and Help**: is anything there that a friend should never need to see; is anything missing that they
  will look for (how to export, how to get help, what the bolt means).

Delete your simulator at the end (`xcrun simctl delete HITList-153`). Write `FINDINGS.md` in your notes folder with
the pictures beside it, and report as the Round 32 block of `dev/briefs/COMMON.md` says.
