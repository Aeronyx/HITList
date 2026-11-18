# Brief 135: Quill's place on the iPhone's theme boxes, and the app's long name (session `small-things`, effort xhigh)

George, 2026-11-14, on 0.9.9 on his iPhone 16:

> Quill is misplaced in Theme menu on iOS

> Make it clear once somewhere in the intro/title menus that the app is actually named "Human-In-The-List" just for
> fun

Read `dev/briefs/COMMON.md` (the Round 27 block first), `dev/briefs/ROUND-27.md`, `dev/briefs/131-swatch-seats.md`
(round 25 put Quill where he is: George had asked for "Quill asleep and almost falling/slumping off the top right
corner"), `Views/Settings/ThemeCompanion.swift` (`seats`, `Placement.overCorner`, `layout`), the swatch in
`Views/Settings/AppearanceSettingsSection.swift`, and the `ThemeCompanion` tests in `SettingsTests.swift`.

## Item 1: Quill
He does not say what is wrong, so **find it in the running app before touching a line** (round 25's lesson: read
the picture before the words). On an **iPhone 16** simulator of your own (`xcrun simctl create HITList-135 "iPhone
16"`: his phone, 393 pt wide; the suites' iPhone 17 is 9 pt wider), Settings → Appearance:
- each of the eight themes selected in turn (the selection ring changes what is around a box; Midnight selected is
  the case round 25's pictures never showed), at the default text size and at two larger ones, by day and with the
  clock forced to night;
- beside the Mac's grid (your Debug Mac app), where he did not complain.
What the supervisor sees in round 25's own picture (`build.noindex/round-25/handover/04-…png` in the main checkout,
`<repo>`): Quill lies above the box's top right corner with 7 pt of him past the edge,
and because the corner is a continuous curve his body is over the curve's empty air: he reads as hovering beside
the box, not draped on it. That may be all of it, or the iPhone may also place him differently from the Mac (a
different side length through `.rounded()`, the ring, the grid's clipping). Report what you found with a picture
at 3x before the fix.

Then put him right: **asleep on the top right corner and sliding off it**. The part of him that lies rests on the
flat of the top edge (left of where the corner starts to curve); what hangs goes down the right side against the
box, following the corner; no gap of more than one sprite pixel between any part of him and the box; clear of the
selection ring's line when Midnight is selected, of Moss's box beside him and of the names under the boxes; the
same on the Mac. Use his own frames (`drape` was added to `Quill.swift` for this in round 25; you may append a
swatch-only frame there, built from his asleep frame with the fewest pixels moved, and nothing else in that file
changes). Pin the result with the seat tests (touching the box, the gap, the ring, the neighbours).

**Picture due 21:00 Eastern**: before and after at 1x and 3x, iPhone 16 and Mac, Midnight selected and not; two
candidates if you are unsure, your pick marked. Send the supervisor its path and carry on; it goes to George at
once.

## Item 2: "Human-In-The-List"
The app has no intro screen. "Once" means one place, met early, that reads as a small smile and not as a banner.
Look at where a person meets the name today (the iPhone's Settings sheet and its About page, the Mac's Settings
page and its About section, the Mac's app menu → About HITList, Browse's profile header) and make two candidates
in pictures, for example:
- A: at the foot of Settings' first screen, where apps keep their version: "HITList · Human-In-The-List" in the
  meta style, the capitals H, I, T, L picked out in the accent;
- B: the head of Settings → About: the app's name with "short for Human-In-The-List" under it.
Pick one, build it on iPhone and Mac in the design system's type (`HITType`, no default control), make sure the
Mac's About panel says it too if the app has one, and send the supervisor both pictures with your pick. One place
in the app's own screens: not a tip, not a toast, not an alert.

## Ownership
`Views/Settings/ThemeCompanion.swift`, what `AppearanceSettingsSection.swift` needs for the sprite's place, a
swatch-only frame appended to `Characters/Quill.swift`, the `ThemeCompanion` tests in `SettingsTests.swift`,
`Views/Settings/AboutSettingsGroup.swift`, `Views/Settings/Mac/MacAboutSection.swift`, and the one place the long
name goes if it is the foot of Settings' first screen (`SettingsView.swift`: only that footer; 136 is adding a
Calendar page to the same file's page list, so touch nothing else there). Not yours: the engine and every other
character file (132, 133, 134), `Services/Calendar`, `Views/Calendar` and General's settings (136), the data and
import groups (137), the sync files and the iCloud page (the supervisor), `scripts/`, `dev/`, `CHANGELOG.md`,
`WhatsNew.swift`, the What's New pin.

## Done (report due 21:30 Eastern)
Both items seen on the iPhone 16 simulator and on your Debug Mac app (`HITLIST_STORE_SUFFIX=s135`), pictures in
`135-small-things/` in the notes folder; `scripts/test.sh macos` and `SIMULATOR=HITList-135 scripts/test.sh ios`
green; the simulator deleted. The report COMMON asks for.
