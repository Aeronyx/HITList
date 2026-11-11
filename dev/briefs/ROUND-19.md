# Round 19: 0.9.3, companions with a life, time zones, a Settings you can find things in (2026-11-11)

0.9.2 (23) is released on both platforms. George's notes, verbatim (with a crop of a pixel creature attached):

> Good work; 0.9.2 released.
>
> WeatherKit has been enabled in App Services. The app should ask for the user's approximate location on first load
> in, and Weather should be on by default (if the user accepts). It should say it does this to automatically adjust
> to different timezones (and use weather effects), which should also be true of this app, and then we can use that
> for weather effects/weather-related animations for each creature while they're awake.
>
> As for your animation rarity settings, instead of making it so that only one small gesture plays every once in a
> while, have it so that a group of gestures (blink, a few leg swings, sometimes a little readjustment, etc.) play in
> quick succession, and then he can return to being idle/only blinking or swinging a foot now and then. In this way,
> each creature can have cute unique loops of animations but only every once in a while so that they stay fresh.
> This is almost the same way that game characters like Mario from Super Mario 64 work when left idle.
>
> Pip does kind of seem like a patterned wedge with a nose; maybe scrap or retry that one. Rosé is my favorite
> theme, so I definitely want it to have a good, adorable, silly lil' creature. Hush is awesome as you confirmed.
> Quill's butt should slope like it's hanging off the side of the "Add task" button when he's lying down, not
> floating above it.
>
> What happened to the creature in my attached screenshot? I loved him! Maybe he was just an interim design before
> Hush, but I still think he's adorable. He looks like a plushy. Perhaps redo his colors and change his design
> slightly and use him as the base for another fatter round character.
>
> Also, please clean up the settings menu a bit; it's become a jumbled mess and takes far too long to scroll
> through, plus many options are weirdly grouped and Appearance/Themes should be much closer to the top. Please
> also add a mini sprite of each creature on each theme! They don't have to be fully visible: some could be poking
> out from behind their theme cards/hues or some could be sitting on top of their theme colors, etc.
>
> I'm soon to use a Fable reset before bed, so please continue working freely overnight on build 0.9.3.

## The round

| Brief | Session | Effort | Owns, in short |
|---|---|---|---|
| 82 | `time-zones` | xhigh | A date with no time is the same calendar day on every device in every zone; everything catches up when the zone or the day changes |
| 83 | `location-weather` | high | Weather on by default, the location question once at first launch, true words for it, the place's time zone for the companion's clock |
| 84 | `companion-routines` | max | Idle routines (a burst of small moves, then quiet), weather that moves, Quill resting on the "+", nothing floating; Nod, Quill, Hush |
| 85 | `new-companions` | max | Rosé's companion again (Pip goes) and the plushy George loved, fatter and rounder, on a theme of its own; a second pass after 84 and 86 merge |
| 86 | `settings-tidy` | xhigh | Settings as one short screen and pages, Appearance second, every option in one home, the same on the Mac; a small companion on each theme's swatch |

An hour in, George added (verbatim):

> Tags pushed; thanks, I forgot. I'm heading to bed soon, but I have a ton of usage left for the week after the
> reset I just used, and we have under 14 hours make use of it, so I've put you in Max mode to both continue on the
> roadmap after Round 19 completes and to hopefully create all the other creatures before I wake, as you have plenty
> of time. Don't rush anything, but please finish what you can by morning (~8am ET or 95% usage limit).

So three more sessions draw the last three companions (`87-last-three-companions.md`), one each, and a ninth
session starts the roadmap's next item (`90-share-extension.md`):

| Brief | Session | Effort | Owns, in short |
|---|---|---|---|
| 87 | `graphite-companion` | max | Graphite's companion (seed: tall and thin, half-sketched) |
| 88 | `moss-companion` | max | Moss's companion (seed: low and wide, carrying something that grows) |
| 89 | `tokyo-companion` | max | Tokyo Night's companion (seed: a small thing with a light of its own) |
| 90 | `share-extension` | xhigh | The roadmap's next item: "Add to HITList" from the share sheet, through an outbox the app drains; ships with 0.9.3 only if it is merged and its packaging proven by morning |

