# Brief 76: pixel companions in quiet corners (session `companions`, effort max)

George, 2026-11-10, starting 0.9.1:

> As for real animations, I would love to start adding little animated pixelated figures to the app in small corners
> so they're not distracting, like a little pixelated vessel from Hollow Knight hanging out sitting with his feed
> dangling over the search bar or an Espeon curled up in the corner of the Browse menu, or Tooth and his bouquet of
> flowers (from the album Picnic at the Cemetery, low-res and upscale versions attached) each with idle animation
> loops/breathing animations as well as unique animations of them getting up/stretching/casting something randomly
> every few minutes or so, rare enough to feel cool when it happens. Only start with two or three animations if you
> start this now to ensure they're very high quality (which doesn't have to mean high framerate as they're pixelated
> creatures, it just means good art style and taste).

Read `dev/briefs/COMMON.md` (Round 17 block first), `dev/briefs/ROUND-17.md`, `44-holiday-delight.md` (the rare sky
whale and how Extras gates such things) and the design system README.

**The characters are ours.** The three George names belong to other people (a game studio, a game company, an
album's artist). HITList goes to testers through TestFlight and its repository is public, so the app ships none of
them and nothing that could be mistaken for them: no horned white mask over a dark cloak, no lilac cat with a
forked tail and a forehead gem, no pointed-eared mask with dot eyes over a striped jumper. Do not look for or work
from their artwork. What George is asking for is the feeling: a small quiet creature with a life of its own, sitting
where you would not expect one, that does something lovely when you happen to be looking. Give him that with
characters he has never seen. (Supervisor's decision, 2026-11-10; the roadmap's "a user's own companion" is how
someone could later put any sprite they like on their own device.)

## The companions (two; a third only if the first two are excellent)
1. **The one on the search field.** A small figure sitting on the top edge of the search field with its legs
   dangling over it: on the Mac's sidebar search (`SidebarSearchField`) and on Browse's field on iPhone. Idle: the
   legs swing a little, out of step; a slow breath; a blink now and then. Rare: it gets up, stretches, does one
   thing that is its own (a small light it carries flares and warms the pixels around it for a moment; or it casts
   a line of sparks that falls into the field; you choose, it should make someone smile and wonder if they saw it),
   then sits back down exactly where it was.
2. **The one asleep in a corner.** Curled up: at the foot of Browse on iPhone (beside or above its last row, clear
   of the tab island and the "+"), and at the foot of the Mac sidebar beside Settings. Idle: breathing, an ear or a
   tail tip that twitches rarely. Rare: it lifts its head, yawns, stands into a long stretch, turns once and curls
   back up the other way.
3. **(Only if earned) The one with flowers**, for a screen with nothing left to do: the Inbox's and Today's empty
   states. It stands holding a small bunch of flowers, swaying. Rare: it holds them up, and a petal or two drifts
   off. It must be its own character, not a version of the first two.

## Art direction
- **Design each character before animating it**: at least four different silhouettes per character on one sheet,
  shown at 1x and 8x. Pick the one that reads at a glance at 1x on the slate background, and say why. A good sprite
  is recognisable as a black silhouette. Avoid generic emoji animals; a character has one odd, memorable feature.
- **Small.** A sprite grid of at most 20 by 20 pixels, drawn at 2 points per pixel (about 32 to 40 points tall on
  screen), every pixel square and crisp at 1x, 2x and 3x displays (nearest neighbour, whole-point origins, never
  blurred or half-pixel shifted).
- **A few colours, from the theme.** Four to six per character, mapped from the palette in use (the text colour,
  the secondary text, the accent, one warm light), so the creatures belong to the slate window and change with the
  eight themes. One accent-coloured or warm detail per character at most. Check all eight palettes.
- **Movement with weight.** Idle loops at 4 to 6 frames a second, mostly single-pixel shifts with held frames
  (breathing is two or three frames, not a bounce). The rare flourish at 8 to 10 frames a second, 12 to 24 frames,
  with anticipation, an overshoot and a settle; it starts and ends on the idle's first frame, so nothing pops.
- **Rare.** Each companion's flourish at a random moment every 2 to 6 minutes while its screen is showing, never
  two companions at once, and never in the first 20 seconds on a screen. A tap or click on a companion may play it
  once (then not again for a while), provided the companion never takes a tap meant for the field or a row.
- **Quiet.** No sound. Hidden from VoiceOver. Nothing runs while its screen is not showing or the app is not
  active; no timer when nothing is on screen. Low Power Mode: idle only. Reduce Motion: a still pose (the idle's
  first frame). Extras gets one toggle, "Companions", on by default, beside "Rare surprises", on iPhone and the
  Mac's Settings page.

## How to build it
- Sprites as data in Swift: frames as rows of palette indices, checked at compile or test time (every frame of a
  character the same size, indices in range, each loop closes), drawn with one small view. A pure clock decides the
  frame from the time, the screen's presence and a seeded random schedule, so tests pin it (`CompanionClock`).
- An engine that takes a character as data, so a fourth is a file of frames and not new code.
- **Look at your work at every step.** Render each character's every frame to a contact sheet at 8x (a test that
  writes PNGs, or a small script), look at it, and redraw until it is good. Then record each animation running in
  the app at real size on the iPhone simulator and the Mac. Judge it at real size: what reads at 8x often
  disappears at 1x.

## Items (one commit each)
1. The engine, the clock and their tests. 2. The first companion's design sheet, then its frames, then its perch on
both platforms. 3. The second, the same way. 4. The Extras toggle and its words. 5. (If earned) the third.

## Ownership
New `HITList/Views/Companions/*` and `HITList/Support/Companions/*`, one overlay line each in
`HITList/Views/Search/SidebarSearchField.swift`, `HITList/Views/Tabs/BrowseView.swift` (the field and the foot) and
at the foot of `HITList/Views/SidebarView.swift` (`SidebarSettingsButton`'s row); for the third, one line in
`InboxZeroView.swift` and Today's empty state; `HITList/Views/Delight/DelightSettingsSection.swift` (the one toggle)
and the Mac Extras section if it does not reuse that view; a key in an `extension Preferences` of your own; new
`HITListTests/Companion*Tests.swift`.
Not yours: everything else in those four view files (brief 75 animates the app around you and must not find them
restructured); `Views/Popouts/*`, the design system (75); widgets (74); the list views (77); `HITTokens`;
`dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`.

## Done
For each companion: the silhouette sheet with your choice explained, the full frame sheet at 8x, the eight-theme
sheet, and recordings (frame strips) of the idle and the flourish at real size on the iPhone and the Mac, beside a
screenshot of the screen it lives on. Tell George in one line each what the character is and what it does. All
three suites green.
