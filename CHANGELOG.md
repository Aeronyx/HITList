# HITList changelog

One section per release, newest first. A release is a version: `scripts/release.sh --version X.Y.Z` refuses to run
until the version has a section here, then stamps the heading with the build number and date. Versions go up by 0.0.1
per release. A second build of one version (0.9.0 had builds 20 and 21) is released with `scripts/release.sh --quick`
and needs a section headed `## X.Y.Z (N)`, which the script stamps with the date.

## 0.9.17

0.9.16 went out on the morning of 2026-11-20, and that day George moved his own Mac and iPhone to HITList's own
sync: the first devices on it in iCloud's Production side. It took 4.2 seconds from the Mac's relaunch to a filled
bolt (68 records sent, fetched back and found the same), his iPhone followed by itself, Check iCloud… found no
difference, and tasks made on each arrived on the other. His friends' devices carry 0.9.16 and stay on the earlier
sync until he gives the word. His words after: "Looks like it worked! … My only issue is that the bolt still goes
hollow for a moment whenever a task is added on either device; remember, the bolt is supposed to indicate to the
user only when there's a pending problem or when there's a successful resync after a long period away … Let's run
some tests to confirm everything landed how we expected and then start cleaning up all these dev sync settings and
logs so they won't be as easily visible to other users going forward." (`dev/briefs/ROUND-35.md`.)

The bolt on the new sync:

- **It keeps still while HITList syncs as usual.** A task added, its send, and the fetch when another device
  changes something no longer empty it. Before, every add emptied it for the second and a half the change took.
- **It empties for a pending problem**: a change still waiting after eight seconds with nothing under way; a send
  or a fetch that has gone on for half a minute; the network gone, or a sync that keeps failing, for half a
  minute. A hold, an item iCloud refused and being signed out show at once, as before.
- **It empties when you come back** after a minute away (or open HITList), until a sync made then has ended; then
  it fills and its strike plays. A quick look at another app changes nothing. On a Mac, coming back to HITList
  after a minute in another app, or waking the Mac, now asks for that sync (it used to wait for a push).
- **At a launch it no longer says "Synced just now" before it has asked iCloud anything** (it did, for half a
  second, then "Checking with iCloud…").
- Two reviewers were set to break this before it was believed, and did, twice: fourteen findings, each fixed
  with a test (`ROUND-35.md`).

Sync:

- **Back online, what waited goes at once.** On the new sync a task added in airplane mode was sent at the next
  retry, up to ten minutes after the network returned, or when HITList next came forward.

Settings:

- **iCloud & data shows what a person needs**: whether it is syncing (and Sync now), backups, export and import,
  and under "If something doesn't sync" Check iCloud… and a new **Send sync log…**, which hands the log's file to
  the share sheet (a save panel on the Mac) for whoever is helping. Reset local cache and Delete all data from
  iCloud stay at the foot.
- **What was there for building the sync is behind a gesture**: the environment row, Details, the Sync log's own
  page, the times of the last fetch and send, and the whole group that moves a device between the two syncs.
  Seven taps on Settings → About → Version show them, under the heading "For troubleshooting"; About then has a
  row that hides them again. George's Mac, already shown the old way, stays shown.
- A device the app moved by itself says so in the Sync group for fourteen days (its other devices need the
  update), then says nothing.
- In that hidden group, two things George misread on the day are reworded: "Everyone's move: Not released" is
  "Friends' devices: Not moving yet: you have not given the word", and the question before a move no longer says
  "wait for the bolt" when the truth is that nothing has been compared since the app was opened.
- Nothing a person can reach without the gesture says CloudKit, environment, engine, zone or mirror.

Under the hood:

- The unit tests have settings of their own. On a Mac they ran inside a Debug copy of HITList that shares the real
  app's settings, so the day George's Mac moved a test saw his store's preference. None wrote it (it was read
  back: as he left it), and none can now.
- A test store's settings start empty instead of inheriting what very old builds left on the device.

## 0.9.16 — build 31, 2026-11-20

0.9.15 was prepared on the afternoon of 2026-11-18 and not released either. George that evening: "I haven't released
0.9.15 yet because I want to be very confident in the next build we release and I also want it to force everyone to
move over to the new sync engine so we can settle this once and for all. Before release, tell me clearly that both
internal and external testers will safely retain their task data after the move, or if I should tell them to
download everything first. The iPhone is still a bit slow, I notice it mostly when switching between home tabs and
when browsing/swiping around the Settings menu … Please take more time to prepare a build that is truly worthy of
both the new sync engine and to be sent to a wider group of friends." So this is 0.9.14, 0.9.15 and that evening's
round together (`dev/briefs/ROUND-34.md`, `ROUND-33.md`, `ROUND-32.md`).

**This release moves every device to HITList's own sync, by itself, once George says so**, and not before: the
build reaches everyone, and nothing changes for anyone until he has seen the new sync work on his own devices and
given the word (one record in iCloud that every device can read; he can also pause it). **The move deletes
nothing.** Each device keeps its own tasks where they are, saves a backup first and keeps it ("HITList before the
new sync", in Files → On My iPhone → HITList, and in the Mac's backups folder), and the earlier sync's copy stays
in iCloud untouched.

The move to the new sync:

- **It waits for George's word**, then starts with the first device of each person; that person's other devices
  follow by themselves as soon as they are up to date, even if the word is paused meanwhile, so nobody is left
  with one device on each sync.
- **A device moves only when it has received everything the earlier sync holds for it.** One whose earlier sync
  never settles is not left behind for good: after seven days it moves with what it has, and its sync log says
  what stayed in the earlier copy (kept there).
- **It always merges.** A device keeps its own store and merges it with what iCloud's new copy holds. (An earlier
  design had a freshly installed device take iCloud's copy instead; a review that set out to lose a tester's
  tasks showed that could hide everything, and that the merge already does the right thing. It is gone.)
- **It finishes by itself**: the move takes effect the next time the app starts, so an iPhone or iPad ends its own
  process once it is in the background, and a Mac relaunches itself behind your other apps. Never while a card, a
  sheet or a question is open (what you were typing stays), and never in a moment the system woke the app for a
  widget or a notification.
- **It checks itself**: the first time the new sync is at rest, the device compares every record in iCloud with
  its own, and its sync log says what it found.
- **A second review read the move's code line by line** and found eleven things, each fixed with a test. The ones
  that could have cost someone data: Reset local cache during the moments a move waits (no longer offered then);
  a default filter deleted on the new sync coming back when a freshly installed device joined; and, on the way
  back only, two devices each deleting the other's copy of an item (the earlier sync never merges such copies
  now). Cancel the move is kept for good; a device that moved by itself shows what happened and no longer shows
  the row that moves it back alone (that row needs the seven taps).
- **What a person with two devices can meet**, in the time between the first and the second moving: something
  deleted on the device that has not moved yet comes back; an item changed on both keeps the later change; a
  task moved to Shared Tasks there shows in both places. Opening HITList on each device the same day keeps that
  time short. A device left on an older build goes on looking synced and reaches nobody until it is updated.
- Rehearsed on iCloud's test side: the word itself (not yet, go, paused, limited to a build, cleared); a Mac that
  waits, then moves, relaunches itself and checks itself; a first send of 6,005 records in a minute and a half,
  every record the same afterwards; a second device that follows under a pause (`dev/briefs/ROUND-34.md`).

From a walk through every screen as a stranger sees it (358 pictures on an iPhone, an iPad and the Mac, each one
read by eye):

- **"3 days ago", "2 weeks ago" and "last monday" are dates in the past**, as typed, with nothing of the phrase
  left in the task's name. They were saved as dates ahead (in three days, next Monday).
- **The Week layout fits the window it has.** A Mac window made narrower, or an iPad turned or put beside another
  app, left the week at its old width with both sides cut off, the month's name among them. A window too narrow
  for seven days shows three, as an iPhone does.
- **On the Mac, Upcoming's toolbar buttons sit inside their capsule**: the Layout button hung out over the sync
  bolt and the gear touched the +.
- Settings → Account offers "Sign out in the Settings app" only when an account is signed in. Words that send you
  to sync's settings name the page you have ("iCloud & data" on an iPhone). Quick add's + menu says "Sub-tasks",
  as a task's card does. On an iPad the "Add task" row no longer draws a band to the screen's edge.

