# HITList changelog

One section per release, newest first. A release is a version: `scripts/release.sh --version X.Y.Z` refuses to run
until the version has a section here, then stamps the heading with the build number and date. Versions go up by 0.0.1
per release. A second build of one version (0.9.0 had builds 20 and 21) is released with `scripts/release.sh --quick`
and needs a section headed `## X.Y.Z (N)`, which the script stamps with the date.

## 0.9.9

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
  "!1hb", "!at") left in a title wakes once the task has a time: opening the task shows it lit, the reminder pill
  shows what Confirm will save, and Confirm sets it and takes it out of the title. Closing with × changes nothing
  and asks nothing.
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
