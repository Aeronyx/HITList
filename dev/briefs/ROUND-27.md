# Round 27: 0.9.11, a bolt that checks the records, creatures that feel alive, the calendar found, Todoist in (2026-11-14, evening)

0.9.10 was prepared (round 26) and its release stopped at the export: Apple had an updated Program License
Agreement waiting for George to accept ("PLA Update available"; the "No signing certificate" lines are the same
refusal). Nothing was uploaded; the version bump the run left in the tree was put back. George's message at about
20:05 Eastern, verbatim (after the pasted export errors):

> Also, the bolt should not be able to be filled while the three records differ; doesn't that defeat the purpose of
> the bolt?
> I feel like eventually we do need to write our own engine, no? How does something like Todoist handle this so
> smoothly?
>
> Both Flint's rain animation and blinking animation are a bit weird. My friend overall likes Flint though so don't
> change his actual character too much yet, just his animations and non-Day sprites.
>
> Also, my bad, but animations do have to happen more often; we made them too sparse. The creatures just feel idle
> now. Animations should happen at least once every like 12 seconds and at most once every 4-7 seconds with some
> randomness involved to feel natural. It's still okay to have creatures skip most of their idle animations during
> weather effects, they just need to feel a bit more alive in their default states (hopefully still without being
> too distracting). Perhaps they should also have task completion animations so they feel more associated with the
> app; that could be cool.
>
> Quill is misplaced in Theme menu on iOS
>
> Have Phase looking down left for rain instead, he looks weird looking up constantly.
>
> Please add calendar/GCal integration
>
> Make it clear once somewhere in the intro/title menus that the app is actually named "Human-In-The-List" just for
> fun
>
> Is there an easy way to allow importing my tasks from Todoist?

## How it is read
- **The bolt.** Round 26 left the record-by-record comparison to Check iCloud… alone and said so as a choice George
  could reverse. He has: a filled bolt must mean this device and iCloud hold the same records. So the comparison is
  part of the bolt again, without what made 0.9.4 to 0.9.9 fail: it runs when something happened (a launch's first
  import, a return after time away, trouble clearing, a repair), never on a timer; a difference is believed only
  from a fresh, whole read, made twice; the words say what differs and never "Sending"; nothing animates while it
  waits; and when iCloud won't answer the read, the bolt falls back on the mirror's own word instead of staying
  hollow. Nothing is repaired by itself (a record here and not in iCloud was never sent, or was deleted elsewhere:
  only the person knows which): Check iCloud… names the records and offers both repairs. The supervisor's own work
  this round, as round 26 was.
- **"Our own engine".** Yes, in the end: a bolt that is exact needs the list of what is waiting to go, and Apple's
  mirror keeps that list to itself. Todoist owns its queue (every change is a command with an id, sent to its own
  server, answered one by one), so "all sent" is a fact it holds. The Apple way to own the queue is `CKSyncEngine`:
  our records, our list of pending changes, Apple's scheduling and pushes. It means new record types in Production
  and moving every tester's data across, so it is a project of its own, begun on George's word. Proposed in the
  hand-over; not started.
- **Flint.** His daytime drawing stays, pixel for pixel, and is pinned. His blink, his rain (the still and what
  moves in it) and the drawings that are not the daytime one (asleep, rain, asleep in the rain, snow where it
  must follow) are made to belong to it.
- **Pace.** In a creature's default states (awake by day, asleep at night) something small happens every 4 to 12
  seconds: the wait is never longer than 12, and never shorter than a floor that is itself between 4 and 7. Under a
  sky that holds, the pace and the skipping stay as they are. And a cheer when a task is completed.
- **Quill** on the iPhone's theme boxes: found in the running app first (every theme selected in turn, an iPhone
  16), then put right.
- **Phase** in the rain looks down and to the left.
- **Calendar.** HITList has shown the device's calendars in Today and Upcoming since 0.9.1 (brief 77), read-only
  and off by default, behind a switch in Settings → General that George may never have met. Google Calendar
  arrives through the device's own accounts (Apple's Calendar holds it), with no Google sign-in inside HITList. So
  this round: a Calendar page of its own in Settings, calendars by account, words that say how Google Calendar
  gets there, a card for an event, and a task put on the calendar by choice. A Google sign-in of HITList's own
  (Google's API, a Google Cloud project of George's, Google's review of the calendar scope) is his to ask for.
- **"Human-In-The-List"** once, where a person meets the app's name.
- **Todoist.** Yes: Todoist hands out its own backup (a ZIP with a CSV for each project) and a CSV for any one
  project. An importer for those, with a preview before anything is written, nothing doubled on a second run, a
  backup first and an undo after.
- 0.9.10 was never uploaded: its notes fold into **0.9.11**, which is this round. No schema change.

## Sessions (all Opus 5.5; six at once, the two that draw first)
| Brief | Session | Effort | What |
|---|---|---|---|
| 132 | `alive` | xhigh | The idle pace (4 to 12 s) in the default states, and a cheer when a task is completed; the engine's one owner |
| 133 | `flint-moves` | xhigh | Flint's blink, his rain, and his drawings that are not the daytime one; the daytime one pinned |
| 134 | `phase-rain` | xhigh | Phase looks down and to the left in the rain |
| 135 | `small-things` | xhigh | Quill's place on the iPhone's theme boxes; "Human-In-The-List" once |
| 136 | `calendar` | xhigh | Settings → Calendar, calendars by account, Google Calendar's way in, an event's card, Add to Calendar |
| 137 | `todoist-import` | xhigh | Import from Todoist's backup ZIP or a project's CSV: parser, mapping, preview, undo |

All xhigh: three are judged by George's eye at real size, 132 changes the one engine every creature runs on, 136
writes to a person's calendar and 137 writes hundreds of records into a person's store.

## The supervisor's own
- The bolt's record check (`Services/Sync/*`, `CloudSyncMonitor.swift`, the bolt's views, the iCloud page's groups).
- Its own look at Flint's blink and rain and Quill's corner, sent as notes in the sessions' first minutes.
- Every sheet looked at at real size and forwarded to George as it arrives.
- The merge, the suites, the UI classes the round touches, the Mac's idle CPU, a Release archive and export,
  `## 0.9.11`, `Entry(version: "0.9.11")`, the pin, the record, the hand-over.
