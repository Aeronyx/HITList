# Round 16: George's and the friends' notes on 0.9.0 (2026-11-10)

0.9.0 is out as build 20 on both platforms. The friends moved from the public TestFlight link to **internal testing**
(they are App Store Connect users on George's team, limited to HITList), so builds reach them without Beta App Review.
From now on **the version stays 0.9.0** (George: "definitely don't update the major version number for a while"):
release with `scripts/release.sh --quick`, no `--version`; §6 of the handbook says what that means for the notes.

This round's supervisor is a new chat on Fable 5.2; the Opus 5.5 supervisor wrote this file and handed over. No briefs
are written yet: the next brief number is **70**. The friend's screenshot is
`/Users/gtrammell/Desktop/HITList/build.noindex/round-16/friend-mac-today-0.9.0.png` (outside git; read it by that
path). Ours for comparison, the same build on George's Mac (macOS 26.7.1) with demo data:
`/Users/gtrammell/Desktop/HITList/build.noindex/round-15/mac/02-today.png`.

## George's notes, verbatim

> My friends are currently using 0.9.0 but there are still some issues. Mainly, why in the world does my friend's Mac
> app still look different than mine if he's running the latest macOS and I disabled the iPad app thing? So confusing.
> A screenshot of his version is attached with many concerning subtle differences.
>
> Also, my friend wants to use the Flipboard slightly differently for his own use case; it's still essentially the same
> functionality, it just needs a better daily switch system (e.g. "reset every day at 4am") and groups of switches
> called Switchboards so he can form daily/weekly routines with groups of switches. Essentially, switches should be
> more focused around routines instead of tasks and allow times to be attached. By default, switches should not become
> tasks when overdue unless the user toggles that option on. Different Switchboards can function as groups such as
> "Deep Clean" or "Before Bed" that contain tasks a user might do daily before bed or weekly to clean the house. Of
> course, none of these routine switches should become actual tasks unless the user toggles on "overdue becomes task".
> Then, looking at your Flipboard in the app becomes more like a personal status check without the stress of your real
> todolist, which is exactly the point.
>
> Add more quickadd highlights, such as "every month on the 28th" and related phrases.
>
> The Browse tab has hidden button at the bottom again behind the home bar, and you also can't swipe left to delete
> Groups but I wish you could.
>
> The lightning bolt animation is very cute! But when I said "twirl and rise up a bit before slamming", I meant twirl
> on the Z axis, as in halfway through the twirl the bolt would technically be invisible or incredibly thin as the edge
> of the icon would be facing the user for a split second. The actual slam animation is almost perfect though, I love
> the slight warp and the sparks.

## What the Opus supervisor found before handing over

**1. The friend's Mac.** It is the macOS build, 0.9.0 (20), the same build as George's: George's `/Applications/HITList.app`
is TestFlight 0.9.0 (20), and the iPad-on-Mac setting is off. So the differences come from the friend's Mac, not
our build. The most likely cause is **the OS**. George is on **macOS 26.7.1**, and every Mac check in rounds 1–15
ran there. If the friend's "latest macOS" is macOS 27, nobody has ever seen HITList on it. Every round-15 toolbar
and sidebar choice (brief 66's `sharedBackgroundVisibility(.hidden)`, the drawn "+", the sidebar search) was tuned
on 26 only. **First ask George for:**
- the friend's macOS version (Apple menu → About This Mac);
- his Accessibility → Display settings (Reduce transparency, Increase contrast);
- his Appearance accent and highlight colours.

The differences, friend's against ours:
- **Sidebar shape.** Ours floats as a rounded, inset glass panel. His runs flush to the window's left and top edges,
  and its sidebar toggle sits in a filled grey circle.
- **Selected row.** Ours is an accent-filled "Today" row. His is grey, while the Search field holds the focus (blue
  ring) at launch. A sidebar list that isn't the first responder draws its selection unemphasized (grey). So **the
  Search field taking focus at launch** may be a real bug on his OS, and our side can fix it whatever the cause.
- **Toolbar.** Ours draws the view-options pill as an outline on a darker neutral toolbar band. His draws it filled
  grey, with no separate toolbar band (the toolbar takes the content's slate colour). His "+" sits closer to the
  window's right edge. His bolt is yellow because his sync is on; ours was a sync-off Debug run.
- **"Overdue" header.** His has a dark band behind it and a rule under it that runs the full window width. The
  "Nov 9, Monday" header below it has neither. We have no screenshot of our Overdue section on 26.7.1: take one
  (`-seedDemoData` has overdue tasks, or move a task's date back) before deciding whether this is his OS or ours.
- **Label colour.** His `@flipboard` labels are green; ours are grey. Check whether his label simply has a colour
  set, or whether a label's colour comes out differently there.

If it is macOS 27, the honest options are:
- George updates his own Mac to the same version (then the supervisor's window-shot checks run on it too);
- or a session gets a macOS 27 VM (Virtualization.framework on Apple silicon);
- and in either case we fix what reads wrong there.

Only a tester on macOS 27 can confirm a fix.

**2. Switchboards (a data-model change).** Today a switch isn't a model of its own. It's an open recurring task with
no time of day and the `flipboard` label (`HITListCore/.../FlipboardSwitch.swift`; `TaskItem.flipTarget`, `flipCount`,
`flipPeriodStart`; app rules in `Views/Flipboard/FlipboardRules.swift`). A red switch shows in Today and the Inbox
(round 13's rule, SUPERVISOR §7). George's notes change three things:
- **Lists.** By default a switch never becomes a task: it stays on the board, green or red, unless "overdue becomes
  task" is on.
- **Time of day.** Switches can have one. Today's membership rule excludes a timed task (`!hasDueTime`).
- **Switchboards.** Named groups of switches ("Before Bed", "Deep Clean"), daily or weekly, with a reset time ("every
  day at 4am").

This needs **schema V6**, additive only, with every new optional field in `-seedSampleData` (`CloudKitSchemaTests`).
George must deploy the task container's schema before the build that needs it. Settle these with George in one
question round before the brief:
- Is "overdue becomes task" per Switchboard, per switch, or both?
- Does a switch belong to exactly one Switchboard, with an unboarded default?
- Is a switch's time a reminder, or only part of its reset or due rule?
- Do existing switches move into one default Switchboard?

Give the brief alone the Flipboard and the model (xhigh).

**3. Quick add: "every month on the 28th"** and related phrases ("on the 28th of every month", "monthly on the 28th",
"every 28th", "every other month on the 15th", "every first Monday", "every last day of the month", "every year on
Mar 3"). Start with a failing test per phrase, to find out which ones already parse. This goes in `HITListCore` `QuickAddParser.swift` and `RecurrenceRule.swift`. Monthly rules already keep an
anchor day (§7: monthly repeats keep their original day). Highlights come from the parser's ranges
(`TokenHighlightField`). High effort, core first, so it merges first.

**4. Browse.**
- The bottom button hides behind the home indicator again. `Views/Tabs/BrowseView.swift`; find out which round's
  change brought it back, and pin the fix with a UI test.
- Swipe left to delete a Group, through the same delete path and confirmation the Group's own menu uses. A Group's
  deletion syncs to every device, as the user intends. Never use a delete as a reset.

**5. The bolt's twirl.** In `HITList/Support/BoltSlamMotion.swift` the `twirl` track is an in-plane rotation (360° ×
`turns` during the hop). George means a spin like a coin, about the vertical axis: half-way through, the bolt is
edge-on and nearly invisible. In SwiftUI that's `rotation3DEffect` about the y axis, with a little perspective.
Keep the crouch, hop, hang, slam, warp and sparks exactly as they are (George: "almost perfect"), the 0.8 s length,
the high frame rate, and the rare gate. A small brief (high).

## Supervisor work in this round (not a session's)
- **Notes without a new version.** What's New entries are keyed by version (`WhatsNew.swift`; `SettingsTests` pins
  "0.9.0"), so a build 21 of 0.9.0 would show the friends 0.9.0's list again. Before the first build-only release,
  key the newest entry by build (for example "0.9.0 (21)"), or show it by build. Give `CHANGELOG.md` a heading per
  build under `## 0.9.0`. Fix the pin, and decide whether `release.sh` stamps that heading.
- **Housekeeping George hasn't answered yet.** 14 finished round-15 worktrees (about 13 GB, all merged) are under
  `.claude/worktrees/`; remove them only on George's yes. Side stores to delete by hand in Finder are listed in the
  0.9.0 hand-over (`~/Library/Group Containers/UC8N98H3RT.com.trammells.hitlist/`, names starting `HITList-s6`,
  `HITList-s15`, `HITList-s70`, `SharedTasks-s64a/b.json`). Listing that folder from a shell hangs.
- **Round 15's leftovers** (COMMON's Round 15 record):
  - The iPhone's top-right pill is about 4 pt wider on the Flipboard. iOS 26 sizes a toolbar menu by its glyph.
  - With a hardware keyboard, the editor's date card may not open while the title is typing.
  - Two different Apple accounts sharing tasks is untested.

## Rules (into SUPERVISOR §7 when the round merges)
- The version stays 0.9.0 until George says otherwise; each release is a new build of it.
- Switches are routines first: by default they never appear as tasks; "overdue becomes task" opts in. Switchboards
  group them. The Flipboard is a calm status check, not a second to-do list.
- The bolt's twirl is a spin about the vertical axis (edge-on half-way); the slam is kept as it is.

## The round as briefed (Fable 5.2 supervisor, 2026-11-10)

George: the friend is on macOS 27.2 ("we should still be able to prepare for that, no? In any case, please work
freely and prepare a new minor build of the app"). Four sessions at once, all Opus 5.5, cut from master after this
commit; the next upload is 0.9.0 (21).

| Brief | Session | Effort | Owns, in short |
|---|---|---|---|
| 70 | `mac-chrome-27` | xhigh | The Mac window draws or pins everything macOS decides by version: launch focus, sidebar rows and selection, toolbar background, the pill, the sidebar toggle |
| 71 | `quick-add-monthly` | high | "every month on the 28th" and its relatives in core's parser and `RecurrenceRule`; the Repeat card's words |
| 72 | `switchboards` | xhigh | Schema V6 (`Switchboard`), switches that are never tasks by default, times, reset times, the Flipboard's sections and cards |
| 73 | `browse-and-bolt` | high | Browse's last row clear of the island, swipe to delete a Group, the bolt's coin spin |

**macOS 27.** No machine here runs it: George's Mac is 26.7.1, GitHub's runner images stop at macOS 26, and a VM would
need a 15 GB download and George at the keyboard for its setup. Brief 70 therefore removes what the two systems can
disagree about rather than tuning for 27, and lists what the system still decides. The friend's next screenshot (he
gets build 21 at once, as an internal tester) is the check. Still the system's after brief 70: whether the sidebar
column floats (26) or sits flush (27). Owning that means our own split view and top bar, a round of its own.

**Switchboards: the open questions, answered by the supervisor** (George said to work freely; each is marked "choice"
in brief 72, the schema holds every other answer without another deploy, and George may reverse any of them):
- "Overdue becomes task" is on a switch and on a Switchboard; either one opts the switch in.
- A switch belongs to at most one Switchboard; one with none is a loose switch on the main board, as today.
- A switch's time is when the step is due: it shows on the switch, orders the board, decides when an opted-in switch
  becomes a task, and reminds at that time as any timed task does.
- Existing switches stay loose. Nothing is migrated and no default board is created.
- A new Switchboard resets at 04:00 (the friend's example); loose switches keep midnight.

**Notes per build.** `WhatsNew.Entry` gains a build number, `CHANGELOG.md` a `## 0.9.0 (21)` heading that
`release.sh` requires and stamps with the date, and `SettingsTests` fails the preflight when the running build is
newer than the newest entry.
