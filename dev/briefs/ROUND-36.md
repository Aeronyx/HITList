# Round 36 (2026-11-23 to 24): reminders in quick add, and the Stream ring

Supervisor: Opus 5.5 (George's Fable allowance for the week was spent; he switched the session to Opus and said he
was "not worried" about its use before Wednesday). Two Opus 5.5 agents with briefs (175, 176), each resumed twice
with its reviewers' findings, and four read-only Opus reviewers (two per brief). Version 0.9.18. 0.9.17 (build 32)
was released by George on 2026-11-20, after a Mac export that failed offline and was rerun whole (the bump was
undone by hand: `release.sh` has no resume and leaves its bump behind).

## What George asked

After showing HITList to a friend: "I typed `!0mb` and it didn't register that I wanted a reminder, nor did spelling
out anything about a reminder. This functionality clearly needs a mild improvement. Todoist handles this better;
when the user types an exclamation point on an untimed task, it pops up with recommendations … but when the task
does have a time it pops up with "At time of task (!0mb), 10 minutes before (!10mb)," etc. … it shouldn't take me
typing out the whole "!0mb" phrase and hitting space for it to register." (Three Todoist screenshots: the notes
folder, `round-36/175/todoist-*`.)

The same day he got a Sandbar **Stream** ring: "Would be able to build a tool or integration for HITList of some
kind such that I could add tasks to it while my phone is in my pocket? That's really what I bought it for." Later:
"I'm happy to pay for Upstream at $10 a month (as I'm a beta adopter) and I also got 3 months free. If it will
vastly improve functionality, let's do that. I really want this to work flawlessly; it would be a massive upgrade
to my productivity."

## What was found before anything was built

- **`!0mb` works, but only beside a typed time, and only after a space** (brief 41's rule that "before" needs a time;
  brief 48's live rule, George's own request then). Nothing read reminders in words.
- **The parser read dictated times wrongly** (a probe on 2026-11-23 14:10): "Call mom tomorrow at 5 p.m." was due
  05:00 with "p.m." left in the title; "2:15 p.m." was 02:15; "at 6" was 6 AM tomorrow; "priority 1" stayed in the
  title. Siri's path had its own "p.m." rewrite (`IntentActions.dictationNormalized`); the card had none.
- **The ring's audio reaches only the Stream app**, and its buttons are media controls: nothing but Stream can take
  what it hears. Sandbar's own help pages (read in the app's built-in browser: support.sandbar.com refuses
  automated fetches) settled the routes out: the **webhook needs Upstream**, is sent from the iPhone over its own
  network, waits 5 s and **is never retried**; **Stream's MCP lists no subscription** (OAuth with dynamic client
  registration, `get_recent_interactions`, the connection ends 90 days after approval). Brief 176's addendum
  changed the design from webhook-only to both.
- Nothing outside the app can write into HITList's iCloud, so the design is a **relay of George's own** (a
  Cloudflare Worker with one SQLite Durable Object, free plan) that holds captures until one of his devices takes
  them, and **Apple wake-up pushes** so a device in a pocket takes them at once.

## What was built

**Brief 175: reminders in quick add.** Typing "!" opens a list of the app's own above the card (iPhone, iPad, Mac;
the editor's title too): timed tasks get At time of task, 10/30/45 minutes, 1/2/3 hours and 1 day before, then In
5/15/30 minutes and Later; untimed ones In 5/15/30 minutes, In 1 hour and Later. Each row shows its code; typing
narrows; a pick is written lit, in words ("!At time of task"), and so is a Reminder chip's choice; the codes still
work. Reminders in words: "remind me 30 minutes before", "remind me at 4pm", "Remind me to … at 5", "Can you remind
me tomorrow at 9 to …"; a bare "reminder" only where it opens a clause; "priority 1–4" at the end. Times as said:
"5 p.m.", and the hour rule for "at N" with no am/pm (1–4 the afternoon; 5–6 the afternoon beside a day, otherwise
the next to come; morning cues such as wake, breakfast, early, morning give the 24-hour reading; evening cues such
as night, tonight, evening, dinner give the evening for 5–11). "At time of task" is stored as an explicit 0, so
Settings → Default reminder no longer moves it earlier.

