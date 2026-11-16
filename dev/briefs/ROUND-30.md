# Round 30: grouped switches keep their timing; the engine's own container (2026-11-16)

0.9.12 was released on the evening of 2026-11-15 (build 29). George's message the next afternoon, verbatim:

> Good work; 0.9.12 is released. Please continue freely on the separate container for the iCloud engine if you
> think that's the best approach for a professional and robust (yet not overengineered) iCloud sync setup.
>
> Also, currently, when you group Switches on Flipboard, they all reset at the same time. Could you make it so that
> when you group switches that already exist that they maintain their old timing? That way we can group switches
> together one that resets once a week and one that resets every other day under the same group etc. Essentially,
> it's okay to have default reset times for a Switchboard but they shouldn't be locked to that reset time.

No sessions: the supervisor alone. Two small, exact changes, each of which had to be decided before it was typed.

## Flipboard: a board's reset is a default, not a lock

**Before.** A switch on a Switchboard had no repeat of its own: moving it onto a board (`Flipboard.move`) rewrote
its repeat to the board's cadence and its due date to the board's next period, the card hid the interval's dial
("Daily, with Before Bed"), and every switch of a board reset together.

**Now.** A switch keeps its own repeat on a board. Which clock it keeps is read from that repeat:

- its repeat is the board's cadence (plain every day on a Daily board, plain every week on a Weekly one, whatever
  its time of day): it **resets with the board**, exactly as every board's switch did before;
- any other repeat: it keeps **its own days**, exactly as a loose switch does (the interval from each flip, its
  day ending at midnight, "Flip to start", "1 of 2 days", flipped early with the question), and only sits on the
  board.

One function says it, in core: `SwitchboardSchedule.resets(_:cadence:)`. The app asks through
`TaskItem.resetBoard` (the board whose clock the switch keeps, or nil), and `filterSwitchboard` answers from it, so
every list, widget, reminder, caption and light follows without knowing: a switch on its own days is judged as a
loose one everywhere. `TaskItem.switchboard` now only says where a switch is shown.

What follows from it:

- `Flipboard.move` keeps the switch's repeat and, unless it joins or leaves a board's clock, everything else: the
  three switches of the test (`testGroupingSwitchesKeepsEachOnesTiming`) have the same due date, repeat and time
  before and after. Joining a clock (same cadence) lands it on the board's day on the side it had; leaving one
  takes it off on the side it had.
