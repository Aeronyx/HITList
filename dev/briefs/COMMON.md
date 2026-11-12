# HITList: facts every delegated session must read first

HITList ("Human-in-the-List") is George's personal Todoist-style task app: SwiftUI multiplatform
(iOS 18+, macOS 15+), SwiftData with CloudKit private database `iCloud.com.trammells.hitlist`,
pure-Swift package `HITListCore` (filter query language, quick-add parser, autocomplete, recurrence,
snapshot JSON; 43 XCTest tests) and app test bundle `HITListTests` (in-memory container, hosted in the
app, runs on iOS simulator and macOS; 21 tests). Build 1 (0.1.0) is on TestFlight on George's iPhone 16
and Mac. George uses it daily as their primary task app and will later share it with friends.
`dev/ROADMAP.md` is the plan. Dark slate theme only, never light mode (`HITList/Support/Theme.swift`:
`Theme.background/surface/elevated/separator/accent/secondaryText`, `slateList()`, `slateRow()`,
`slateSheet()`; `HITList/Support/Formatting.swift` has priority colours and `DueFormatter`).

Data layer (already on master): `HITListSchemaV1` versioned schema + `HITListMigrationPlan`
(`HITList/Models/SchemaVersions.swift`; read its header rules before touching any `@Model`;
`SchemaTests` pins entity hashes and fails on any shape change). `Deduplicator` runs at launch and
2 s after each successful CloudKit import, triggered by `Notification.Name.cloudKitImportSucceeded`
posted from `CloudSyncMonitor.record`. `SeedIdentity` (HITListCore) gives seeded records stable ids.
The store lives in the App Group container (`HITList/Support/AppGroup.swift`; `AppGroup.defaults` for
settings; `ModelContainerFactory.groupStoreURL`). `HITList/Support/Debouncer.swift` exists.
`TaskActions` (create, toggleCompletion with recurrence roll-over, reschedule, delete, seeding).

## Environment (each of these cost hours to learn)

- Every xcodebuild / swift / xcrun command needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (xcode-select points at CommandLineTools). Xcode 27.2, macOS 26.7.1.
- The Xcode project is generated: edit `project.yml`, run `xcodegen generate`; never hand-edit the
  xcodeproj. `HITList/HITList.entitlements` is generated from `project.yml`;
  `HITList/HITList-macOS.entitlements` is hand-maintained. Do not add entitlements unless your brief
  says so. Never add `com.apple.developer.icloud-container-development-container-identifiers`.
- Always build signed (`-allowProvisioningUpdates`); unsigned builds crash in CloudKit.
  Simulator: `-destination 'platform=iOS Simulator,name=iPhone 17'`. Mac: `-destination 'platform=macOS'`.
- Tests: `cd HITListCore && swift test`; app tests: `xcodebuild test -project HITList.xcodeproj
  -scheme HITList -destination 'platform=macOS' -allowProvisioningUpdates` (and the simulator destination).
- Logs: `/usr/bin/log show --info --last 5m --predicate 'subsystem == "com.trammells.hitlist"'`.
  Plain `log` is a zsh builtin and prints nothing; `--info` is required. Categories: sync, storage, dedupe.
- CloudKit.framework is linked explicitly on purpose (macOS 26 sandbox bug) and
  `CloudSyncMonitor.refreshAccountStatus` is a real CKContainer call for the same reason. Keep both.
- Production CloudKit schema is additive-only forever. Never rename/delete/retype a field.
- The real Mac store: `~/Library/Group Containers/UC8N98H3RT.com.trammells.hitlist/HITList.store`.
  Copy it before any destructive test. Never call `ModelContainer.deleteAllData()`; never delete
  objects as a "reset": deletions mirror to CloudKit and wipe every device.
- `scripts/release.sh` uploads to App Store Connect: never run it, never edit it.
- The home-server backup prototype (`server/`, `BackupService.swift`) was removed on 2026-11-05; do not rebuild it.
- Work in the git worktree you were started in, on its branch. Commit per sub-item with clear
  messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push, do not
  open a PR, do not merge, do not switch branches. Touch only the files your brief lists; another
  session is editing the rest of the app at the same time.
- George reads instructions only in chat. Anything they must do goes in your final message with exact
  commands or click paths. Write no documents except the dev/ROADMAP.md status row your brief names.
- Final message always includes: what changed per commit, test counts before/after, how you verified
  it running (simulator and/or Mac), the branch name, and anything George must do.

## How sessions run (from 2026-11-04, round 9)
Sessions are Claude Code sessions the desktop app starts from the supervisor's session (an Opus 5.5 session
following `dev/SUPERVISOR.md`) on George's subscription: each in its own git worktree on a branch named after its
brief, cut from master. The supervisor reads each final report, merges, tests and prepares the release; George
runs `scripts/release.sh`. TestFlight build 14 (0.4.1) is live on George's devices and about to go to friends as
external testers; the next upload is 0.5.0 (15). Production's CloudKit schema is V3 (deployed 2026-11-03);
session 34 adds V4 (`Profile`), which George must deploy to Production before 0.5.0 uploads.

**Your own simulator.** Several sessions run at once and the shared "iPhone 17" simulator would get every
session's build installed over the others'. Make your own at the start and delete it at the end:
`xcrun simctl create "HITList-NN" "iPhone 17"` (NN = your brief number; it prints the UDID), boot it, build with
`-destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath build.noindex/sim`, launch it with the iOS
Simulator tool using that UDID, and run iOS tests as `SIMULATOR=HITList-NN scripts/test.sh ios`. When done:
`xcrun simctl shutdown <UDID>` then `xcrun simctl delete <UDID>`, and say so in the report. Never touch another
session's simulator, never quit George's `/Applications/HITList.app`, and quit any Debug Mac app you started.

## Round 25 (2026-11-12, late afternoon; briefs 127–131 in parallel, all five at once; `ROUND-25.md` says why)
0.9.8 was prepared and not released; this round is **0.9.9**: a reminder a friend could not set from the editor, a
gryphon cub in Gargle's place, Phase's black eyes, Nod's canopy without its handle, Tuck asleep with a mouth, and
new seats on the theme boxes in Settings. Sessions are Opus 5.5 (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. George has the build in hand and is not waiting:
nobody waits for him, and the supervisor forwards your sheet to him the moment it arrives. **No schema change.**
- **Gargle is Flint.** Renamed on master before you were started: `id: "flint"`, `Characters/Flint.swift`,
  `CompanionFlintTests.swift`, `-companion flint`. Notes-folder paths with "gargle" in them are old folders and
  keep their names.
- **The rule of five rounds: change the least that answers his words.** Of 0.9.8 he wrote: "Hush, Quill, Glim, and
  Button are all looking good along with the new weather effects"; of Phase "The other opacity and design changes
  you made for him are great"; of Tuck "I just want him to look at peace". So outside what your brief names, no
  pixel of any frame changes, and your report says none did. Judge every change **at 1x beside 0.9.8's frame**
  (master as you were cut from it) and beside the build he names.
- Ownership (a creature session owns its characters' files, their own test files and their own cases in the shared
  companion tests; nothing else): 127 `phrases-on-a-task` the quick-add parser, the task editor's title and every
  parser call site its brief lists, with their tests. 128 `flint` `Characters/Flint.swift`, `CompanionFlintTests`,
  the one comment in `CompanionCast.swift`. 129 `phase-eyes` `Characters/Phase.swift`, `CompanionPhaseTests`,
  Phase's cases in `CompanionLightTests`. 130 `nod-tuck` `Characters/Nod.swift`, `Characters/Tuck.swift`,
  `CompanionTuckTests`. 131 `swatch-seats` `Views/Settings/ThemeCompanion.swift` (every seat, Flint's and Tuck's
  included), what `AppearanceSettingsSection.swift` needs for a sprite to hang outside its box, the `ThemeCompanion`
  tests in `SettingsTests.swift`, and swatch-only frames appended to `Quill.swift` and `Glim.swift`. **Nobody
  touches the engine** (`CompanionCharacter.swift`, `CompanionSprite.swift`, `CompanionPerch`, `CompanionDirector`):
  if you think you must, stop and tell the supervisor. In a shared test file change only the lines that name your
  creature. Nobody: `scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`, the What's New pin, the models' shape.
- **Everything in Round 24's block below still holds**: the water recipe (three inks `p h u`, beads that stay, a
  puddle on the flat of the "+", a drop that runs off, every whole rain frame carrying the water, blue only, a
  rain still asleep), no open eye is a single pixel, the large round black eye with a glint is Button's alone, a
  real glow only where a brief says, the format's limits (20 × 20, 4 to 6 own inks, accent and warm never both, a
  small gesture changes 16 pixels at most, a frame drawn nowhere is an error), original characters only.
- **The clock**: your brief names when your sheet and your report are due, counted from your start
  (`TZ=America/New_York date`). Work in the brief's order, commit each item as it becomes whole; ten minutes before
  the report time stop starting things, run your tests, write the report. Fewer moves, all good, beats many.
- **The sheet**: small, and at real size: before and after at 1x, 2x and 3x on the "+" in the creature's own theme
  and once on the Mac's field. Send the supervisor its path and your pick with one line of why
  (`mcp__ccd_session_mgmt__send_message`, `session_id: "parent"`), and carry on with your pick; the supervisor
  stops you only if it is wrong. The supervisor may send you rows it has drawn itself: they are the starting
  point, not a suggestion.
