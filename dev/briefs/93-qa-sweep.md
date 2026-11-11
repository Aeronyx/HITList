# Brief 93: look at every screen as George would (session `qa-sweep`, effort xhigh)

George, 2026-11-11, 03:35, going to bed:

> after you finish reviewing Round 19 and the testing suites, please continue reviewing, improving, and hardening
> HITList until ~8am ET, 85% of my usage limit, or you have truly completed everything worth working on without my
> feedback.

George gives feedback after every build by looking at screens, and scrutinises spacing to the pixel (the checkbox
centred on the title's line, an icon 4 pt from its text, shared left edges, "the kerning is slightly too much, by
like a pixel"). 0.8.0 shipped an Inbox with a name shown twice, two controls that looked alike and two fonts in
one header because nobody looked. Tonight you look, at everything, before he does.

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/SUPERVISOR.md` §7 (the decisions George has made: do not
undo one), `HITList/Support/DesignSystem/README.md` (the components and tokens; custom controls are mandatory),
`dev/briefs/HIG-NOTES.md`, and `HITListUITests/ScreenTourUITests.swift` (it screenshots every main iPhone screen
with demo data: `TEST_RUNNER_HITLIST_TOUR=1`, see its header).

## What to do
1. **Take the pictures.** With `-seedDemoData YES`, sync off, on your own simulators: an iPhone 17, an iPhone 17
   Pro Max, an iPad (11-inch, both orientations) and the iPhone Duo's two displays if the simulator has it
   (`Views/Duo/*` says how it is detected). Every main screen (Inbox, Today, Upcoming, Flipboard with a
   Switchboard, Browse, a Group, the Shared Tasks Group, Search with a query, Completed), every card (quick add
   empty and typed, the editor, each picker, the switch card, Review Inbox), the Settings first screen and each of
   its pages (new tonight), the empty states (a fresh store), a long title that wraps, a task with every kind of
   meta (date, time, repeat, reminder, labels, sub-tasks, Group), Dynamic Type one step up and one down if the
   app follows it. Then the Mac, with your own Debug app (`scripts/window-shot.sh`, `scripts/window-drive.sh`):
   the same screens, the board, the sidebar, each Settings section, a narrow window and a wide one.
2. **Look at each one, enlarged, as he would**, and write down what is off: two left edges a pixel or two apart,
   a gap that differs from its neighbours', a baseline that does not sit on its row's line, text that truncates
   or wraps where it should not, a control that looks like another, a name shown twice, two type roles in one
   header, a colour that is not a token, a default SwiftUI control, a touch target under 44 pt on iPhone, anything
   clipped by the home indicator, the island or a rounded corner, a screen that is wrong only on iPad or only in
   landscape. Measure: say "the label is 3 pt left of the rows' text edge", not "looks a bit off".
3. **Fix what is plainly a defect**, one commit per fix, with the before and after crops. A defect is something
   George would call wrong on sight and that has one right answer under the design system and §7. Anything that is
   a matter of taste, or that changes how a screen works, is not yours to change: list it for George with the
   picture and your suggestion.
4. **Leave it better tested**: where a fix is a number (a padding, a width), pin it in a test if the screen has
   layout tests already; extend the screen tour with any main screen it misses.

## Ownership
Any file under `HITList/Views/` and `HITList/Support/DesignSystem/` for a fix that is a defect by the rule above,
except what others hold tonight: `Views/Companions/*` and `Support/Companions/*` (five sessions), the share
extension's files, `Services/*`, the models, core. Brief 94 (`accessibility`) is adding labels, traits and hit
targets in the same view files while you work: keep each change to the lines it needs so the two merge, and leave
VoiceOver wording and hit-target sizes to it (tell it in your report what you saw). `HITListUITests/ScreenTourUITests.swift`
and a UI test file of your own. Not `scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`, `project.yml` beyond
what `xcodegen generate` needs.

## How to work tonight
Nine sessions share one slow Mac. Build once per platform, keep your simulators shut down when you are not using
them, run the three suites once at the end. Nobody answers questions or system dialogs tonight; never touch
George's `/Applications/HITList.app` or its store; side store `HITLIST_STORE_SUFFIX=s93`.

## Done
The findings as a table: screen, device, what is off (measured), fixed in which commit or left for George and
why, with the crops' paths (put them in the shared notes folder, `93-qa-sweep/`). The contact sheets of every
screen per device after your fixes. All three suites green. The branch name; changelog lines only for fixes a
person would notice.
