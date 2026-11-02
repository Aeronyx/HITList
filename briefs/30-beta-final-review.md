# Brief 30: Final review before 0.4.0, the build George's friends get

Effort: Max. Model: Opus 5.5. Read `briefs/COMMON.md`, then `briefs/26-beta-review.md` (the first review,
merged) and the reports' subjects in `ROADMAP.md`'s last rows: sessions 25–29 (sync log and watchdog,
twelve core fixes, dates/times/repeats, tappable tokens and sticky drafts, completion/toast/popout/push).

## Why
George ships 0.4.0 to friends as their first TestFlight build. Brief 26 reviewed the core once; since
then four sessions landed on master in parallel and were merged by Fable. This is the last pass: review
what changed since the first review (`git log d4a7436..HEAD` is the range), hunt for interactions between
the branches that no single session could see, and leave master ready to archive.

## What to look at, in order
1. **Interactions.** Sessions 28 and 29 both edited `Views/Popouts/PopoutHost.swift` (quick-add overlay vs
   toasts and task popout) and `PopoutController.swift`; session 27 changed `QuickAddParser.swift`'s date
   and time assembly while 28 added `QuickAddParser+Disabled.swift` on top of it. Read the merged result
   as one: does disabling a token still work with the new time rules ("tom 13" with "tom" switched off
   leaves "13" as text?), does the restored sticky card survive the toast ownership change, does
   `closeTaskIfDeleted` fire while a quick-add card is open, does `hasSavedForClose` still hold on every
   save path, does the Discard flow interact with the restored card at launch.
2. **The date rules on real calendars.** Month ends across a year, leap years, DST days (the US spring
   forward on 2027-03-14 and fall back on 2027-11-07; times typed around 2 am), week starts Monday and
   Sunday (`Preferences.weekStartWeekday`), "every weekday" across a weekend, repeats whose anchor is lost
   when a user picks a preset again. Tests for each.
3. **Everything brief 26 listed**, re-run as a regression pass over the new code: data safety (no
   `fatalError`/`try!` on a user-data path), adding (every token kind with and without disabling, the
   500-character cap, whitespace), completing (tap rule, undo, recurring advance and undo, from the popout
   and from a notification action), sync (log, watchdog, environment, push waiter, the relaunch), reminders
   (nothing fires for completed/deleted/moved tasks; rescheduling after the new push waiter), startup and
   lifecycle (a stored card at launch on a fresh install, after a reset, with the store in-memory fallback).
4. **The Mac.** Earlier sessions could not look at the Mac app. Build it, open the product, and drive it as
   far as the allowlist lets you: the inline Add task row with tokens, clicking a highlight, the Settings
   iCloud section with the Sync log, Relaunch, the task panel closing on a deletion from a second window.
   Report what you could and could not see.
5. **Performance smells on the hot path:** anything on every keystroke (`parse(_:disabling:)` re-parsing
   in a loop, `Text.LayoutKey` work, the draft store writing defaults on every character) measured with a
   500-character title; nothing may stutter typing.

Not in scope: visual polish, themes, Settings layout, copy. Do not restyle.

## Files you own
Any file a finding needs, with the smallest change that fixes it, each with a failing test first and its
own commit. Not `Models.swift`/schema (additive-only in Production: a schema need is a finding to report),
`scripts/`, `project.yml`, entitlements, `CHANGELOG.md`, `WhatsNew.swift` (Fable writes those). One ROADMAP
row.

## Report
Findings by severity with file and line, the failing test, the fixing commit; the interaction checks and
their results; what you saw on the Mac; test counts before and after; the branch name; the decisions for
George; and your one-paragraph answer to "ship 0.4.0 to friends?".
