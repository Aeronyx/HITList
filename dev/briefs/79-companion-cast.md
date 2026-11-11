# Brief 79: one companion per theme, mostly still, asleep at night (session `companion-cast`, effort max)

George, 2026-11-11, on 0.9.1:

> The little guys you designed are awesome! I love the guy who hangs out over the search bar. Here's what we need to do:
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

Read `dev/briefs/COMMON.md` (Round 18 block first), `dev/briefs/ROUND-18.md`, `76-companions.md` (the art direction
and "The characters are ours" still bind you: original characters only, never anyone else's, and do not look for or
work from other people's character art), and the engine you are changing: `HITList/Support/Companions/*`,
`HITList/Views/Companions/*`, the characters `Nod.swift` and `Quill.swift`.

## The rules
1. **Mostly still.** At rest a companion is a still picture. Nothing loops. Now and then it does one small thing
   and is still again: a blink, one swing of a leg, an ear or tail tip, a glance. One small gesture every 45 to 120
   seconds, at random, each under a second, never the same one three times running. No breathing.
2. **The flourish is rare.** While its screen is showing and the app is in front, the flourish comes about once
   in three hours on average, at random, never within 45 minutes of the last one. The time of the last flourish is
   kept on the device across launches (the app group's defaults), so quitting and reopening never brings it sooner.
   Someone who uses the app for an hour a day should see it perhaps twice a week.
3. **A tap or click may play it**, if no flourish (tapped or not) has played in the last 20 minutes on this device.
   Sooner than that, a tap gets a small acknowledgement only (it looks up, or blinks) and at most once every ten
   seconds. The tap must never take a tap meant for the search field or the "+".
4. **One companion at a time, by theme.** Each colour theme has its own companion, and only that one shows. This
   round: Slate has Nod (George's favourite stays the default), Midnight has Quill, and your two new ones belong to
   two of the other six themes (Graphite, Moss, Nord, Tokyo Night, Mocha, Rosé): choose the two whose palette and
   name your designs answer best, and say why. A theme whose companion is not drawn yet has Nod. Changing the theme
   changes the companion at once. There are no points, unlocks or collecting of any kind, now or later.
5. **One place per platform, the same for every companion.** The Mac: on the search field, its right-hand middle,
   as Nod sits today. iPhone and iPad: on or about the top right of the "+" (the floating add button), on every
   screen that shows it; it goes away with the "+" when a card opens and comes back with it. Nowhere else this
   round: remove the perches on Browse's search field, at Browse's foot and beside the Mac's Settings row. Every
   character needs a pose that sits well in both places (Quill was drawn lying on a card's edge: give it one for the
   field and one for the "+").
6. **Asleep at night.** From 22:00 to 07:00 by the device's clock a companion is asleep: its own sleeping pose in
   the same place, still, with at most a rare stir (once in several minutes). No flourish while asleep. A tap wakes
   it for a moment (one eye, a look), then it settles again. The change from awake to asleep and back happens while
   nobody is looking: no transition is owed.
7. **Dressed for the weather.** `CompanionSkySource.shared.sky` (the supervisor's file; brief 80 feeds it, you only
   read it) says `unknown`, `clear`, `clouds`, `rain`, `snow` or `storm`. For rain and storm, and for snow, each
   companion has a still variation of its resting pose that suits the character (something held overhead, a hood,
   a dusting on its hat or back: one prop or change, a few pixels). `unknown`, `clear` and `clouds` are the ordinary
   pose. Asleep wins over weather unless you can make a sleeping-in-the-rain pose you are proud of. Debug:
   `-companionSky rain` already forces the sky.
8. **Quiet, as before**: no sound, hidden from VoiceOver, nothing running while its screen is hidden or the app is
   not in front, one timer at most and none while nothing is scheduled within the hour (schedule the next event,
   do not tick). Reduce Motion: the still pose for the hour and the weather, no gestures. Low Power Mode and Reduce
   Effects: gestures, no flourish. Extras → Companions still turns them all off.

## The two new companions
"Familiar but not quite real": a creature you feel you have seen and could not name. As good as Nod and Quill, in
the same hand: at most 20 by 20 pixels at 2 points per pixel, four to six inks from the theme's palette, one warm or
accent detail, readable as a silhouette, one odd memorable feature. Design each for its theme (a mossy thing for
Moss, something that keeps warm for Nord, and so on, are obvious first thoughts: look for a second thought). Six
silhouettes each on a sheet, your pick starred with the reason. Then, for each of the four companions: the resting
pose in both places, three small gestures, the flourish (Nod's and Quill's stay as they are), asleep, a stir, rain,
snow.

## Items (one commit each)
1. **The engine**: gestures instead of loops, the rare schedule with its kept time, the tap rules, the hour, the
   sky, theme to companion; pure and tested (`CompanionClock`, `CompanionSchedule`, `CompanionDirector`): the
   expected gaps over a simulated month, the kept time across a relaunch, night's edges, a theme change, and that
   nothing is scheduled within the hour when nothing is due. Debug arguments to force the hour (`-companionHour 23`),
   play a gesture or the flourish now, and pick a companion whatever the theme.
2. **Places**: the Mac's field for every companion; the "+" on iPhone and iPad; the three old perches removed.
3. **Nod**: its pose on the "+", asleep, stir, rain, snow, its three gestures cut from today's idle.
4. **Quill**: its poses for the field and the "+", asleep (it already sleeps well: make night different from its
   day pose), stir, rain, snow, gestures.
5. **The third companion**, 6. **the fourth**: design sheet, then frames, then both places.

## Ownership
`HITList/Views/Companions/*`, `HITList/Support/Companions/*` except `CompanionSkySource.swift` (the supervisor's:
read it, do not edit it), the perch lines in `HITList/Views/Search/SidebarSearchField.swift`,
`HITList/Views/Tabs/BrowseView.swift` (remove yours) and `HITList/Views/SidebarView.swift` (remove yours and the
row-width constant that served it), one perch line where the iPhone and iPad "+" is drawn
(`HITList/Views/Tabs/MobileShell.swift` or `HITList/Views/Popouts/QuickAddEntry.swift`: that one line and nothing
else in those files), an `extension Preferences` of your own for the kept times, `HITListTests/Companion*Tests.swift`
(not `CompanionSkySourceTests.swift`), `HITListUITests/CompanionsUITests.swift`.
Not yours: `HITList/Views/Delight/DelightSettingsSection.swift` and anything under `HITList/Services/Weather/`
(brief 80 writes the Extras rows and their words, the Companions sentence included); `HITListWidgets/*`,
`Services/Widgets/*`, `Services/Intents/*`, `Services/Sync/*` (81); `Theme.swift` (read `ThemeStore`, do not change
palettes); core; `dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`.

## Done
For each of the four: the silhouette sheet (new ones), every frame at 8x and at real size, all eight palettes, and
the companion in both places at real size, by day, asleep, in rain and in snow, iPhone and Mac. A timeline from the
tests of what one companion does over a simulated eight-hour day (gestures, flourishes, night). Which theme each new
companion belongs to and why, and one line each on what it is. All three suites green and your UI tests on a fresh
simulator.