Brief 84's engine commit (routines as data) was fast-forwarded onto master at 02:10 so these three draw routines
in one pass, and brief 85 (Posy for Rosé, Mallow for Mocha) goes straight to its second pass. The Mac was
saturated by then (five builds, swap full), so the three draw with brief 85's scripts and build once, late. The
next roadmap items wait for the round's merge and a freer machine.

At 03:05 George asked for the weather to show on the creature (`91-weather-on-the-creature.md`: drips, a
shake-off, snow that piles up, a hot day; nothing in the air), and at 03:35, going to bed (verbatim):

> Thanks, the companions seem almost complete and we still have so much time and usage left! I'm heading to bed
> for real now, but after you finish reviewing Round 19 and the testing suites, please continue reviewing,
> improving, and hardening HITList until ~8am ET, 85% of my usage limit, or you have truly completed everything
> worth working on without my feedback.

So three review-and-hardening sessions run beside the round:

| Brief | Session | Effort | Owns, in short |
|---|---|---|---|
| 92 | `day-anchor-review` | max | A second pair of eyes on brief 82's rewrite of stored dates: try to break it before it runs on real data |
| 93 | `qa-sweep` | xhigh | Every screen on iPhone, iPad, the Duo and the Mac looked at as George would; plain defects fixed, matters of taste listed |
| 94 | `accessibility` | xhigh | The system's accessibility audit on every screen, VoiceOver wording, the keyboard on the Mac, hit targets (the Mac's sync bolt takes clicks on a 4 pt strip) |

## The supervisor's decisions (George: "work freely")
- **The creature in George's crop** is an unshipped sketch from round 18's companion session (Nord's inks, Hush's
  face). Found nowhere in the shipped frames; transcribed into brief 85 from the crop. It becomes the fifth
  companion, on a theme the session chooses.
- **What "adjust to different timezones" means here.** The device already knows its zone without a permission, so
  the app's tasks, reminders and lists follow the device (brief 82), and the real fault to fix is that a date with
  no time is stored as a local midnight and shows a day early after a flight west. The location's own part is
  small and safe: the place's time zone drives the companion's night and day. It does not drive due times: a
  wrong guess at a border, or a stale Wi-Fi position, would silently make every time in the app wrong.
- **The location question's words** say exactly that: "HITList uses your approximate location to keep your
  companion on local time and dressed for the weather where you are. It is never stored or shared." iOS shows the
  sentence to every user and App Review holds it to what the app does.
- **The stored form of a day** (brief 82): 10:00 UTC on that day, which older builds and every existing comparison
  read as the same day from Honolulu to New Zealand; one switch turns the rewriting off; a backup is taken first.
- **Routine numbers**: a flicker (a blink, one foot swing) every 40 to 110 seconds; a routine of 3 to 7 seconds
  after 5 to 12 minutes of showing time, kept across launches; the flourish as rare as before; a tap plays a
  routine when the flourish is not due.
- **Weather by default** means a switch nobody touched is on; the question comes once, shortly after the first
  screen shows; a Debug build never asks by itself, so no session meets a system dialog.
- **Themes without a companion of their own show no sprite on their swatch** (no four Nods in a row).
- `CompanionSkySource.timeZone` (the supervisor's seam) was added first so briefs 83 and 84 compile apart, and
  `WeatherSettingsText` moved to `Services/Weather/` so briefs 83 and 86 do not share a file.

## After the merge (supervisor)
The second pass for brief 85 (routines, weather, swatch entries) once 84 and 86 are in. The three suites and the
UI suite on the merged tree; a Release archive and export of both platforms (no upload), by the script's checks;
the screenshot pass (every Settings page on both platforms, the five companions in both places, a routine
recorded, two zones side by side); `## 0.9.3`, `Entry(version: "0.9.3")`, the pin; the hand-over with
`scripts/release.sh --version 0.9.3 --quick`.
