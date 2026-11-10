# Round 17: 0.9.1, widgets and everything that moves (2026-11-10)

0.9.0 (21) is released on both platforms. George's notes, verbatim:

> Thanks, build released. We should still bump numbers for versions by 0.0.1 just for our own visual clarity as that
> shouldn't trigger a review, but it's okay that we doubled up on 0.9.0 with Build 20 and 21 this time around.
>
> Let's go ahead and get started with 0.9.1 already, with a primary focus on Widgets and Animations, along with any
> other crucial steps from the roadmap that I've ignored for a long while (now's a good time to clean up the roadmap
> too).
>
> Widgets: For Mac and iOS, we should have simple Today and Upcoming widgets (along with any other obvious additions)
> which showcase a few tasks and a little calendar respectively. I'm sure we'll iterate on these after seeing them and
> using them, but we need to have them first to give feedback on them. Please implement Widgets!
>
> Animations: I want you to perform some checks on certain screen transitions/add certain animations where they
> would be best, such as better popouts, small UI interactions, etc. By "animations" in this instance I mostly mean
> anything that moves/should move within the app, as many things are clean and smooth right now but certainly not
> everything. As for real animations, I would love to start adding little animated pixelated figures to the app in
> small corners so they're not distracting, like a little pixelated vessel from Hollow Knight hanging out sitting
> with his feed dangling over the search bar or an Espeon curled up in the corner of the Browse menu, or Tooth and
> his bouquet of flowers (from the album Picnic at the Cemetery, low-res and upscale versions attached) each with idle
> animation loops/breathing animations as well as unique animations of them getting up/stretching/casting something
> randomly every few minutes or so, rare enough to feel cool when it happens. Only start with two or three animations
> if you start this now to ensure they're very high quality (which doesn't have to mean high framerate as they're
> pixelated creatures, it just means good art style and taste).
>
> Once again, work freely and professionally with an eye for aesthetics.

## The round

| Brief | Session | Effort | Owns, in short |
|---|---|---|---|
| 74 | `widgets` | xhigh | Today, Upcoming and Flipboard widgets (and Lock Screen pieces if earned): the first extension target, the snapshot the app writes for it, deep links |
| 75 | `motion-polish` | xhigh | An audit of every transition and small interaction, then repairs: cards, pickers, tabs, rows, controls, the Mac sidebar, the Flipboard |
| 76 | `companions` | max | Two (perhaps three) original pixel creatures with idle loops and a rare flourish, the engine behind them, the Extras toggle |
| 77 | `calendar-events` | high | The roadmap's item 8: read-only calendar events in Today and Upcoming, off by default |

## The supervisor's decisions (George: "work freely")
- **Versions.** 0.9.1 next, then 0.0.1 at a time. A patch bump does send the public-link group's copy through Beta
  App Review; the friends are internal testers and get it at once, so nobody waits.
- **The companions are original characters.** The three George names belong to a game studio, a game company and
  an album's artist. The app is distributed and the repository is public, so none of them ships and the session
  does not work from their artwork (George's two attached pictures stay out of the repository and out of the
  brief). The session designs its own creatures for the same places and the same feeling. A later item, "a user's
  own companion" (the roadmap's Next 7), lets anyone load a sprite sheet of their own on their own device.
- **The roadmap item George "ignored for a long while"** is item 8's calendar overlay, the only one of the original
  eight never built. The share extension, also promised by the App Group move, is first in Next.
- **Widgets read a snapshot**, never the store; no completing from a widget in the first pass.
- **`dev/ROADMAP.md`** is rewritten (259 lines of per-brief rows to 97: now, next, parked, shipped) and sessions no
  longer edit it.

## After the merge (supervisor)
- Run the three suites and the UI suite on the merged tree.
- Archive and export both platforms with the widget extension, without uploading, before handing George the
  release command; tell George which App IDs automatic signing registered.
- The screenshot pass on both platforms, the widgets' renders, the companions at real size, a strip of each repaired
  transition; `## 0.9.1` in `CHANGELOG.md`, `Entry(version: "0.9.1")`, the `SettingsTests` pin.
