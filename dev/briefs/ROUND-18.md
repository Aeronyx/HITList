# Round 18: 0.9.2, a cast of companions and widgets you can trust (2026-11-11)

0.9.1 (22) is released on both platforms. George's notes, verbatim:

> Good work. 0.9.1 released. GitHub Actions failed, but that's okay.
>
> The little guys you designed are awesome! I love the guy who hangs out over the search bar. Here's what we need to
> do:
>
> The animated creatures are great, but they need to occur less frequently. I was wrong to call them "breathing
> animations". Even the blinking/leg swinging/other idle animations should only happen every so often, not constantly,
> and then the special/unique animations should be quite rare, such that you might not even catch him doing it one
> day. This is an app that users will live inside for many hours, so any animations that occur constantly will become
> annoying and mundane over time. (A direct tap/click being able to trigger their unique animation every once in a
> while though is also still a good idea; just ensure it has a long global refresh as well.)
>
> Running with this same idea, each little animated creatures should also have sleeping animations/states for
> nighttime as well as ones for different weather if it's not too difficult to add a weather connector.
>
> Two creatures should never be visible on the same page; when I said to hide the second creature in the corner of
> the settings/Browse page, I meany fully within that subpage, not so that both were visible at the same time on Mac.
> No worries, though, as I had an idea about what I want to do with the creatures; make it so that there's one for
> each different color theme! They should all hang out by default in the same place in each app: for Mac they should
> interact with the middle-right side of the Search bar (as the dangly leg creature does now), and for iOS they
> should hang out on top-right of/around the "Add task" button. They can appear in other nested menus depending on
> the theme, but all should appear in both of those areas by default. We'll never have a point system or unlock system
> of any kind; these creatures are just for aesthetics and cute vibes. Please continue with creating two more little
> creatures this turn that are as good as the first two (as well as adding sleeping animations and such to the first
> two), and keep with the theme of having them be familiar-but-not-quite-real critters. We'll finish off the rest of
> the eight themes in future turns.
>
> As for Widgets, they need to have robust cloud sync and should definitely allow for task completion within the
> widget. It can be slow (Todoist's widgets are pretty slow to update; when I check off a task, it takes 5+ seconds to
> register/disappear/get repalced with a new task, but it does at least show that it's checked), so speed isn't
> important, but it should be reliable. In general, Todoist seems to take the stance that a checked task doesn't
> complete/disappear until it properly syncs to iCloud, which is a very good approach; it properly prioritizes data
> resilience over user experience. We should adopt that mentality as well.
>
> Once again, please work freely, and prepare build 0.9.2 when ready.

## The round

| Brief | Session | Effort | Owns, in short |
|---|---|---|---|
| 79 | `companion-cast` | max | One companion per theme in one place per platform, still by default with rare gestures and a rarer flourish, asleep at night, a variation for rain and snow, two new critters |
| 80 | `weather` | high | The sky for the companions: WeatherKit behind an Extras switch, off by default, approximate location, on the device |
| 81 | `widget-completion` | xhigh | Completing a task and flipping a switch from a widget: a durable outbox, the app does the work, the row stays checked until iCloud has it; widgets that refresh while the app is closed |

## The supervisor's decisions (George: "work freely")
- **The CI failure was ours**, not the runner's: its older Swift could not type-check one expression in
  `CompanionSprite.swift`. Fixed before the round's worktrees were cut.
- **Numbers for "less frequently".** One small gesture every 45 to 120 seconds; the flourish about once in three
  hours of the screen showing, never within 45 minutes of the last, the time kept across launches; a tap plays it
  only if none has played for 20 minutes. Night is 22:00 to 07:00 by the device's clock.
- **Themes.** Slate keeps Nod, Midnight gets Quill, the session picks which two of the other six its new critters
  belong to; a theme without its own yet shows Nod.
- **Places.** The Mac: the search field. iPhone and iPad: the "+". The Browse and sidebar-foot perches go.
- **Weather is WeatherKit**, opt-in, with Apple's attribution in Extras. If automatic signing cannot switch the
  capability on, George ticks it in the developer portal and the feature stays `unknown` meanwhile: no other weather
  provider.
- **"Until it properly syncs" applies to the widgets**, where George said it. The app's own lists keep their
  completion and Undo toast as they are (the local store is the truth there and Undo is the app's safety): to be
  asked, not assumed.
- `CompanionSky` (core) and `CompanionSkySource` (app) were committed by the supervisor first, so briefs 79 and 80
  compile apart and meet in one place.

## After the merge (supervisor)
The three suites and the UI suite on the merged tree; a Release archive and export of both platforms with the new
entitlements (no upload), by the script's checks; the screenshot pass (the companion by day, asleep, in rain and
snow, on four themes, both platforms; the widget's tap to checked to gone); `## 0.9.2`, `Entry(version: "0.9.2")`,
the pin; the hand-over with `scripts/release.sh --version 0.9.2 --quick`.
