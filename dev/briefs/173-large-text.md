# 173: the largest text sizes: nothing cut, nothing broken in the middle of a word

Read `dev/briefs/COMMON.md` first (its "Round 34" block applies to you), then this.

George, 2026-11-18: "Please take more time to prepare a build that is truly worthy of both the new sync engine and
to be sent to a wider group of friends." Brief 169 photographed the iPhone at the largest text size and found six
screens broken. The supervisor then photographed the three sizes between. What the pictures show:

- **Up to the largest standard size (XXXL) everything holds.** Nothing you do may change a pixel there.
- **At the first accessibility size (AX1)** only quick add is wrong: its chips are cut off along their lower edge.
- **From the second (AX2) on**: Upcoming's week strip shows "…" where the days' numbers were and its month breaks
  into two lines; Appearance's theme names break in the middle of a word ("Graphit/e", "Midnig/ht"); the
  Flipboard's tiles cut their words ("every 3 da…"); the task card's row of pills runs off its edge.
- **At the largest (AX5)**: all of that, worse ("Nove/mber", "Toda/y", "Slat/e"), plus the card's "Description"
  pill cut top and bottom and "Add Sub-task" wrapped and cut.

The pictures: `…/round-34/type-before/` (AX1 `type-accessibilitym-*`, AX2 `type-accessibilityl-*`, AX3
`type-accessibilityxl-*`) and `…/round-34/169/iphone/type-ax5-*`, `type-xxxl-*` in the supervisor's notes folder
(`~/Library/Application Support/Claude/side-session-notes/local_8995b93d-4779-400a-855f-77db7b4e0b1d/`).
Look at them before you open a file.

## The rule

**What a person reads keeps growing; what they only operate stops where it still fits.**

- A task's name and notes, a row's line of date and Group, a Settings row's words, a section's header: these grow
  through AX5, as now. Do not cap them.
- Dense controls that cannot grow without breaking stop at `.accessibility1` (the largest size at which the
  pictures hold), with `.dynamicTypeSize(...)` on the smallest container that holds them, as
  `MobileTabBar` and `DatePickerCard` already do: Upcoming's header and week strip; the Week layout's header, day
  names and chips; Appearance's theme grid; the Flipboard's tiles; quick add's row of chips; the task card's row
  of pills and its sub-task rows; and anything else your pictures show cut or broken that fits this description.
  One constant for the cap (put it beside the type scale, with a comment saying why AX1), never a literal in
  six files.
- **Quick add's chips are cut at AX1 already**, so a cap alone does not mend them: find what holds the row
  shorter than its chips (`QuickAddChipRow`, `QuickAddPopout.optionBar`, the compact card) and make the row as
  tall as its chips at every size.
- Where a cap is the wrong tool (a title that should wrap rather than shrink, a grid that should go to fewer
  columns), do the right thing if it is small and say so; otherwise cap and say what a later round should do.

## Proof (yours to make and to look at)

`StrangerSweepUITests/test12DynamicType` walks Inbox, Today, Upcoming, Flipboard, a task's card, quick add,
Browse and Settings at each size named in `HITLIST_SWEEP_SIZES`:

    TEST_RUNNER_HITLIST_SWEEP=1 TEST_RUNNER_HITLIST_SWEEP_SIZES="XXXL,AccessibilityM,AccessibilityXL,AccessibilityXXXL" \
    TEST_RUNNER_HITLIST_SHOTS_DIR=<folder> xcodebuild test-without-building … \
      -only-testing:HITListUITests/StrangerSweepUITests/test12DynamicType

(the variables before the command, in `xcodebuild`'s environment). Add to the walk what it lacks for your work:
Upcoming's Week layout, Settings → Appearance scrolled to the themes, the task card scrolled to its sub-tasks,
quick add with a picker open. Save your pictures in `…/round-34/173/` and **read every one yourself**.

- At XXXL: the same as `169/iphone/type-xxxl-*` on every screen (say how you compared).
- At AX1, AX3 and AX5: nothing cut by an edge, nothing broken inside a word, no "…" where a number was, no control
  under another. List, by picture, whatever is still wrong and why you left it.
- A hosted test for whatever you can hold without a picture (the cap's constant in use; the chip row's height
  against a chip's at an accessibility size).
- `scripts/test.sh ios` green on your tree before you report (the Mac suite if you touched shared code).

## Bounds

- Files: `HITList/Views/Upcoming/`, `HITList/Views/Flipboard/`, `HITList/Views/Popouts/`,
  `HITList/Views/Settings/AppearanceSettingsSection.swift`, the design system's type file, your tests, and
  `StrangerSweepUITests.swift`'s text-size walk. **Not** `HITList/Views/Tabs/` or any other Settings page (agent
  168 is in them), nothing under `Services/`, nothing of sync.
- A simulator of your own, named `HITList-173` (iPhone 17), deleted when you finish. Agent 168 may run UI tests
  at the same time and two simulators share the Mac's keyboard: if typed words come out wrong in a picture, run it
  again rather than believing it.
- The Mac and the iPad are out of scope unless a change of yours touches what they draw: then one picture of each.
- Commit each item the moment it is whole. No push, no merge, no `scripts/release.sh`.

## Report

What changed, by screen, in a person's words; the pictures' folder and count; what is still wrong at AX3 and AX5,
by picture; what you compared at XXXL and how; tests run and their counts; your branch and commits; your
simulator deleted.
