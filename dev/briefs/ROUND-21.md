# Round 21: 0.9.5, creatures that move like themselves, and the iPhone Duo (2026-11-11, overnight)

0.9.4 (25) is released on both platforms. George's message that evening, verbatim (one screenshot attached):

> Solid work; 0.9.4 released. We have a few creatures to continue iterating on as well as some iPhone Duo bug fixing
> and quality assurance to do.
>
> Please don't be lazy and just have every creature with feet swing their feet as a part of their idle animations;
> the new mushroom creature certainly shouldn't be swinging his feet as he has tiny stubs for feet and it makes no
> sense for his character's vibe anyways. Each animation should match the vibe of its creature. The new mushroom
> should stand fully on top of the search bar and puff around or roll around, doing mushroom-related animations,
> whichever makes most sense for how you imagined his vibe. He's also a bit large and looks kind of creepy.
>
> Then, the new bat-looking creature also looks a bit lazy visually/like a grey blob (he's not too bad though) and
> doesn't need to be hanging his feet over the search bar either. His tail also should be behind the search bar/Add
> task button, not in front of it. It seems this turn you're starting to realize that these creatures can sit both
> in front of and behind certain elements on the Z-axis, making them feel more real, which is great (but no need to
> overdo it). Of course, some characters should definitely still hang down such as the creature with the long ears
> (Hush?) and the original sleepy creature and maybe a few others, but each character's positioning and idle
> animations should actually make sense with/act as flavor for that creature.
>
> Please display creature names next to/under each Theme name in small font or even next to the creatures
> themselves. Whichever will look best.
>
> My friend on his iPhone duo has noticed several screens that are poorly designed for his phone, including lots of
> overlapping text, poorly spaced buttons and symbols, and even overlapping menus (screenshot attached). It looks
> pretty bad indeed, but we haven't focused on the iPhone duo in a while either. Please take a pass in the simulator
> and both clean up the Duo version of the app as well as having the confidence to move/reorganize certain buttons
> or features to improve the user experience as you see fit (but don't feel the need to rerun rigorous tests for
> every version unless required).
>
> Work freely overnight and create build 0.9.5 when ready. Ensure this is a solid build.

## The screenshot (in words; the file is `round-21/george/duo-outer-flipboard.png` in the shared notes folder)
The Duo's outer display (about 466 × 678 pt), the Flipboard with no switches, on 0.9.3 or 0.9.4's predecessor: the
large title and the bolt at the top; the old empty page (a symbol, "No Switches Yet", two paragraphs that wrap to
eleven lines, a green "Add a Switch", a plain "New Switchboard"); and down the trailing edge the system's bar
column: the camera island with a call running, the time, the battery ring, then **the speaker button of the
Flipboard with the tab island drawn over its lower half** (whatever else belongs in that group of controls is
under the island), the island (Inbox, Today, Upcoming, Flipboard) and the upright "+". On the left edge a small
grey handle with a chevron, which is the system's.

## What the supervisor saw first (the simulator, 0.9.4, the outer display, before any session)
`round-21/duo-walk-before/` in the shared notes folder: brief 93's walk of every screen (81 pictures), run on a
folded iPhone Duo simulator. The simulator boots folded, so the outer display needs no Device Hub.
- **The bar column overflows.** Status, then our toolbar items as the system stacks them, then our island and the
  "+" from the bottom: on every pushed screen (Back and two controls) the pill's lower control is drawn on the
  island's top cell, and with a call in the camera island the same happens on every first screen (the friend's
  screenshot).
- **Our content under the system's clock and battery**: Upcoming's week strip and Browse's saved filters scroll
  sideways into the column.
- **Cards that do not fit a 678 pt display**: quick add's date picker shows no grid at all, the editor's is cut top
  and bottom, the reminder picker starts off the left edge, a switch card with its Discard question loses its
  title off the top.
- A row's Group cut to one letter ("W"); at XL the island's labels are wider than the island and Settings' second
  lines are cut.
- The inner display was not looked at (it needs Device Hub's fold): brief 108 starts there.

## Sessions (all Opus 5.5; six at once)
| Brief | Session | Effort | What |
|---|---|---|---|
| 103 | `button-stands` | xhigh | Button redrawn small and sweet, standing on the bar, with a mushroom's idles (the roll, the puff) |
| 104 | `gargle-perched` | xhigh | Gargle carved and perched, his tail behind the bar; the format's "behind the host" layer |
| 105 | `cast-flavor` | xhigh | Nod, Quill, Tuck, Hush, Glim and Phase: every idle judged against who the creature is |
| 106 | `duo-column` | xhigh | The Duo's outer display: the bar column (controls, island, "+"), the lists, Browse, the Flipboard |
| 107 | `duo-cards` | xhigh | The Duo's outer display: quick add, the editor, pickers, cards, Settings and its pages, sheets |
| 108 | `duo-inner` | xhigh | The Duo's inner display: the sidebar shell, the editor column, the board, landscape, half open |

xhigh for all six: three are drawing work that George judges by eye (this afternoon's first attempts at the highest
effort still needed sending back), three are multi-screen layout work on a device nobody has looked at in a week.
Nothing tonight touches stored data, so none is max.

## The supervisor's own
- Each creature's name under its theme in Settings (`AppearanceSettingsSection.swift`, `ThemeCompanion.swift`).
- The merge, the three suites, the UI suite on the merged tree, a Release archive and export of both platforms
  (no upload), the screenshot pass on an iPhone 16, the Mac and the Duo, `## 0.9.5`, `Entry(version: "0.9.5")`,
  the pin, the record, and the hand-over with `scripts/release.sh --version 0.9.5 --quick`. "Create build 0.9.5
  when ready" is read as every earlier round's hand-over (George runs the release; `dev/SUPERVISOR.md` §1): the
  build is made ready and proven to package, and the upload is his command.
