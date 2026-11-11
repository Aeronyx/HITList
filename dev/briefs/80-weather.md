# Brief 80: the sky for the companions (session `weather`, effort high)

George, 2026-11-11, on 0.9.1:

> Running with this same idea, each little animated creatures should also have sleeping animations/states for
> nighttime as well as ones for different weather if it's not too difficult to add a weather connector.

Read `dev/briefs/COMMON.md` (Round 18 block first), `dev/briefs/ROUND-18.md`, `77-calendar-events.md` (the same
shape of feature: a system service the person opts into, read-only, on the device; copy its manners) and
`HITList/Support/Companions/CompanionSkySource.swift` with core's `CompanionSky`.

The companions (brief 79, running beside you) draw a small variation in rain and in snow. Your whole job is to tell
them, honestly and cheaply, what the sky is doing where the person is: you call `CompanionSkySource.shared.set(_:)`
and `.clear()`, and nothing else in the app reads the weather. No forecast, no temperature, no weather on screen.

## The rules
- **Off by default, asked once.** Extras gets "Weather" under Companions (iPhone and the Mac's Settings page):
  "Your companion dresses for the weather where you are." Switching it on asks for location while the app is in use,
  at reduced accuracy (a town is plenty). Refused or restricted: the row says so and offers the system's settings,
  as Calendar events does. Off, never asked, refused: the sky is `unknown` and the app makes no weather or location
  call at all. The row is disabled while Companions is off.
- **Apple's weather, on Apple's terms.** Use WeatherKit (the `WeatherKit` capability on the app, both platforms).
  Show Apple's required attribution where the setting is (the Apple Weather mark and the link to its data sources,
  as WeatherKit's attribution API gives them), in the design system's quiet footer style. Nothing leaves the device
  except the request Apple's framework makes; the location is never stored, synced, logged or sent anywhere else.
- **Cheap.** One reduced-accuracy location fix and one current-conditions request when the app comes to the front
  and the last observation is older than an hour; never in the background, never on a timer while hidden. Keep the
  last sky in memory only. An observation older than three hours is `unknown`.
- **Six skies.** Map WeatherKit's conditions to `CompanionSky` with a pure, tested table in core: thunder and
  severe weather are `storm`; drizzle, rain, showers and freezing rain are `rain`; snow, sleet, flurries and
  blizzards are `snow`; clear and mostly clear are `clear`; everything else is `clouds`.
- **Fail quiet.** No capability yet, no network, a WeatherKit error, a location that never arrives: the sky is
  `unknown`, one line in the unified log (category `weather`), no alert, no retry storm (back off to the next time
  the app comes forward).

## Items (one commit each, failing test first where there is logic)
1. **The capability and the strings**: `com.apple.developer.weatherkit` in the iOS entitlements (`project.yml`) and
   `HITList/HITList-macOS.entitlements`; the Mac sandbox's location entitlement
   (`com.apple.security.personal-information.location`); `NSLocationWhenInUseUsageDescription` (both platforms, in
   plain words: "HITList uses your approximate location only to ask Apple Weather whether it is raining or snowing,
   so your companion can dress for it. It is never stored or shared."). Automatic signing should switch WeatherKit on
   for the App ID. **Prove a Release archive and export of both platforms** as brief 74 did (no upload, never
   `scripts/release.sh`), and paste the exported app's entitlements. If signing cannot provision WeatherKit by
   itself, stop that path, say exactly what George must tick in the developer portal, and leave the build signing
   as it did before (the feature simply stays `unknown` until then): do not switch to another weather provider.
2. **The table** in core (`CompanionSky` mapping) and its tests.
3. **The service** (`HITList/Services/Weather/*`): location and weather behind protocols so tests use fakes; the
   one-hour and three-hour rules, the triggers, the quiet failures, tested with a fake clock.
4. **The setting**: the Extras rows, the permission states, the attribution. While you are in that file, replace
   the Companions footer sentence (it names two creatures and places that brief 79 is changing) with: "Companions:
   a small creature keeps you company, one for each theme, by the search field on the Mac and by the + on iPhone.
   Mostly it sits still. Reduce Motion keeps it still."
5. **The privacy page** (`docs/`): one short section in the page's voice.
6. **Debug**: `-seedDemoSky rain` (any `CompanionSky`) makes the service report that sky without location or
   network, with the setting shown on, for screenshots and UI tests. (`-companionSky` in the source is the
   companions' own override; leave it.)

## Ownership
New `HITList/Services/Weather/*`, new core file for the table (not `CompanionSky.swift`, which is the supervisor's:
add an extension in a file of your own), `HITList/Views/Delight/DelightSettingsSection.swift` and the Mac Extras
section if it does not reuse it, `project.yml` (the iOS entitlement and the usage string; brief 81 edits the same
file elsewhere), `HITList/HITList-macOS.entitlements` (two keys), `docs/` privacy page, an `extension Preferences`
of your own, new `HITListTests/Weather*Tests.swift`, a UI test file of your own.
Not yours: `HITList/Support/Companions/*` and `Views/Companions/*` (79: you call `CompanionSkySource` and stop
there), `HITListWidgets/*` and its entitlements (81; the widgets get no weather), `Services/Sync/*`, the models,
`dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`. Test the location prompt on your own simulator only; never
answer or script a system dialog on the Mac, and never run `tccutil` (COMMON).

## Done
Screenshots, iPhone and Mac: Extras with Weather off, on (with the attribution) and refused; the permission prompt
on the simulator. The archive and export proof with the entitlements, or the exact portal step George must take.
What happens with the capability missing (the log line). All three suites green.