- **Tools**, in the shared notes folder: `round-25/draw/kit.py` (rows to a picture on a "+" at 1x to 3x, water inks
  included), `view.py <Swift file> <theme> <seatRow> <out.png> frame…`, `cast.py <out.png> Name:theme:seatRow:frame…`
  (several creatures side by side, each in its own theme: the line-up); `round-25/cast-rest.png` and
  `round-25/settings-grid-0.9.8.png` are what the supervisor looked at. Earlier workshops are there by brief
  (`116-glim-subtle/workshop/carry.py` stamps touches onto every frame without moving a pose, `plays.py` and
  `ticks.py` say what still plays in a weather; `121-phase-ether`, `122-tuck-rest`, `123-quill-nod`,
  `124-gargle-button-rain` hold round 24's generators). Themes and seat rows: slate nod 17, graphite flint 18,
  midnight quill 16, moss tuck 20, nord hush 17, tokyo glim 15, mocha phase 20, rose button 19.
- **The machine**: creature sessions (128, 129, 130) draw first, build little and use no simulator: one
  `scripts/test.sh macos` at the end, one look in a Debug Mac app of your own with `HITLIST_STORE_SUFFIX=sNN` if
  the clock allows (build it with `-derivedDataPath build.noindex/mac-sNN`, `open -g -n`, quit it by its pid,
  never George's `/Applications/HITList.app`). 127 and 131 each make one simulator of their own (`HITList-NN`),
  boot it only when they first need it, and delete it at the end. Find your own processes with `pgrep -x HITList`,
  never `pgrep -f`. Your pictures go in a folder named after your brief in the notes folder. Never push or merge.

## Round 24 (2026-11-12, midday; briefs 121–126 in parallel, all six at once; `ROUND-24.md` says why)
0.9.7 was prepared and not released; this round is **0.9.8**: rain that is rain, a ghost you can see through, eyes
that are not dots, and Switchboards in rows. Sessions are Opus 5.5 (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. George is awake and has said "Please work freely":
nobody waits for him, and the supervisor forwards your sheet to him the moment it arrives. **No schema change.**
- **The rule of four rounds: change the least that answers his words.** A creature George has seen is his. Of
  0.9.7 he wrote "Glim: done", "Hush: done for now", "Button: done for now", "Gargle: much better. Can be largely
  left alone", "Phase: almost there … I really do like him so don't ruin him please", "Tuck: almost done", "Be
  careful with Nod too please as I love his character and he's essentially done apart from his eyes". So: outside
  what your brief names, no pixel of a plain, heat, snow or asleep frame changes, and you say in your report that
  none did. Judge every change **at 1x beside 0.9.7's frame**.
- Ownership (a session owns its characters' files, their own test files, their own line in `ThemeCompanion.seats`
  and their own cases in the shared companion tests; nothing else): 121 `phase-ether` `Characters/Phase.swift`,
  **the engine** (`CompanionCharacter.swift`, `CompanionSprite.swift` and what the glow and the fade need in
  `CompanionPerch`/`CompanionDirector`; nobody else touches these) and the one `glow:` argument of Glim's
  `CompanionCharacter(` call. 122 `tuck-rest` `Characters/Tuck.swift`. 123 `quill-nod` `Characters/Quill.swift`,
  `Characters/Nod.swift`. 124 `gargle-button-rain` `Characters/Gargle.swift`, `Characters/Button.swift`, and the new
  placement in `Views/Settings/ThemeCompanion.swift` with its tests. 125 `hush-glim-rain` `Characters/Hush.swift`,
  `Characters/Glim.swift` (its frames and modes; not the `CompanionCharacter(` call's arguments). 126
  `flipboard-rows` `Views/Flipboard/*`, the Flipboard's tests and UI tests. In a shared test file change only the
  lines that name your creature. Nobody: `scripts/`, `dev/`, `CHANGELOG.md`, `WhatsNew.swift`, the What's New pin,
  the models' shape.
- **Water, for every creature session.** George: "Their rain interactions don't make much visual sense, as the rain
  is both not blue enough to be clear that it's rain and also many of the characters don't even get rain on them to
  begin with. During rain, they should have little droplets bead off of them every once in a while, and have some
  droplets stick around or tiny puddles pool around their feet so it's clearer why they're cowering/hiding." Three
  inks are on master for it, the same in every theme, never see-through, not counted among a creature's 4 to 6
  colours: `p` water, a clear rain blue (#4CA6FF); `h` its glint (#DDF1FF); `u` its deep tone (#1F6FE0)
  (`CompanionInk.water`, `.waterLight`, `.waterDeep`; add them to your workshop's palette). What each creature does
  about the rain (round 23: Nod's umbrella, Gargle's wing, Button's cap, Quill's tail, Hush's hood, Glim's lantern
  in his lap) stays; the water is why it does it. In every rain still, awake and asleep, both places:
  1. **Wet.** Two to four beads that stay: single `p` pixels (one that hangs is two tall, `p` over `u`; where the
     light catches, `h` over `p`) where water would sit or hang: along the top of what shelters it, on a brow, a
     nose, an ear tip, a shoulder, a rim. Not in a row, not mirror-symmetric, never on an eye or a mouth, never on
     a pixel a blink, a glance or the reply to a tap changes (a gesture plays over the rain still only where it
     leaves the still's own pixels alone: after your change the blink, the reply to a tap and most idles must still
     play in the rain; say which no longer do).
  2. **A puddle at its feet.** On the surface it sits on (the last row above `seatRow`), beside or around its
     feet: four to eight pixels wide and one high (two where it pools), `p` with one `h` glint and a `u` pixel at
     an end or in the creature's shadow, its ends ragged. A puddle, not a plinth: never a band under the whole
     creature, never wider than the creature, no pixel hanging in the air past the shoulder of the "+" (look on the
     real "+" profile, `CompanionSeatTests` and the workshops model it, and on the Mac's field). Where the creature
     sits is unchanged (`CompanionPerch` lines it up by its plain `rest` frame).
  3. **A drop runs off, now and then.** A gesture with `sky: .rain`, marked `flicker` (asleep every gesture is
     one), under a second: a bead swells at an edge (a rib of the canopy, a wing tip, the cap's rim, an ear, a
     nose), lets go, falls (one drop, `h` over `p` or a single `p`; the only thing ever in the air, and only one at
     a time), lands in the puddle, whose glint jumps or which widens a pixel for a tick, and the still is back. A
     rarer second one may run down the creature itself.
  4. **Nothing blinks out.** Every frame drawn whole for the rain (the rain routines' own frames, gestures with a
     sky) carries the puddle, and the beads where that surface is still there. Stamp them with a script.
  5. **Blue only.** No drop anywhere is left in `l`, `m`, `a`, `w` or a snow ink: recolour the ones already drawn.
  6. **Asleep in the rain** every creature has a still of its own (`Mode(rain:)` in the asleep mode; today only Nod
     has one): the asleep pose, sheltered its own way where that makes sense asleep, beads, the puddle, and the
     drop that runs off, slower.
  7. It must read at real size: on the "+" and on the Mac's field at 1x, beside 0.9.7's rain still, a stranger
     says "it is raining on it". Snow is not touched this round except where a brief names it.
- **Eyes.** George: "an art style where none of the characters have just single-pixel dots for eyes". No creature's
  open eye is one pixel. Round 22's rule stands: the large round black eye with a glint is Button's alone.
- **A real glow** (121 builds it): a creature may name inks that cast a soft halo of their own colour (Phase's
  eyes, Glim's lantern). Nobody else draws light with it this round.
- **The clock**: your brief names when your sheet and your report are due, counted from your start
  (`TZ=America/New_York date`). Work in the brief's order, commit each item as it becomes whole; ten minutes before
  the report time stop starting things, run your tests, write the report. Fewer moves, all good, beats many.
- **The sheet**: small, and at real size. Before and after (0.9.7's frame beside yours) at 1x, 2x and 3x on the
  "+" in the creature's own theme and once on the Mac's field. Send the supervisor its path and your pick with one
  line of why (reply to the message that started you), and carry on with your pick; the supervisor stops you only
  if it is wrong. The supervisor may send you rows it has drawn itself: they are the starting point, not a
  suggestion.
- The supervisor's tools, for any session: `round-23/draw/kit.py` (rows to a picture on a "+" at 1x to 3x) and
  `round-23/draw/view.py <Swift file> <theme> <seatRow> <out.png> frame…` in the shared notes folder; round 23's
  workshops there (`116-glim-subtle/workshop`: `carry.py` stamps touches onto every frame without moving a pose,
  `plays.py`/`ticks.py` say what still plays in a weather; `117-gargle-pup/workshop`, `118-phase-sheet/workshop`,
  `119-tuck-quill/workshop`, `120-nod-button-weather/workshop`).
- Everything in Round 23's and Round 22's blocks below still holds: the format's limits (20 × 20, 4 to 6 own inks,
  accent and warm never both, a small gesture changes 16 pixels at most, a frame drawn nowhere is an error),
  creature sessions build little and use no simulator (one `scripts/test.sh macos` at the end, one look in a Debug
  Mac app of your own with `HITLIST_STORE_SUFFIX=sNN` if the clock allows, quit it and unregister its extensions),
  original characters only, the shared notes folder (your pictures in a folder named after your brief), never touch
  George's `/Applications/HITList.app`, never push or merge.

## Round 23 (2026-11-12, mid-morning; briefs 116–120 in parallel, all five drawing; `ROUND-23.md` says why)
0.9.6 (26) is released; this round is **0.9.7**: the creatures, a third time. Sessions are Opus 5.5 (commits end
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. George is awake and
has said "Please work freely to iterate on these creatures": nobody waits for him, and the supervisor forwards
your concept sheet to him the moment it arrives. **No schema change, no engine change.**
- **The rule this round: change the least that answers his words.** George on 0.9.6: "Hush is actually the perfect
  example of a good rework; you kept his vibe without changing much, just slight improvements to coloration and
  design"; and of a creature redrawn freely: "so much worse". A creature he has seen is his. Start from the
  drawing he likes (your brief names it), keep its outline, its eyes, its size and its pose unless his words are
  about exactly those, and judge every change **at 1x beside the drawing he likes**: if a stranger would say "a
  different creature", it is wrong, however well drawn.
- **Not to be touched by anyone**: `Characters/Hush.swift` ("Keep the new Hush"), Button's plain, heat and asleep
  stills (pinned to `v0.9.4`), Gargle's asleep stills (the night sprite he adores), Nod's plain drawing.
- Ownership (a session owns its characters' files, their own test files, their own line in
  `ThemeCompanion.seats` and their own cases in the shared companion tests; nothing else): 116 `glim-subtle`
  (xhigh) `Characters/Glim.swift`. 117 `gargle-pup` (xhigh) `Characters/Gargle.swift`. 118 `phase-sheet` (xhigh)
  `Characters/Phase.swift`. 119 `tuck-quill` (xhigh) `Characters/Tuck.swift`, `Characters/Quill.swift`. 120
  `nod-button-weather` (high) `Characters/Nod.swift`, `Characters/Button.swift`. In a shared test file change only
  the lines that name your creature.
- **The clock**: your brief names when your sheet and your report are due, counted from your start
  (`TZ=America/New_York date`). Work in the brief's order, commit each item as it becomes whole; ten minutes
  before the report time stop starting things, run your tests, write the report. Fewer moves, all good, beats many.
- **The sheet**: small, and at real size. Each candidate at 1x, 2x and 3x on the "+" in its own theme **beside
  the drawing George likes** and beside Hush, and one on the Mac's field. Send the supervisor its path and your
  pick with one line of why (reply to the message that started you), and carry on with your pick; the supervisor
  stops you only if it is the wrong one.
- **Weather, a little more obvious** (George: "Snow and rain need to be slightly more obvious on most of these
  creatures"): in rain and in snow the creature **does something about it that reads at a glance at 1x** (an
  umbrella held up, a wing held over the head, a cap pulled down, a light kept dry). Round 19's rule still holds:
  the weather shows on the creature and what it holds, never as effects in the air around it; a drop on it or
  running off it is on it. Snow is still round 22's powder in the three snow inks (`s`, `b`, `c`; the recipe is in
  the Round 22 block below), a little more of it at each depth, never a cap. Phase alone stays untouched by both.
- The format's limits you will meet: sprites are 20 × 20; a creature uses 4 to 6 inks of its own (the snow inks
  do not count); the accent and the warm ink never both; a small gesture changes 16 pixels at most; a frame drawn
  nowhere is an error (`problems`). `105-cast-flavor/dump.sh` and the workshops in the notes folder
  (`110-phase-cloth/workshop`, `111-gargle-dragon/workshop`, `112-hush-quill/workshop`, `113-glim-tuck/workshop`,
  `109-button-back/workshop`) render frames on the real "+" profile.
- Everything in Round 22's block below still holds: creature sessions build little and use no simulator (draw
  with the workshops, look at 1x, one `scripts/test.sh macos` at the end, one look in a Debug Mac app of your own
  with `HITLIST_STORE_SUFFIX=sNN` if the clock allows, quit it and unregister its extensions), original
  characters only, the shared notes folder (`round-23/study.png` is the app enlarged, 0.9.5 beside 0.9.6), never
  touch George's `/Applications/HITList.app`, never push or merge.

## Round 22 (2026-11-12, before dawn; briefs 109–115 in parallel, all seven at once; `ROUND-22.md` says why)
0.9.5 was prepared and never released (George: "I'm not quite satisfied with it yet"); this round is **0.9.6**, and
George wants it **by 09:00 Eastern today**. Sessions are Opus 5.5 (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. George is away until then: nobody answers a question or
a system dialog, so decide by your brief and George's words, and write down what you decided. **No schema change.**
- **The clock decides.** Your brief names when your report is due, in Eastern time (`TZ=America/New_York date`).
  Work in the brief's order, commit each item as it becomes whole, and fifteen minutes before that time stop
  starting things: commit what is coherent, run your tests, write the report. An item you did not reach is one line
  in the report, never a rushed half. A report that is late is merged after the build and waits a round.
- Ownership, the creatures (a session owns its characters' files, their own test files, their own line in
  `ThemeCompanion.seats` and their own cases in the shared companion tests `CompanionSpriteTests`,
  `CompanionSeatTests`, `CompanionCastFlavorTests`, `CompanionIdleTests`, `CompanionIslandTests`; nothing else):
  109 `button-back` (high) `Characters/Button.swift` and Nod's snow frames in `Characters/Nod.swift`. 110
  `phase-cloth` (xhigh) `Characters/Phase.swift`. 111 `gargle-dragon` (xhigh) `Characters/Gargle.swift`. 112
  `hush-quill` (xhigh) `Characters/Hush.swift`, `Characters/Quill.swift`. 113 `glim-tuck` (xhigh)
  `Characters/Glim.swift`, `Characters/Tuck.swift`. **Nobody changes the engine** (`CompanionCharacter.swift`,
  `CompanionDirector`, `CompanionSchedule`, `CompanionClock`, `CompanionSprite`, `CompanionPerch`) **or the ink
  table**: if a drawing needs it, send the supervisor one message saying what, and carry on without it. In a shared
  test file change only the lines that name your creature, so the merges stay clean.
- Ownership, the spacing: 114 `card-insets` (xhigh) what opens over a list: `Views/Popouts/*` (quick add, the
  editor, every picker) and `Support/DesignSystem/*`. 115 `screen-insets` (xhigh) the screens and the rest:
  `Views/Tabs/*`, `Views/Duo/*`, the lists and rows, `Views/Flipboard/*` with its cards, Review Inbox,
  `SettingsView` and `Views/Settings/*`, `Views/Help/*`, sheets, toasts, tips.
- Nobody: `scripts/`, `dev/briefs/`, `dev/ROADMAP.md`, `CHANGELOG.md`, the entries in `WhatsNew.swift`, the
  `SettingsTests` What's New pin, the models' shape, `CompanionCast.swift`, `CompanionSky*.swift`,
  `AppearanceSettingsSection.swift`, and in `ThemeCompanion.swift` anything but your own creature's seat.
- **Snow, for every creature session.** George: "The snow effects just looks like hats for many characters
  (especially Quill). Fix it to look more like powdery, pixelated fallen snow than just white globs. Be artistic
  with the pixelated snow and add some blue hues to make it look professional." Three inks are on master for it,
  the same colours in every theme and never see-through: `s` the lit crest (#F3F7FF), `b` the powder's body, a pale
  blue (#BFD2F4), `c` its shaded side and lone flecks, a deeper blue (#8CA5D8) (`CompanionInk.snow`, `.snowBlue`,
  `.snowShade`; add them to your workshop's palette). Redraw every snow still of your creatures (`snow`, each
  `snowDeep`, awake and asleep, both postures, and whatever is carried or drawn onto them) to this recipe:
  1. Snow lies where it would fall and stay: on what faces up (a crown, the tops of ears and horns, shoulders, a
     back, the upper side of a tail, a rim), thinner on a slope than on a flat, deepest in a hollow (between two
     ears, the crook of a tail). None on a vertical side or under an overhang. The creature's outline stays the
     creature's: ear tips, horns and the curve of a head still show at every depth.
  2. Powder, not a cap: the first still is a dusting one pixel deep with gaps in it (never one unbroken band from
     side to side) and a fleck or two lower down (a shoulder, a cheek, a foot). Each deeper still adds unevenly, a
     drift to one side, up to three pixels at the deepest. The lower edge is ragged, single pixels stepping down
     into the creature: never a straight rim, never mirror-symmetric.
  3. Three tones in every still: `s` only along the top where the light lands, `b` under it, `c` on the lee side,
     under a ledge of snow and for the flecks; where the snow thins it breaks into a checker of `b` or `c` and the
     creature's own colour. No block of one snow ink larger than 2 × 3 pixels.
  4. It must read at real size, on the "+" and on the Mac's search field, as "snow has fallen on it", and never as
     headgear: put it beside the 0.9.5 still (the old white cap) at 1x, 2x and 3x and look.
  What a creature does about its snow (its shake-off, a heap that slides off) stays its own, redrawn over the new
  pile. The old snow used the creature's own light ink `l`; none of that is left when you are done.
- **Eyes.** George: "I don't love that three of the characters have the same style of large black eyes (the bat,
  the mushroom and Mocha); they fit best on the mushroom". The large round black eye with a glint is Button's
  alone from now on; every other creature has eyes of its own. His standard is unchanged: a face that looks at
  you, a light in each eye ("soulless" is his word for eyes without one), cute beside Hush.
- **Original characters only** (`dev/SUPERVISOR.md` §7): nothing that is, or could be mistaken for, a character
  someone else owns.
- **Creature sessions build little.** Draw with the workshops in the shared notes folder (python:
  `105-cast-flavor/workshop`, `103-button-stands/workshop`, `104-gargle-perched/workshop`, `101-phase/workshop`,
  `102-rose-and-graphite/`, `84-companion-routines/workshop`; `105-cast-flavor/dump.sh` and each README say how),
  look at your sheets at real size and enlarged, and use no simulator. Near the end build once and run
  `scripts/test.sh macos` (every companion test is in it); one look at your creature in a Debug Mac app of your
  own on the search field (`HITLIST_STORE_SUFFIX=sNN`, `-disableCloudKit YES -ApplePersistenceIgnoreState YES
  -hideTips YES -companion <id>`; `scripts/window-shot.sh`) if the clock allows. The supervisor runs the iOS suite
  and the UI suite on the merged tree.
- **Spacing sessions**: a Duo simulator of your own (`xcrun simctl create "HITList-NN" "iPhone Duo"`, it boots
  folded on the outer display; `xcrun simctl io <udid> screenshot --display=primary <file>`) and an iPhone 16 of
  your own (`HITList-NN-16`), **one booted at a time**; an iPhone 17 (`HITList-NN-17`) for `scripts/test.sh ios`
  at the end. Delete all three when you finish.
- **The shared notes folder** (outside git):
  `/Users/gtrammell/Library/Application Support/Claude/side-session-notes/local_8995b93d-4779-400a-855f-77db7b4e0b1d/`.
  Your pictures go in a folder named after your brief (`110-phase-cloth/`). `round-22/george-saw/` holds the eleven
  pictures of 0.9.5 that George judged.
- **A message to the supervisor** is for what your brief asks for (a concept sheet's path and your pick) or for
  something that blocks you: reply to the message that started you, and carry on meanwhile. The supervisor looks
  at every concept sheet at real size and stops you only when the pick is wrong.
- Everything in Round 21's block below still holds: pictures are part of the work, George's phone is an iPhone 16,
  seven sessions share one Mac (your own derived data in your worktree, your own side store), the CI runner's older
  Swift, no session answers a system dialog, never touch George's `/Applications/HITList.app` or its store, quit
  what you started.

## Round 21 (2026-11-11, overnight; briefs 103–108 in parallel; `ROUND-21.md` says why)
0.9.4 (25) is released; this round is **0.9.5**. Sessions are Opus 5.5 (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. George is asleep while you work ("Work freely
overnight"): nobody answers a question or a system dialog tonight, so decide by your brief and George's principles,
and write down what you decided. **No schema change this round**, in SwiftData or in CloudKit: a fix that needs one
stops and reports.
- Ownership, the creatures: 103 `button-stands` (xhigh) `Characters/Button.swift` and its tests. 104
  `gargle-perched` (xhigh) `Characters/Gargle.swift` and its tests, and a "behind the host" layer in the format (the
  frame parsing and `problems` in `CompanionCharacter.swift`, `Views/Companions/CompanionSprite.swift`, the figure,
  seat and tap area in `CompanionPerch.swift`). 105 `cast-flavor` (xhigh) `Nod`, `Quill`, `Tuck`, `Hush`, `Glim`,
  `Phase` and their tests.
- Ownership, the iPhone Duo (George's friend uses one; `round-21/george/duo-outer-flipboard.png` in the shared
  notes folder is his screenshot, `round-21/duo-walk-before/` the supervisor's 81 pictures of 0.9.4 on the outer
  display): 106 `duo-column` (xhigh) the outer display's shell: `Views/Tabs/*` (`MobileShell`, `MobileTabBar`,
  `ScreenMenu`, `BrowseView`), `Views/Duo/VerticalBar.swift`, the lists and their rows, the Flipboard's board and
  tiles, the completion toast. 107 `duo-cards` (xhigh) what opens over a list there: `Views/Popouts/*`, the
  Flipboard's cards, Review Inbox, `SettingsView` and `Views/Settings/*`, `Views/Help/*`, the sheets, the tips. 108
  `duo-inner` (xhigh) the inner display: `ContentView.swift`, the rest of `Views/Duo/*`, `SidebarView.swift`,
  `Views/Search/*`, the board, the `.duo` column in `PopoutHost.swift`, and Device Hub (only 108 opens it). Each
  brief's own Ownership list is the contract; these lines are the map.
- **The Duo simulator**: `xcrun simctl create "HITList-NN" "iPhone Duo"`. It boots folded, on the outer display
  (about 466 × 678 pt, the system's bar column down its trailing edge); the inner display (about 669 × 951 pt)
  needs Device Hub's fold (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`; there is no Simulator
  app in Xcode 27). `xcrun simctl io <udid> screenshot --display=primary <file>` (it has two displays, so
  `--display` is required). Brief 93's walk (`HITListUITests/QASweepUITests`, `TEST_RUNNER_HITLIST_QA=1`)
  photographs every screen of whatever it runs on in about sixteen minutes.
- Nobody: `scripts/`, `dev/briefs/`, `dev/ROADMAP.md`, `CHANGELOG.md`, the entries in `WhatsNew.swift`, the
  `SettingsTests` What's New pin, the models' shape, `CompanionCast.swift`, `CompanionSky*.swift`, and the
  supervisor's own tonight: `ThemeCompanion.swift` and `AppearanceSettingsSection.swift` (each creature's name
  goes under its theme in Settings; a Duo session that finds the theme grid wrong reports it instead of editing).
- **The shared notes folder** (outside git; every session can read and write it):
  `/Users/gtrammell/Library/Application Support/Claude/side-session-notes/local_8995b93d-4779-400a-855f-77db7b4e0b1d/`.
  Put your pictures and long tables in a folder named after your brief (`106-duo-column/`). This afternoon's
  reports, pictures and the companions' workshops are there (`100-companions-alive/`, `102-rose-and-graphite/`,
  `84-companion-routines/workshop/`).
- **Six sessions share one Mac** (12 cores, 32 GB; eight at once saturated it this afternoon). Build once per
  platform when you can, prefer `-only-testing` while you iterate, run the three suites once, at the end, and keep
  your simulator shut down when you are not using it. The drawing sessions draw first and build late. Your own
  derived data inside your worktree (`build.noindex/…`), your own simulator (`HITList-NN`), your own side store
  (`HITLIST_STORE_SUFFIX=sNN`). Delete the simulator, quit your Debug Mac app and unregister its extensions
  (`pluginkit -r`) when you finish.
- **How much to test** (George tonight: "don't feel the need to rerun rigorous tests for every version unless
  required", and "Ensure this is a solid build"): look at what you changed where it shows (a Duo session on its Duo
  simulator, and on an iPhone 16 wherever the code is shared with every iPhone), run the three suites once at the
  end, and leave the whole UI suite to the supervisor, who runs it on the merged tree. A UI test of your own goes in
  a file of your own.
- **George's phone is an iPhone 16** (393 × 852 pt); the suites use the iPhone 17 simulator (402 × 874). The Duo's
  outer display is about 466 × 678 pt with the system's bar column on its trailing edge, its inner display about
  669 × 951 pt. Nothing a Duo session changes may make an iPhone 16 or the Mac worse: show the same screen on an
  iPhone 16 before and after wherever shared code changed.
- **Pictures are part of the work.** George judges by looking. Every visible change comes with a before and an
  after at real size, looked at by you, enlarged, as he would: left edges that share a pixel, one size of type
  per role, a control that looks like what it is, nothing on top of anything else.
- **A message to the supervisor** (the session that sent you your brief) is for what your brief asks for (a
  commit's hash, a concept sheet) or for something that blocks you; reply to the message that started you. Carry
  on meanwhile.
- Everything in Round 20's, 19's, 18's and 17's blocks below still holds: the CI runner's older Swift (keep mixed
  `Int`/`Double`/`CGFloat` expressions short, one step per line; guard 27-only symbols with `#if compiler(>=6.4)`),
  data resilience over speed, no session answers a system dialog or changes a system permission, a Debug build
  never asks for the location by itself, never a test that reads the wall clock or the device's time zone without
  injecting it, touch only your own lines of `project.yml`, leave the Debug Mac app's window as you found it, never
  touch George's `/Applications/HITList.app` or its store.

## Round 20 (2026-11-11, afternoon; briefs 95–102 in parallel, all eight at once; `ROUND-20.md` says why)
0.9.3 (24) is released; this round is **0.9.4**. Sessions are Opus 5.5 (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. George said "work freely" and is not watching: nobody
answers a question or a system dialog, so decide by your brief and George's principles, and write down what you
decided. **No schema change this round**, in SwiftData or in CloudKit: a fix that needs one stops and reports.
- Ownership: 95 `sync-truth` (max) `Services/Sync/*`, `CloudSyncMonitor`, `Support/SyncStatusViews.swift`,
  `Views/Settings/ICloudCheck.swift` and `ICloudSettingsGroups.swift`. 96 `flipboard-phone` (xhigh)
  `Views/Flipboard/*`. 97 `repeat-picker` (xhigh) `Views/Popouts/PopoutPickers.swift`, `Views/Popouts/Pickers/*`,
  the repeat chips, the `PickDatePopover` lines, the wording in core's `RecurrenceRule.swift`. 98
  `quick-add-words` (high) core's parser files, new `Views/Help/*`, one "?" in Browse, one row in Settings →
  General, one Help-menu item. 99 `sweep-polish` (xhigh) `ScreenMenu.swift`, `Views/MacChrome/*`, Settings' views
  except 95's and 98's lines, the lists' chrome and headers, the sidebar. 100 `companions-alive` (xhigh) the
  companions' schedule, director and clock, `Views/Companions/*`, `Nod`, `Quill`, `Tuck`, `Hush`, `Glim`. 101
  `phase` (xhigh) a new `Phase.swift`, `Mallow.swift` (deleted), see-through ink. 102 `rose-and-graphite` (xhigh)
  new character files, `Posy.swift` (deleted), `Smudge.swift`. Nobody: `scripts/`, `dev/briefs/`,
  `dev/ROADMAP.md`, `CHANGELOG.md`, the entries in `WhatsNew.swift`, the `SettingsTests` What's New pin, the
  models' shape, `ThemeCompanion.swift`, `CompanionSky*.swift`.
- **The shared notes folder** (outside git; every session can read and write it):
  `/Users/gtrammell/Library/Application Support/Claude/side-session-notes/local_8995b93d-4779-400a-855f-77db7b4e0b1d/`.
  Put your pictures and long tables in a folder named after your brief (`96-flipboard-phone/`); George's five
  pictures are in `round-20/george/`; last night's reports and the companions' workshop are there too.
- **Eight sessions share one Mac** (12 cores, 32 GB; twelve at once filled the swap last night). Build once per
  platform when you can, prefer `-only-testing` while you iterate, run the three suites once, at the end, and keep
  your simulator shut down when you are not using it. The drawing sessions draw first and build late. Your own
  derived data inside your worktree (`build.noindex/…`), your own simulator (`HITList-NN`), your own side store
  (`HITLIST_STORE_SUFFIX=sNN`). Delete the simulator, quit your Debug Mac app and unregister its extensions
  (`pluginkit -r`) when you finish.
- **George's phone is an iPhone 16** (393 × 852 pt); the suites use the iPhone 17 simulator (402 × 874). Anything
  that must fit a screen is checked at both sizes.
- **Pictures are part of the work.** George judges by looking. Every visible change comes with a before and an
  after at real size, looked at by you, enlarged, as he would: left edges that share a pixel, one size of type
  per role, a control that looks like what it is. A report that says "could not see it running" names an item the
  supervisor must check.
- **A message to the supervisor** (the session that sent you your brief) is for what your brief asks for (a
  commit's hash, a concept sheet) or for something that blocks you; reply to the message that started you. Carry
  on meanwhile.
- Everything in Round 19's, 18's and 17's blocks below still holds: the CI runner's older Swift (keep mixed
  `Int`/`Double`/`CGFloat` expressions short, one step per line; guard 27-only symbols with `#if compiler(>=6.4)`),
  data resilience over speed, no session answers a system dialog or changes a system permission, a Debug build
  never asks for the location by itself, UI tests in a file of your own on a fresh simulator, never a test that
  reads the wall clock or the device's time zone without injecting it, touch only your own lines of `project.yml`,
  leave the Debug Mac app's window as you found it, never touch George's `/Applications/HITList.app` or its store.

## Round 19 (2026-11-11; briefs 82–86 in parallel, all five at once; `ROUND-19.md` says why)
0.9.2 (23) is released; this round is **0.9.3**. Sessions are Opus 5.5 (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. George is asleep while you work: nobody answers a
question or a system dialog tonight, so decide by your brief and George's principles below, and write down what you
decided. **No schema change this round**: a fix that needs one stops and reports.
- Ownership: 82 `time-zones` (xhigh) core's date, ordering and grouping files, a new anchor, `Services/Dates/*`, the
  date-writing lines of `TaskActions`, the "calendar changed" triggers, the Shared Tasks and JSON date lines. 83
  `location-weather` (high) `Services/Weather/*` (with `WeatherSettingsText.swift`), the weather's start-up lines in
  `HITListApp`, the location purpose string in `project.yml`, the privacy page. 84 `companion-routines` (max)
  `Support/Companions/*` and `Views/Companions/*` except what 85 and the supervisor own, `Nod`, `Quill`, `Hush`. 85
  `new-companions` (max) new character files, `Pip.swift` (deleted), `CompanionCast.swift`, the lines that name Pip
  in the companions' tests. 86 `settings-tidy` (xhigh) `SettingsView`, `Views/Settings/*`, `Settings/Mac/*`,
  `DelightSettingsSection`, a new `ThemeCompanion.swift`, the Settings tests and the Settings lines of UI tests.
  Nobody: `scripts/`, `dev/briefs/`, `dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` What's
  New pin, the models' shape, `CompanionSky.swift` and `CompanionSkySource.swift` (the supervisor's: where briefs 83
  and 84 meet; it now carries the place's time zone as well as the sky).
- Added at 02:10: 87 `graphite-companion`, 88 `moss-companion`, 89 `tokyo-companion` (max each; one brief,
  `87-last-three-companions.md`): one new character file each, two lines each in `CompanionCast.swift`, a test file
  each. Brief 85's companions are Posy (Rosé) and Mallow (Mocha). Brief 84's engine commit is on master.
- Added at 02:25: 90 `share-extension` (xhigh): a new `HITListShare/` target, a core outbox, `Services/Share/*`, one
  start-up line in `HITListApp`, one drain line in `WidgetRefresh`, its own target lines in `project.yml`, one
  sentence in the privacy page.
- Added at 03:40 (George: "continue reviewing, improving, and hardening"): 92 `day-anchor-review` (max) core's
  `DayAnchor` and date files, `Services/Dates/*`, the date-writing lines; 93 `qa-sweep` (xhigh) spacing and
  consistency defects in `Views/` and the design system; 94 `accessibility` (xhigh) accessibility modifiers, focus
  and hit shapes in the same view files, and the Mac toolbar's sync bolt. 93 and 94 share view files: each keeps
  its change to the lines it needs. Brief 91 (03:05) adds the weather on the creature to every companion session.
- **The Mac is saturated tonight** (nine sessions, swap full): no baseline suite runs for the three companion
  sessions; everyone else, prefer `-only-testing` while you iterate and run the full suites once, at the end.
- **A Debug build never asks for the location by itself** (brief 83 keeps it so): if a system dialog appears on the
  Mac anyway, leave it, say so in the report and carry on with what does not need it.
- **Five sessions build at once.** Use your own derived data folder inside your worktree (`build.noindex/…`), your
  own simulator (`HITList-NN`), your own side store (`HITLIST_STORE_SUFFIX=sNN`), and expect builds to be slow.
  Delete the simulator and quit your Debug Mac app when you finish.
- Everything in Round 18's and Round 17's blocks below still holds: the CI runner's older Swift (keep mixed
  `Int`/`Double`/`CGFloat` expressions short, one step per line; guard 27-only symbols with `#if compiler(>=6.4)`),
  data resilience over speed, whatever moves by itself is rare, no session answers a system dialog or changes a
  system permission, UI tests in a file of your own on a fresh simulator, `dev/ROADMAP.md` is the supervisor's,
  touch only your own lines of `project.yml`, leave the Debug Mac app's window as you found it, unregister your
  Debug build's widget extension (`pluginkit -r`) when you finish.
- **Do not run a test that reads the wall clock without injecting it** (round 18: a UI test failed only after
  midnight). Tonight's sessions run across midnight and across a day boundary: a test that passes at 23:00 and
  fails at 01:00 is a bug in the test.

## Round 18 (2026-11-11; briefs 79–81 in parallel, all three at once; `ROUND-18.md` says why)
0.9.1 (22) is released; this round is **0.9.2**. Sessions are Opus 5.5 (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. **No schema change this round**: a fix that needs one
stops and reports.
- Ownership: 79 `companion-cast` (max) `Views/Companions/*`, `Support/Companions/*` (not `CompanionSkySource.swift`),
  the perch lines in `SidebarSearchField`, `BrowseView`, `SidebarView` and where the iPhone "+" is drawn. 80 `weather`
  (high) new `Services/Weather/*`, a core file for the sky table, `DelightSettingsSection` (the Extras rows and their
  words), the app's entitlements and one usage string in `project.yml`, the privacy page. 81 `widget-completion`
  (xhigh) `HITListWidgets/*`, `Services/Widgets/*`, core's widget files and a new outbox, `Services/Intents/*`, the
  background-work lines of `HITListApp` and `SyncAppDelegate`, a read-only addition to `CloudSyncMonitor`,
  `project.yml` (background identifiers, files in both targets). Nobody: `scripts/`, `dev/briefs/`, `dev/ROADMAP.md`,
  `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` What's New pin, the models, `CompanionSky.swift` and
  `CompanionSkySource.swift` (the supervisor's: where briefs 79 and 80 meet).
- **The CI runner's Swift is older than yours** (Xcode 26.x on `macos-26` against 27.2 here): 0.9.1's CI failed on
  one long arithmetic expression inside a closure ("unable to type-check this expression in reasonable time"). Keep
  expressions that mix `Int`, `Double` and `CGFloat` conversions short: one step per line, explicit types.
- **George's principle for anything that syncs (2026-11-11): data resilience over speed.** Slow is fine, wrong is
  not; never show a change as finished before it is safe.
- **George's principle for anything that moves by itself: rare.** People live in this app for hours; whatever
  animates constantly becomes a nuisance. Still by default, a small movement now and then, a flourish you might
  miss.
- Everything in Round 17's block below still holds: no session answers a system dialog or changes a system
  permission; UI tests in a file of your own, on a fresh simulator; `dev/ROADMAP.md` is the supervisor's; two
  briefs edit `project.yml`, each its own lines; leave the Debug Mac app's window as you found it; unregister your
  Debug build's widget extension (`pluginkit -r`) when you finish.

## Round 17 (2026-11-10; briefs 74–78 in parallel; `ROUND-17.md` says why)
0.9.0 (21) is released; this round is **0.9.1** (each release bumps the version by 0.0.1 again). Sessions are Opus
5.5 (commits end `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`), the supervisor a Fable 5.2 chat. **No
schema change this round**: a fix that needs one stops and reports.
- Ownership: 74 `widgets` (xhigh) new `HITListWidgets/`, `Services/Widgets/`, `Services/DeepLinks/`, core's widget
  snapshot, `project.yml` (the extension target, the version lines, the URL scheme), one line in `HITListApp`. 75
  `motion-polish` (xhigh) the design system's motion and control styles, `Views/Popouts/*`, `MobileShell`,
  `MobileTabBar`, `TaskRow`, the completion views, `ProfileMenu`, `Views/Tips/*`, `Views/MacChrome/*`,
  `MacSettingsPage`, `Views/Flipboard/*`. 76 `companions` (max) new `Views/Companions/*`, `Support/Companions/*`,
  one overlay line each in `SidebarSearchField`, `BrowseView`, the foot of `SidebarView`, the Extras toggle. 77
  `calendar-events` (high) new `Services/Calendar/*`, `Views/Calendar/*`, Today's section of `TaskListView`,
  `Views/Upcoming/*`, `GeneralSettingsSection`, the Mac entitlement, the privacy page. 78 `steady-bolt` (xhigh,
  added an hour into the round on George's note) the sync marks and what feeds them: `SyncState`, `SyncStatusViews`,
  `CloudSyncMonitor`, `AccountWatch`, `Services/Sync/*`, the iCloud settings groups and the sync log view. Nobody: `scripts/`,
  `dev/briefs/`, `dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` What's New pin, the models.
- **Never answer a system dialog and never change a system permission.** A permission prompt (Calendars,
  Notifications, Accessibility, "would like to access data from other apps"), a crash notice or any other system
  alert on the Mac is George's to answer: do not click it, script it (AppleScript, Accessibility, `tccutil`) or
  dismiss it. Test a prompt on your own simulator only; on the Mac, describe what you needed and stop. (Round 17: a
  session scripted the Mac's calendar prompt, hit a crash notice's button instead, and reset HITList's calendar
  permission with `tccutil`.)
- **`dev/ROADMAP.md` is the supervisor's.** Do not add a row; your report is the record. (Every earlier brief asked
  for a row, and the rows conflicted at every merge.)
- **UI tests go in a file of your own** (`HITListUITests/<Yours>UITests.swift`), and run on a fresh simulator.
- **`project.yml` is edited by two briefs** (74: a new target and the version lines; 77: one usage string). Touch
  only your lines, run `xcodegen generate`, and never commit a hand-edited `project.pbxproj`.
- The Mac window's sidebar is a scroll view of `MacSidebarRow`s since round 16, not a `List`, and the toolbar's
  band, pill and toggle are drawn by the app (`Views/MacChrome/*`): anything new on the Mac is drawn or pinned the
  same way, never left to the system (a friend's macOS 27.2 draws system chrome differently, and nobody here has it).
- A switch is not a task unless it opted in and is due (`FlipboardSwitch.listing`); ask core, never judge a switch
  yourself. Debug arguments worth knowing: `-seedDemoData YES` (a believable week with two Switchboards),
  `-flipboardNow` (the board's clock), `-focusSearchAtLaunch YES`, `-boltStrikeDemo YES`, `-hideTips YES`.
- Recording motion: `xcrun simctl io <udid> recordVideo --codec h264 out.mp4`, then `ffmpeg` (installed at
  `/opt/homebrew/bin/ffmpeg`) for frames and tiled strips; on the Mac, capture the Debug app's own window in a loop
  with `scripts/window-shot.sh`. `scripts/window-drive.sh` has no scroll: set the vertical scroll bar of the
  window's `AXScrollArea` through Accessibility on your own Debug app's pid.

## Round 16 (2026-11-10; briefs 70–73 in parallel, all four at once; `ROUND-16.md` says why)
The supervisor is a Fable 5.2 chat; sessions are Opus 5.5 as before (commits end `Co-Authored-By: Claude Opus 5.5
<noreply@anthropic.com>`). **The version stays 0.9.0**: the next upload is 0.9.0 (21), a new build of the same version,
and its notes are the supervisor's (`CHANGELOG.md` `## 0.9.0 (21)`, `WhatsNew.swift`). Xcode is 27.2 (SDK 27.2), this
Mac macOS 26.7.1. Brief 72 adds schema V6 (`Switchboard`, two `TaskItem` fields); George deploys it before the build.
- Ownership: 70 `mac-chrome-27` (xhigh) the Mac's sidebar, toolbar, search field and window: `SidebarView`,
  `ContentView`, `ScreenMenu` (Mac), `QuickAddEntry` (Mac toolbar item), `Views/Search/*`, `ListChrome`, the Mac Settings
  sidebar, `MacWindowKeeper`. 71 `quick-add-monthly` (high) core's `QuickAddParser`, `DateExpression`, `RecurrenceRule`,
  the Repeat card's words. 72 `switchboards` (xhigh) the models and schema, `Views/Flipboard/*`, core `FlipboardSwitch`,
  `FilterableTask`, `TaskOrdering`, `GroupedOrdering`, snapshot and backup, the switch lines of notifications, Spotlight,
  Claude and Intents. 73 `browse-and-bolt` (high) `BrowseView`, `Views/Groups/*`, `BoltSlamMotion`, the slam's lines in
  `SyncStatusViews`. Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, `WhatsNewPopout`, the
  `SettingsTests` What's New pin, `project.yml` beyond adding files, `TaskRow`, `HITTokens`.
- **UI tests go in a file of your own** (`HITListUITests/<Yours>UITests.swift`): three rounds of merges conflicted in
  the shared `HITListUITests.swift`. Only brief 72 edits that file, and only its two Flipboard tests.
- **A friend's Mac runs macOS 27.2 and nobody here has it** (no VM, no CI runner). Anything you draw on the Mac must
  not lean on what the system decides by OS version or by which view holds the keyboard: a system list selection, a
  toolbar's glass or background, a sidebar's icon size. Draw it or pin it with an explicit value (brief 70 does this
  for the window's chrome; follow it in anything new).
- A switch is no longer a task by default (brief 72): when your screen lists tasks, call core's rules
  (`TaskOrdering`, `FlipboardSwitch.listing`) and never judge a switch yourself.

## Round 11 (2026-11-05; briefs 47–52 run in parallel, all six at once)
Next version 0.7.0 (17). Session 48 adds schema V5 (`TaskItem.reminderDate`); George deploys it before 0.7.0.
Read `dev/briefs/HIG-NOTES.md` (Apple's guidelines as they apply here) before designing anything visible.

**Seeing the Mac app (new, 2026-11-05).** George granted screen recording, so a session can capture its own Debug
Mac app's window (never the whole screen, which shows George's own windows):
1. Build: `xcodebuild build -project HITList.xcodeproj -scheme HITList -configuration Debug -destination
   'platform=macOS' -derivedDataPath build.noindex/mac-NN -allowProvisioningUpdates -quiet`.
2. Run it on its own store with sync off for that process only:
   `HITLIST_STORE_SUFFIX=sNN build.noindex/mac-NN/Build/Products/Debug/HITList.app/Contents/MacOS/HITList -disableCloudKit YES -seedSampleData &`
   (`-disableCloudKit YES` is a launch argument: never write `disableCloudKit` into the app-group defaults, which
   George's real app reads; only a schema push run keeps CloudKit on, still with its own suffix.)
3. `scripts/window-shot.sh <pid> build.noindex/shot-NN.png`, then Read the PNG (shrink it first with
   `sips -Z 1400`). Quit the Debug app with `kill <pid>` when done; never touch `/Applications/HITList.app`.
4. Click and type in it (George granted Accessibility, 2026-11-05): `scripts/window-drive.sh <pid> click X Y wait 1
   type "Call Sam p1" key escape shot build.noindex/s.png` (points from the window's top-left = capture pixels / 2;
   actions click, dclick, move, type, key, wait, shot). It refuses anything but a Debug HITList under `build.noindex`
   or the Simulator, acts only while that app is frontmost (George may be at the Mac: it stops if he takes over), and
   hands focus back afterwards. Keep runs short. iPhone/iPad: your own simulator as before; ask George once for tap access and carry on meanwhile.

**Driving the iPhone app without the panel permission (from round 12).** `HITListUITests` (XCUITest, its own
scheme) taps and types through the real app: `SIMULATOR=HITList-NN scripts/test.sh ui`. Add a test of your own beside
`testTabsAndQuickAdd` for your screen; launch with a fresh `HITLIST_STORE_SUFFIX` and `-disableCloudKit YES -hideTips`
(a first-run tip takes the first tap); wait for a closing card to go before the next tap (taps during its slide are
swallowed); keep screenshots with `XCTAttachment` and export them with `xcrun xcresulttool export attachments --path
<.xcresult> --output-path <folder>`. Stable identifiers: `quickAddButton`, `quickAddTitle`, `quickAddSave`, `tab-<name>`,
`browseButton`, `viewOptions`, `syncBolt`.

**Decisions from 2026-11-05 (George):** no login system ever (the Apple account is the identity; profiles serve
Shared Tasks); the Claude integration is off and hidden by default, its privacy choices shown only once switched on;
"Delight" is called "Extras"; a quick-add highlight is removed by a click/tap or by Backspace right after it; "!"
reminder phrases light up only once complete (after a space); `!15m` = 15 minutes from now, `!15mb` = before the due
time; the Discard question sits inside the card it concerns.

## Round 13 (2026-11-07; briefs 57–60 in parallel; `ROUND-13.md` says why)
Next version 0.7.2, or 0.8.0 if 0.7.2 shipped first (`ROUND-13.md`). No schema change; George deploys three
`TaskItem` fields that were missing from Production (`deadline`, `locationName`, `flipPeriodStart`). Ownership: 57
`TaskListView`, `InboxView` (not its "Review Inbox…" line), `ListChrome`, `ScreenMenu`, `BrowseView`, `SidebarView`,
`ProjectEditorView`, `SettingsPreferences`, new `Views/Groups/*`, new core `GroupedOrdering`; 58 `MobileTabBar`,
`MobileShell`, `TapHaptic`, `HITMotion`, `MobileChromeTests`; 59 `Views/Flipboard/*`, `TaskRow`, core `TaskOrdering`,
`FilterQuery`, `FilterableTask`, new core `FlipboardSwitch`, `UpcomingSchedule`, the board model, `DuoNextDays`,
`SpotlightSync`; 60 `Views/Inbox/InboxProcess*`, `InboxZeroView`, `InboxText`, `InboxPicker`, the "Review Inbox…" line
of `InboxView`, new core `InboxReview`. `HITTips.swift`: one tip each (57 `#`/`@`, 59 Flipboard, 60 review).

**New since round 12.** `-seedDemoData` on a side store fills it with a believable week (`TaskActions.demoLines`; the
README's screenshots came from it). `-seedSampleData` must set every optional field (`CloudKitSchemaTests` fails
otherwise) and `release.sh` fails its preflight while Production lacks a field the models have. The sync watchdog
counts only the task store's entities: TipKit's `Core*Record` saves post `ModelContext.didSave` too. The iOS build
no longer runs on a Mac (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO`): a Mac check means the macOS build, never the
iPad app in a Mac window. In a test, keep the `ModelContainer` in a `let` for the whole test (a `ModelContext` does not
retain its container; `ModelContainerFactory.preview().mainContext` alone traps on the next fetch).

## Round 14 (2026-11-07 evening; briefs 61 and 63 in parallel, 62 after 61 merges; `ROUND-14.md` says why)
Next version 0.8.1 (0.8.0 shipped as build 18). No schema change. Ownership: 61 `TaskListView`, `InboxView`, `InboxText`,
`BrowseView`, `ListChrome`, `ScreenMenu`, `Views/Groups/*`, `SettingsPreferences`, `HITTips`, core `GroupedOrdering` + new
`SearchIntent`, `GroupsTests`, the Groups and Review UI tests; 63 `MobileShell`, `MobileTabBar`, `TaskRow`, `HITTokens`,
`Views/Duo/*`, `MobileChromeTests`, its own UI test; 62 (later) `Views/Shared/*`, `Services/Sharing/*`, the list views,
`Upcoming/*`, `TaskRow`, `SidebarView`, `PopoutController`, core `FilterableTask` + new `ListRow`. The rules of the round
are in `ROUND-14.md` and SUPERVISOR §7 (a name once, large titles, one control, the three sorts, filters in search).

## Round 15 (2026-11-08; briefs 64–69 in parallel, all six at once; `ROUND-15.md` says why)
Next version 0.9.0 (0.8.2, the supervisor's fix for the Mac's invisible picker cards, may ship before the round merges).
No schema change. Ownership: the table in `ROUND-15.md` and each brief's list; where two briefs share a file, each
names its region. New facts:
- The Mac's picker cards live on a layer in the window's frame view (`PickerLayerHost.host(in: window)`): with the Xcode
  27.2 SDK a SwiftUI content view draws over any AppKit view added inside it. Never draw over SwiftUI that way.
- A Debug Mac app has the real app's bundle id and may restore its saved window state and open no window: launch it
  with `-ApplePersistenceIgnoreState YES` beside `-disableCloudKit YES`, e.g. `open -g -n --env HITLIST_STORE_SUFFIX=sNN
  build.noindex/mac-NN/Build/Products/Debug/HITList.app --args -disableCloudKit YES -hideTips YES -ApplePersistenceIgnoreState YES`
  (add `-seedDemoData YES` the first time for a believable week).
- George's screenshots for this round: `/Users/gtrammell/Desktop/HITList/build.noindex/round-15/` (outside git; read by
  that absolute path).
- Your report includes screenshots of every screen you changed, on both platforms where it exists, and names anything
  that looks alike or that you could not check (SUPERVISOR §4 step 8 applies to sessions too).

## Round 24 record (2026-11-12, 11:45 to about 15:20 Eastern; sessions 121–126 merged for 0.9.8)
0.9.7 was held back; George's notes came at about 11:45 (`ROUND-24.md`). The three water inks went onto master at
12:00, six sessions started at 12:02, the five drawing ones were in by 12:50 and the Flipboard's at 14:05. George
asked for a pause at 13:00 for a meeting ("Come to a stopping point … we'll pick up in a bit and merge the
Flipboard") and was back at 13:13; the sessions worked through it and nothing was merged meanwhile. No schema change.
- **The supervisor's own**: `CompanionInk.water`, `.waterLight`, `.waterDeep` (`p` #4CA6FF, `h` #DDF1FF, `u`
  #1F6FE0; `weatherInks` are never among a creature's own colours); sketches made in the sessions' first ten
  minutes with `round-24/draw/sk.py` and sent as rows with a stop: Tuck asleep (his day head, the eye balls shut,
  a row lower and a pixel further apart on one-pixel stalks), Nod's eyes (two pixels tall), Nod's rain (0.9.6's
  canopy with a four-pixel handle; a longer shaft read as 0.9.7's wire again); every sheet forwarded to George;
  `testFlipboardLightsStayOnTheirSwitches` rewritten for rows (one height everywhere, one width in the grid, one in
  the rows); the notes.
- **121 `phase-ether`** (xhigh, about 45 minutes, one note on the halo): the engine's `glow:` (inks that cast a
  halo of their own colour about a pixel wide, over the body and under the crisp pixels, on a larger canvas laid out
  at the sprite's size), `Frame(name:, fade:, light:, rows:)`, a see-through body thinning down its own rows,
  Reduce Transparency drawing it solid, and a new ink `e` (the accent lightened). A character with no glow draws
  as before (`CompanionLightTests`, Nod and Button pixel for pixel). Phase, pick b: 72% at the crown to under a
  quarter at the hem, the hem's last row a checker of veil, the tail thinning to a wisp, the same eyes turned over
  (lit, a dark pupil low) with the halo; his bob thins and fills him, a tap dips him twice, the phase fades him
  from the hem up to his eyes alone and back; asleep at 0.8; one mound of snow; blue drops inside him and a puddle
  under him. Glim: `glow: [.warm]`, halved asleep.
- **122 `tuck-rest`** (xhigh, 25 minutes): the rain still is his `rest` with water only (a puddle lapping the front
  of his foot, the pot brimming, beads on a leaf, his back and a stalk's root, one hanging under the rim); a drop
  falls from a leaf into the pot; 0.9.7's stretch is one glad move in a routine; the 31 frames drawn for 0.9.7's
  raised eyes are retired and his clearance is 34 pt again. Asleep is the supervisor's frame, with its breath, a
  dream, the reply to a tap, the three snow depths and a rain still.
- **123 `quill-nod`** (xhigh, about 48 minutes): 0.9.6's face on all 143 of Quill's frames, then three pixels
  friendlier (the M's centre stroke gone, a small mouth); his rain wet, and a rain still asleep under his own tail.
  Nod's eyes on the 57 frames where they are open; 0.9.6's canopy held, beads, a drop off the right tip; the puddle
  is two tiny pools beside his seat (the supervisor's single puddle hung over the "+"'s curve); tip, peek, duck at
  thunder; asleep under it. 0.9.7's dome, wire, twirl and gust are gone. Five idles each do not play in the rain.
- **124 `gargle-button-rain`** (xhigh, 38 minutes): beads on Gargle's wing and snout, a drop that runs from the wing
  tip over his nose to his chin, a puddle under his paws, `sleepRain`; `snow2` and `snow3` redrawn from `snow` so
  that only the drifts grow (his back's hollow, the wing's slope, his nape, his toes) and his horns, brow, eye and
  snout stay stone. Button: beads on the cap, a drop at each low point of the rim, a puddle round his boots (the
  only flat under him), a second drop down his side, `sleepRain`. `ThemeCompanion.Placement.onFloor` and Button's
  seat.
- **125 `hush-glim-rain`** (xhigh, 33 minutes): Hush: beads on the hood, a drop off its right tip, a puddle round
  his right foot in the deep tone with a glint; his thunder flick no longer drops the hood; asleep in the rain as he
  sleeps. Glim: beads on an ear, his head and cheek, a drop off his left ear, a puddle on his left; never water on
  or beside the lantern; asleep curled round it. 75 of Hush's frames stay pinned to `v0.9.6`.
- **126 `flipboard-rows`** (xhigh, about two hours, one note): `SwitchRow` (a board is one sideways row resting on
  tile edges, the dashed Add outline last, tiles sized by `FlipboardLayout.rowTileWidth`: whole tiles and a fifth
  of the next, one and a half at the accessibility sizes), `BoardPanel` (the card surface at half strength, a
  hairline, corners 30, a trace behind the tiles that is green when the board is all on), `BoardLightsStrip` (dots,
  then segments, then a bar with a count, by the room the header has; a tap scrolls to the switch; rings and stubs
  with Differentiate Without Color; one VoiceOver element), the "Ungrouped" header that folds the loose grid
  (`AppGroup.defaults`), the switch card under its row on the Mac and iPad, a chevron that pages a row on the Mac.
  The add jitter: `SwitchLanding` jumped to its start in a 1 ms linear keyframe and the spring after it took that
  speed (the tile drew mirrored, double and tiny); now a `MoveKeyframe`, a softer spring, and on iPhone the tile
  hidden until the card has gone. Also fixed: after Add the Mac's card reset to "No Switchboard".
- **What worked**: the water recipe in this file (five sessions, one look); sending rows instead of words; all
  drawing at xhigh; the UI suite on an integration checkout while the last session finished.
- **What cost time**: nothing much. The first Flipboard design cut a tile at nine-tenths (the brief asked for two
  things that collide); an older UI test pinned one tile width for the whole screen.
- **Final counts** (on `775dc77`, the last code commit; only documents after it): core 704, Mac 1967 (1 skipped),
  iOS 1930 (1 skipped). The UI suite (138 tests: 76 passed, 61 skipped as on demand or Duo only) ran on an
  integration checkout whose tree is master's (`git diff` empty) and failed once, in
  `testFlipboardLightsStayOnTheirSwitches`, which still asked for one tile width on the whole screen; rewritten, it
  passes on the iPhone 16 and iPhone 17 simulators. On a Duo simulator `DuoCardsUITests`, `DuoColumnUITests`,
  `ScreenInsetsUITests` and `CompanionIslandUITests` pass (20 tests, 10 skipped as on demand). A Release archive and export of both platforms pass the 44 checks
  (`build.noindex/package-proof-143502`: iOS 16,589,233 bytes, macOS 32,241,654 bytes). The cast was photographed
  in the app on an iPhone 16 simulator (0.9.7 beside 0.9.8: `build.noindex/round-24/handover/`) and in a Debug Mac
  app on the search field.
- **Never seen running**: any of it on a real phone; a row scrolled by trackpad or shift-wheel on a real Mac (the
  chevron was); the Duo's inner display; the Flipboard on the Duo beyond the outer display in a simulator.
- **Open in the code**: at the largest accessibility text size the ungrouped tiles' names and the floating switch
  card still truncate (as before this round); Glim's heat bead and the drips in his snow `melt` are still in his own
  inks; one Flipboard UI test waits a minute after each long press (the app does not report idle there).
- **Side stores to delete by hand** (the Mac's app-group folder): `HITList-s121*`, `HITList-s123*` to
  `HITList-s126*`, `HITList-sup24*`. Never `HITList.store`.

## Round 23 record (2026-11-12, 09:55 to about noon Eastern; sessions 116–120 merged for 0.9.7)
0.9.6 (26) was released about 09:30; George's notes on its creatures came at 09:50 (`ROUND-23.md`). Five drawing
sessions started at 10:00 and were all in by 10:45. **Drawings only**: since `v0.9.6` nothing changed outside
`Characters/*.swift`, their tests, one comment in `ThemeCompanion.swift` and the notes. No schema change.
- **116 `glim-subtle`** (xhigh, 37 minutes): every frame of `f3da1e6`'s Glim back, his plain stills pinned by
  digest; touch-up "B" (nine pixels on `rest`, three asleep: lower lids, the hood's shade at the face's top corners
  and under the chin, two pale rings down the tail, one glow pixel on the lantern), carried onto all 110 frames by
  `116-glim-subtle/workshop/carry.py`; in rain, snow and thunder the tail curls in and the lantern is held in his
  lap in both paws, all of it lit, its glow on his chin (`warm` in snow); powder on his ear tops and between them.
- **117 `gargle-pup`** (xhigh, 25 minutes, one note): every awake frame starts from v0.9.6's `sleepBreathe` (the
  sleep frame, head up a pixel) with an open eye (dark, a light, a warm glint under it), the mouth's corner up and
  no tooth; 247 pixels against 265. Asleep stills pinned to `v0.9.6`. Rain: the wing rises from his shoulder in a
  curve over his crown to a point before his snout (`peek`, and `duck` at thunder). Six moves that needed the
  three-quarter head are gone (tilts, sniffs, scratch, crumb, chase, flop); horn flick, spade wag are new.
- **118 `phase-sheet`** (xhigh, 34 minutes): one drape (concept C, face 1): a round crown leaning two pixels, soft
  S sides, a hem of four unequal waves with its tail trailing left; two dark 2 × 3 holes with a light low in each,
  a one-pixel mouth; hovering two pixels over the bar; asleep hovering low and slack. 149 frames from
  `118-phase-sheet/workshop/build.py` (the face is one part in `gen.py`: the glowing ovals swap in by one line).
  `testNothingSticksOutAboveTheHem`. Its last-snow sweep puffs six flecks into the air for under a second.
- **119 `tuck-quill`** (xhigh, 45 minutes, three passes on Tuck): Quill's 0.9.5 face on all 139 frames of the
  tabby; in rain his ears lie back and a drop hangs off his tail's tip. Tuck asleep is the supervisor's drawing
  (stalks folded flat at the head's top corners, each eye a shut grey ball at cheek level, no mouth; breathing
  sways the balls; a tap lifts one stalk and opens its eye); in rain he stretches a pixel taller with a bead on each
  eye (his clearance above the "+" is 36 pt, was 34). Not done: Quill's tail round his feet in snow; Tuck drawn
  half down in snow.
- **120 `nod-button-weather`** (high, 32 minutes, two notes on the umbrella): Nod holds a domed umbrella (13 × 4,
  a ferrule, a scalloped edge, drawn over the top-left of his cap; the shaft a pixel clear of his side, his arm out
  to it); twirl, gust, peek, duck at thunder; asleep in rain it leans on him. Button's cap comes three rows down to
  his cheeks, bent where he grips it, eyes peeking; a peek routine. Snow half as deep again on both (15/28/45 and
  14/27/44 pixels). While a creature holds its umbrella or cap a few idles do not play in the rain.
- **The supervisor's own**: `CompanionKeptTests` (every frame of Hush pinned to v0.9.6); Tuck's sleeping frame,
  sketched in `round-23/draw/` after three passes by text; every sheet forwarded to George as it arrived; the notes.
- **What worked**: starting each session from the drawing George likes; small sheets within 25 minutes; looking at
  a session's current frames with `round-23/draw/view.py` instead of waiting; the cast photographed in the app.
- **What cost time**: Tuck asleep (three text passes that made hooks and ears before the supervisor drew it); the
  supervisor's earlier rule about faces, which had pushed Gargle away from the profile George likes.
- **Final counts** (on `5216132`, the last code commit; only documents after it): core 704, Mac 1945 (1 skipped),
  iOS 1908 (1 skipped). The companion UI classes pass on an iPhone 16 simulator (`CompanionsUITests` 8,
  `CompanionPhaseUITests`, `CompanionListEndUITests`) and `CompanionIslandUITests` on a Duo simulator; **the whole
  UI suite was not rerun**: nothing but drawings changed since `v0.9.6`, where it passed (136 tests). The cast was
  photographed in the app on an iPhone 16 simulator (0.9.6 beside 0.9.7: `build.noindex/round-23/handover/`) and on
  the Mac's search field. A Release archive and export of both platforms pass the 44 checks
  (`build.noindex/package-proof-105424`: iOS 16,452,298 bytes, macOS 31,941,347 bytes).
- **Never seen running**: any of it on a real phone; the new creatures on the Duo's tab bar in a simulator (their
  seat and island tests pass); Phase's swatch in Settings on a device.
- **Side stores to delete by hand** (the Mac's app-group folder): `HITList-s116*` to `HITList-s120*`,
  `HITList-cast*` is the simulator's own. Never `HITList.store`.

## Round 22 record (2026-11-12, 05:00 to 09:00 Eastern; sessions 109–115 merged for 0.9.6)
0.9.5 was handed over at 04:30 and sent back at 04:55 from its pictures (`ROUND-22.md`). Seven sessions started at
05:09 and were all in by 06:34, each with a clock in its brief; master carries their branches and the supervisor's
follow-ups. **No schema change. 0.9.5 was never released: 0.9.6's notes carry rounds 21 and 22.**
- **109 `button-back`** (high, 25 minutes): Button's stills pinned to `v0.9.4` by digest; seat row 19 (he stands,
  nothing over the host's face); bob, puff, cap wobble, spore puff, a snuggle asleep, no frame moves a boot (a test);
  Button's and Nod's snow. Not done: the roll (his cap fills the frame's width).
- **110 `phase-cloth`** (xhigh, 50 minutes, sent back twice at the sheets): a hooded head with the curled point, a
  one-pixel pinch, a skirt of three uneven points with a lifted corner, 4 × 3 almond eyes (`l`, an `r` iris, a `k`
  pupil); seat row 20, no veil in any still (the veil only while it phases); going through the bar leaves out what
  is below its top; rain goes in at the crown and out at the hem; snow gathers in a drift on the bar under it. 169
  frames from `110-phase-cloth/workshop/build.py`. The format refuses the accent and the warm ink together, so the
  iris is not warm.
- **111 `gargle-dragon`** (xhigh, 35 minutes): a three-quarter head with a short snout, horns swept back, a warm iris
  under a brow that lowers, a closed mouth with one fang (a test: nothing dark or warm below his eyes in any frame);
  a smoke puff, an ember hiccup, a wisp when he snores; his sleep kept with a second horn and two spines.
- **112 `hush-quill`** (xhigh, 40 minutes): Hush's inner ears in `r`, a brow peak, lower lids, a belly; Quill a
  tabby with accent eyes; their snow. Hush's ear tips turn in (out-turned tips failed the seat test).
- **113 `glim-tuck`** (xhigh, 55 minutes): Glim mid grey-blue with a dark outline, a moon face, the lantern's light
  low in his eyes; in rain, snow and thunder the tail curls round him and the light is held to his chest (`peek`,
  `warm`); Tuck asleep keeps its eyes on lowered stalks under round lids; their snow. Not done: reeling the tail in
  as the weather turns (the engine plays nothing on a change of sky).
- **114 `card-insets`** (xhigh, 85 minutes): `CardInsetsUITests` (every card over a list: 12 pt to the border, 6 pt
  between controls, nothing cut; 45 places under the floors on the Duo before, 0 after; 30 to 0 on an iPhone 16;
  `TEST_RUNNER_HITLIST_INSETS_OUT`), `CardInsetsTests`; the reminder card's insets and its short row ("Later…");
  quick add's chips wrap (`HITFlowLayout`); the date card's tiles sized to their labels; the editor's pills in a
  fading scroll row (`HITScrollingChipRow`); `HITCalendar.circlesOnEdges`; the Mac's date card 344 pt.
- **115 `screen-insets`** (xhigh, 85 minutes): rows end with their headers (a 12 pt gap sat before an empty
  spacer); the Flipboard on the screen's margin; the switch card's choices with 8 pt around their words; Browse's
  title row at one 7 pt gap on the Duo and its filter chips fading at the edge; Review Inbox's tiles;
  `ScreenInsetsUITests`; a meter that reads screenshots (`115-screen-insets/tool/measure.swift`).
- **The supervisor's own**: three snow inks `s`, `b`, `c` (`CompanionInk.snowInks`; `inks` leaves them out,
  `allInks` has them; the weather test counts them); "Pick a Group" at an 8 pt inset (one line on an iPhone 16, two
  on the Duo); the reminder card's four times in its two columns where they do not fit one row; the walk's menu
  dismissal under the status bar; the notes.
- **What worked**: a clock in every brief; concept sheets within half an hour, looked at at 1x beside Hush; the
  cast photographed in the real app, 0.9.5 beside 0.9.6 (`build.noindex/round-22/handover/02-…`); shared fixes on
  master handed out as hashes with a stop.
- **What cost time**: two shared lines every snow session met (the 4…6 colours rule, the snow count), found after
  the start; a walk picture of quick add's date card with its lower half blurred, which was a frame caught
  mid-animation while three suites ran (a rerun on a quiet machine showed the whole calendar).
- **Final counts** (core, Mac and iOS on `ca8f87f`, the last code commit; the UI suite, 136 tests with 61 on demand or for the Duo only, 0 failures in 76 minutes, on the merged tree an hour earlier, and what touched the later changes, `CardInsetsUITests`, `HITListUITests` and the Duo's own, again on the final build): core 704, Mac 1939 (1 skipped), iOS 1902 (1
  skipped). On the Duo simulator `DuoCardsUITests`, `DuoColumnUITests` (7 run), `CompanionIslandUITests`,
  `CardInsetsUITests` and `ScreenInsetsUITests` pass; `CardInsetsUITests` passes on an iPhone 16 too. Brief 93's walk
  was looked at on the Duo's outer display (87 pictures) and an iPhone 16 (83). A Release archive and export of both
  platforms pass the 44 checks (`build.noindex/package-proof-073722`: iOS 16,458,629 bytes, macOS 31,956,284 bytes; the last commit after it changes comments and documents only). GitHub Actions green on `ac52fc4`.
- **Looked into and left**: under a starved simulator (three suites at once) quick add's date card landed 44 pt
  above its chip, its arrow in the title; a probe at ordinary load put every card 13 to 18 pt above its chip and
  steady, which is the system's arrow. The popover follows its chip as the popout drops with the keyboard, and a
  starved main thread can leave it at a stale spot. `HITListUITests.testFlipboardSwitchesStayOnTheBoardUnlessTheyOptIn`
  takes fifteen minutes in every run since round 20 (after a long press on a switch the app never reports idle, so
  each step waits a minute): worth a brief of its own.
- **Never seen running**: the Duo's inner display itself (still a stand-in; CoreDeviceService); a real call on the
  Duo; VoiceOver on the Duo; the new creatures on a device's own screen (simulator and Mac only); quick add's
  wrapped chips with a picker open at the larger text sizes on the Duo.
- **Left**: Settings' two-line rows keep 8 pt of row padding (about 11 pt above the title's caps and 10 below the
  second line's baseline; judged balanced, and the first screen has 0.3 pt of height to spare); the system places a
  wide card 8 pt from the Duo's edge; "Shave" (round 20).
- **Side stores to delete by hand** (the Mac's app-group folder): `HITList-sup22*`, `HITList-s109*` to
  `HITList-s113*`, `HITList-s114*`, `HITList-s115*`, and round 21's if still there. Never `HITList.store`.

## Round 21 record (2026-11-11 to 12, overnight; sessions 103–108 merged for 0.9.5)
All six branches are merged on master. Two early commits went first so siblings could build on them (104's "behind"
layer at 22:20, 106's bar column at 23:30); then 104, 105, 103, 104's island companion, 106, 108, 107. No schema
change.
- **103 `button-stands`** (`claude/button-stands-22ca15`): Button redrawn at 14 × 12 pixels, the smallest of the
  eight: a rose cap over a rose stem with the face on it (nothing bone white), both stub feet on the host's top
  edge, centred on the flat of the "+". Idles: bob, breeze, puff, grow, tiptoe, a tipped cap, a shiver, a blush, a
  spot that lights. Routines: the roll, the spore puff (the format's one exception to "nothing in the air"), a
  bounce, planting itself, a doze. The boots and their kicks are gone.
- **104 `gargle-perched`** (`claude/gargle-perched-6967f4`): the "behind the host" layer (a capital ink letter is
  that ink behind the host, drawn only outside `CompanionPerch.surface`, not at all with no host;
  `CompanionBehindTests`); Gargle redrawn (side-on body, his face toward you, pale horns at the sides, a broad
  nose, one fang, a folded wing in flat shapes, the tail behind the bar with its spade beside him; the profile is
  his statue pose and his sleep); and the companion on the Duo's outer display (a new spot on the crown of the
  upright tab island: its own surface, a base carried down the dome up to 8 pt, shown only while the room above is
  its height plus 8 pt; `CompanionIslandTests`, `CompanionIslandUITests`).
- **105 `cast-flavor`** (`claude/cast-flavor-1de84d`): the audit (`105-cast-flavor/audit.md`: on 0.9.4 Nod's two
  minutes were seven idles, six of them his feet); new idles and routines for Nod, Quill, Tuck, Hush, Glim and
  Phase, each its own; `CompanionCastFlavorTests` (enough idles each, none too small to see, feet at most a fifth);
  the contact sheets are drawn in pages of 120 frames. It used the behind layer for none of the six.
- **106 `duo-column`** (`claude/duo-column-c20f70`): on the outer display a screen's bolt and pill are the system's
  title-row item (`ScreenControlsPlacement`; an overlay of our own took no taps under the navigation bar) and the
  column keeps the status, Back, the island and the "+" (`BarColumnBudget`); a 1 pt scroll view above the list
  keeps the title row in place; the week strip and Browse's saved filters stop at the content's edge; a row's
  meta line gives way in order (labels to "@first +N", then the Group to a line of its own); the upright island's
  labels keep the default size (large-content viewer on a long press); the island and "+" fade while the keyboard
  is up. `DuoColumnUITests`, `DuoOuterListsTests`, `DuoSweepUITests` (on demand), `-duoStatusPad 60` (a Debug
  stand-in for a call).
- **107 `duo-cards`** (`claude/duo-cards-f7ad0e`): the app chooses a picker card's side (above or below its chip,
  by the room, never beside it); short layouts for the date and reminder cards and denser lists where a card still
  does not fit; the editor at full height on a short screen; Review Inbox's cards hang under the title; a switch
  card's Discard question makes the keyboard step aside; Settings' descriptions wrap at XL. All keyed on the room
  on screen, not on the device (`DuoCardsTests`, `DuoCardsUITests`).
- **108 `duo-inner`** (`claude/duo-inner-a0aa19`): on the inner display the sidebar has the search field (there
  was no search there at all), one gear, the list and the editor meet at the hinge, the board shows whole days,
  the days beside Today use the lists' headers and rows, the sidebar steps aside after an unfold with the editor
  open. `-duoStandInSize inner` draws the app at 669 × 951 on an iPad mini; `DuoInnerUITests` (on demand).
- **The supervisor**: each creature's name under its theme (`ThemeSwatchButton`; the grid and the first screen's
  group spacing give back the height, 719.7 of 720 pt); the format's header line for Button's spores. **Found on
  the merged tree by brief 93's walk on the Duo simulator, not by any session's tests:** after one quick add a
  second in a row did not open. 106 hid the upright island while the keyboard was up by switching its opacity, hit
  testing and accessibility off and on in place; once the keyboard had gone the "+" reported the whole column as its
  frame (a tap aimed at it landed on whatever lay under the column's middle), and `IslandAddButton`'s own comment
  already warned that interactive glass ignores the first tap after hit testing returns. The column is now taken
  out and put back new (`MobileShell`), with `DuoColumnUITests.testThreeQuickAddsInARow`. Also there: Browse's
  profile is its picture alone in the title's row, because with a name beside it the system shrank "Browse" to
  three quarters of every other title. The walk's text notes ("no card for…", "no + for…") were the evidence: read
  them, not only its pictures.
What worked: concept sheets again. Button's pick was right the first time; Gargle's first pick (a profile, one eye,
"the only one that reads as a gargoyle") was sent back within minutes with a stop: the three-quarter pup with his
face toward you is the resting pose and the profile is his statue. A note between sessions (108 to 107: the open
Duo on its side is as short as the outer display, so key fixes on the room) was worth a stop too.
What cost time: six sessions' first builds with six fresh simulators on two iOS runtimes took the Mac to a load of
900 and 15 GB of swap for an hour; simulators' SpringBoards and a Python crashed, and their crash dialogs and one
privacy prompt ("claude.app would like to access data from other apps") were left on George's screen, unanswered.
**The Duo's inner display was never reached**: Device Hub lists simulators through CoreDevice, whose per-user
service was stuck on the morning's device list; restarting it was refused to the session and is George's to do
(`killall -u "$USER" CoreDeviceService`); `108-duo-inner/unfold.sh` and its README are the procedure for the next
round. `scripts/test.sh` builds into Xcode's default derived data, so `build.noindex/mac-tests` holds whatever was
last built there by hand: build the Debug Mac app with `-derivedDataPath` before looking at it (the supervisor
looked at a round-old app for a minute). `window-drive.sh` refuses a click that a system alert covers.
Never seen running, for the hand-over: the Duo's inner display itself; a real call in the Duo's camera island;
VoiceOver's order on the Duo; sheets on the open Duo; a tip and a Flipboard drag on the Duo; a sharing invitation
and the profile picture picker on the Duo. Known and left: Settings closes when the Duo folds or unfolds (it is
presented from inside each shell); Browse at AX5 breaks "Default Group" inside words; on a pushed screen during a
real call the island's companion may come within a few points of Back.
On the final tree (da976dd and this record): core 704, Mac 1927 (1 skipped), iOS 1890 (1 skipped), UI 130 with 0
failures (58 skipped: the walks on demand and the Duo's own) on a fresh iPhone 17 simulator in 72 minutes; the
Duo's own UI tests (`DuoColumnUITests` 6, `CompanionIslandUITests`, `DuoCardsUITests`) pass on an iPhone Duo
simulator; brief 93's walk was looked at on the Duo's outer display and on an iPhone 16; a Release archive and
export of both platforms pass `release.sh`'s 44 checks (iOS 16.4 MB, Mac 31.9 MB); GitHub Actions green.
Side stores left in the Mac's app-group folder, for George to delete by hand: `HITList-sup21*` and the sessions'
(`HITList-s103*` to `HITList-s108*`).

## Round 20 record (2026-11-11, afternoon; sessions 95–102 merged for 0.9.4)
All eight branches are merged on master (in this order: 98, 97, 95, 102, 101, 100, 96, 99). No schema change.
- **95 `sync-truth`** (`claude/sync-truth-b7f2bc`): `BoltTruth` (filled only within 30 s of a confirmation, two lost
  answers end it), `SyncBeat` (one small CloudKit read every 15 s while a bolt can be seen), `ICloudZoneIndex` and
  `ICloudZoneReader` (the app's own record of what the Core Data zone holds: kind, id, change stamp, never a title),
  `SyncComparison` (only here, only in iCloud, newer here, newer there), `SyncAudit` (Check iCloud…), `SyncWords`.
  What it found about George's morning, from the Mac's unified log: the Mac's account was "temporarily unavailable"
  from 21:28 on the 10th to 13:35 on the 11th and the bolt showed "Synced 18 hr ago", filled, twice. Why "Shave"
  was on the iPhone and not the Mac was not settled without the iPhone's log; George saved both devices' logs at
  18:15 (`build.noindex/logs/george-*-sync-log-2026-11-11.txt`, outside git) and the session was sent back to read
  them (its findings, if any, are in `95-sync-truth/logs-timeline.md` in the notes folder).
- **96 `flipboard-phone`** (`claude/flipboard-phone-25d3e0`): the empty board is the Add switch tile alone; the card
  (one scale of type, a time chip, "Become a task when Overdue", "Flip 1 time", the preview rocker removed); a switch
  dragged onto a Switchboard and off it; Duplicate; tile intervals on one line. The supervisor changed the Flipboard
  tip's words to match.
- **97 `repeat-picker`** (`claude/repeat-picker-968dae`): core's `RepeatChoice` (the menu's words) and `RepeatForm`
  (Custom…), `RepeatMenuCard`, `RepeatCustomCard`, the Repeat button in `DatePickerCard`; `PickDatePopover` is gone.
  Every rule's words begin "Every".
- **98 `quick-add-words`** (`claude/quick-add-words-796569`): "starting", weekday lists, the guide (`Views/Help/*`).
  At the merge the supervisor fixed what it found in `RecurrenceRule`: a several-day rule's week begins after its
  longest rest (`cycleStart`), and its first occurrence is the soonest of its days whatever the interval.
- **99 `sweep-polish`** (`claude/sweep-polish-61caeb`): 18 items, 24 commits; the "…" is a gear on the Mac and iPad
  and its items sit under the view options; one day formatter; one section header; rows on the system's margin.
- **100 `companions-alive`** (`claude/companions-alive-4301ff`): `idleGap` 6…36 s, `firstIdle` 2…6 s, `routineGap`
  180…480 s, `Routine.little`, asleep breaths at the same pace; `CompanionSeat` (a base pixel carried down to the
  host's curve, see-through as the character is) and `CompanionSeatTests` (every character, every still, every
  host); idles for the five; Tuck's eyes; the lists' end clears the companion.
- **101 `phase`** (`claude/phase-9da93e`): Phase, the `veil` ink ("v"), `CompanionCharacter.seeThrough` and
  `opacity(_:)`. Mallow deleted.
- **102 `rose-and-graphite`** (`claude/rose-and-graphite-e07fcb`): Button and Gargle, the `accentDark` ink ("r").
  Posy and Smudge deleted.
What worked: **concept sheets first.** Each character session sent three concepts within the hour; the supervisor
looked at them at real size and sent two of three back (a grey mushroom with a skull's face; a gargoyle that read as
a cat, then as pixel noise), and looked again at the stills in the app (Phase read as a drop until its hem lay over
the button; Tuck's first new eyes were still hollow squares). A stop is needed to deliver such a note to a working
session. What cost time: eight sessions saturated the Mac again once they all reached their suites (load near 1000,
20 GB of swap); the seat test used a macOS-only view and broke the iOS test bundle on master until a sibling found
it (build both platforms' test bundles before merging an early commit).
On the final tree (f52ba60 and this record): core 704, Mac 1871 (1 skipped), iOS 1831 (1 skipped), UI 102 with 0
failures (31 on demand) on a fresh iPhone 17 simulator; a Release archive and export of both platforms pass
`release.sh`'s checks (iOS 16.2 MB, Mac 31.6 MB); GitHub Actions green. In the first full UI run
`testReviewInboxSwipes` failed after twenty minutes of waiting and passed alone and in the second full run (the
fresh simulator again), and `testSortByOnTheInboxAndToday` needed the one day format. Session 95's second pass (both
of George's logs): nothing either device saved since 2 November failed to reach the other; the stores differed
before the logs' evidence begins (44 and 46 dated tasks counted at 0.9.3's first launch); three fixes (the bolt's
words count records, one log line per retry storm, a background push is a note).
Never seen running, for the hand-over: a real sign-out and the new bolt on Production; Low Power Mode; a large first
read of the zone; a switch dragged through to a drop on the Mac; the Mac's summary-time field; the feedback card's
Done; the iPad's moved menu items; the Duo's inner display; macOS 27.
Side stores the sessions left in the Mac's app-group folder, for George to delete by hand: `HITList-s95a*`,
`HITList-s96*`, `HITList-s99*` (and the files session 95's report lists under Application Support).

## Round 19 record (2026-11-11, overnight; sessions 82–90 and 92–94 merged for 0.9.3)
Twelve sessions on three of George's turns, all Opus 5.5, supervised by a Fable 5.2 chat while George slept: 82
`time-zones` (xhigh), 83 `location-weather` (high), 84 `companion-routines` (max), 85 `new-companions` (max), 86
`settings-tidy` (xhigh), 87 to 89 one companion each (max), 90 `share-extension` (xhigh), then 92
`day-anchor-review` (max), 93 `qa-sweep` (xhigh), 94 `accessibility` (xhigh); brief 91 (the weather on the
creature) went to every companion session as a second pass. Merged in the order that unblocked others: 82, 83, 86,
the engine's first commit of 84 (so the others could draw routines), the cast (85, 88, 87, 89), 84's weather
engine, 92, the cast's weather, 93, 90, 84's own three. Conflicts: the generated project (regenerated),
`CompanionCast.swift` at each cast merge (a list per line now), one comment. Supervisor's own: `CompanionSky.heat`
and the reading that feeds it (apparent temperature and daylight from the same WeatherKit answer), the sheet
request that opens Settings on a page, calendar-change listeners on six more screens and the sidebar's counts, the
eight swatch seats and a 2 pt clearance under the names above them, the release script's share-extension checks,
the notes.
After the round:
- **Days**: core's `DayAnchor`: a date with no time is stored at 10:00 UTC on its day. `DayAnchor.verdict` anchors
  only a midnight in the device's own zone (brief 92: never on a guess); everything else is kept byte for byte and
  read as the local day it shows, as 0.9.2 did. Three passes share it: every save, after each import, and once per
  store after a backup (`Backups before day anchors`); `DayAnchor.isEnabled` turns the rewriting off. A day a 0.9.2
  device wrote in another zone keeps its old reading until a device in that zone anchors it. `CalendarChange`
  (`Services/Dates`) is the one source of "the zone, the clock or the day changed"; a view with its own clock adds
  `.onReceive(CalendarChange.moments)`. Debug: `-calendarChangeTo Asia/Tokyo -calendarChangeAfter 90`.
- **Location and weather**: on unless switched off; asked once, about 2 s after the first screen is up
  (`LaunchLocationQuestion.decide`); a Debug build never asks without `-askLocationAtLaunch YES`. Each fix also
  asks Apple's geocoder for the place's zone, which only `CompanionSkySource.zone` (the companions' clock) reads.
  Skies: unknown, clear, clouds, rain, snow, storm, heat (by day, when it feels like 30 °C or more and nothing is
  falling).
- **Companions**: the format is explained at the top of `CompanionCharacter.swift` (read that, not this). Still;
  a flicker every 40 to 110 s; a routine after 5 to 12 minutes of showing time (kept across launches); the
  flourish as before; a tap plays the flourish after 20 minutes, else a routine after 3, else the small answer.
  Weather on the creature: sky-bound gestures and routines, `snowDeep` piling up every 8 to 14 minutes until a
  `shakesOff` routine, `heat`. Nothing is drawn in the air. Cast, in the themes' order: Nod, Smudge, Quill, Tuck,
  Hush, Glim, Mallow, Posy (`CompanionCast`); seats on the swatches in `ThemeCompanion.seats`. The drawing
  workshop (frames as text, sheets, mock-ups of the "+" and the field) is in `build.noindex/round-19/workshop/`
  on George's Mac, outside the repository. Debug: `-companion glim`, `-companionSky heat`, `-companionSnowDepth 2`,
  `-companionPlay routine:<name>`, `-companionHour 23`, `-companionZone Asia/Tokyo`.
- **Settings**: `SettingsHome` (the first screen) and `SettingsPage` pushed inside the sheet (`HITSheetPages`, a
  design-system piece); the Mac's `MacSettingsSection` in the same order. `SettingsView(page:)` and
  `SettingsSheetRequest` open the sheet on a page. The first screen measures 718 of the 720 pt an iPhone 17 has
  (`SettingsTidyTests.testFirstScreenFitsAnIPhone17`); on George's iPhone 16 its last row ends at the home
  indicator's edge.
- **Share extension**: `HITListShare/` (one target, three platforms), core's `ShareOutbox`, the app's
  `Services/Share/ShareInbox` (drains at launch, on activation, on the bell, in the widgets' background moments;
  tasks through `TaskActions.create`). On the Mac it must be switched on once in System Settings → General → Login
  Items & Extensions → Sharing; Safari's real Share menu there was never seen. `TEST_RUNNER_HITLIST_SHARE=1` runs
  its UI test.
- **Accessibility**: a task row is one VoiceOver stop with completing as an action (`TaskRowSpeech`; `-voiceOverRows
  YES` shows rows that way to tests), the iPhone's tabs are a tab bar, a switch says off or on, chips say what they
  are, an open card is read alone, the Undo toast is announced; the Mac's keyboard reaches the editor; the toolbar's
  sync bolt and its pill are one toolbar item so the whole bolt takes a click. `AccessibilityAuditUITests` runs the
  system's audit on every screen, on demand (`TEST_RUNNER_HITLIST_AUDIT=1`): 9 tests pass on a fresh iPhone 17
  simulator, each of its 404 findings excluded with a written reason in the test (custom fonts the audit misreads,
  clipping it guesses at the largest sizes, the screen behind a card, text under the tab island's glass). It stays
  out of the ordinary UI run until it has passed at night and on another device size. Never use
  `accessibilityHidden(false)` over a container: it un-hides everything inside (use `accessibilityHidden(true,
  isEnabled:)`). Debug: `-dumpAccessibility YES` logs what VoiceOver can reach.
- **Left for George** (the sweep's `FINDINGS.md`, with pictures): the large title 4 pt right of its rows on the Pro
  Max and the Duo, the system date picker in Review Inbox and Upcoming's swipe, day headers written four ways,
  "Done" with three looks, empty states in four styles, the Mac Settings page's name shown twice, the companion on
  the "+" covering a row's chevron.
- **Not seen running**: a real zone change on a device; the location question on a real Mac; real weather for a
  hot day or snow; the share sheet on a real Mac; anything on macOS 27.

## Round 18 record (2026-11-11; sessions 79–81 merged for 0.9.2)
Three sessions on George's turn, all Opus 5.5, supervised by a Fable 5.2 chat: 79 `companion-cast` (max, 9 commits),
80 `weather` (high, 8), 81 `widget-completion` (xhigh, 12). Merged 80, 81, 79; one conflict, the generated project
(regenerated). The supervisor committed `CompanionSky` (core) and `CompanionSkySource` (app) before the worktrees
were cut, so 79 and 80 compiled apart and met there. Supervisor follow-ups: three fixes for the CI runner's Xcode
26.6 (two type-check timeouts, and `IntentExecutionTargets`, which only the 27 SDK has: guarded with
`compiler(>=6.4)`), the Companions footer's words, the 0.9.2 notes.
After the round:
- **Companions**: still by default (`CompanionSchedule`: a gesture every 45 to 120 s, the flourish after 45 min plus
  a random stretch averaging 2 h 15 of showing time, kept in the app group's defaults; a tap plays it if none has
  for 20 min); one per theme (`CompanionCast`: Slate Nod, Midnight Quill, Nord Hush, Rosé Pip, the rest Nod); one
  place per platform (the Mac's search field; the "+" on iPhone and iPad, one line in `QuickAddEntry`); asleep 22:00
  to 07:00; a still variation for rain or storm and for snow, read from `CompanionSkySource`. Debug: `-companion
  hush`, `-companionHour 23`, `-companionPlay flourish`, `-companionSky rain`.
- **Weather**: `Services/Weather/*` (`CompanionWeather`), WeatherKit behind Extras → Weather, off by default,
  reduced-accuracy location, at most one request an hour and only while the app is in front. The app's
  entitlements carry `com.apple.developer.weatherkit`; Apple's server answers only once George has ticked WeatherKit
  under App Services for the App ID. Debug: `-seedDemoSky rain`, `-seedDemoWeatherAccess denied`.
- **Widget taps**: `WidgetCompletionIntent` (in the app and the extension), `WidgetOutbox` (one file per tap in
  the App Group, written before anything else; only the app removes them, a ledger stops a second apply),
  `WidgetCompletionCenter` (the app applies through `TaskActions` and `Flipboard`, and the row leaves the snapshot
  only after an export that started after the completion has finished), `WidgetRefresh` (background refresh on iOS,
  an hourly settle on the Mac). On iPhone and iPad the intent runs in the app's process (`LiveActivityIntent`); on
  the Mac in the extension, which rings `WidgetOutboxBell` for the running app. Debug: `HITLIST_WIDGET_SUFFIX`,
  `-widgetExportDelay`, `-widgetTapProbe`.
- **Building for the CI runner**: it has Xcode 26.6 (Swift 6.3, the macOS 26 SDK). A symbol that only the 27 SDK has
  needs `#if compiler(>=6.4)`; arithmetic that mixes numeric conversions inside a closure needs one step per line.
  Only a push shows it: the local `-warn-long-expression-type-checking` scan rated the line CI rejected as fast.
Left for later: four themes still share Nod; the Duo's upright "+" (`IslandAddButton`) has no companion; a companion
on screen across 22:00 stays awake until the app is left; no flourish in rain or snow; the Mac must be running for a
widget tap to finish, and a real desktop widget tap, a real iCloud push to a widget and the background refresh were
never seen running; shared-list tasks have no checkbox on the widget and the Lock Screen widget has no button; side
stores `HITList-s79`, `HITList-s80`, `HITList-s81` and `HITList-sup18` in the Mac app group folder (delete by hand).

## Round 17 record (2026-11-10; sessions 74–78 merged for 0.9.1)
Five sessions on George's turns, all Opus 5.5, supervised by a Fable 5.2 chat: 74 `widgets` (xhigh, 10 commits), 75
`motion-polish` (xhigh, 11), 76 `companions` (max, 4), 77 `calendar-events` (high, 9), 78 `steady-bolt` (xhigh, 8, added
an hour in on George's note about the bolt and a sync blip). Merged 78, 77, 76, 74, 75; conflicts only in the
generated project (regenerated) and `project.yml` (two info keys, both kept). Supervisor follow-ups: brief 75's glide
line in `SidebarView`; `release.sh` checks the embedded extension; the Mac sidebar's 200 pt minimum (the column-width
modifier sat under round 16's toolbar modifiers and was not applied: the divider rested at 148 pt); Quill shows only
when the Settings row has room; the 0.9.1 notes; `dev/ROADMAP.md` rewritten. Tests after the round: core 528, Mac 1462,
iOS 1421, UI 45 (10 skipped: the tours that run on demand).
After the round:
- **Widgets**: one extension, `HITListWidgets/` (`com.trammells.hitlist.widgets`, registered with App Groups by
  automatic signing), for iPhone, iPad and the Mac. It reads `widget-snapshot` JSON the app writes into the App
  Group (`Services/Widgets/*`; a side store writes its own) and asks core's rules (`UpcomingDays`, the Today and
  switch rules); it never opens the store. `hitlist://task/<id>`, `/today`, `/upcoming`, `/flipboard` route through
  `Services/DeepLinks` and `IntentRouter`. Design-system files are compiled into the extension from the app
  (`project.yml`): if one of them starts to use an app-only type, the extension stops building. The version lines sit
  at the project level; the extension has none.
- **A Debug Mac build registers its widget extension with PlugInKit.** List with `pluginkit -m -v -i
  com.trammells.hitlist.widgets`, and unregister your build's with `pluginkit -r <path to the .appex>` when you
  finish, or George's widget gallery may offer a build that is about to be deleted.
- **A Debug Mac app shares the real app's saved window state** (frame, sidebar width, sidebar hidden; AppKit's own
  defaults, not the app group's): leave the window as you found it, sidebar shown and at its usual width.
- **Companions**: `Views/Companions/*`, `Support/Companions/*`; characters are data (`CompanionCharacter`, frames as
  rows of palette letters), `CompanionClock` picks the frame, one perch line per host view. Nod (search field) and
  Quill (Browse's foot, the Mac sidebar's Settings row). `-companionDemo all` plays the flourishes. Original
  characters only (SUPERVISOR §7).
- **Calendar events**: `Services/Calendar/*` (EventKit behind a read-only protocol), `Views/Calendar/*`, core's day
  rules; off by default, device-local keys; `-seedDemoEvents YES` fakes a day.
- **Sync marks**: `CloudSyncMonitor.state` and `accountStatus` are steadied (`SyncSteadiness`, `AccountSteadiness`);
  `rawState` and `rawAccountStatus` are the instant truth (the strike gate and the log read them). `SyncState` has
  `.retrying(since:)`. `-syncReplay YES` plays four minutes of raw states.
- **Motion**: `MotionUITests` films each family (`TEST_RUNNER_HITLIST_MOTION=1`); `macSidebarSelectionGlide`; the
  iPhone card follows the keyboard's own curve one run-loop turn after UIKit's animation block.
Left for later: on the Mac a completed row's gap closes in one frame and its flash snaps (`TaskListView` is a
system `List`); the Mac's widgets and a `hitlist://` link on the Mac were never seen running; no completing from a
widget; a busy calendar day pushes Today's tasks down (no collapse); a day with events and no tasks still says
"Nothing due"; Check iCloud… still says "sign in again" for a temporary answer; no third companion; Quill's inked tip
is faint on Graphite; the keyboard curve was fitted on the iOS 27 simulator only; a session scripted a system
permission prompt and reset a permission with `tccutil` (now forbidden above); side stores `HITList-s74*`,
`HITList-s75`, `HITList-s76`, `HITList-s77*`, `HITList-s78` and `HITList-sup17` in the Mac app group folder (delete
by hand in Finder).

## Round 16 record (2026-11-10; sessions 70–73 merged for 0.9.0 (21))
Four sessions at once on George's turn, all Opus 5.5, supervised by a Fable 5.2 chat: 70 `mac-chrome-27` (xhigh, 9
commits), 71 `quick-add-monthly` (high, 7), 72 `switchboards` (xhigh, 9, schema V6), 73 `browse-and-bolt` (high, 4).
Merged 71, 73, 70, 72; conflicts only in `dev/ROADMAP.md` (rows kept) and the generated project (regenerated).
Supervisor follow-ups: Group and label counts leave out unlisted switches (`SidebarCounts.group`, `.label`), the editor's
"Add to Flipboard" words, the demo week's green flipboard label, `NewSwitchboardRow` at the Flipboard's foot (on iPhone
"New Switchboard…" sat only behind a long press on the sound button), notes per build (`WhatsNew.Entry.build`,
`release.sh`'s `## 0.9.0 (N)` check and stamp).
After the round:
- Core: `SwitchboardSchedule` (a board's day and week from its reset time), `FlipboardSwitch.listing` (a switch is
  `.hidden` unless opted in and due), `FilterableTask.filterSwitchOptedIn` and `filterSwitchboard`,
  `RecurrenceRule.Place` (a day, the last day, a weekday in the month, a date in the year; a sixth part of the encoded
  string that builds before 0.9.0 (21) ignore), `QuickAddParser+Repeats.swift`.
- Mac: `Views/MacChrome/*` (`MacSidebarRow`, `MacToolbarChrome`, `ToolbarPill`, `WindowFocusGuard`). The sidebar is a
  scroll view of our rows, not a `List`; the toolbar's background is hidden and a `Theme.background` band is drawn
  under its items. Debug arguments: `-focusSearchAtLaunch YES` forces macOS 27's bad case (a text field holding the
  keyboard at launch), `-flipboardNow` sets the Flipboard's clock for screenshots.
- Still the system's on the Mac, so macOS 27 can still differ: whether the sidebar column floats or sits flush, the
  toolbar's height and gaps, menus, and the task list's own selection highlight and header hairlines (`TaskListView`
  is a system `List`). Owning the column's shape means our own split view and top bar: a round of its own.
Left for later: no swipe to delete on the iPad's full sidebar (`SidebarView`); a long repeat chip ("Second Tuesday of
the month") runs past the editor card's edge until scrolled; the Repeat card was checked on iPhone only; VoiceOver and
Full Keyboard Access on the new Mac sidebar are unchecked; typing a letter no longer jumps to a sidebar row; a
weekly board's timed switch is due on the reset day only (no weekday of its own); two Apple accounts sharing still
untested; side stores `HITList-s70a`, `HITList-s71`, `HITList-s72a`, `HITList-s73` and `HITList-sup*` in the Mac app
group folder (delete by hand in Finder).

## Round 15 record (2026-11-08; sessions 64–69 merged for 0.9.0)
Six sessions at once on George's turn, all Opus 5.5: 64 `shared-group` (xhigh, 8 commits), 65 `editor-quick-add`
(xhigh, 7), 66 `mac-chrome` (high, 6), 67 `type-scale` (xhigh, 3), 68 `bolt-slam` (xhigh, 4), 69 `flipboard-add` (xhigh,
6). Merged 68, 69, 67, 65, 66, 64; conflicts only in `dev/ROADMAP.md`, the generated project and `HITListUITests.swift`
(65's new test kept, 64's replacement of 62's kept). Supervisor follow-ups: 67's measured Mac row details (a light circle
8 pt from the title and 1 pt lower, a 1 pt date icon; `TaskRowMetrics`), Group dots in the editor's Move to… and its
typed-Group row, the Mac Extras subtitle; George's tweaks (the "+" in the Confirm pill's look, tips outside the
quick-add card, the Flipboard lights). Left for later: the Priority and Repeat cards' buttons take keyboard focus only
with Full Keyboard Access (`PopoutPickers`); `TokenHighlightField`'s `apply` can overwrite a letter just typed when its
owner is rebuilt mid-keystroke inside a keyboard-height `GeometryReader` (69's finding, worked around in the Flipboard
card; a guard in `apply` would fix it everywhere); on iPhone the toolbar pill is still about 4 pt wider on the
Flipboard than on a list: iOS 26 sizes a toolbar menu by its glyph and ignores a frame on the menu, on its label and on a
container label (tried all three; only a plain Button took a width), so the fix is a narrower glyph or a different
control there; on a simulator that behaves as if a hardware keyboard is attached (the long-lived "iPhone 17"), the
editor's date card does not open while the title has focus, so run UI tests on a fresh simulator, and an iPad with a
hardware keyboard may show the same; the quick-add tips show in the floating Mac card and the iPhone card
but not in the Mac's inline and board cards; two Apple accounts sharing still untested; side stores `HITList-s64*`,
`HITList-s65`, `HITList-s66`, `HITList-s68*`, `HITList-s69*`, `HITList-s15*` and `SharedTasks-s64a/b.json` in the Mac app
group folder (delete by hand in Finder).

## Round 14 record (2026-11-07/08; sessions 61–63 merged for 0.8.1)
61 `lists-cleanup` (xhigh, 6 commits), 63 `duo-and-shell` (high, 3) at once, then 62 `shared-in-lists` (xhigh, 6) on
the merged lists. No conflicts. Supervisor follow-ups: Upcoming's iPhone title made large; the disabled "Sort"
placeholders removed from Group, label and filter lists; day headers hide the day on their rows in every list; the
Duo test sums `IslandMetrics.sideChromeHeight`; Browse's Inbox count includes shared tasks. The supervisor looked at
every screen on both platforms before the hand-over (ROUND-14's list) and sent the screenshots with it.
Core API after the round: `ListSort` (priority/group/date) with `Preferences.inboxSort`/`todaySort`; `SearchIntent`
(Browse's field: text or a filter query); `ListRow` (a task of yours or a `SharedRow`) feeding `TaskOrdering`,
`GroupedOrdering`, `FlipboardSwitch.listing` and `UpcomingSchedule`; `SharedRows` (observable, actions through the
shared store); `SidebarItem.sharedList(id)`. Left for later: the Mac shared editor panel is drawn by the list column
rather than `PopoutHost`; a shared list's screen keeps the Shared screen's card look; the badge and morning summary
count neither shared tasks nor red switches as George means them; two Apple accounts untested for shared rows; side
stores `HITList-s6*.store` and `SharedTasks-s62*.json` in the Mac app group folder (delete by hand).

## Round 13 record (2026-11-07; sessions 57–60 merged for 0.8.0)
Four sessions at once on George's turn, all Opus 5.5: 57 `groups` (xhigh, 9 commits), 58 `tab-motion` (high, 4),
59 `flipboard-intervals` (xhigh, 6), 60 `review-inbox` (high, 5). Merged 59, 57, 58, 60; the only conflicts were the
shared `HITListUITests.swift` (both sides kept, twice). Supervisor follow-ups: 59's list-view lines applied by hand to
57's reworked `TaskListView`, `InboxView` and `BrowseView` (`todaySection(of:)` in both Today layouts,
`Flipboard.completion`/`completeRow`/`undo` in the completion paths, `now:` passed to `inbox`, `sorted` and `search`);
`GroupedOrdering`'s default `order` became a closure once `TaskOrdering.sorted` gained `now:`, and its default
`sectionOf` is `todaySection(of:)` so a grouped and an ungrouped Today agree about switches; the motion table in the
design-system README gained `tabPill` and `tabSwitch`; the 0.7.2 notes were renamed 0.8.0 with the round's lines.
Sessions' notes, patches and screenshots live in `~/Library/Application Support/Claude/side-session-notes/<id>/`.
Left for later: the task editor's Group row shows a coloured "#" rather than the Group's dot (`TaskPopout`); the
morning summary and the app badge still count an overdue red switch as overdue; two side stores `HITList-s59a.store`
and `HITList-s59b.store` sit in the Mac app group folder (listing it from a shell hangs; delete by hand).

## Round 12 (2026-11-05; briefs 53–56 in parallel, the build friends get)
Still 0.7.0 (17), unreleased: add to its notes, never a new version. No schema change. Ownership: 53 profile menu
(`ProfileMenu`, Browse's profile button, new `WhatsNewPopout`/`BetaFeedback`); 54 `SyncStatusViews`/`SyncState`
(bolt); 55 Claude settings + `ClaudeAccess` default + `HingeCreak*` + the Extras hinge row; 56 `Views/Tips/*`,
`UpcomingBoard`, `TaskRow` meta line, `HITListUITests/*`. The official Claude logo is not used (Anthropic's trademark
guidelines require their prior approval).

## Round 12 record (2026-11-05; sessions 53–56 merged into 0.7.0 (17), the Friends build)
53 `profile-feedback` (profile menu: What's New popout, Send Beta Feedback mail to george@trammells.com with a
version/device footer, version line), 54 `bolt-strike` (bolt 12.65 pt, `BoltStrikeGate` + strike motion, Debug
`-boltStrikeDemo YES`), 55 `claude-hinge-polish` ("Only tasks with @claude" default/left, audio audit test, wooden creak
at ≤ −18 dBFS, "Creaky hinge"), 56 `release-polish` (tips wait for `HITTip.settled`, inline quick-add tips, board meta
flow layout, Duo board safe area, `FirstRunUITests`). All High. Supervisor: merged 47's single-writer focus fix; found
that interactive Liquid Glass on the iPhone "+" ignored its first tap after `allowsHitTesting` came back (the button is
now removed and re-inserted; `testPlusOpensTheNextCardRightAfterAnAdd`); toast tail truncation;
`CADisableMinimumFrameDurationOnPhone`; the official Claude logo NOT used (Anthropic's trademark guidelines require
their prior approval). 0.7.0's release stopped at the Shared Tasks container's schema check, so it ships as 0.7.1 (17)
with George's last fixes: the Mac's Send Beta Feedback copies the address instead of opening Mail, and the bolt
strikes only on the first good sync after launch, after ≥ 1 min away, or after ≥ 1 min of sync trouble.

## Round 11 record (2026-11-05; sessions 47–52 merged for 0.7.0 (17))
Six sessions on George's turn: 47 `highlight-engine` (xhigh), 48 `reminder-language` (xhigh, schema V5), 49
`extras-claude-polish` (High), 50 `duo-hinge` (xhigh), 51 `shared-tasks` (max), 52 `tips-spotlight-cleanup` (High).
Mid-round the supervisor added `scripts/window-drive.sh` (George granted Accessibility) and sent it by `SendMessage`;
47, 48, 49 and 52 then drove their Debug Mac apps for real and found bugs the hosted tests missed (pointer flicker
from SwiftUI's own cursor handling, box geometry). 50 drove the real fold through Device Hub's AX buttons.
51 chose a second CloudKit container `iCloud.com.trammells.hitlist.shared` (registered by automatic signing,
permanent), `CKSyncEngine`, a JSON store per task store, push routing in `SyncAppDelegate`, and an iOS scene delegate
for share acceptance; off by default. Supervisor follow-ups: Claude `reminder_at` and add_task wording, the
tips' attach lines, README reminder grammar, reminder/summary taps routed through `IntentRouter` (nothing listened for
`.openTask`), side-store runs keep their own settings suite (`AppGroup.suiteName(suffix:)`), privacy policy sections,
`release.sh` drift check over both containers. Lessons: launch a Debug Mac app with `open -g -n --env
HITLIST_STORE_SUFFIX=… <app> --args -disableCloudKit YES` so it never takes George's keystrokes, then `open <app>`
to bring it forward for window-drive; check nothing covers the window first. Known open: on the Duo's inner display
on its side the system bar overlaps the board's last column; a friend accepting a Shared Tasks link is untested
(George tests with friends on TestFlight).

## Round 11 ownership
- `47-highlight-engine` (xhigh): `TokenHighlightField`, new `Views/Popouts/HighlightText/*`, the field's call sites in
  `QuickAddPopout`/`CompactQuickAddCard`, `HighlightAreaTests`, new `HighlightFieldTests`.
- `48-reminder-language` (xhigh, merged last): parser (+Disabled), `DateExpression`, `Snapshot*`, `QuickAddDraft`,
  `Models.swift`, `SchemaVersions.swift`, new `SchemaV4Models.swift`, notifications, `TaskActions` reminder paths,
  `SnapshotBuilder`, `Deduplicator` (field), `QuickAddPopout` Reminder chip region, reminder picker, `TaskPopout`/`Editor/*`
  Reminder pill region, `TaskRow` meta bell, `SchemaTests`, new `ReminderDateTests`.
- `49-extras-claude-polish` (High): `ClaudeSettingsSection`, `Services/Claude/*`, helper messages, `docs/connect-claude.md`,
  `PopoutController`, "Delight" strings (`DelightSettingsSection`, `MacSettingsSection`), `SidebarView`/`ProfileMenu`
  spacing, `CompactQuickAddCard` + `QuickAddPopout` compact Discard, `InlineAddRow` in `QuickAddEntry`.
- `50-duo-hinge` (xhigh): `Views/Duo/*`, `MobileShell`, `MobileTabBar`, `ContentView`, `PopoutHost`, `UpcomingView.showsBoard`,
  `TaskPopout` fold continuity, `Views/Flipboard/*` column count, new `HingeCreak*`, one row line in `DelightSettingsSection`.
- `51-shared-tasks` (max): new `Services/Sharing/*`, `Views/Shared/*`, its own model/schema, `SyncAppDelegate` share
  acceptance, `BrowseView` (preview row + entry), one line in `SidebarView`, entitlements/`project.yml` only if a
  second container is needed.
- `52-tips-spotlight-cleanup` (High): new `Views/Tips/*`, `Services/Spotlight/*`, `Services/Intents/*`, one line each in
  `HITListApp` and `AccountSwitch`, About sections, `MacSettingsPage`, `SettingsRouter`, dead files nobody owns.
- Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` version pin.

## Round 10 record (2026-11-04; sessions 39–46 merged for 0.6.0 (16))
Eight desktop-app sessions, all started on George's own turns: 39 `board-inline-add` (High), 40 `profile-chrome`
(High), 41 `quick-add-polish` (High), 42 `sync-profile-hardening` (xhigh), 43 `claude-connector` (xhigh), 44
`holiday-delight` (High), 45 `iphone-duo` (xhigh), 46 `app-intents` (High, started mid-round). Cross-session fixes went
by `SendMessage` to the owning session while it still ran (42's `ProfileStore.shown` to 40; 41's Discard findings to
39 and 45). Supervisor follow-ups: `PopoutController` listens for `.accountDidSwitch`; the holiday accent on the "+";
privacy policy sections for Claude and Siri; 46's `.intentRouting` lines in the shells. No schema change. Known and
open: the account-switch banner overlaps the large title on iPhone; Claude's completions post
`.claudeDidCompleteTask` with no Undo toast listening; the Duo inner display shows the iPhone Upcoming list
(`UpcomingView.showsBoard` is iPad-idiom only); editor typing is lost when the editor moves sheet ↔ column across a
fold; the Mac lists' `InlineAddRow` × does not ask Discard. Lesson: a session given a Debug probe on the Mac must set
`HITLIST_STORE_SUFFIX`, or an in-memory run can write into the TestFlight app's app-group defaults (39 did once).

## Round 10 ownership (2026-11-04; briefs 39–45 run in parallel, all seven at once)
Next version 0.6.0 (16). No schema change this round: a fix that needs one stops and reports. Every session makes its
own simulator (`HITList-NN`; 45 an iPhone Duo, 39 an iPad) and deletes it at the end.
- `39-board-inline-add` (High): `UpcomingBoard` (+ card file), new `CompactQuickAddCard`, `QuickAddPopout.swift`,
  `QuickAddEntry.swift` (Mac focus), `UpcomingBoardTests`, new `CompactQuickAddTests`.
- `40-profile-chrome` (High): `MobileTabBar`, `BrowseView`, `SidebarView`, new `Views/Account/ProfileMenu.swift`,
  `SettingsRouter`, `MobileChromeTests`, new `ProfileMenuTests`.
- `41-quick-add-polish` (High): parser (+Disabled), `TokenHighlightField`, `QuickAddDraft`, `TaskPopout`/`Editor/*`
  (× only), `HighlightAreaTests`, `PopoutTests`.
- `42-sync-profile-hardening` (xhigh): `ProfileStore`, `Deduplicator`, `CloudSyncMonitor`, `AccountWatch`,
  `Services/Sync/*`, `ModelContainerFactory`, `LocalBackup`, notifications (account switch), `AccountSettingsSection`,
  `ICloudSettingsGroups`, `SyncStatusViews`, new `AccountSwitchTests`.
- `43-claude-connector` (xhigh): new `Services/Claude/*`, new helper target, `project.yml` target, Mac entitlements,
  new `ClaudeSettingsSection`, one line in `SettingsView`, the Claude entry in `MacSettingsSection`, `docs/claude.md`.
- `44-holiday-delight` (High): new HITListCore `Holidays.swift`, `Views/Delight/*`, `Support/Delight/*`,
  `DelightSettingsSection`, `TaskRow` overlay hook only.
- `45-iphone-duo` (xhigh): `ContentView`, `MobileShell`, `PopoutHost`, new `Views/Duo/*`, new `DuoLayoutTests`.
- Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` version pin, everything else.
  ROADMAP: only your row. `project.yml`: add files only (43 also adds its target).

## Round 9 record (2026-11-04; sessions 34–38 merged for 0.5.0 (15))
Five desktop-app sessions started by the Opus 5.5 supervisor: 34 `accounts-profile` (xhigh, 171 turns), 37
`highlight-merge-override` (High, 96), 38 `mac-upcoming-board` (xhigh, 158) first; then 35 `tabs-browse` (High,
26) and 36 `editor-space-confirm` (High, 247), cut from master after the first three merged. Sessions in the
second wave were proposed as cards George started: the app refuses `start_session` on a turn opened by a
background-task or session event. Supervisor follow-ups: the sync bolt and dot are grey for someone who never
used iCloud (`SyncBolt.everSignedIn`), an Upcoming day's add card keeps the day when a priority/label/reminder sits
beside the time, stale comments. Schema V4 (`Profile`) is in CloudKit Development; George deploys it before 0.5.0
uploads. The repo is public and GitHub Pages serves `docs/` (privacy policy at
https://aeronyx.github.io/HITList/privacy/). Sessions need George to grant simulator tap access in their own
panel; 35 never got it, so the supervisor tapped its menus.

## Round 9 ownership (2026-11-04; briefs 34–38; 34, 37, 38 first, then 35 and 36)
- `34-accounts-profile` (xhigh): `Models.swift`, `SchemaVersions.swift`, new `SchemaV3Models.swift`,
  `ModelContainerFactory` model list, new `Services/ProfileStore.swift`, `Deduplicator` (profile merge),
  `SyncLog` category, new `Views/Settings/AccountSettingsSection.swift`, one line each in `SettingsView.swift`
  and the Mac settings section list, `AboutSettingsGroup`/`MacAboutSection` (privacy link), `Diagnostics.swift`,
  `ICloudSettingsGroups.swift` (account lines), new `docs/`, `SchemaTests`, new `ProfileTests`.
- `35-tabs-browse` (High): `Views/Tabs/*` (iPhone), `BrowseView`, `ScreenMenu` iPhone branch, start tab in
  `SettingsPreferences`/`GeneralSettingsSection`, `screenChrome` call-site items, `MobileChromeTests`.
- `36-editor-space-confirm` (High): `TaskPopout`, `Editor/*`, `QuickAddPopout` footer + title submit,
  `TokenHighlightField` submit/Return lines, `PopoutHost` detents and editor dismiss, `PopoutTests`.
- `37-highlight-merge-override` (High): HITListCore `QuickAddParser` (+Disabled), `TokenHighlightField` areas,
  drawing and tap targets, `QuickAddDraft` (`disable`, reminder text), new `HighlightAreaTests`.
- `38-mac-upcoming-board` (xhigh): `Views/Upcoming/*` (iPhone branch unchanged), new `UpcomingBoard`,
  `UpcomingSchedule`, `TaskRescheduling`, `QuickAddContext` day context, `UpcomingScheduleTests`, new
  `UpcomingBoardTests`.
- Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, the `SettingsTests` version pin, everything
  else. ROADMAP: only your row. `project.yml`: add files only.

## Round 8 record (2026-11-03; sessions 31–33 merged for 0.4.1 (14))
Three desktop-app sessions on the subscription, all merged by Fable the same day: 31 `quick-add-language`
(High, 97 turns), 32 `subtasks-editor` (xhigh, 137 turns), 33 `feel-and-chrome` (High, 143 turns). Fable's
follow-ups after the merge: the editor's time setters and `TaskActions.reschedule` call
`TaskActions.syncRepeatTime(of:)`; sidebar and Browse counts skip sub-tasks. Schema V3 (`TaskItem.parent`)
is in CloudKit Development; George deploys it to Production before 0.4.1 uploads.

## Round 8 ownership (2026-11-03; briefs 31–33 ran in parallel; kept for the record)
- `31-quick-add-language` (branch `quick-add-language`, High): HITListCore `DateExpression`, `QuickAddParser`
  (+Disabled), `RecurrenceRule`, `TaskOrdering.priorityThenDue`, `FilterQuery.defaultSort`; `TaskActions`
  roll-over/`setRecurrence`; `QuickAddPopout` suggestion row (removal); `QuickAddContext`; `QuickAddDraft`
  `restoredDraft`; help text; their tests.
- `32-subtasks-editor` (branch `subtasks-editor`, xhigh): `Models.swift`, `SchemaVersions.swift`, new
  `SchemaV2Models.swift`, `SchemaTests`; `TaskActions` (all but the roll-over's time); `Deduplicator`;
  `Snapshot`/`SnapshotBuilder`; `TaskPopout.swift` + new `Views/Popouts/Editor/`; `QuickAddPopout` option bar
  + subtask lines; `QuickAddDraft` subtask lines; `TaskRow` meta line; subtask exclusion in `TaskOrdering` /
  `FilterQuery`; `project.yml` (adding files only).
- `33-feel-and-chrome` (branch `feel-and-chrome`, High): `SyncAppDelegate` Mac half, `HITListApp.swift`
  window lines, new Mac window helper; `QuickAddEntry.swift`; `CompletionFeedback.swift`, new `TapHaptic.swift`;
  `CompletionToast.swift`, `CompletionMotion.swift`; `PopoutHost` toast placement; list toast call sites;
  one haptic call in `QuickAddPopout`; `HITTokens.swift`, `IslandMetrics`; `TaskRow` line height.
- Nobody: `scripts/`, `dev/briefs/`, `CHANGELOG.md`, `WhatsNew.swift`, everything else. ROADMAP: only your row.

## Where things stand (2026-10-31, after round 3 and Fable's follow-ups)
On master and in TestFlight build 5: design system (`HITList/Support/DesignSystem/`, README = component
guide), Inter typeface (`HITType` roles only; never `.font(.subheadline)`), schema V2 (`reminderOffsetMinutes`,
`deadline`, `locationName`, `flipTarget`, `flipCount`, `flipPeriodStart`; V1 frozen in SchemaV1Models.swift),
shared due colours (`HITColor.due`), popouts (`HITList/Views/Popouts/`: oval quick-add card with the "+"
options bar, reminder offsets `!15mb`, task popout with Deadline/Location), the iPhone tab shell
(`HITList/Views/Tabs/`: Inbox, Today, Upcoming, Browse, oval "+" in `MobileShell`; iPad and Mac keep the
sidebar), Today's Overdue + day sections sorted priority-then-due (`HITListCore/.../TaskOrdering.swift`), the
Inbox rule (dated tasks in any Group + undated tasks with no Group; undated grouped tasks only inside their
Group), "Group" as the user-facing word for Project, Flipboard long-press menu, faint-green lamp and charging
switches. `TaskRow` aligns the checkbox and priority badge on the title's first line and draws its second
line with `MetaItem` (never `Label`, whose List style reserves a wide icon column).

Lesson from round 3: commit after every item. Twice the runner's permission stream closed near the end of a
long session and every write (git, xcodegen) was refused from then on; work left uncommitted had to be
committed by hand afterwards.

Also on master since build 5 (Fable, 2026-10-31): `HITType.taskName` is one step above body (20 bold on
iPhone, 15 on Mac; George found 14 too small). `HITList/Support/AppInfo.swift` (`AppInfo.versionLabel` =
"0.2.0 (6)"), shown in Settings → About. `HITList/Support/Preferences.swift`: shared preference keys
(`startTab`, `defaultReminderOffsetMinutes`, `theme`, `reduceEffects`); add your own keys only as an
`extension Preferences` in a file you own. `SyncIndicatorDot` (6 pt, in `SyncStatusViews.swift`).
`Views/Settings/AppearanceSettingsSection.swift` is a stub for session 22. `CHANGELOG.md` has a section per
version; `scripts/release.sh --version X.Y.Z` (Fable only) runs the preflight tests (core, macOS, iOS) before
anything is archived and refuses a version without a changelog section. Liquid Glass (iOS 26 / macOS 26)
is allowed behind `#available` with the slate look as fallback; deployment targets stay iOS 18 / macOS 15;
the API names are listed in briefs 20 and 22 and were checked against the Xcode 27.1 SDK interface.

## Round 7 (2026-11-02; sessions 25–30, all merged for 0.4.0 (13))
- Sessions 27 `dates-and-times` (High, $4.20), 28 `quick-add-card` (High, $4.65), 29
  `completion-popout-push` (High, $7.23) ran in parallel on George's nine decisions; 30 `beta-final-review`
  (Max, $16.64) reviewed the merged result (six fixes). Self-launched from Fable's Bash; reports read from
  the task output files.
- Session 25 `sync-robustness` (Max, $36.61, 74 min, merged 2026-11-02): sync log, watchdog (5 s rule),
  CloudKit environment and push diagnostics, Settings → iCloud → Sync log, the stuck-sync relaunch, the
  Development side store. Found the Nov 1 Mac hang (an import that never ended; CloudKit refused every
  later request, NSCocoaErrorDomain 134417).
- Session 26 `beta-review` (Max, $33.89, 62 min, merged 2026-11-02): 12 core fixes, each with a failing
  test first (reset safety, in-memory fallback for a damaged store, complete backups, Debug/TestFlight
  separation, reminder rescheduling on every save, stale-reminder completion, sticky draft fields, blank
  titles, integer overflow in quick add, environment detection from signed entitlements, first-import
  grace). Nine behaviour decisions left for George are in its report (Fable's session notes).

## Round 6 (finished 2026-11-01; kept for the record)
- `24-mac-settings-page` (branch `mac-settings`): `SettingsView.swift`, `Views/Settings/*`, new
  `Views/Settings/Mac/*`, `HITListApp.swift` (Settings scene + appSettings command only), `ContentView.swift`
  (`.settings` item + screen), `SidebarView.swift`, `openAppSettings` in `Tabs/ScreenMenu.swift`,
  `SettingsTests`, new `MacSettingsTests`, its ROADMAP row.
- Nobody: everything else. Fable's build-7 polish is already on master (`Tabs/ScreenMenu.swift` layout,
  `SyncStatusViews.swift`, `Popouts/*`, `Theme.swift`, `Upcoming/*`, `Browse`, `Flipboard`).

Also on master since build 8 (Fable): `ThemePalette` has a ninth colour, `bolt`, and `SyncBolt.look(for:)`
decides the bolt's shape (filled / hollow / struck through) and colour per state; the Mac Settings page
(`MacSettingsPage`) takes the whole window: `SplitContent` sets the split view to `.detailOnly` while
`SidebarItem.settings` is selected and the page's Back (`SettingsRouter.close()`) restores the previous
list; `AddSwitchTile` is the Flipboard grid's last cell; Inbox groups by priority; Upcoming's view options
hold Show overdue and Days shown; the Mac quick-add title is a `TextEditor` with a hidden background;
`Preferences.compactRows` reaches `TaskRow`.

Also on master since build 7: `screenChrome` draws the small `SyncBolt` outside the toolbar's shared glass
(`sharedBackgroundVisibility(.hidden)` on iOS 26 / macOS 26) and then exactly two controls: the screen's
own (`viewOptions`) and the "…" with Settings… and the version on every platform; eight theme palettes;
the iPhone quick-add card is put away in one motion (`PopoutHost.retireQuickAdd`); build output lives in
`build.noindex/` and Xcode's DerivedData in `~/Library/Developer/Xcode/DerivedData.noindex` so Spotlight
never offers a stale HITList.app.

## Round 5 (finished 2026-11-01; kept for the record)
- `23-mac-pickers` (branch `mac-pickers`): `Views/Popouts/PopoutPickers.swift`, new `Views/Popouts/Pickers/*`,
  new `Support/DesignSystem/HITCalendar.swift` (+ README section, gallery entry), the chip `.popover` call
  sites and `chipBinding` plumbing in `QuickAddPopout.swift` and `TaskPopout.swift`, `PopoutTests`, new
  `PickerTests`, its ROADMAP row.
- Nobody: everything else. Fable is polishing the iPhone lists and the Mac toolbar on master at the same
  time (`MobileShell`, `TaskRow`, `TaskListView`, `InboxView`, `UpcomingView`, `PopoutHost`, `QuickAddEntry`,
  `TokenHighlightField`, `InboxProcessView`); do not touch those.

Also on master since build 6: `screenChrome` shows the "…" on the Mac too (Inbox review and Flipboard
actions live there on every platform); the iPhone shell is a bottom-aligned ZStack with
`contentMargins(.bottom, IslandMetrics.chromeHeight + 8)` on the stack (a `safeAreaInset` on the
NavigationStack did not reach the lists inside it on iOS 26).

## Round 4 (finished 2026-11-01; kept for the record)
Sessions 20 (iphone-chrome), 21 (settings-v2) and 22 (motion-themes) are merged. 20 and 21 stopped early
when the runner's 1 MB message buffer overflowed on a screenshot Read; the runner now allows 64 MB. Fable
finished brief 20's items 3–9 on master: `Views/Tabs/ScreenMenu.swift` (`screenChrome` = view-options
icon + "…" on every screen; iPhone "…" has Settings, the version and `SyncIndicatorDot`), `hitGlass` and
`HITGlassContainer` replace session 20's own guard, `IslandMetrics.chromeHeight` positions the toast,
`PopoutController.requestDelete` + one dialog in `PopoutHost` honour Confirm before deleting, the week
start preference reaches Upcoming, quick add and rescheduling, and the toast/collapse curves use the
`HITMotion` roles.

## Round 3 ownership (finished 2026-10-31; kept for the record)
- `17-mobile-tabs` (branch `mobile-tabs`): `ContentView.swift`, new `Views/Tabs/`, `TaskListView.swift`,
  `TaskRow.swift`, `SidebarView.swift`, `Views/Inbox/*`, `Views/Upcoming/*`, `Popouts/QuickAddEntry.swift`,
  `Support/Formatting.swift`, new `HITListCore/.../TaskOrdering.swift`.
- `18-quick-add-v2` (branch `quick-add-v2`): `Views/Popouts/*` except `QuickAddEntry.swift`,
  `HITListCore/.../QuickAddParser.swift` + `DateExpression.swift`, `Services/NotificationScheduler.swift`,
  `Services/Notifications/*`, `TaskActions.create`, `DesignSystem/HITChip.swift` (compact size only).
- `19-flipboard-charge` (branch `flipboard-charge`): `Views/Flipboard/*` and its tests.
- Nobody: `Models.swift`, `SchemaVersions.swift`, `SchemaV1Models.swift`, `HITTokens.swift`, `project.yml`,
  `HITListApp.swift`, `SettingsView.swift`, `scripts/`, `dev/briefs/`. ROADMAP: add only the row your brief names.