Lighter on iPhone (measured on George's phone in a Release build, by a probe that drives the app itself):

- **An overdue switch's light no longer keeps the phone busy.** Each overdue light was redrawn thirty times a
  second: with a handful of overdue switches the Flipboard cost 5 s of work a minute while it was open, with a few
  dozen 29 s. Now 0.7 s. The light looks the same.
- A switch to a tab takes 0.12 to 0.2 s of work with a small store, and a Settings page 0.05 s with no dropped
  frame. Keeping visited tabs alive was tried: it halved a switch and doubled every add and check-off, so it was
  taken back. A tab that holds a great deal (some forty switches, or hundreds of open tasks) still takes 0.4 to
  0.7 s to show: the next round's work.
- Text sizes above the largest standard one: dense controls (the week strip, the Week layout, Flipboard tiles,
  theme names, a card's pills, quick add's chips and pickers) stop growing at the first accessibility size, where
  they still fit; what you read (task names, notes, rows, Settings) keeps growing.

From the afternoon's round (0.9.15, never released). 0.9.14 was prepared on 2026-11-17 and not released: George wanted the release to come at a time of his choosing, and
wrote on the 18th with what he had seen meanwhile. "Several external testers are now also using HITList on 0.9.13,
and as it takes a while to release a new build for them, I want to ensure this next one is incredibly solid … some of
the pages are not very user-friendly (such as the Calendar page) and some of the tooltips are really hard to read …
The mobile app is also a bit slow to respond now … The Upcoming page should have a Task-based layout (the current
layout) and also a new Week view … The tagging options in the 'Add task' popout should be a horizontally scrolling
bar, not one that wraps … definitely keep tasks on the device after sign-out if possible, and remove any identifying
information from the repository." And of the new sync: "I'd even rather the update just automatically move their
tasks after we've confirmed the new engine is working." So this is 0.9.14 and the round after it together
(`dev/briefs/ROUND-33.md`, `ROUND-32.md`): seven Opus agents in one afternoon, then the supervisor's merge.

New in Upcoming:

- **A Week layout**: the week's tasks on a calendar. Tasks with a date and no time sit in a band under the day's
  name (two rows, then "N more" opens it); tasks with a time sit at their hour; a line marks the present time. An
  iPhone shows three days and moves a day at a swipe; an iPad and a Mac show the week. A tap opens the task, its
  ring completes it (with Undo), and a red Overdue at the top lists what is overdue. Choose it from the new Layout
  button at the top of Upcoming; the list (the board on a Mac) stays the default, and the choice is kept on each
  device.

Quick add and tips:

- **Quick add's options stay on one line** that scrolls sideways, so the card keeps its height; a chip that changes
  scrolls into view, and the row fades softly at an edge where more waits.
- **Tips are shorter and hold their shape**: one width, a title of a few words and one sentence. A tip no longer
  appears over quick add or a task's card, and goes away for good once you use what it points at.

Settings:

- **The Calendar page reads at a glance**: one switch ("Show calendar events"), an Access row that always says
  where the permission stands and, when it was refused, is the one tap that fixes it, the calendars to show, Google
  Calendar as one row, Add to Calendar last.
- Shorter titles and footers on General ("App icon badge"), Reminders, Extras, iCloud & data and Claude.
- Opening Settings → Appearance no longer works out every theme swatch's companion afresh each time it draws.

Quicker on iPhone:

- Switching tabs does less: the app no longer redraws for popouts that are not open (measured on a simulator, a
  Debug build: a third less work on the main thread per switch). Taps were found to be recognised at once; the time
  goes into drawing the screen that answers. What George's own phone does with his real data and iCloud on could
  not be measured this round (its UI automation is switched off) and is the next thing to measure.

The sync engine (switched on only where it is moved to):

- **Signing out of iCloud keeps your tasks on the device.** They can be read and changed, and sync again at sign-in;
  reminders stay too. Signing in to a different account still removes them, after a backup. (On the earlier sync
  Apple's mirror removes its copy at a sign-out, as before, and brings it back at sign-in.)
- A store set aside (Reset local cache, a move back that takes a fresh copy) is kept for thirty days whatever
  comes after it. Cancel the move after choosing "Another device already moved back" no longer sets the store
  aside.

The repository:

- No e-mail address, surname, home folder, device id or App Store Connect key id is in its files any more. The
  address Send Beta Feedback writes to is a build setting from an untracked file (`Config/Local.xcconfig`), and
  `scripts/release.sh` stops without it; a build made without one offers TestFlight's own feedback.

From the round before (0.9.14, never released). 0.9.13 was released on 2026-11-16. George that night: "Please work freely and complete the sync engine. The app is
largely feature complete, or as far as I wanted it to get for an initial release; let's shift into review and
hardening mode so we can prepare for a real launch, but I also won't feel comfortable launching until we have at
least a few days of experience with the new sync system to confirm its legitimacy". Six reviews of the whole app
by Opus agents, their findings fixed, and the engine made ready for his own devices (`dev/briefs/ROUND-32.md`).

HITList's own sync engine can now be switched on for one device at a time, from a group in Settings → iCloud that
stays hidden until it is revealed; it is for George's devices first.

Safer:

- **A label that is on tasks asks before it is deleted**, and says how many tasks it comes off. Flipboard's own
  label can no longer be deleted (deleting it emptied the Flipboard).
- **Two Groups, two labels or two filters can no longer share a name**: the editor says so. Before, HITList merged
  such pairs later by itself, and a filter's query could be lost with it.
- **The question before deleting a task names its sub-tasks**, which go with it.
- **Undo after completing a repeating task puts everything back**: its reminder and its ticked sub-tasks too.
- **Moving a task to Shared Tasks asks first** when the move would drop something a shared task cannot hold (a
  label, a repeat, a reminder, a deadline, a location, ticked sub-tasks).
- **What you type in a task's card is kept** if you leave HITList before confirming.
- **Import JSON asks** before bringing back what was deleted since the backup; **Import from Todoist** keeps two
  tasks with the same title, and an import that stops part way says what it wrote and can be undone.
- **A daily backup that fails says so**, in Settings → iCloud & data → Backups and in the sync log; backups no
  longer hold up the app while they are written. Reset local cache saves a backup first.
- A description is limited to 100,000 characters (a larger one could stop a device's sync).

Reminders:

- **HITList asks to send notifications the first time you give a task a reminder.** Before, reminders stayed silent
  until they were switched on in Settings → Reminders, while quick add said "Fires 10:45 AM" all the same.

Clearer:

- Settings → iCloud & data says what the bolt means: it is filled when everything on this device is in iCloud.
- An empty Flipboard says what a switch is.
- The iCloud page no longer shows a line meant for developers.

Private:

- The sync log never holds a task's title or a Group's name (a share or a widget's completion wrote them), nor the
  Mac's user name; the copy made for sharing the log is removed afterwards.
- With "All tasks but @private", a sub-task that carries the label is hidden from Claude wherever it sits. Claude
  can no longer clear a task's description without saying so, and is told that edits cannot be undone.
- The location question says where the location goes: only Apple's weather and map services.

Faster with a long list (measured on a Mac with 5,000 tasks, before and after: checking off a task 2.6 s of
processor time to 0.9 s, opening Today 2.6 s to 0.8 s, launch 3.8 s to 1.9 s; with a few dozen tasks nothing
changes):

- The sidebar's counts are kept by one small model instead of being recounted from every task on each change.
- Each list fetches only the tasks it can show and keeps its rows between redraws.
- A list on screen does nothing at all while it waits (it used to redraw itself every minute).
- Search waits a moment after the last keystroke; the widgets' snapshot holds only what a widget can show.

Steadier:

- Fixes for crashes that could follow a task, Group, label or switch being deleted on another device while its
  card or a delete question was open, and while Spotlight was indexing.
- Siri and Shortcuts say plainly when HITList cannot open its data, instead of "Added".

The sync engine (switched on only where it is moved to):

- It catches up at every launch and return to the app. Found on George's iPhone beside the Mac: Apple's engine, left
  to schedule itself, fetched only when a push told it to, and missed what another device changed while the app was
  closed. HITList now asks for each sync itself and keeps its own push subscription.
- If iCloud is not ready for a new version of HITList (a schema not yet deployed), the engine waits and says so;
  nothing is refused and nothing is lost.
- Check iCloud… on the engine reads every item in iCloud afresh and compares it with the device, field by field.
- Moving back to the earlier sync asks whether this is the first device to go back (it sends its tasks) or another
  (it downloads a fresh copy), so nothing is saved twice.
- The move was rehearsed with two real devices on iCloud's test side, with a copy of George's own tasks.

Before release (2026-11-20; George: "I don't want to lose my friends' trust in this app because we missed something
obvious"). A store made by 0.9.13 was opened by this build on the simulator and compared row by row (the stored
data's shape has not changed since 0.9.13, so nothing is migrated). Three reviews read what the suites cannot: what
an updated device does on its first day with no move asked for, what the build says about itself against what the
code does, and whether the faster lists can show something old. None found a reason to hold the release; they found
these, each fixed with a test:

- **A task's card keeps the space you typed last when you leave HITList and come back.** What you typed is saved
  the moment the app goes to the background (so nothing is lost if iOS ends it there); the space, or the line
  break in the description, was dropped with it, so "Call Sam about " came back as "Call Sam about" and the next
  word, or what you pasted from the other app, ran into it.
- **Week: "Previous week" is greyed out while this week is showing.** On an iPad or a Mac it was a live button
  that changed nothing until it had been pressed once.
- **Week: the open all-day row scrolls after six tasks.** A day with twenty tasks that have a date and no time
  pushed the hours off the screen and its own last tasks out of reach.
- **The question about notifications is asked only while HITList is in front.** A pass that ran while the system
  had woken the app in the background could have recorded a "no" nobody gave, and reminders would have stayed off.
- **The Mac's and iPad's sidebar counts follow a switch that becomes a task when overdue** at the moment it falls
  due, as the list beside them does; they waited for the next change.
- Settings → iCloud → Details no longer calls the new sync "early access".

Known and left as they are: leaving HITList in the middle of a date or time word in a card's title saves it as
read so far ("Meeting at 1" is a meeting at one o'clock; a change that stored the words unread instead was written
that night, reviewed, found to leave a whole "tomorrow" as plain words in other cases, and taken back); "this
monday" typed on a Friday means the Monday of this week (as in 0.9.13); a tap on an empty day of the Week layout
does nothing; a sub-task typed and not entered is added when you leave the app.

## 0.9.13 — build 30, 2026-11-16

0.9.12 was released on the evening of 2026-11-15. George the next day: "currently, when you group Switches on Flipboard, they all
reset at the same time. Could you make it so that when you group switches that already exist that they maintain
their old timing? That way we can group switches together one that resets once a week and one that resets every
other day under the same group etc. Essentially, it's okay to have default reset times for a Switchboard but they
shouldn't be locked to that reset time." And on the sync engine: "Please continue freely on the separate container
for the iCloud engine if you think that's the best approach for a professional and robust (yet not overengineered)
iCloud sync setup."

Flipboard:

- **A switch keeps its own timing on a Switchboard.** Drag a switch onto a Switchboard, or choose the board in its
  card, and nothing about it changes but where it is shown: its interval, the day it is next due and its time stay.
  Before, every switch on a board took the board's Daily or Weekly and they all reset together.
- **A Switchboard's reset is a default, not a lock.** A switch made on a board starts on the board's cadence (every
  day on a Daily board, every week on a Weekly one) and resets with the board at its reset time, as before. Its
  card has the quick choices and the interval's dial on a board now: give it any other interval and it keeps its
  own days, exactly as a loose switch does ("every 2 days" is two days from each flip). Set it back to the board's
  cadence and the row reads "Every 1 day with Before Bed": it resets with the board again.
- Switches that were already on a board reset with it as they always did. Changing a board's cadence or reset time
  moves the switches that reset with it and leaves the others alone.
- One limit, by design: every week on a Weekly board, and every day on a Daily board, mean the board's own week and
  day. For seven days from each flip on a weekly board, set "7 days".
- Nothing new is stored or synced: which clock a switch keeps is read from its own repeat. A device still on an
  older build shows every switch on a board on the board's clock, as it did.

Under the hood (HITList's own sync engine is still switched off, and a released build cannot run it):

- **The engine has an iCloud container of its own**, `iCloud.com.trammells.hitlist.sync`, beside the tasks' and
  Shared Tasks'. The sync HITList uses today reads everything in its own container, and older builds stay in
  people's hands; in a container of its own, nothing an older build does can ever reach the engine's records, and
  today's data stays exactly as it is if a device ever has to go back. This version only lists the container; it
  opens nothing in it.
- The reviewed engine ran against iCloud's test side for the first time, in the new container: every step of its
  probe passed, and two Debug Mac apps synced through it.
- On a Mac the engine now asks for pushes itself (until now only today's sync did, which the engine switches off).
  A push waking the engine is still not proven: it takes a second device.

## 0.9.12 — build 29, 2026-11-15

0.9.11 was released on 2026-11-15, and George wrote back within minutes: "Why did all the creatures in the Theme menu
get so small? And why does Quill look like he's melting in the Theme menu now? I simply wanted you to position Quill
properly, not change his Theme menu sprite." And: "If we need to make our own engine for proper cloud sync, let's get
started. I want it to be professionally built."

Then, before releasing it, on 2026-11-15: "we first need to clean up, ensure that my friends won't lose data (or
instruct them to export it before they do), and fix some crashing bugs", with two crash reports from a friend, and
"finalize and critically review your new CloudSync engine as if you were a lead Apple developer with a focus on
efficient simplicity."

A crash:

- **Tapping a reminder no longer crashes HITList.** Two reports from a friend's iPhone 17 Pro on iOS 26.5.1 (0.9.3
  and 0.9.9): tapping a reminder on the Lock Screen, or in Notification Centre, opened HITList and it crashed. The
  app answered the system on a background thread, where iOS requires the main one; iOS 26 aborts the app for it.
  It answers on the main thread now, for a reminder tapped, completed, snoozed, or shown while the app is open.
  (Not reproduced here: the only simulators on this Mac run iOS 27, and a Debug build never handles reminders. The
  cause is in the crash logs themselves, and a test pins the thread.)

The Theme menu:

- **Quill is himself again.** 0.9.11 drew him a frame of his own for his theme's box, bent to follow its corner; it
  read as melting. That frame is gone. He sleeps in the pose he has on the "+" at night, every pixel as since 0.9.6,
  and only his place changed from 0.9.9's: 6 pt to the left, so he lies on the box's top edge with his hindquarters
  over the corner instead of hanging in the air beside it. The selection ring passes behind him.
- **On the Mac the creatures fit their boxes.** Nothing had changed their size: the Mac's Theme page always drew them
  at the iPhone's size (a point a pixel) on boxes half as big again, where they looked lost, and 0.9.11's notes
  showed that page. The Mac's box is now the iPhone's one and a half times the size, creature and all (three device
  pixels a sprite pixel), so each sits exactly as on the iPhone. The iPhone's and iPad's boxes are as they were.

Editing while another device edits:

- **An open editor no longer puts old text back.** With a task open in the editor, if its notes were changed on
  another device meanwhile and you then changed only the title, Confirm saved the notes the editor had opened with
  over the newer ones, and they won on every device. The same held for the title, and for a Group's, a label's and a
  filter's name, colour and query. Each editor now saves only what you changed. (Found by the review of the new sync
  engine; the hole was there under today's sync too.)

HITList's own sync engine (built this round, **switched off in this version**: every device syncs exactly as in 0.9.11):

- **Why.** Today's sync is Apple's mirror of the database. It keeps to itself the list of what is waiting to go, so
  the bolt can only be worked out from the outside; it names iCloud's records itself, so two can stand for one item;
  it says "succeeded" for an export that sent nothing. The engine replaces it with records of HITList's own (one per
  item, named by the item), a list of what is waiting that the app holds, written rules for two devices changing one
  thing, and Apple's `CKSyncEngine` underneath for the scheduling, the retries and the pushes. The design is
  `dev/SYNC-ENGINE.md`.
- **How it was built.** A design and a contract in code first; then nine sessions in two waves. One proved the rules
  that settle a record (21,700 generated cases), one built a pretend iCloud that keeps the real one's rules with every
  failure on a switch, one ran the engine through thousands of random histories on several devices against it, one
  read all of it as a stranger looking for the bug that loses data and found twenty, and one probed the real service
  on its Development side. The design was corrected on evidence more than a dozen times in three hours.
- **The review, the same day.** Read again as a lead engineer would, the engine's weakest idea was that it found a
  deletion by comparing: an item iCloud held that was not on the device was "deleted here". A store that read empty
  therefore looked like everything deleted, and that took a guard of numbers (ten items and half of everything), a
  hold that asked the person, a vouch the app had to remember before every bulk delete, and a third way out. All of
  that is gone. **The engine now deletes in iCloud only what was deleted**: each deletion is written down as it is
  saved, before the save commits, and an item that is merely not on a device is missing and comes back from
  iCloud. A store that reads empty, loses rows or is put back from an older copy cannot delete anything for anyone,
  and nobody is ever asked whether they meant it.
- **Also from the review**: a released build cannot run the engine at all (before, a stored preference could have
  switched it on); a save that deletes names its rows instead of asking for a read of the whole store, and a fetch no
  longer ends with one; a change that arrives while you have the same item open and unsaved is applied as soon as
  your edit is saved or dropped, not at the next launch; a task un-completed just after its completion was sent, when
  the network dropped before iCloud's answer, no longer completes itself again; the test rigs are no longer compiled
  into released builds.
- **What it will change when it is switched on**: the bolt is exact ("3 changes waiting to go to iCloud", filled
  only when nothing is waiting and iCloud has been read); the same item on two devices is always one record;
  a deleted item stays deleted on a device that was away; an undo of a deleted label gives its tasks the label back.
- **What is not done**: it has not run on real data or on a phone; a push waking it is not proven; moving a device
  over from today's sync is built and rehearsed only on test data. The decisions that are George's are in section 12
  of the design, and what is still open in section 13.

## 0.9.11 — build 28, 2026-11-15

0.9.10 was prepared on 2026-11-13 and never uploaded: Apple had a new Program License Agreement waiting for George to
accept, and the export stopped there. He read its notes instead and wrote back the next evening: "the bolt should not
be able to be filled while the three records differ; doesn't that defeat the purpose of the bolt?" So this is 0.9.10
and the round after it together: a sync bolt that costs nothing at rest and is filled only when this device and
iCloud hold the same records, creatures that move every few seconds and cheer a finished task, Flint's blink and
rain, the calendar where it can be found, an import from Todoist, and the app's long name. Six sessions and the
supervisor's own work on sync; George saw every sketch as it was made.

Sync:

- **The bolt is filled only when two things are true.** iCloud's own sync (CloudKit's mirror) has fetched in this
  session and nothing has failed since; and a fresh read of every record iCloud holds (its kind, id and change stamp,
  nothing else) matched what is on this device. After a launch that takes a few seconds, about two after the
  mirror's own import, and the words say "Checking with iCloud…" or "Last synced 3 min ago, checking…" meanwhile.
  0.9.10 as prepared would have filled the bolt on the mirror's word alone.
- **If the two differ, the bolt says what differs**, in counts: "1 label and 2 filters on this device aren't in
  iCloud". A difference is believed only when two reads four seconds apart both find it with sync quiet, so a change
  that is merely on its way never shows. It is drawn hollow for two minutes and hollow in red after; Settings →
  iCloud & data says where it is settled, and Check iCloud… names the records and offers "Send to iCloud" or "Remove
  from this device", as before. Nothing is repaired by itself: a record here and not in iCloud was either never sent
  or deleted on another device, and only the person knows which.
- **What the check never does**, each of which 0.9.4 to 0.9.9 did: ask iCloud on a timer (every 15 seconds while a
  window could be seen), keep its own copy of iCloud's index between launches (a stale copy can disagree for good),
  animate while it waits, or say "Sending 3 changes" about records nothing was sending. A read follows something
  that happened: the launch's first import, coming back to the app after half an hour, trouble that cleared, Check
  iCloud… or one of its repairs, and, only while the two differ, an import or export. At rest nothing is read and no
  timer runs: the Mac app idles at 0.0% CPU.
- **If iCloud won't answer the read**, the bolt says "iCloud isn't answering, HITList will keep trying", tries twice
  more (20 seconds and two minutes later), and then follows the mirror's own word again until you come back to the
  app: a check that can't run must not hold the bolt hollow for good, which is how 0.9.9 failed.
- The bolt's "good to go" plays when the records have been found the same, not at the first import.
- George's three records are explained. One of them carries the same fingerprint and the same October timestamps
  as a starter filter that sits in iCloud's Development side: they were made on his Mac in the app's first days,
  when test builds still shared the real store and synced with Apple's Development side of iCloud. The released app
  took the store over later, and records never changed since were never sent to Production. Check iCloud… → Send to
  iCloud sends them.
- From 0.9.10, unchanged: the hollow bolt stands still (its endless "breath" cost a fifth of a processor core in the
  Mac's toolbar, where every frame lays the toolbar out again); Settings' sync line redraws every 30 seconds, not
  every second; "Last change" on the Mac names both directions at once ("Received 3 min ago · Sent just now")
  instead of flipping between them at every click into the window. Underneath, SwiftData's CloudKit mirror, the
  store, the schema, pushes, the sync log and the watchdog are as they were.

Companions:

- **They move.** George: "we made them too sparse. The creatures just feel idle now." In their default states (awake
  by day, asleep at night, no weather holding) a small idle comes 4 to 12 seconds after the last one ended: the wait
  is never longer than 12, never shorter than a floor that is itself drawn anew each time between 4 and 7, and never
  within half a second of the wait before, so there is no beat to notice. The first comes 1.5 to 4 seconds after the
  creature appears. With three or more idles to choose from, an idle is never one of the last two. Under rain, a
  storm, snow or heat the pace and what is skipped stay as they were (6 to 36 seconds). The longer routines and the
  flourish keep their rules. On the Mac the new pace averages 0.8% of a processor core, and reads 0.0% between moves.
- **They cheer when a task is completed**, each in its own way and only with frames it already had: Nod's lamp
  flares twice, Quill kneads, Tuck's sprout puts up a bud, Hush's ears shoot up, Glim's lantern burns brighter, Phase
  jumps up tall, Button springs up blushing, Flint lifts his wings and giggles. One cheer in any six seconds (ten
  tasks ticked in a row cheer once); it never cuts a routine or the flourish short; asleep, the creature opens an eye
  instead, at most once a minute; in the rain or snow it gives its usual reply over its weather pose, never a dry
  frame; nothing plays with Reduce Motion, Reduce Effects, Low Power Mode or Companions switched off. Any list's
  task counts, shared tasks and Flipboard switches flipped green included.
- **Flint's blink** painted his eyes grey and left a sliver of pupil over a white bar, so for two ticks his eyes
  dropped and shrank to a scowl. Now the pale eye stays where it is and a lid closes over it, with a dark lash low
  in the eye; the same shut eye is his asleep eye, and his glad eyes (the wink, the giggle, the cheer) are two arcs
  curving up. **His rain** drew a white ring round his whole head: a helmet, with no ears and no tail tuft. Now he
  is the daytime Flint holding his own wing over his head, with beads on it, a puddle at his talons and a drop that
  falls past his face; in the drip and the peek only the water moves. Asleep in the rain the same wing lies over
  him. His 32 daytime frames are 0.9.9's, byte for byte, pinned by a test: a friend likes him as he is.
- **Phase looks down and to the left in the rain**, at the water gathering under him ("he looks weird looking up
  constantly"): four pixels in each of seventeen frames, and his `watch` now follows where the drop will land. His
  sudden looks at thunder are kept; the last frame of each is the down-left look.
- **Quill on Midnight's box** in Settings → Appearance lay above the corner's curve, over empty air, and sat on the
  selection ring when Midnight was picked. He lies on the corner and hangs down the side against the box now, picked
  or not, on iPhone and Mac.

Calendar:

- HITList has shown the device's calendars in Today and Upcoming since 0.9.1, behind a switch in Settings → General
  that George, who asked for "calendar/GCal integration", had never met. It has **a page of its own now: Settings →
  Calendar** (a section on the Mac). The switch, the calendars listed by account with their colours (iCloud, Google,
  Exchange, subscribed), and what to do when access was refused.
- **Google Calendar** arrives through the device's own accounts; HITList signs in to nothing. The page says so, and
  while the device has no Google account among its calendars it gives the path to add one.
- **An event opens a card**: its title, day and time (and its own time zone when that differs), calendar, place,
  the first lines of its notes and its link. Read-only, inside the window, closed by a tap outside or Escape.
- **Add to Calendar** on a task with a date (the row's menu and the editor's): one event in the calendar chosen on
  the page, at the task's time for 30 minutes or all day, with the task's notes and a link back to it. A toast says
  "Added to Work" with Undo; a task already there says "Already on your calendar". It is a copy: changing the task
  later does not change the event. With calendar events switched off it asks only for permission to add.
- A tip in Today, once, says the day's calendar can show there.
- Events still never enter the store, iCloud, backups, widgets, Spotlight or the Claude export.

Import from Todoist:

- **Settings → iCloud & data → Import from Todoist…** (Settings → Data on the Mac) reads Todoist's own backup (a ZIP
  with a CSV for each project; no need to unzip it) or one or several project CSVs.
- **A preview before anything is written**: where each project goes (a new Group, an existing one of the same name,
  the Inbox), how many tasks, checklist lines and labels will be made, which tasks repeat, which dates could not be
  read, and what is already in HITList. Then one button.
- What comes across: titles, descriptions, comments (as text in the notes), priorities, labels typed as `@name`,
  dates and times with their time zone, repeats ("every day", "every mon, wed at 9am", "every 2 weeks", "every
  15th"), deadlines, and sub-tasks (plain ones as checklist lines; ones with a date, priority or label of their own
  as tasks, with "Under: …" in their notes). Sections become labels (a switch on the preview). What HITList cannot
  hold is kept as words in the task's notes: assignees, durations, a repeat's end, a repeat counted from
  completion, a date in words it cannot read.
- **Nothing is doubled**: a task with the same title in the same Group that isn't completed is skipped, so a second
  run of the same file makes nothing. **Nothing already there is touched**, a backup is taken first, and **Undo last
  import** removes exactly what the import made.
- Not in Todoist's files at all: completed tasks, reminders, filters.

Small things:

- **HITList is short for Human-In-The-List**, and now says so once: at the head of Settings → About, and in the
  Mac's About HITList panel.

## 0.9.9 — build 27, 2026-11-12

0.9.7 and 0.9.8 were each prepared and never released: George looked at their pictures the same day, wrote "we're
getting closer to the final product" of the first and "I already have enough feedback for you to prepare 0.9.9" of
the second. So this is everything since 0.9.6: a reminder a friend could not set from a task's title, the creatures
as he sent them back three times in one day, their seats on the theme boxes in Settings, and the Flipboard's
Switchboards as rows. Sixteen sessions over the three rounds; he saw every sketch as it was made.

Reminders and quick add:

- A reminder typed into a task's title is no longer lost. A friend's screenshot showed a task due at 8:00 PM with
  "PNHP Working Group tonight !30mb" as its title and no reminder. It failed two ways, and both are fixed. Typed in
  quick add, the line had no time ("tonight" was not a word the app read), so "!30mb" stayed in the title as text,
  and it stayed dead there after the task was given a time by hand. Now a reminder before the due time ("!30mb",
  "!1hb", "!at") left in a title is set the moment it can count: when the task is given a time in the editor, or
  when a task that already has one is opened. The reminder appears on its pill and the phrase leaves the title;
  nothing waits for Confirm. A task that already has such a reminder keeps it, and the words stay words.
- Typed in the editor, such a reminder showed nothing until a space was typed after it, so it looked dead although
  Confirm saved it. The editor's rows and pills now show it at once; the highlight in the title still waits for
  the space, as in quick add.
- "tonight" is a day word: today, with no hour of its own.
- "!0mb", "!0hb", "!0db" and "!0b" mean at the due time, like "!0" and "!at".
- The same fault looked for everywhere a typed phrase leans on something the task holds: Review Inbox kept dropping
  a reminder typed into a title and read the task's stored title as if it had just been typed; "starting friday"
  typed on a task that already repeats now starts that repeat on its first day from there; Claude's update_task no
  longer keeps "minutes before" on a task whose time it removes, and reads a reminder in a due phrase.
- Removing a task's date (the editor's "No date", "Remove Date" in a row's menu or in Upcoming) removes its reminder
  before the due time with it. Kept, it came back unasked the day the task was given a time again.
- A title never breaks its line between a "!" and the word it starts: on an iPhone "!30mb" at a line's end left the
  "!" on one line and "30mb" on the next, its highlight in two pieces.

The creatures:

- Rain is rain. Water is blue now, three blues that are the same in every theme. In the rain every companion has
  beads on it that stay, a drop that swells and runs off it now and then, and a small puddle at its feet, by day
  and asleep (each has a rain still for the night now; only Nod had one). What each does about the rain is why it
  is wet there: Nod sits under his canopy, Flint holds a wing over his head, Button pulls his cap down to his
  cheeks, Quill lays his ears back under his arched tail, Hush draws his ears up into a hood, and Glim curls his
  tail in and holds his lantern in his lap to keep it dry (there is never a drop on it).
- Graphite's companion is Flint, a gryphon cub, in place of Gargle the stone dragon. George: "he's the only creature
  that doesn't fit the theme. He needs to have more cartoonish eyes and appearance (not necessarily sillier, just
  less real), and perhaps make him a Gryffin … (Also, please rename him; Gargle is a bad name)". Flint is drawn as
  the other seven are: a round owl's face looking at you, eyes ringed in light, a peach beak and talons, and behind
  it a lion cub's body in flat greys with one folded wing and a short tail that ends in a soft tuft. He preens a
  wing, pounces on his own tail and misses, and flaps until he lifts off the bar for a moment; now and then he lets
  out a squeaky screech and giggles. Asleep he lies down with the tuft over his talons; in the rain he holds his
  wing over his head in an arc; snow gathers between his ear tufts, on his wing and on his tail, never over his
  eyes, until he shakes it off.
- Phase, Mocha's ghost, is one floating sheet you can see through: a wavy drape with a wavy hem, no head and body,
  nothing that reads as hands, no horn. His body thins from the crown down to a nearly clear hem and a tail that
  ends in a wisp, and what he does is done with opacity: his bob thins and fills him, a tap makes him flicker, and
  now and then he fades from the hem up to a faint shape round his eyes, then fills back in from the crown. His
  eyes are black with one white pupil, solid on the see-through body (0.9.8 had lit them white: "ruin his entire
  vibe"). By day he looks down and to the right; in rain up and away to the left; in snow at the pile under him,
  and when it is deep he looks a little worried. Rain falls through him to a puddle on the bar; snow gathers under him in one
  mound.
- A companion can give real light: it names the inks that glow, and the app draws a soft halo of their colour
  under the crisp pixels. Glim's lantern does (fainter in his lap, fainter still asleep). With Reduce Transparency
  on, a see-through body is drawn solid.
- Glim, Tokyo Night's mouse, is 0.9.5's drawing again, every frame; 0.9.6 had redrawn him and he was "so much
  worse". He has nine pixels of new shading that nobody sees at real size without looking for them.
- Tuck, Moss's snail, sleeps at peace: his daytime head, his shut eyes resting low on short stalks that lean apart,
  and a small flat line for a mouth (0.9.6 left him smiling in his sleep on upright stalks; 0.9.8 took the mouth
  away altogether). In the rain he is himself, in a puddle that laps at his foot, his pot brimming, and now and
  then a drop falls from a leaf into the pot.
- Quill, Midnight's cat, keeps 0.9.6's face, three pixels friendlier: the centre stroke of the M on his brow, which
  read as a frown, is gone, and he has a small mouth under his nose.
- Nod has eyes two pixels tall; George: "an art style where none of the characters have just single-pixel dots for
  eyes". In the rain 0.9.6's little canopy floats over his cap, with beads on it and a drop off its rim, and it
  stays over him while he sleeps.
- Button pulls his cap down over his eyes in the rain and lifts it now and then to look out.
- Hush is as 0.9.6 drew it ("the perfect example of a good rework") but for the water in its rain, and a test pins
  every other frame.
- Snow lies about half as deep again on Nod, Button, Glim, Tuck and Quill, still as powder and never as a cap.
- In Settings → Appearance each companion sits its own way on its theme's box. Nod sits on the card; Flint is in
  the air at the left edge, partly outside his box; Quill is asleep, sliding off the top right corner; Tuck sits
  in the middle of the floor and Button at its left; Glim sits at the right of the floor with his lantern hanging
  below the box toward "Tokyo Night"; Phase sleeps on the accent dot; and Hush peeks over the top, the only one
  behind a box.

The Flipboard:

- A Switchboard is one row that scrolls sideways, on a quiet panel of its own, so its switches read as mounted on
  one board. The row shows whole tiles and a part of the next, comes to rest on tile edges, and ends in the dashed
  Add switch outline, which adds to that board. On the Mac a small chevron pages a long row.
- Each board has lights: a strip of small dots beside its name, one a switch, in the row's order, green or red,
  always in view however far the row has scrolled. Tapping a light brings its switch to the front of the row. When
  there are too many for dots the strip becomes slimmer segments, and past that a bar with the count. A thin trace
  joins the tiles behind the row and turns green when the whole board is on.
- The ungrouped switches stay at the top, two across on iPhone, under an "Ungrouped" header with lights of its own
  that folds them away to one line; folded is remembered on the device.
- Adding a switch on iPhone no longer makes it flash large, mirrored and tiny before it settles. The landing
  animation handed a spring an impossible speed; the new tile now appears once, in its place.

## 0.9.6 — build 26, 2026-11-12

0.9.5 was prepared overnight and never released: George looked at its pictures and sent it back before dawn ("not
quite satisfied with it yet"). So this is everything since 0.9.4: 0.9.5's work, with his notes on those pictures
worked in by seven sessions before nine in the morning. The creatures are drawn again where he asked, snow looks
like snow, and the cards have room around their words.

The creatures:

- Button, Rosé's mushroom, is himself again: 0.9.4's drawing pixel for pixel (the big glinting eyes, the smile, the
  rosy cheeks, the cap pulled down over his eyes at night), which 0.9.5 had redrawn smaller and plainer. Two things
  are new. He stands on his boots on top of the bar instead of dangling them over its edge, and his idle moves are a
  mushroom's: a bob, a puff, a wobble of his cap, a couple of spores let go. No boot ever swings.
- Phase, Mocha's ghost, is a little cloth ghost now instead of a dome over a scalloped hem: a round hooded head with
  its curled point, wide pale eyes, and a hanging cloth that falls into three uneven points, one corner lifted. It
  hovers on top of the bar and nothing of it lies over the button any more (the darker band is gone). The weather
  goes through a ghost: a raindrop falls in at its crown and out at its hem, and snow gathers on the bar under it
  instead of on it.
- Gargle, Graphite's stone pup, is more of a dragon: a short snout, horns swept back, warm reptile eyes under a brow
  that lowers, a closed smile with one small fang. Now and then a puff of smoke leaves a nostril or he hiccups one
  ember; nothing ever hangs from his mouth. His tail still drops behind the bar and he still sleeps as a statue.
- Hush and Quill are drawn with more care, in the same places and poses. Hush's ears have an inside, there is a peak
  of fur over the brow, a soft lower lid, a small round belly. Quill is a tabby: an M on his brow, inner ears, a pale
  muzzle, whiskers, a ringed tail, stripes down his side, and cat's eyes in his theme's colour.
- Glim, Tokyo Night's mouse, has a head that reads as a head (round ears with a pale centre, a moon-pale face, a
  nose, peach cheeks) and eyes with his lantern's light low in each. In rain and snow he takes his tail out of the
  weather and holds its light to his chest in both paws; now and then he peeks at it, blows on it and tucks it back.
- Tuck, Moss's snail, sleeps with his eye stalks lowered and his eyes shut on them. He used to pull the stalks in
  while two lines appeared on his face, which read as his eyes turning into lines.
- Snow is powder: three tones (a lit crest, pale blue, a deeper blue in the shade) lying where snow would fall and
  stay, thin on a slope and deep in a hollow, ragged at its edge. It was a white cap in the creature's own light ink,
  and read as a hat. The three snow inks are the same in every theme and do not count among a creature's colours.
- The large black eye with a glint is Button's alone now; every other creature has eyes of its own.
- Each companion moves like itself (from 0.9.5). Watched for two minutes on 0.9.4, Nod did seven things and six of
  them were his feet. Now Nod nods off and jerks awake, rubs his eyes, yawns and pulls his nightcap down; Quill turns
  an ear toward a sound, writes with his tail tip and kneads; Tuck draws his eyes in one after the other and leans
  toward his seedling; Hush lifts an ear to listen and peeks out from behind it; Glim tends his lantern. A test keeps
  a creature's feet to a fifth of its idles at most.
- A companion can be behind what it sits on (from 0.9.5): Gargle's tail drops behind the "+" or the search field
  instead of hanging over its face.
- Each theme's companion is named under it in Settings (from 0.9.5).

Room around the words (George: "some text is right next to a border"), on every iPhone and most of all on the Duo:

- Quick add ("Add task"): its chips wrap onto a second and third line, each whole and inside the card, instead of
  running off the card's edge and being cut through a word ("11:00 AM · 15"). On the Mac too, when they do not fit
  one line.
- The reminder card: every label, chip and field is 12 pt inside the card (they were 6 to 8, and "Later today…"
  ended on the border). On a narrow card the three "from now" choices fit one row as "In 15 min", "In 1 hour",
  "Later…", and the note about notifications is left out so the card needs no scrolling. "N min" is laid out like
  its neighbours, the four times keep the card's two columns where they do not fit one row ("8 PM" sat alone on a
  second one), and the card is never wider than the screen.
- The date card: the five quick choices have 8 pt either side of their words and 6 pt between them (the words
  filled them from border to border), and the month's name, the day grid, the choices and the time field share one
  left edge.
- The editor's row of pills scrolls inside the card's padding and fades where more are hidden, instead of being cut
  at the edge. The Group and labels lists end clear of the card's foot, and a Discard question keeps the card's own
  padding under its buttons.
- Task rows end where their section headers do: a task's Group and its dot no longer stop 12 pt short of the right
  edge.
- The Flipboard's tiles, its Add switch tile and its Switchboards' names start on the title's left edge (they were
  4 pt off on the Duo), a tile's words sit 16 pt inside it, and the switch card's quick choices (Daily to Monthly)
  keep 8 pt around their words and no longer touch.
- Browse on the Duo: the picture, the bolt and the buttons beside the title are evenly spaced. On every iPhone the
  saved filters fade out at the edge instead of cutting a word.
- Review Inbox: the three tiles stand equally tall with their symbols on one line, and a name keeps clear of its
  tile's sides. The "task done" toast starts on the list's own margin.
- Two tests measure it from now on. `CardInsetsUITests` opens quick add, the editor and every card under them and
  fails when a text or a control is under 12 pt from the card's border, under 6 pt from its neighbour, or cut;
  `ScreenInsetsUITests` pins the Flipboard's and Browse's edges.

The iPhone Duo (from 0.9.5, the first full pass over it since October):

- Closed (the outer display): a screen's controls (the bolt, the view options, search or Settings) sit beside its
  title, and the column down the side keeps only the clock, Back, the tab bar and the "+", so nothing is drawn on
  top of anything else, on a pushed screen or during a call. The title and its controls stay at the top while a list
  scrolls. The week strip and Browse's saved filters no longer slide under the clock and battery, and the tab bar
  steps aside while you type.
- Closed: the date, reminder, repeat, priority, Group and labels cards open whole, above or below their button and
  never off an edge (quick add's date card showed no calendar at all); the task editor opens at its full height; a
  switch's "Discard this switch?" no longer pushes its card off the top. These go by the room on the screen, so the
  open Duo held on its side and any other short screen get them too.
- Closed: a companion lives there now, on top of the upright tab bar, which had no place for one.
- Open (the inner display): search is in the sidebar; one Settings gear instead of two; the list and the editor meet
  at the fold; Upcoming shows whole days (two upright, three held like a book); the days beside Today look like
  Today's; the sidebar steps aside when you unfold with a task open.
- On every iPhone: a task's Group is never shortened to a letter (several labels shorten to "@first +2" first, then
  the Group moves to a line of its own); the Reminder card in the editor is never cut at the top; Review Inbox keeps
  the task in sight while its calendar is open, and "Move to a Group" reads "Pick a Group"; Settings' descriptions
  wrap at larger text sizes instead of being cut.

For the record, what nobody saw running: the Duo's inner display itself (Device Hub could not list the simulators,
so every inner-display picture is an iPad mini drawn at the inner display's size); a real call in the Duo's camera
island (a Debug stand-in moved the tab bar instead); VoiceOver's reading order on the Duo; how sheets are sized on
the open Duo. Known and left: Settings closes when the Duo is folded or unfolded; on a pushed screen during a real
call the companion on the tab bar may come within a few points of Back.

## 0.9.4 — build 25, 2026-11-11

George's notes on 0.9.3, worked through in an afternoon by eight sessions: a sync bolt that cannot claim more than
it knows and a check that names what two devices disagree about, companions that are never still for long and sit
on the button, three new creatures, a real repeat picker, more words for quick add and a guide to them, a calmer
Flipboard on the phone, and the answers to the screen-by-screen sweep.

- The sync bolt tells the truth. It is filled only while iCloud itself has confirmed, within the last 30 seconds,
  that this device and iCloud hold the same things; HITList asks every 15 seconds while a bolt is on screen (a small
  request, under half a megabyte an hour). When it is not filled, the bolt and Settings say what it is waiting for
  ("Sending 2 changes to iCloud…", "Receiving 1 change…", "Last synced 3 min ago, checking…"); signed out, offline
  and "iCloud needs you to sign in again" show within half a minute. On 0.9.3 a Mac whose Apple Account needed
  verifying showed a filled bolt and "Synced" for eighteen hours.
- Check iCloud… compares this device with iCloud, record by record, and names what is on one side and not the
  other (Settings → iCloud & data → If something doesn't sync). It repairs nothing by itself: a task that is here
  and not in iCloud was either never sent or was deleted elsewhere, and only you know which, so you choose Send to
  iCloud or Remove from this device, after a backup. The sync log now records how many of each thing the store
  holds at launch and at every account change, never a title.
- From George's two sync logs (both devices, 4,120 entries, read end to end): every change either device saved
  since 2 November reached the other, usually within a second, and nothing was deleted; the Mac was held out of
  iCloud for sixteen hours and caught up within a second of signing back in. So the bolt's words now count every
  change waiting to go ("Sending 46 changes to iCloud…" after a launch that rewrote 46 dates); when iCloud is busy
  and the system retries dozens of times in a second, the sync log keeps one line for the run instead of a hundred;
  and on iPhone a sync notification that arrives while HITList is in the background is a note, not an "Import
  overdue" error. Why the two Inboxes differed is older than those logs and still open: the two stores counted 44
  and 46 dated tasks that morning with nothing changed between them. Check iCloud… on each device will name it.
- Companions are alive. Every 6 to 36 seconds on screen a companion blinks, glances, swings a foot or plays a
  little loop of two to four moves, the first within a few seconds of appearing; asleep it breathes at the same
  pace. The longer routines come every three to eight minutes of showing time, and the flourish is as rare as
  before. (On 0.9.3 a companion could sit for a minute and a half without moving.)
- Companions sit on the "+". Each is drawn down to the button's curve, a check fails any pose that leaves a gap or
  a flat base overhanging it, and the end of every list on iPhone scrolls clear of the companion.
- Three new companions. Rosé has Button, a mushroom in the theme's own rose whose cap is its hat, its umbrella and
  its bed. Mocha has Phase, a see-through ghost that rises out of the "+" with its wavy hem lying over the button;
  a task row shows faintly through it. Graphite has Gargle, a gargoyle pup that lets a drop fall from its chin in
  the rain and turns to stone to sleep. Posy, Mallow and Smudge have retired. Tuck's eyes are round and dark, with
  a glint, and look where he looks.
- Choosing a repeat. The Repeat menu speaks of your task's day ("Every week on Wednesday", "Every month on the
  11th", "Every year on November 11"); Custom… makes any repeat quick add can type (every few days, weeks, months
  or years; chosen weekdays; a day of the month, the last day, the second Wednesday; a date each year); the date
  picker has a Repeat button, so a task gets a day and a repeat in one visit. A repeat picked for a task with no
  date starts at its next occurrence. Review Inbox and Upcoming pick dates with HITList's own calendar, weeks
  starting on your day.
- Quick add. "every 3 days starting friday" starts on Friday and "starting" stays out of the title; several days
  named together ("vacuum tue thu sat", "on tuesday thursday and saturday", "every mon, wed & fri") repeat every
  week on those days; "every other sat and sun" keeps the weekend together whichever day your week starts on. A
  guide shows what quick add understands, each example drawn by quick add itself: Browse → Quick add guide,
  Settings → General → Quick add guide, Help ▸ Quick Add Guide on the Mac.
- Flipboard. The empty Flipboard is a single "Add switch" outline, on every device. The Add a Switch card has one
  scale of type, a small time chip beside the Switchboard's, "Become a task when Overdue" on one line, "Flip 1
  time", and no unexplained switch (the red and green rocker was a preview that saved nothing). Press, hold and
  drag a switch onto a Switchboard, or back off it. Duplicate a switch from its menu. A tile's interval sits on one
  line across a row.
- Mac and iPad: the top-right "…" is the Settings button; what it held (Review Inbox…, Edit Group…, Jump to today)
  sits under the view options.
- From the sweep: every list writes a day one way ("Nov 11 · Today · Wednesday"); "Done" is the same accent pill
  everywhere; Browse's and Settings' section headings are one style; no line under a list's big title; on larger
  iPhones rows share the title's left edge; Mac Settings names each section once; Settings → Data shows its counts
  in two rows of three; What's New shows this version only; the sync log's All and Errors are a switch, not
  buttons; the Mac board's month, day headings and cards share an edge; no empty Filters heading in the Mac
  sidebar; the iPad's selected sidebar row is filled; theme names wrap at large text sizes and captions stay
  readable at small ones; Reminders → Summary time is typed; the Mac editor's check circle is easier to click.

For the record: no schema change, in SwiftData or in CloudKit. Never seen running: a real sign-out and the new
bolt on Production, Low Power Mode, a large first read of iCloud; a switch dragged all the way to a drop on the
Mac; the Mac's summary-time field (switching the summary on asks for notification permission); the Duo's inner
display; macOS 27.

## 0.9.3 — build 24, 2026-11-11

George's notes on 0.9.2, worked through in one night by sixteen sessions: a companion for every theme with a life
of its own, weather that shows on the creature, the location asked once, time zones done properly, a Settings you
can find things in, and then a night of review: a second pair of eyes on the date change, a screen-by-screen
sweep, and accessibility.

- A companion for every theme. Slate has Nod, Graphite has Smudge (an owlet on legs far too long), Midnight has
  Quill, Moss has Tuck (a snail whose shell is a flowerpot), Nord has Hush, Tokyo Night has Glim (a small mouse
  whose tail ends in a lantern), Mocha has Mallow (a round soft toy in a knitted band) and Rosé has Posy (a piglet
  with wings far too small for it). Pip has retired.
- Companions come alive now and then. A companion is still most of the time, blinks or swings a foot every minute
  or so, and every five to twelve minutes on screen does a few seconds of a routine that is its own (Smudge
  doodles a heart with its foot and scribbles it out; Glim's lantern goes out and it shakes it alight). Never the
  same routine twice running. The flourish is as rare as before; a tap plays a routine when the flourish isn't due.
- The weather shows on the companion, and nothing is drawn in the air around it. In rain a drop gathers on what it
  holds and it shakes itself dry; snow gathers on it, a dusting, then a cap, then a heap, until it shakes it off;
  on a hot day (when it feels like 30 °C / 86 °F or more, by day) it wilts or finds its own shade; thunder makes
  it start.
- Quill rests on the "+" with its hindquarters down the button's shoulder, and no companion floats above what it
  sits on.
- Weather is on unless you switch it off (Settings → Extras → Weather), and HITList asks once, when you first open
  it, to use your approximate location: "to keep your companion on local time and dressed for the weather where you
  are". Say no and nothing else changes. Your tasks, reminders and lists follow your device's own time zone.
- A task due on a day stays on that day wherever you are: flying west no longer shows it a day early. The first
  time 0.9.3 opens it backs up your tasks, then updates how their days are stored; it only touches a date this
  device can vouch for, and leaves anything else exactly as it was. Change time zone, or let midnight pass, and
  Today, Upcoming, the Flipboard, the sidebar's counts, reminders, the badge and the widgets catch up by themselves.
- Settings opens on one short screen: you, your themes (each with its companion on its swatch), then a row for
  each page. Pages open inside Settings, every option lives in one place, and the two that erase something sit
  last on their page. On the Mac the sections follow the same order, with Appearance second. "Account settings…"
  opens Account, and the sync bolt opens iCloud & data.
- Add to HITList from the share sheet: share a web page, a link or some text from Safari or any app on iPhone,
  iPad and the Mac and it becomes a task. Type a date, p1 or #Group in the title as in quick add; the address and
  the text you chose go in the notes. What you share is saved the moment you press Add and becomes a task the next
  time HITList opens (at once on a Mac where HITList is running).
- Accessibility. VoiceOver hears a task as one stop (its title, then its second line, with completing as an
  action), the iPhone's tabs as a tab bar, a Flipboard switch as off or on instead of red or green, a chip by what it
  is ("Date: Tomorrow", "Priority: P1"), an open card alone, and the Undo toast when it appears. Under Differentiate
  Without Colour a priority is written as well as coloured. Small iPhone controls take a press in the space around
  them. On the Mac the keyboard reaches the editor, and the toolbar's sync bolt takes a click anywhere on it (it
  used to answer only on a 4 pt strip). The system's accessibility audit can be run on every main screen, card
  and Settings page (`TEST_RUNNER_HITLIST_AUDIT=1`).
- From the screen-by-screen sweep: Settings rows are all one height on the Mac; "+ Add task" lines up under the
  tasks on the Mac and iPad; an empty Completed says "Nothing completed yet"; the Mac sidebar's Settings lines up
  with the rows above it; Upcoming's "Overdue" is the same red as Today's.

## 0.9.2 — build 23, 2026-11-11

George's notes on 0.9.1: companions that keep still, one for each theme; the weather for them; widgets that check a
task off and wait for iCloud. Three sessions at once.

- Companions keep still now. A companion is a still picture that does one small thing every minute or two (a blink,
  a swing of a leg) and its flourish about once in three hours of use, so you may not catch it for a day. A tap or
  click plays the flourish if none has played for twenty minutes; sooner, it only looks up.
- One companion for each theme, and never two on a screen. Slate has Nod, Midnight has Quill, Nord has Hush (ears
  longer than it is) and Rosé has Pip (a pinecone that is also a creature); the other four themes have Nod until
  their own are drawn. On the Mac the companion sits on the search field; on iPhone and iPad, on the top right of
  the "+". The spots in Browse and beside the Mac's Settings are gone.
- Companions sleep from 22:00 to 07:00 and stir if tapped, and with Weather on they dress for rain and snow.
- Weather for your companion: Settings → Extras → Weather. Off until you switch it on; it uses only your approximate
  location, and only to ask Apple Weather whether it's raining or snowing.
- Check off a task from the Today and Upcoming widgets, and flip a switch from the Flipboard widget. A checked task
  stays on the widget, ticked, until iCloud has it; then the next one takes its place. If iCloud is slow or offline
  the widget says "Waiting for iCloud"; if the Mac app isn't running it says "Open HITList to finish".
- Widgets catch up after changes from your other devices while HITList is closed (a push now ends in a fresh
  widget, and there is an hourly background refresh), and say "As of yesterday" when they haven't heard anything in
  a day.
- GitHub Actions builds again: the runner's older Swift could not type-check two expressions in the companions'
  code.

## 0.9.1 — build 22, 2026-11-10

Widgets, everything that moves, two pixel companions, calendar events and a sync bolt that keeps still: George's
notes after 0.9.0 (21), in five sessions at once. Versions bump by 0.0.1 per release again.

- Widgets on iPhone, iPad and the Mac. Today shows what's due and what's overdue, in Today's order, small, medium or
  large. Upcoming shows this week (or the month) with a dot on each day that has tasks, and what's next. Flipboard
  shows your switches green or red, the loose ones or one Switchboard you pick in the widget's settings. Tap a task to
  open it, anywhere else to open its screen. On the iPhone's Lock Screen: today's count, the next two tasks, or
  "3 tasks today" beside the date. Widgets can't complete a task yet.
- The sync bolt keeps still. It says all is well and stays that way while syncs come and go, breathes slowly only
  when a sync is taking a while, and shows trouble only once it has lasted. It no longer swaps and pulses on every
  background sync; the strike and the slam still play when you're good to go.
- A short iCloud hiccup, like the one after an update, no longer shows alarming words. If it lasts, HITList says
  "iCloud isn't answering, HITList will keep trying"; if sync has stopped while changes wait, Settings says "Sync is
  stuck" and the Mac offers Relaunch. An account blip no longer clears reminders, and the sync log ends a stretch of
  trouble with "Sync recovered after …".
- Two small pixel creatures live in quiet corners. Nod, in a nightcap with a glowing bobble, sits on the search field
  with its legs swinging; Quill sleeps at the foot of Browse (on the Mac, beside Settings) with an ink-dipped tail.
  Every few minutes one of them does something, if you happen to be looking. Settings → Extras → Companions turns
  them off.
- Calendar events beside your tasks: turn on Settings → General → Calendar events and Today and Upcoming show your
  events from the calendars you pick, read-only. Events never leave the device; HITList never changes them. Off by
  default.
- On iPhone the card for a new task moves with the keyboard: no jump when it asks Discard, and tapping the title to
  keep typing brings the keyboard back. The Flipboard's switch card settles sooner.
- On the Mac, task cards come down into place and leave a little quicker, the first date card in a window fades in
  like the rest, "Add task" opens and closes smoothly, the sidebar's highlight glides to the row you pick and its
  counts roll to their new number.
- Siri can open the Flipboard ("Open Flipboard in HITList"); `hitlist://` links open a task or a screen.
- The roadmap was rewritten: now, next, parked, shipped (`dev/ROADMAP.md`).

## 0.9.0 (21) — 2026-11-10

George's and a friend's notes on 0.9.0, in four sessions at once: the Mac drawn the same on macOS 26 and 27,
Switchboards and routine switches, monthly and yearly repeats in quick add, Browse's last row and swipe to delete, and
the bolt's coin spin. The version stays 0.9.0 from here on; each release is a new build with a section of its own.

- Switches are routines now. They stay on the Flipboard, green or red, and never show in Today, the Inbox, search, the
  badge or the morning summary. Turn on "Overdue becomes task" on a switch, or on a whole Switchboard, to have it wait
  in Today once it's due. Before this build every red switch was one of today's tasks.
- Switchboards group switches into routines such as "Before Bed" or "Deep Clean". Each resets daily or weekly at its
  own time (4 AM for a new one), so a switch flipped at 11 pm stays green until morning. "New Switchboard" is at the foot
  of the Flipboard; a board's name opens its card (name, Daily or Weekly, the reset time, the toggle, Delete…) and its
  "+" adds a switch to it. Deleting a board asks whether its switches stay on the Flipboard or go with it.
- A switch can have a time: type "Take meds 9pm" in the switch card. It shows on the switch, sorts its board and
  reminds you then.
- Quick add reads repeats on a day ("every month on the 28th", "every 28th", "every 3 months on the 10th",
  "quarterly"), the month's ends and weekdays ("every last day of the month", "every first Monday", "every last
  Friday", "every 2nd Tuesday") and dates in the year ("every year on Mar 3", "every March 3"), each as one highlight.
  A repeat shows its day: "Monthly on the 28th", "First Monday of the month", "Yearly on Mar 3". Update every device: a
  build before this one reads the weekday repeats as plain "every month".
- Mac: HITList draws what macOS used to decide, so the window looks the same on macOS 26 and 27. The sidebar's rows
  and selection are ours (the selected list stays accent-filled while you type in Search or the window is in the
  background), the toolbar is the list's own slate with no grey band and no dark strip behind the first header, and the
  view-options pill and the sidebar toggle are drawn by the app. Nothing takes the keyboard when the window opens. On
  macOS 27 the sidebar still sits flush with the window's edge where 26 floats it: that shape is the system's.
- Browse's last row (Settings) no longer hides behind the tab bar on iPhone. Swipe left on a Group or a label in
  Browse to delete it; a Group with tasks still asks first, from a full swipe too.
- The sync bolt's twirl is a coin spin: as it hops it turns about its upright axis and for an instant shows only its
  edge. The slam, the warp and the sparks are as they were.
- Group and label counts leave out switches that aren't listed. The editor's "Add to Flipboard" no longer says a switch
  drops its time.
- CloudKit schema V6: a `Switchboard` record type, and `switchboard` and `overdueBecomesTask` on a task. Deployed to
  Production before this build.

## 0.9.0 — build 20, 2026-11-08

George's notes on 0.8.1, in six sessions at once and the day's fixes: shared tasks as one Group that looks like your
own, the editor's title reading quick add, the Mac's toolbar, sidebar search and type, a second bolt style, and a small
card for adding Flipboard switches. 0.8.2 (the Mac's invisible picker cards) was never uploaded; its fixes ship here.

- Shared tasks live in one Group, Shared Tasks, last in your Groups. They look like your tasks, with the people's
  pictures where labels go, and open in the same editor. Sharing… in its view options invites people, shows who's in,
  leaves, or switches sharing off. Type `#Shared` in quick add, or pick Shared Tasks in the Group card, to add one.
- The badge, the morning summary and the sidebar count shared tasks, and count a red Flipboard switch as one of today's
  tasks, never as overdue. Groups show their coloured dot everywhere instead of "#".
- The task editor's title understands quick-add phrases: type "tomorrow 5pm p1" and the date row and Priority show it
  before you Confirm. Words already in the title stay as they are.
- Mac: the date, Group, priority, label, reminder and repeat cards show again (built with Xcode 27.2 they opened
  invisibly); a card that doesn't fit under its chip opens beside it, and a chip at the end of a row scrolls into view
  when its card opens. iPhone: opening a card in the editor moves the keyboard aside so the whole card shows.
- Rows read larger and lighter, closer to George's reference: Inter 14 over 12 on the Mac, drawn without font
  smoothing, with 14 bold section headers and the date line 22 pt under the title; 17 over 13 on every iPhone (the
  Duo's sizes).
- Mac: a Search field at the top of the sidebar (⌘F), with results in the main column and "Save as filter…" for a
  filter query; a saved filter's toolbar reads "Search: …" (click it to search with that query); more room above and
  below the profile; Filters below Groups.
- Mac toolbar: the "+" is one accent capsule with the same dark glyph as the Confirm pill, in an active or a
  background window; the view-options pill keeps its width on every screen.
- Tips float outside the quick-add card instead of pushing it around, and a tap anywhere on a tip puts it away.
- The sync bolt has a second way of saying you're good to go, the slam: a twirl, a little hop and a slam with a tiny
  buzz of sparks, all in under a second. Settings → Extras → Sync bolt: Strike or Slam (the default). It still plays
  only when the app opens, after a while away, or once sync is back after trouble; Reduce Motion keeps the blink.
- Adding a Flipboard switch is a small card: type "Water the plants every 3 days" and the interval fills in, or pick
  Daily, 3 days, Weekly, 2 weeks or Monthly, or turn the number like a dial. "Edit switch…" opens the same card.
- Flipboard: the lights stay on their switches (an overdue switch's light used to drift in across the board each time
  the Flipboard opened). They are slim pills now, one row at the top of each switch, and every switch is the same size.

## 0.8.1 — build 19, 2026-11-08

0.8.0's Inbox shipped with a small title that was a button, two filter-looking controls, its name twice and two
fonts in one header. This build puts that right and does what 0.8.0 should have: the Inbox and Today cleaned up,
shared tasks in your lists, and the iPhone Duo's type and island.

- The Inbox's top is clean again: the large title "Inbox", one view-options button beside the magnifying glass, and
  no "Inbox · N" header. iPhone titles are large everywhere and are not menus; a Group's screen shows its name once.
- Sort by, in the Inbox: Priority (the default: the flat list, priority then date, as it always was), Group
  ("Ungrouped" last) or Date. Today sorts by Priority or Group. Section headers read "Work · 3" in one font, and a day
  header no longer repeats the day on its rows.
- Browse lists Groups first, then Shared Tasks and Labels. Saved filters are chips under the search field, and the
  search understands filters (`#Work`, `@waiting & p1`, `no date`, `overdue`), which can be saved as a filter.
- Shared tasks are tasks in your lists: with a date they show in Today, Upcoming and the Inbox among your own, with
  their list's name and the people symbol. Complete them from the row (with Undo) or tap to edit. Sort by Group
  gives each shared list its own section after your Groups. Mac: each shared list has a row under "Shared" in the
  sidebar, and its tasks drag to another day on the Upcoming board; iPhone: Browse lists them under Shared Tasks.
  Coming back to the app fetches shared changes.
- iPhone Duo: on the outer display, task titles and their details are a little larger, and the side tab bar has
  more room around its tabs and the "+".
- Switching tabs takes the tab you left back to its first screen, so Browse is not still open when you return.

## 0.8.0 — build 18, 2026-11-07

Round 13, from the friends' first week: Groups you can group and filter by, a tab bar that moves, the Flipboard as
George meant it, and a Review Inbox that is one card and two swipes. First, the three things that went wrong on the
first Mac tester's first day (2026-11-06), each with its own cause and fix.

- The iPad build no longer runs on a Mac. TestFlight offers "iPhone and iPad apps" to Apple silicon Macs unless the
  build opts out, and he installed that one: the iPad layout in a plain Mac window (grey title bar, cramped sidebar,
  a tip cut off), not the Mac app uploaded beside it. The iOS build now declares that it runs on neither a Mac nor a
  Vision Pro; the Mac app is the macOS build.
- Sync: three task fields (deadline, location, and the Flipboard's period start) had never reached CloudKit's schema,
  so the first flip of a switch, or the first deadline, stopped that device exporting: CloudKit Production rejects a
  record with a field it lacks, and the export is retried with the same record for good. The sample-data run that
  teaches Development every field now carries them all, a test fails if a model field is ever left out of it, and
  `release.sh` refuses to upload while Production lacks a field the models have (its old check compared Development
  with Production only, and both lacked the three). The fields themselves ship by deploying the schema, not by a build.
- The sync watchdog no longer counts TipKit's own saves (its tip, event and rule records share the process) as task
  saves that must export; they made it report "Export overdue" errors that were never due.
- The sidebar's "Preview" badge beside Shared Tasks gives way in a narrow sidebar instead of wrapping one letter per
  line.
- Developer: `-seedDemoData` on a side store fills it with a believable week for screenshots; the README shows the app.

Groups (brief 57)
- Group the Inbox and Today by Group, or by priority, from the view options; each list remembers its choice, and
  rows under a Group's header stop repeating its name.
- Filter the Inbox by Group, label, priority or "No date"; the active choices show as chips, and "Save as filter…"
  keeps the query as a saved filter.
- On iPhone, tap the Inbox or Today title to jump to any Group or label; a Group's section header opens it too.
- Drag Groups to reorder them in the Mac sidebar and in Browse; a Group's screen shows its colour and open count;
  deleting a Group that still has tasks asks first and says where they go.
- The Group and label editors, and Browse, say the difference: a task lives in one Group; a label is a tag any task
  can carry.

The island (brief 58)
- The tab bar's highlight is one pill that slides to the tab you tap, with a light haptic tick; the icon fills and
  takes the accent as it arrives.
- Switching tabs crossfades the screens instead of cutting. Reduce Motion keeps both plain.

Flipboard (brief 59)
- Switches stay off your lists until they are due: a green switch lives only on the Flipboard; a red one is in Today
  (and the Inbox) as today's task until you flip it. Upcoming shows no switch. A filter that names `@flipboard`
  sees them as they are.
- Completing a switch from its Today row flips it ("Flipped", with Undo).
- Long-press a switch on iPhone for its menu: Flip or Mark done, Flip back to red, Edit task…, Edit interval…,
  Flips per interval…, Remove from Flipboard, Delete (with Undo).
- Spotlight and Siri list red switches only; Siri's Complete Task flips one.

Review Inbox (brief 60)
- Review Inbox goes through only the tasks with no date and no Group, oldest first; the Inbox menu says how many
  ("Review 3 unsorted…") and hides the item at zero.
- One card at a time: swipe right for Today, left to delete (with Undo); under it Pick a date, Move to a Group and
  Later, and Edit… opens the full editor. The sheet says what it is for, and ends on "Inbox reviewed".
- On the Mac: T Today, D date, P Group, ⌫ delete, → later, Esc close.

## 0.7.1 — build 17, 2026-11-05

0.7.0 was built and tested but never uploaded (its release stopped at the Shared Tasks container's schema check), so
its notes ship here, with George's last fixes. George's notes on build 16 and a read of Apple's design guidelines,
in ten sessions over two rounds: highlights rebuilt on native text views, reminders "from now", Extras and a quieter
Claude, the iPhone Duo done Apple's way with a creaky hinge, a Shared Tasks preview, first-run tips with Spotlight,
then the polish for friends: the profile menu's What's New and beta feedback, a lightning strike on the sync bolt,
and a smoother first run. The first build for the TestFlight group "Friends".

- Profile menu (Mac sidebar, iPad, and Browse's top left on iPhone): What's New (this version, earlier ones on
  request), Send Beta Feedback…, and the version at the foot. On iPhone and iPad, Send Beta Feedback starts an
  email to George with the version and device filled in (never your tasks); on the Mac it never opens Mail: it
  copies George's address and says so.
- The sync bolt is 15% larger, and says "you're good to go" with one quick lightning strike (under a third of a
  second): on the first good sync after you open HITList, after you come back from a minute or more away, or after
  sync was in trouble (offline, an error) for a minute or more. Never for ordinary syncs; a short blink with Reduce
  Motion. Animations may run at 120 Hz on ProMotion iPhones.
- Settings → Claude: "Only tasks with @claude" (the default, on the left) or "All tasks but @private"; the
  integration itself stays off until you turn it on.
- The iPhone Duo's hinge creaks like an old wooden door now, quietly (Settings → Extras → Creaky hinge, on by
  default only on the Duo). Holidays, themes and the rare visitor are silent; the only sounds are the completion
  sound, Flipboard's flip and the hinge, each with its switch.
- A friend's first minutes: tips wait until you've added a task (none on the very first screen), the quick-add
  tips sit inside the card, and no tip ever swallows a tap. On iPhone one tap on "+" right after adding a task opens
  the next card (it used to take two). The Undo toast keeps "Completed" and shortens the title instead.
- Board cards on the Mac and iPad wrap their bottom line rather than cutting the time and Group to "5:38…" and
  "S"; on the Duo's inner display the board stops short of the side bar.

- Quick-add highlights are drawn by the text view itself: boxes sit evenly on the words at any width, and on the
  Mac the pointer is a steady pointing hand over a highlight and the text cursor elsewhere (no more flicker).
- Backspace right after a highlighted phrase removes the highlight first and keeps the letters; the next
  Backspace deletes as usual. ⌘Z (or shake) brings the highlight back. Clicking/tapping it still works too.
- Reminders: `!15m`, `!2h`, `!1d` (and `!1h30m`) remind you that long from now, with or without a due date;
  `!15mb` is 15 minutes before the due time, as before. A "!" phrase lights up once you type the space after it.
  The Reminder chip offers "In 15 minutes / In 1 hour / Later today…", the editor and the task row show the time,
  and tapping a reminder notification now opens its task (the morning summary opens Today).
- Settings → Claude is one switch, off: only once it is on do the privacy choice, the Mac setup and Copy for
  Claude appear. A task Claude completes shows the usual Undo toast.
- "Completing Tasks" in Settings is now "Extras". The profile button has a little more room above Inbox.
- Mac and iPad: the "Discard this task?" question sits inside the board's add card (and the lists' inline add
  row) instead of floating above it; × or Esc there now asks too.
- iPhone Duo: on the outer display the tab island stands on the side where Apple puts bars; the inner display
  shows Upcoming's board; typing in the editor survives a fold; the crease is kept clear when it's half open.
  With HITList open, the hinge creaks as it moves (Settings → Extras → Creaky hinge; silent switch respected).
- Shared Tasks (preview, off until you switch it on in Browse → Shared Tasks): make a list, invite friends with
  Messages, Mail or a link, and everyone can add, complete and edit; each task says who completed it. No sign-up:
  it uses your Apple Account and shows people by their HITList name and picture.
- First-run tips for new people (the quick-add syntax, how to undo a highlight, Browse, Flipboard, the board's
  Add task); Settings → About → Show tips again. Open tasks show up in Spotlight and open in the editor.
- Mac Settings: the window title names the pane, and Settings reopens on the last pane.
- Launch: the app no longer waits on the push service before its first frame. On a freshly booted iPhone that
  wait reached 25 seconds of black screen (iOS kills an app stuck at about 20); the first screen now comes in
  about 2 seconds either way.
- Housekeeping: unused code and 66 MB of unused font files removed; test runs on a side store keep their own
  settings, so they never change the real app's.
- Privacy policy: sections for Shared Tasks and the switched-off Claude integration.
- Schema V5 adds `TaskItem.reminderDate`, and Shared Tasks uses its own container
  (`iCloud.com.trammells.hitlist.shared`); both deployed to CloudKit Production before this build, and
  `release.sh` checks both containers.

## 0.6.0 — build 16, 2026-11-05

George's notes on build 15 and his backburner list, in eight sessions: the Mac board's inline add, the
profile in the corner, quick-add polish, sync and profile hardening, a Claude connector, Siri and Shortcuts,
holidays, and the iPhone Duo.

- Mac and iPad Upcoming board: "+ Add task" on a day opens a small add card right in that day's column, with
  the cursor already in it. Add one task after another; Esc or × closes it and asks before throwing away
  typing. Every Mac quick add (toolbar "+", ⌘N) starts with the cursor in the task name.
- Your profile sits top-left: at the top of the Mac and iPad sidebar (picture and name, with a menu for
  Account settings, Settings and the iCloud state) and at the top left of Browse on iPhone.
- iPhone tabs: Inbox · Today · Upcoming · Flipboard (Flipboard back on the right).
- Quick add: the pointing hand over highlighted words on the Mac; a phrase you switched off lights up again if
  you delete it and type it again; "!15mb" stays plain until the task has a time (a reminder picked from the
  chip waits on the chip). In the task editor, × and Esc ask Discard when you have typed something.
- Claude: on the Mac, Settings → Claude → Allow Claude lets Claude Desktop and Claude Code list, add, complete
  and edit your tasks while HITList is open (a small helper inside the app, reached only by HITList; no server).
  Choose what Claude sees: everything except tasks labelled @private, or only tasks labelled @claude. Copy for
  Claude on both platforms copies the allowed tasks as JSON. Setup guide at aeronyx.github.io/HITList/claude.
- Siri and Shortcuts: "Add a task in HITList" (spoken the way you type, "Buy milk tomorrow 5pm p1 #Home"),
  "What's on my HITList today", Complete Task, and Open Today / Inbox / Upcoming, from Siri, Shortcuts or the
  Action button.
- Holidays: completing a task throws snow dust at Christmas, fireworks on July 4th and New Year's, hearts,
  bats, leaves and clovers on their days, with a tiny seasonal glyph on the "+". Once in a long while, a sky
  whale swims by. Settings → Delight → Holiday touches and Rare surprises.
- One device, two Apple accounts: switching accounts clears the previous person's open card, Undo toast,
  reminders and badge, and sets their backups aside; nothing in iCloud is touched. Settings → iCloud and
  Account show the same sync line; the profile picture is decoded once; saving the same name twice writes
  nothing; duplicate tidying no longer collides with a download in progress; the sync log records the time
  to first screen.
- iPhone Duo: folded, the outer screen keeps the iPhone tabs; unfolded, the inner screen becomes the sidebar
  layout with the task editor in a column beside the list (no sheet) and Today showing the next days alongside.
  Folding or unfolding keeps you on the same list and keeps an open quick-add card.
- Mac and iPad: the quick-add panel's ×, Esc or a click on the dimmed backdrop, and a backdrop click around the
  editor, ask Discard before throwing away typing.
- Siri and Shortcuts "Open Today / Inbox / Upcoming" switch to that screen.
- Privacy policy: new sections on the Claude connection and on Siri.

## 0.5.0 — build 15, 2026-11-04

George's notes on build 14, in five sessions: an account and profile for friends on TestFlight, a privacy
policy, the iPhone tabs, a roomier editor, quick-add highlights, and a board for the Mac's Upcoming.

- Settings → Account: your name and picture, synced to all your devices through iCloud, and a plain answer
  to "which iCloud am I on?" (signed in, signed out, restricted), how to sign out, and how to delete your
  data. Delete profile removes only the name and picture. Your account is the Apple account the device uses
  for iCloud; there is no separate login.
- Privacy policy at aeronyx.github.io/HITList/privacy, linked from Settings → About. Short version: HITList
  collects nothing. Copy diagnostics says whether a profile exists and has synced (never its name).
- iPhone tabs: Inbox · Today · Flipboard · Upcoming. The magnifying glass at the top right opens Browse; on
  Browse the gear there opens Settings. Browse shows who you are at the top (or "Add your name") and ends
  with Completed and Settings. A screen's old "…" items (Review Inbox, Jump to today) are at the bottom of
  its view-options menu; on Flipboard, long-press the sound button for Add Switch…. Flipboard can be the
  start screen; a saved Browse start screen opens on Today.
- The task editor opens taller (sub-tasks and Confirm fit without scrolling), the Confirm pill is bigger
  (76 × 48 on iPhone, on both Add task and Edit task), and the "Created …" line moved to the bottom of the
  editor's "…" menu.
- iPhone: the keyboard has a plain return key and only the Confirm pill saves a task; Return in a title
  does nothing. Swiping the editor down after typing asks Discard; with nothing typed it just closes.
- Quick add: type a second date, time, priority, Group, repeat or reminder and the later one wins; tap it off
  and the earlier one comes back ("jan 6 zach fox in a month" → tap "in a month" → Jan 6). Same-coloured
  highlights next to each other read as one box ("tom 4"), and one tap turns the whole box back into text.
  A reminder picked before the task has a time lights up at once and counts as soon as a time is added.
- Mac (and iPad at full width): Upcoming is a board, an Overdue column then seven days side by side, each
  with its count and its own scrolling. ‹ › move a day, Today comes back, the month title jumps to any day.
  Drag a task to another day and it keeps its time and its repeat's time; Overdue's Reschedule moves every
  overdue task; each day's "+ Add task" adds on that day. iPhone keeps its list.
- The sync bolt stays grey, not red, for someone who has never signed in to iCloud; a task added from an
  Upcoming day with a time and a priority or label lands on that day, not today.
- Schema V4 adds `Profile` (additive; deployed to CloudKit Production before this build).

## 0.4.1 — build 14, 2026-11-03

George's notes on build 13, split across three sessions: sub-tasks, a real task editor, quick-add time
phrases, and the feel of taps, toasts and buttons.

- Sub-tasks: a checklist inside any task, one level deep. Add them from the quick-add "+" (Subtasks: one
  line each, Return for the next) or in the editor; rows show "2/5". Completing a task ticks its open
  sub-tasks and Undo reopens them; a repeating task's next occurrence starts with its checklist open.
  Sub-tasks never appear as rows of their own and are not counted in Group and label counts.
- The task editor is rebuilt: a title card with Group and date rows, value pills for Description,
  Priority, Reminder, Labels, Repeat, Deadline and Location, the Sub-tasks checklist, and one Confirm pill
  that saves everything typed and closes in one tap (Return in the title, ⌘Return on the Mac). × or Esc
  closes without saving unsaved typing.
- Quick add understands "in 10 minutes", "in two hours", "in half an hour", "in three days", "in a week",
  "in a month" (number words one to twelve); the phrase is one highlight, tap to keep it as text.
- Reminder shortcuts (`!15mb`, `!1h`, `!at`) only count, and only light up, when the task has a time; a
  bare "!" or "!0mb" stays in the title.
- Repeating tasks keep their exact time across the clock changes: the rule now stores the time of day
  and each occurrence is rebuilt from it.
- Tasks with the same priority and date stay in the order you added them.
- The suggestion pills under the quick-add title are gone.
- A quick-add card reopened after its Group was renamed adds to that Group; one whose Group was deleted
  adds to the Inbox.
- iPhone: one light tap when you press "+", confirm a task, or complete one (it used to tap twice on
  completion); the "+" is larger; task titles are a step smaller and a pixel tighter.
- The Undo toast is one big button, 48 pt tall and sized to its text; on the iPhone it sits beside the
  "+", on the Mac and iPad at the list's bottom-right corner; swipe it away to keep the completion.
- Mac: the window comes back at once after you close it and click the Dock icon (or ⌘Tab back); the
  toolbar "+" is smaller.

## 0.4.0 — build 13, 2026-11-02

The first beta for friends. Two review passes on the core, each change with a test that failed first, then
George's decisions on dates, times, taps and drafts.

- iCloud sync keeps a record. Settings → iCloud shows which CloudKit environment and build channel this
  copy syncs with ("Production · TestFlight build 13") and has a Sync log: every setup, import, export,
  push, account and network change with timings and full error details, filterable to errors, with Copy
  and Share. A watchdog records an error when a local change has no export within 5 seconds or a push no
  import within 5 seconds, and when a sync request has hung for a minute; after two minutes the bolt is
  struck through, "Sync paused: stuck", and Settings offers Relaunch on the Mac (a first import on a new
  device gets ten minutes). This is the state that held the Mac's changes back for 16 hours on Nov 1.
- Builds run from Xcode keep their own store, reminders and backups, apart from the TestFlight app's; a
  TestFlight or App Store build is never mistaken for one.
- Reminders no longer fire for tasks completed, deleted or moved from a list. Complete on a stale
  reminder no longer skips a repeating task's next occurrence; Snooze no longer undoes a move.
- Daily backups and Export JSON now carry reminder offsets, deadlines, locations and Flipboard state;
  old backups still restore.
- A store that cannot be opened no longer crashes the app at launch: it runs on an empty in-memory copy,
  leaves the file alone, says so, and offers Reset. A cache reset acts only on the store that asked for it.
- Typing a very long number in quick add ("!9999999999999999d", "every 99999999 days") no longer crashes.
- Sticky drafts keep the location and deadline picked from "+". Clearing a task's title in the popout
  puts the original back instead of saving a task with no title.
- About → Copy diagnostics and Check iCloud report the right CloudKit environment on every build.
- iPhone: the quick-add title has standard autocorrect and sentence capitals (it had autocorrect off).
- Dates and times read the way George does: monthly and yearly repeats keep their original day (Jan 31,
  Feb 28, Mar 31; Feb 29 in leap years), a repeating task typed after its time today starts at its next
  occurrence unless a date was typed, and times are 24-hour unless am or pm is typed ("tom 13" is
  tomorrow 13:00, "at 5" is 05:00). Picking "Every month" again keeps the day.
- Quick add: tap or click a highlighted token to switch it off and keep the words as plain text ("Call
  Tom" with no date); highlights are rounded like buttons. "Sticky" now means only that an open card
  with text survives app switches and a kill, reopening on launch in its own list; nothing is ever restored
  into a fresh card, and every way of closing clears it. Each build keeps its own open card.
- Completing is final until Undo: a second tap on a row still animating does nothing; undo is the toast
  or the Completed list. Every iPhone toast is drawn above the island on every screen size. A task
  popout closes by itself when the task is deleted on another device. The iPhone push handler finishes as
  soon as its import lands instead of waiting 25 seconds.
- Two review passes over the merged work: highlights never sit on the wrong words of a long title, the
  Mac's ⌘N over an open panel starts a fresh card, a pasted line break becomes a space, typing parses the
  title once per keystroke, and tapping away asks "Discard?" whenever the card holds anything.

## 0.3.5 — build 12, 2026-11-02

- iPhone lists look like the Mac's: rows flat on the background with hairline separators, headers over the
  checkboxes; no more inset cards on Today and the Inbox. The undo toast rises above the island instead of
  behind it.
- Completing a task is snappier: the checked row leaves after 380 ms instead of 600.
- Quick-add: the confirm pill is hollow and faded until there is a title, then fills with the accent.
  Tapping away from a card with text drops the keyboard and offers "Discard" in a bubble above it; any
  other tap brings the keyboard back. Drafts are sticky: the text survives closing the card, backgrounding
  and relaunching, until the task is added or discarded (`QuickAddDraftStore`).

## 0.3.4 — build 11, 2026-11-01

- Task rows measure like Todoist's (`ListMetrics`: 12 pt above the title, 10 below the second line, on
  both platforms; Compact rows trims it), every row the same height unless a long title wraps. Titles are
  capped at 500 characters; a description shows its first line under the title.
- Mac: one line under a section header, not two; the toolbar "+" is back to build 9's.
- Mac: the lists' sidebar only fades under the Settings sections (it stays built), so nothing stutters.
- iPhone: after adding a task the card holds still and fades while the keyboard drops; nothing rides the
  keyboard or re-lays out on the way.

## 0.3.3 — build 10, 2026-11-01

- Task rows are slimmer and all the same height, with the same air above and below (`ListMetrics`), on
  both platforms; Compact rows trims it further. The "P1"/"P2" badge is gone: the checkbox's colour is
  the priority.
- Section headers ("Overdue", "Nov 1, Sunday", "Priority 1") share one type size and one padding on
  every list, so the gap to the first row is the same under every header; the Inbox's priority headers
  are no longer caption-sized.
- Mac: Settings uses the window's sidebar for its sections, System Settings style, with Back on top; the
  sidebar column no longer collapses and reopens, which stuttered.
- The "+" oval is a little shorter on both platforms; the sync bolt sits nearer the two controls.

## 0.3.2 — build 9, 2026-11-01

- The sync bolt says its state by shape: filled when synced, hollow and breathing while syncing, struck
  through when it cannot sync or has not synced in a day. Each theme has its own pastel bolt colour
  (Slate's is a soft yellow); errors and sign-out turn it red.
- Mac: Settings is a full-window page with its own Back; the sidebar slides away while it shows. ⌘,, the
  gear, the "…" and the bolt all open it. Sections: General (with every keyboard shortcut), iCloud,
  Reminders, Completing tasks, Appearance (theme previews, Reduce effects, Compact rows), Data, About.
- Flipboard: a dashed switch-shaped tile with a big + adds a switch, in the grid itself.
- Inbox: one section per priority, Priority 1 first.
- Upcoming: the filter-lines menu holds Show overdue and Days shown (2 weeks, 1 month, 2 months); Jump to
  today moved into the "…".
- Mac: the quick-add title no longer draws a grey box behind the words; the Add task row reads at body size.
- iPhone: the theme swatches in Settings wrap to two rows (they overflowed the sheet in 0.3.1).

## 0.3.1 — build 8, 2026-11-01

- Sync status is a small bolt in the toolbar's empty space, soft accent when synced, breathing while it
  syncs, slashed grey offline, orange when it needs attention; the cloud icon in the pill is gone.
- Every screen has two controls beside it: Upcoming gets Jump to today, Browse gets New… (Group, label,
  filter), the Flipboard gets Add switch; the "…" on the Mac now holds Settings… and the version too.
- iPhone: the quick-add card is put away in one motion, fading as it rides the keyboard down.
- Four more themes: Nord, Tokyo Night, Mocha, Rosé.
- Release artifacts move to build.noindex so Spotlight stops offering stale copies of the app.

## 0.3.0 — build 7, 2026-11-01

- Mac: every chip in the quick-add and task popouts opens a card drawn inside the window (no more system
  popovers hanging past the edge): a HITList month calendar, a time row that reads "9am", "17:30" or
  "noon", presets (Today, Tomorrow, Next week, Weekend, No date), a reminder card with offsets and the
  fire time, and the Priority, Group, Labels, Repeat, Deadline and Location cards. Escape and a click
  outside close just the card; Tab moves into it; arrows and Return pick a day.
- Sync status is a small cloud icon at the left of every screen's toolbar (tap for Settings) instead of
  the Mac sidebar's footer line and the dot on the "…".
- Mac: the toolbar "Add task" is a proper prominent capsule; the card's confirm button is an outlined
  capsule so the two no longer look alike.
- iPhone: adding a task puts the quick-add card away (sliding back down behind the keyboard); lists show
  no "Add task" row, only the oval "+", and an empty list says "No tasks" (or "All clear for today",
  "Nothing due") in grey; every list leaves room for the floating island, so the last row (Browse →
  Settings) is reachable again.
- Task rows: the second line is always laid out, so rows with and without dates line up; the Group sits
  at its trailing end with its colour dot after the name.
- Mac: the toolbar "Add task" is the same accent oval as the iPhone's; the quick-add title no longer shows
  a grey text-view box when focused; Inbox review ("Review Inbox…") and the Flipboard's actions live in
  the "…" menu on every platform; the review sheet's Done buttons use the design system; the popout
  panel's shadow is flattened before animating.

## 0.2.0 — build 6, 2026-10-31

- Quick-add title one step larger than the list text (14 pt was too small): Inter 20 bold on iPhone.
- iPhone chrome: the tab bar is a floating island (a 64 pt capsule inset from the edges, lists scroll
  under it), the oval "+" sits above its right end, and every screen has the filter-lines view options
  and a "…" menu beside it with the screen's actions, Settings… and the version; a 6 pt sync dot on the
  "…" turns green when everything has synced and pulses once when a sync lands.
- Liquid Glass on iOS 26 / macOS 26: the island, the "+", the quick-add card, sheet headers, the segmented
  control's highlight and chip hover; the slate look stays on iOS 18 and under Reduce Transparency or the
  new Reduce effects setting.
- Four dark themes (Slate, Graphite, Midnight, Moss) in Settings → Appearance, switching live.
- Motion roles (quick, standard, enter, exit, emphasis, celebrate): nothing outside the completion check
  lasts over 250 ms; crisper check pop; completed rows slide away; the undo toast rises and falls.
- Settings: Start screen, Week starts on (Upcoming, "next week" in quick add and rescheduling), app icon
  badge, Confirm before deleting (one dialog for every delete path), Default reminder offset, Morning
  summary notification, notification authorization and test, Check iCloud round trip, Copy diagnostics,
  What's new, Version.
- Releases: `scripts/release.sh --version` with this changelog; preflight tests before any upload.

## 0.1.0 — builds 1–5, 2026-10-27 to 2026-10-31

- Build 1: first TestFlight build. SwiftUI multiplatform, SwiftData + CloudKit private database.
- Build 2: dedupe for seeded records, versioned schema, App Group store, sync resilience, reminders, CI.
- Build 3: filter language with autocomplete and editor, completion delight and sounds, Upcoming, Inbox
  polish, Task Flipboard.
- Build 4: design system (buttons, toggles, chips, fields, sheet chrome), task popouts, floating "+".
- Build 5: Inter typeface, schema V2 (reminder offsets, deadline, location, Flipboard charge), iPhone
  tabs (Inbox / Today / Upcoming / Browse), oval quick-add card with "+" options and `!15mb` reminders,
  Flipboard long-press menu, faint-green lamp and charging switches, aligned task rows.
