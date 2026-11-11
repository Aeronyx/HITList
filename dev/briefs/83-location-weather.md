# Brief 83: ask where you are once, weather on by default (session `location-weather`, effort high)

George, 2026-11-11, on 0.9.2:

> WeatherKit has been enabled in App Services. The app should ask for the user's approximate location on first load
> in, and Weather should be on by default (if the user accepts). It should say it does this to automatically adjust
> to different timezones (and use weather effects), which should also be true of this app, and then we can use that
> for weather effects/weather-related animations for each creature while they're awake.

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/briefs/ROUND-19.md`, `80-weather.md` (what you are
changing and its manners, all of which still hold except "off by default, asked once from the switch"),
`HITList/Services/Weather/*`, `HITList/Support/Companions/CompanionSkySource.swift` (the supervisor's seam: you
call `set(_:)`, `setTimeZone(_:)` and `clear()` and never edit it).

WeatherKit is live for the App ID now, so real answers arrive. Brief 82 makes tasks and reminders follow the
device's time zone (no permission needed); brief 84 animates the weather on the companions. You own the question,
the default, the words and what the location feeds.

## The rules
1. **On by default.** Extras → Weather is on for everyone who has never touched the switch: a key that was never
   written means on. Someone who switched it off keeps it off. Companions off still means no weather and no
   question.
2. **Asked once, at the first launch.** The system's location question (approximate: `NSLocationDefaultAccuracyReduced`
   stays) appears once, shortly after the first screen is showing and the app is in front: not during launch, not
   over a card, sheet or tip, never in the background. People updating from 0.9.2 who were never asked are asked
   at their first launch of this build. Allowed: the weather starts. Refused: nothing changes on screen, the Extras
   row says so with the way to the system's settings (as today), and HITList never asks again by itself.
3. **Never in a test, a screenshot or a session's run.** A Debug build does not ask by itself: it asks only with
   `-askLocationAtLaunch YES` (use it on your own simulator). The XCTest host, the UI tests, `-seedDemoData`,
   `-seedDemoSky` and `-seedDemoWeatherAccess` runs never ask. The decision is one pure, tested function (build
   kind, arguments, Companions, the switch, whether it was asked, the permission's state, what is on screen).
   COMMON's rule stands: no session answers or scripts a system dialog on the Mac.
4. **The words are true.** The app's purpose string (`NSLocationWhenInUseUsageDescription`, both platforms) becomes:
   "HITList uses your approximate location to keep your companion on local time and dressed for the weather where
   you are. It is never stored or shared." For it to be true, the location also feeds the companion's clock: with
   each fix, work out the time zone of that place and call `CompanionSkySource.shared.setTimeZone(_:)` (brief 84's
   clock reads `zone` for night and day). Find the cheapest honest way in the 27.2 SDK (WeatherKit's own answer if
   it carries the zone; otherwise one reverse geocode per fix, by Apple's geocoder, the placemark's `timeZone`);
   in memory only, nil when unknown, cleared with the sky. Nothing else in the app uses this zone: tasks,
   reminders and lists follow the device (brief 82), because a wrong guess there would be a wrong due time.
5. **Cheap and quiet, as before**: one reduced-accuracy fix and one request when the app comes forward and the
   last observation is older than an hour; never in the background; the location never stored, logged or sent
   anywhere but to Apple's weather and geocoder; failures are one log line (category `weather`) and `unknown`.
6. **Real answers.** With the capability live, check a real request end to end on your simulator (set a simulated
   location with `xcrun simctl location <udid> set <lat>,<lon>`; try a rainy and a snowy place if the world offers
   one tonight) and paste the log line. If Apple's server still refuses, paste what it says and stop there: do not
   switch provider.

## Items (one commit each, failing test first where there is logic)
1. **The default**: never-written means on; the stored "asked" flag; a migration test for someone who had it on,
   off, or untouched in 0.9.2.
2. **The question at first launch**: the pure decision, where it is called from (after the first scene is active
   and settled), the Debug rule, the tests.
3. **The zone of the place** into `CompanionSkySource`, with fakes and tests; cleared when weather goes off, is
   refused or goes stale.
4. **The words**: the purpose string in `project.yml` (and wherever the Mac's is), `WeatherSettingsText`
   (`HITList/Services/Weather/WeatherSettingsText.swift`: "Your companion dresses for the weather and keeps the
   hours of where you are." and the refused and restricted lines), the privacy page in `docs/` (location is asked
   at first launch now; what it is used for; the geocoder if you use it).
5. **Seen working** on your simulator: first launch → the question → Allow → a real sky in the log and on the
   companion; first launch → Don't Allow → the Extras row; the second launch asks nothing.

## Ownership
`HITList/Services/Weather/*` (the service, sources, `WeatherSettingsText.swift`), the core sky table if a
condition needs moving, the lines of `HITList/HITListApp.swift` that start the weather (the first-launch call
goes with them), `project.yml` (the location purpose string only; run `xcodegen generate`),
`HITList/HITList-macOS.entitlements` only if the geocoder needs a key, `docs/` privacy page,
`HITListTests/Weather*Tests.swift`, a UI test file of your own if you add one.
Not yours: `HITList/Views/Delight/DelightSettingsSection.swift` and every other Settings view (brief 86 is
rebuilding Settings: the Weather row stays wired to `CompanionWeather.shared` as it is, and 86 only moves it; if
the row needs a change you cannot make from the service, say so in the report), `CompanionSkySource.swift` and
`CompanionSky.swift` (the supervisor's), the rest of `Support/Companions/*` and `Views/Companions/*` (84, 85),
core's date files (82), `HITListWidgets/*`, the models, `dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`.

## Done
The simulator's question with the new words (screenshot), the Extras row allowed and refused, the log of a real
request, the zone reaching the source (a test and a log line). The table of who gets asked when (new install,
update never asked, update with weather on, update refused, Companions off, Debug). A Release archive and export of
both platforms still pass with the entitlements unchanged (no upload, never `scripts/release.sh`). All three
suites green.