- The card has the quick choices and the dial on a board too. A new switch on a board starts on the board's
  cadence (the board's default; `SwitchDraft(on:)`, `setBoard`), and the interval row then reads "Every 1 day with
  Before Bed". An interval someone chose, or typed, or an existing switch's, is left alone by the Switchboard chip.
- `Flipboard.setRule` on a board joins or leaves the board's clock as the interval says.
- `Flipboard.update` (the board's card) re-lands only the switches that reset with the board; a switch on its own
  days is untouched by a new reset time, and joins only if its repeat is the board's new cadence.

**Why read from the repeat, and not a new field.** A stored "keeps its own days" flag would say the same thing
without the one limit below, at the cost of schema V7, a field in three places (the mirror's record type in both
CloudKit environments, the engine's schema, the backup), and a Production deploy that is forbidden until the tasks'
container's Development side is reset. Every switch that was on a board before this round carries its board's
cadence (the old move wrote it), so reading the repeat changes nothing for any of them, on any device, and a
device still on an older build reads the same rows as it always did. The limit: every week on a Weekly board, and
every day on a Daily board, mean the board's week and day; seven days from each flip on a weekly board is "7 days"
on the dial. George has not asked for that case; if he does, the flag is the answer, with the next schema change.

**Mixed builds.** A device on 0.9.12 or older shows every switch on a board on the board's clock, and its own move
or board edit still rewrites repeats, as it always did. Nothing is lost; the newer device reads what it wrote.

## The engine's own container

His word was conditional on my judgment, so the judgment first. The mirror imports every zone of its own
container's private database and takes any record whose type is a model's name for its own (session 142, round 28);
builds on the mirror stay in friends' hands for as long as they do not update. In the tasks' container the engine
was safe only by the `HL` prefix on its record types, and its test runs left those types in a schema that must one
day be deployed for the mirror's sake. In a container of its own none of that can happen, the mirror's zone stays
exactly as it was at a move (the way back), and each schema is deployed alone. The cost is one identifier in the
entitlements. That is the professional arrangement and it is less machinery, not more; a fourth would be
overengineering. So:

- `SyncEngineSwitch.containerID` is `iCloud.com.trammells.hitlist.sync`; the probe uses it; both apps' entitlements
  list it third (the tasks' stays first); a test reads the hosting app's signature for it.
- **Registered 2026-11-16** by automatic signing at the first build that listed it (permanent). Its Development
  schema held `Users` alone until the probe ran.
- `scripts/release.sh` knows it (`SYNC_CONTAINER_ID`) and compares its environments only from the release in
  which `SYNC_ENGINE_LIVE` is 1. The tasks' container is always compared on the mirror's record types alone now.
- The `HL` types stay: with the container they are a second lock that costs a prefix.

What the first minutes of a new container look like, so nobody chases it again: a send answered "Not
Authenticated: could not determine iCloud account status", the next run "Bad Container: couldn't get container
configuration from the server", while `cktool` already exported the schema; about five minutes after registration
everything passed.

Proof on CloudKit Development, in the new container (the first run of the reviewed engine against the service):

- The transport's probe: 18 of 18 steps with the mirror off, and with the mirror on the engine's records and the
  side store untouched a minute after the engine's save. (That step used to wait for the mirror to import, pushed
  by the engine's save in the shared container; across containers no import comes, which is the point, and the
  step now says so.)
- Two Debug Mac apps on side stores `r30a` and `r30b`, zone `HITList-r30`: the first sent its 10 records; the
  second, launched empty, showed them; a repeating task completed on the first reached the second when it came
  forward (two records, M7).

**A push, again.** No push reached a Debug build on this Mac in rounds 28 to 30. Two reasons turned up. On a Mac
the app never asked for pushes itself: Core Data's mirror registers once its setup succeeds, and the engine runs
with the mirror off, so nobody did; the engine registers at its start now. And two apps on one Mac are one device
to iCloud, which does not notify the device a change came from: no arrangement on this Mac alone can show a push
arriving. It needs a Debug build on George's phone beside this Mac. Until then the engine is known to sync at
launch, on coming forward and on its own schedule, and not known to wake for a push
(`dev/SYNC-ENGINE.md` section 13).

Also: a sync asked for while the engine was still starting (the app came forward in that moment) was reported as
"stopped" with an error; it is nothing (the start ends with its own sync) and is no longer said.

## Proof

- Core 1,047, Mac 2,205, iPhone 2,168 tests on the final tree, no failures. New: core
  `testOnlyASwitchOnTheBoardsOwnCadenceResetsWithIt`; the app's `SwitchboardTests` (grouping three switches leaves
  each one's due date, repeat and time as they were, and each flips and counts by its own days; a switch on the
  board's cadence joins and leaves its clock keeping its side; a board's clock changed moves only its own),
  `FlipboardAddTests` (a new switch takes its board's cadence until an interval is chosen or typed; an existing
  switch put on a board from its card keeps its timing; the dial on a board says which clock the switch keeps);
  `SyncEngineWiringTests.testTheEngineHasAContainerOfItsOwn` (the hosting app's signature lists it).
- Two tests pinned the old behaviour or an old habit and were brought in line: a switch set on a board by hand was
  expected on the board's clock whatever its repeat; and What's New had to name a Settings path in every version
  (0.9.13's changes are nowhere in Settings; the newest notes that name a path are the ones checked now).
- iPhone 17 simulator, XCUITest: `FlipboardPhoneUITests.testASwitchGroupedOntoABoardKeepsItsOwnTiming` (the demo
  week's "Water the plants", every 3 days, dragged onto Before Bed: still "every 3 days" on its tile; its card has
  the dial at 3 and no "with Before Bed"; Daily brings the words, 3 days takes them away), with the rest of
  `FlipboardPhoneUITests` and `SwitchboardUITests`.
- The Mac, by hand in a Debug app on the demo week: a new switch's card with Before Bed chosen reads "Every 1 day
  with Before Bed".
- Release archives of both platforms export and pass the packaging checks; the exported iPhone app is signed for
  Production with the three containers, the tasks' first.
- CloudKit Development, the engine's container: above.
- Pictures: `build.noindex/round-30/handover/`.

## Not done, not proven

- A push waking the engine: needs a second device (above).
- A deletion through the app on the real service (through the app it ran on the pretend iCloud in round 29; the
  probe carries markers and removals on the service). Driving the Mac app's delete menu by script failed twice and
  was not worth a third try for what the probe already shows.
- The UI suite beyond the Flipboard's two classes was not rerun: nothing else on screen changed.
- Housekeeping for George: the side stores of this round in the App Group's folder (`HITList-r30*`, their
  `.ledger` files), beside those listed in round 29's record; zone `HITList-r30` in the engine's container's
  Development side holds ten sample records; 72 merged session worktrees (about 105 GB) are still his to say.
