# Brief 96: the Flipboard on the phone (session `flipboard-phone`, effort xhigh)

George, 2026-11-11, after 0.9.3:

> Flipboard UI on mobile is still not excellent; there's so much text on the "No Switches Yet" page, "New
> Switchboard" shouldn't be a starting option, and the "Add a Switch" button should look like a switch outline in
> the same way it does on Mac. As for the "Add a Switch" popout, it's not awful, but it's still a bit confusing; the
> add time bar is strangely long, fonts are different sizes, and I have no idea what the red/green switch on the
> right even does, and change "Overdue becomes task; waits in Today once it's due" to just simply "Become a task
> when Overdue".
>
> Add force-touch drag-and-drop for switches onto Switchboards. Also, allow duplicating the settings of a Switch to
> create a new one just with an empty name using a simple "Duplicate" menu option that opens the "Add a Switch"
> popout with the settings filled out.

Read `dev/briefs/COMMON.md` (Round 20 block first), `dev/SUPERVISOR.md` §7 (what stands: adding or editing a
switch is a small card, never a sheet; every switch tile on a screen is the same size; the Flipboard is a calm
status check; switches are routines first), `HITList/Support/DesignSystem/README.md`, then `Views/Flipboard/*`.
Look before you change: run the iPhone app with a fresh store and with `-seedDemoData YES`, and the Mac app, and
screenshot the empty Flipboard, the Add a Switch card (empty and typed) and a Switchboard on both. The card on an
iPhone 17 today, top to bottom: "Switch name"; a row of five (Daily, 3 days, Weekly, 2 weeks, Monthly); "Every
[‹ 3 ›] days" with a small green rocker switch at the right end; a wide "Add time" field beside a "No Switchboard"
button; "Overdue becomes task" over "Waits in Today once it's due" with a toggle; "[‹ 1 ›] flip", a cross and the
send arrow.

## Items (one commit each; a test where there is logic; before and after pictures of each)
1. **The empty Flipboard on iPhone and iPad.** Almost no words: a title-size line at most, no paragraphs. The way
   in is the **Add a Switch tile drawn as a switch's outline**, the size and place of a real tile, as the Mac draws
   it (find the Mac's and share the drawing, do not copy it). No "New Switchboard" on the empty page: a Switchboard
   is offered once there is a switch (where it lives today when there are switches) and from the card's own
   Switchboard picker.
2. **The Add a Switch card, both platforms** (it is one component; the Mac's must come out as good).
   - "Add time" is a compact control the same height and style as "No Switchboard" beside it (the sweep measured
     35.5 pt against 28 pt on the Mac), not a bar across the card.
   - One scale of type: the name at the card-title size, every label at one size, every secondary line at one
     smaller size. Give the table: each piece of text, its font before and after.
   - The red/green rocker at the right: find out what it does. A control George cannot read is removed if the card
     works without it; if it does something needed (the switch's state today, say) it gets a label in words and
     looks like what it is.
   - "Overdue becomes task" and its second line become one line: **"Become a task when Overdue"** (George's
     words, exactly), on the switch card and on the Switchboard card. If the row needs explaining, the explanation
     belongs in the quick-add-style tip system, not under the row.
   - The last row ("[‹ 1 ›] flip", the cross, the arrow): the same sizes and baseline as the rows above; say what
     "flip" counts and whether a person would know.
3. **Drag a switch onto a Switchboard** (iPhone and iPad: press and hold, then move; George's "force-touch"). The
   tile lifts with a haptic, the Switchboard under the finger shows it will take it, a drop moves the switch in
   (its reset and schedule rules as if chosen in the card); a drop on the loose switches takes it out. A tap still
   flips; holding still opens the menu (item 4); nothing moves by accident while scrolling. On the Mac a plain
   drag does the same if it does not already. VoiceOver gets the same move as an action ("Move to…").
4. **Duplicate.** In a switch's menu: "Duplicate" opens the Add a Switch card with every setting of that switch
   (schedule, time, Switchboard, become a task, flips) and an empty name with the keyboard up. Nothing is saved
   until the person confirms; cancelling leaves nothing behind.
5. **From the sweep.** Mac Flipboard, narrow window: a tile whose title wraps ("Take out the recycling") puts its
   subtitle a line lower than its neighbours': subtitles sit on one line across a row.

## Ownership
`HITList/Views/Flipboard/*`, the Flipboard's tests and a UI test file of your own, the switch lines of the demo
seed if a picture needs them. Not yours: `Views/Popouts/*` (97), Settings and the toolbar (99), companions,
`Services/*` beyond what a switch move already calls, the models' shape (no schema change), `scripts/`, `dev/`,
`CHANGELOG.md`, `WhatsNew.swift`.

## Done
Before and after pictures of the empty Flipboard, the card (empty, typed, with a time and a Switchboard) and a
drag in progress, on iPhone 17, on an iPhone 16-size simulator if you can make one (George's phone: 393 × 852) and
on the Mac; the type table; what the rocker was and what became of it. All three suites green, your UI test on a
fresh simulator. The branch; changelog lines in plain words; decisions George might reverse.
