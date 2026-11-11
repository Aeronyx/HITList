# Round 20 (2026-11-11, afternoon): what George said after 0.9.3, and what the supervisor decided

0.9.3 (24) is released. This round is **0.9.4**. George's message, whole (five pictures came with it; they are
described under it and sit, outside git, in the shared notes folder under `round-20/george/`):

> Thanks, 0.9.3 released.
>
> Feedback, first on FINDINGS.md:
>
> * Mac settings: I agree with your recommendation.
> * Mac data: three columns of two is good, whatever fits best.
> * About: Earlier versions isn't even a necessary feature.
> * Sync log: agree.
> * Honestly, I'm not going to read the rest of these; most of them have obvious answers, and if they really don't
>   ask me directly in the chat.
>
> Other feedback:
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
>
> The top right (...) button on Mac should just be the Settings button in most/all menus.
>
> For repeated tasks, there should be a custom dropdown like when repeating tasks on a calendar (in the third,
> fourth, and fifth attached screenshots you can see examples of this; Todoist manages this by having a Repeat
> button inside the Pick a Date popout for when a task isn't already set to be repeating).
>
> Have quickadd ignore the word "starting", and add detection/support for multi-day phrases such as "vacuum on
> tuesday thursday and saturday".
>
> Make a "?" help page in a good spot inside Settings/Browse to explain/show very concisely to users how to use the
> quickadd system to the fullest.
>
> The bolt should never, ever display as full/filled in unless it actually successfully synced within the last
> real-time 30 seconds. I just saw it filled in for a long time when it wasn't successfully synced before it finally
> realized and started flashing again. This time, it was because I accidentally got signed out of my iCloud account,
> but it still shouldn't happen. Concerningly, even after I signed back into iCloud, both the iOS and Mac apps
> showed a synced bolt, but their Inboxes were not consistent (screenshots attached, you can see Mac is missing the
> "Shave" task). What is going wrong here? The logs: [the Mac's sync log, below]
>
> About the creatures: I started at my phone screen for like a whole 60 seconds and he didn't move a muscle, which
> just makes them feel dead. We still need either single idle animations or small custom animation loops at least
> every ~30-40sec and at most every ~5-10seconds.
>
> Also, we need to replace some of the creatures that aren't cute, which includes Mocha, Rosé, and somewhat
> Graphite; the Moss snail is cute, but needs a glint in his eye or something to seem a bit less soulless. Some of
> these creatures could be a bit more fantastical:
>
> * Remove and replace Rosé's cow-bat thing with a cute mushroom creature.
> * The creature for Mocha is ugly; please remove and replace him with a sneaky, slightly transparent purple-y
>   ghost-like creature named Phase, with similar vibes to Shuppet in terms of design (pointy head, wavy body, larger
>   eyes and mischievous demeanor, etc.).
>
> And, some of them still don't sit on the "Add task" button quite right; they shouldn't look like they're floating
> above it or simply superimposed on top of it.
>
> Please work freely.

The pictures:
1. The iPhone's Inbox, the bolt filled: "call mom" (repeats, Friday) and "Shave" (repeats, Nov 24).
2. The Mac's Inbox at the same time, the bolt filled: "call mom" (repeats, Friday) only, then "+ Add task".
3. HITList's own repeat menu on the Mac today, under the green "Every day" chip: Every day, Every weekday, Every
   week, Every 2 weeks, Every month, Every 3 months, Every year, a divider, Don't repeat.
4. Todoist's date popout (Nov 2026 calendar, the 11th chosen) with a "Repeat" button at its foot, and the menu that
   button opens: "Every day", "Every week on Wednesday", "Every weekday (Mon - Fri)", "Every month on the 11th",
   "Every year on November 11th", "Custom…" (the part after the first two words in a dimmer colour).
5. macOS Calendar's custom repeat: "Frequency: Weekly", "Every [1] week on:", seven day buttons M T W T F S S with
   one pressed, Cancel and OK.

The Mac's sync log as George pasted it (the header and the last launch; the file holds 1731 entries):

```
HITList 0.9.3 (24) · macOS 26.7.1 (Build 25G241) · Mac14,5
CloudKit: Production · TestFlight build 24
Exported 2026-11-11 13:38:17 -05:00
13:38:12.865  launch    Launch HITList 0.9.3 (24) · … · lastExport=just now · lastImport=just now · … · storeSize=2.4 MB
13:38:12.889  container Store opened with CloudKit sync
13:38:12.889  note      Marks show: Synced just now
13:38:13.049  account   iCloud account: available
13:38:13.050  network   Network reachable via wifi
13:38:13.050  event     Setup started · id=ECBE3F1A
13:38:13.344  launch    First screen 586 ms after launch · dedupe=137 ms · firstFrame=586 ms · …
13:38:13.584  event     Setup finished in 0.20 s
13:38:13.585  event     Export started · 13:38:13.616 Export finished in 0.00 s
13:38:14.514  event     Import started · 13:38:14.738 Import finished in 0.13 s
13:38:14.758  event     Export started · 13:38:14.789 Export finished in 0.02 s
13:38:14.803  event     Export started · 13:38:14.815 Export finished in 0.01 s
```

## The sessions (all Opus 5.5, all at once; the supervisor is a Fable 5.2 chat)

| Brief | Session | Effort | What |
|---|---|---|---|
| 95 | `sync-truth` | max | the bolt is filled only within 30 s of a confirmed sync; why two devices disagreed; a check that proves it |
| 96 | `flipboard-phone` | xhigh | the empty Flipboard, the Add a Switch card, drag onto a Switchboard, Duplicate |
| 97 | `repeat-picker` | xhigh | the repeat menu worded for the date, Custom…, a Repeat button in the date picker; no system date pickers |
| 98 | `quick-add-words` | high | "starting" is not a title word; several weekdays at once; the "?" guide to quick add |
| 99 | `sweep-polish` | xhigh | the Mac's "…" becomes Settings; the sweep's findings, George's answers and the obvious ones |
| 100 | `companions-alive` | xhigh | an idle every 5 to 40 s; every companion sits on the "+"; Tuck's eyes |
| 101 | `phase` | xhigh | Phase, the ghost, for Mocha (Mallow goes) |
| 102 | `rose-and-graphite` | xhigh | a mushroom creature for Rosé (Posy goes) and a cuter creature for Graphite |

## What the supervisor decided (George said "work freely" and "most of them have obvious answers"; he may reverse any)

- **The bolt.** A filled bolt needs something to have been confirmed in the last 30 s, and iCloud's mirror syncs only
  when something changed. So while the bolt can be seen the app asks iCloud itself, every 15 to 20 s: a small request
  that needs the account and the network. Filled means: answered within 30 s, nothing here waiting to go, nothing
  there waiting to come. At 30 s without an answer it is never filled, whatever the steadying of brief 78 would hold.
- **The disagreement.** Nobody can open George's stores. Session 95 works from the code, from two Debug instances and
  from the logs George sends, and builds the check George can run on each device: what is here and not in iCloud,
  what is in iCloud and not here, by name. Nothing is ever repaired by itself: a task missing from iCloud may be one
  that was never sent, or one deleted elsewhere whose deletion never arrived, and only the person knows which.
- **Several weekdays typed together repeat weekly** ("vacuum on tuesday thursday and saturday" is a task every
  Tuesday, Thursday and Saturday, with or without "every"); one weekday alone stays a date.
- **The repeat menu** keeps today's seven choices, worded for the task's date as Todoist's are ("Every week on
  Wednesday"), then "Custom…", then "Don't repeat". Custom can say everything quick add can.
- **Day headers** read one way everywhere: "Nov 11 · Today · Wednesday" (the Mac board's, and Todoist's order).
- **"Done"** is the accent pill everywhere; one section-header style (the lists'); rows share the large title's left
  edge on every iPhone width; no hairline between a large title and the first row; our own date and time pickers
  everywhere; the Mac sidebar shows no "Filters" header over nothing.
- **Companions.** An idle (one small gesture, or a little loop of two to four) every 6 to 36 s of showing time, the
  first within 2 to 6 s of coming on screen, so a ten-second visit sees it move; asleep it breathes at the same
  pace. The long routines stay rare (every 3 to 8 minutes) and the flourish rarer. Phase and the mushroom are
  George's; Graphite's new creature is the session's to design (the brief suggests a gargoyle pup, perched on the
  ledge; a redrawn Smudge is allowed if it wins on cuteness). All three are original: Phase takes a ghost's general
  shape (a pointed head, a wavy hem, big eyes, mischief) and nothing that belongs to the character George named.
- **A seat, for every companion**: nothing between it and the "+", ever. It rests on the capsule's curve where it
  sits, and its base follows that curve or is tucked behind the rim; and the last row of a list scrolls clear of it.