**Brief 176: the Stream ring.** `relay/stream-inbox/` (plain JavaScript, no packages): Stream's signed webhook, a
poller of Stream's MCP every minute, a claim (held 60 minutes, re-woken at 10 and 40) and ack protocol with the
devices, the "only captures that start with Task" rule kept on the relay, Apple background pushes (macOS at once,
iOS only if still unclaimed after 30 s or 75 s when a Mac is awake), `setup.sh` that George runs, `test.sh` (153
checks against a pretend Stream and a pretend Apple) and `test/setup-dry.sh`. In HITList: `Services/Inbox/`
(`StreamInbox`: claims, reads each capture as quick add does **as of when it was said**, saves, acks; a failed save
leaves nothing; a note before each save survives a kill; a lost ack goes again as a background upload), the push
token and the wake-up in `SyncAppDelegate` (added lines only), `NotificationPlan.Arrival` (a late capture's
reminder goes off on arrival), and Settings → Stream Ring, **listed only where it is in use** (a connected device,
the revealed troubleshooting rows, a Debug side store; `StreamRingListing`, the supervisor's change): a friend's
Settings is as in 0.9.17, and About stays where it was on an iPhone 17.

## Reviewed four times

Every review ran after green suites and found real faults; every fix came with a test that failed first.

| Review | Findings | The worst |
|---|---|---|
| 176, first | 11 | a late pickup read "tomorrow" from the pickup; one Stream answer looped the relay at 1,800 requests a second |
| 175, first | 13 | Mac Return turned "!30m" into "30 minutes before"; "every morning at 6" became 18:00; "Set a reminder in 10 minutes to check the oven" lost "reminder in 10 minutes" from the middle |
| 176, second | 7 | a late capture's reminder never fired; waking every device on every capture spent the background-push budget the sync engine's own pushes need |
| 175, second | 12, and a corpus of 294 titles at four times of day (92 better, 13 debatable, 5 worse before round 3) | an overdue repeating task kept a stale reminder whose Complete then skipped an occurrence; "Can you remind me at 5 to call mom" → "Can you to call mom"; "Wake up at 6 tomorrow" → 18:00 |

Decisions the supervisor took against a reviewer: no task ids derived from capture ids (it touches sync identity;
a lost ack is covered by a 60-minute hold, two re-wakes and a background upload instead); "remind me at <time>"
keeps an explicit 0 (asking to be reminded at a time is asking for that time, as Apple's Reminders does).

## Proof

On the final tree (`0adbbfc4`, then documents only):

- **Suites**: core 1,156, Mac 2,490, iPhone 2,450 (an iPhone 17 simulator of the supervisor's own), no failures.
  Round 35 ended at 1,100, 2,428 and 2,388.
- **The UI suite, two lanes** (one `build-for-testing`, two `test-without-building` on two iPhone 17 simulators):
  126 passed, 75 on demand, one failed: `CalendarEventsUITests.testRefusingAccessSaysWhyAndOffersSettings` (the
  system's calendar prompt, answered while the other lane drove its own simulator). Alone it passed twice; no
  calendar code changed this round.
- **The relay**: `relay/stream-inbox/test.sh` 153 checks and `test/setup-dry.sh` 16, each run twice from clean by
  the agent; nothing deployed.
- **Package proof**: `scripts/release.sh --no-upload --no-bump --skip-tests --skip-schema-check`: both platforms
  archive, export and pass the entitlement checks (iOS 20,951,428 bytes, macOS 42,801,177 bytes).
- **Pictures**: the agents' own, read by them and by the supervisor's reviewers, in the notes folder under
  `round-36/175/` (29) and `round-36/176/` (12).

## Left open

- **Unproven until George's first real capture**: Apple's push service reached from a Worker over HTTP/2 (local
  workerd cannot); Stream's real webhook fields and MCP answers (the troubleshooting rows on the Stream Ring page
  show the fields, the tool's arguments, whether both routes share ids, whether a refresh token came); Cloudflare's
  own alarms (proved on local workerd only); iOS's real background upload.
- A late capture's reminder goes off only on the device that took it; a device that gets the task through iCloud
  doesn't know when it was said.
- A clock reminder on a repeating task reminds once ("!8am" every day); re-anchoring it to each occurrence is not
  done.
- The iPad and Duo board's day card has no "!" list (codes and words still parse there).
- A capture becomes two tasks only if the device that saved it cannot ack for an hour while another takes it.
- George's side stores from this round's agents (`HITList-r36-175*`, `HITList-r36-176*`) are in the app group, his
  to delete by hand.
- A macOS privacy question from the Claude app ("bypass the system private window picker") came up while an agent
  captured its own window; it is George's to answer.

## After the release: George's first real capture (2026-11-23, 20:44 EST)

0.9.18 released and the relay set up (webhook and MCP, wake-ups, the "Task" rule on). His "Task, …" capture never
became a task. The relay's status (read with the key setup.sh keeps in his login keychain, never printed) said:

- **Proved**: Stream's webhook body is exactly `interaction_id` and `text`; it arrived signed and passed the Task
  rule. **Apple took the relay's wake-up push over HTTP/2 from a Worker** (the Mac's token, production service).
- **Why nothing took it**: HITList on the Mac had been quit (the test asked for that), and the relay knew no iPhone
  at all: the iPhone had never claimed with its push token, so there was no device to wake. The capture waited.
- **Stream's MCP gave nothing readable**: every poll since the approval found a list with no capture in it the relay
  could read (`interactionFields` stayed empty), and said nothing. The relay now says so with the interactions' field
  names and Stream's count (`stream.lastListed`), reads more names for the words, and a changed reader (`READER`)
  starts the poller again from its next poll, so a reader that learns to read Stream's answer never takes the past
  week's captures as new tasks (the old code failed that check). test.sh: 164.
