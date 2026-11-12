# Round 24: 0.9.8, rain that is rain, a ghost you can see through, and Switchboards in rows (2026-11-12, midday)

0.9.7 was prepared (round 23) and not released. George's message at about 11:45 Eastern, verbatim:

> Good work, we're getting closer to the final product, but I didn't release 0.9.7 as there's still a bit more work
> to be done. Here are my latest opinions on each of the creatures:
> For all creatures: Their rain interactions don't make much visual sense, as the rain is both not blue enough to be
> clear that it's rain and also many of the characters don't even get rain on them to begin with. During rain, they
> should have little droplets bead off of them every once in a while, and have some droplets stick around or tiny
> puddles pool around their feet so it's clearer why they're cowering/hiding.
>
> * Glim: done.
> * Gargle: much better. Can be largely left alone for now, but perhaps not perfect. He looks barely recognizable in
>   deep snow, though.
> * Phase: almost there; os it possible to make him slightly transparent or at least more ethereal-textured? Messing
>   with his default opacity as well as having some of his animations involve shifting his opacity around would be a
>   great addition to his character. He also looks just slightly too generic; if you can, please make tiny
>   adjustments to his body (not his face!) to make him more unique or at least more detailed (such as better
>   shading on his waves/around him in general, but I really do like him so don't ruin him please). His snow sprite
>   should also only have one pile/mound of snow, not three weird looking ones. Actually, although I said "not his
>   face", I meant the style, not the color; making his eyes glow after making him slightly transparent might be
>   really cool. Can you also make Glim's tail glow in that case, if it's possible, or does "glow" in this context
>   just mean clever use of colors? In any case, yes, making Phase a cool, slightly-transparent ghost creature is
>   definitely the vibe here.
> * Tuck: almost done, but his eyes/sprite don't make much sense during rain. He should be in a little puddle
>   and/or have a bit of water pool up in his pot. He also looks extremely depressed at night instead of like he's
>   sleeping. Can you make him look relaxed instead and perhaps with his eyes slightly bowed apart to show he's
>   resting?
> * Quill & Nod: Actually, please revert Quill's face to the 0.9.6 version as it now looks out of place (with slight
>   modifications to Quill's 0.9.6 face to make him look a tad more friendly if you can, but be careful) and update
>   Nod's eyes as well, as that will lead us towards an art style where none of the characters have just
>   single-pixel dots for eyes. Be careful with Nod too please as I love his character and he's essentially done
>   apart from his eyes. Also for Nod, I thought his 0.9.6 design featured an umbrella over his head, which is what
>   I wanted you to have him hold; the new umbrella in 0.9.7 is terrible. Please either revert his rain sprite to
>   0.9.6 or turn the thing above his head into an umbrella he's holding that rain can drip off for 0.9.8.
> * Button: done for now; just have him sit at the bottom of his square box in the Theme settings menu for
>   variety's sake.
> * Hush: done for now.
>
> Flipboard UI/UX feedback:
>
> * Switchboards should grow/scroll horizontally, not vertically, and the "Add switch" button outline should appear
>   at the right end of each Switchboard scroll. Ungrouped switches can still live at the top and move downwards
>   vertically in groups of two (on iOS), but they should be collapsible to easily get to your horizontal
>   Switchboards.
> * Switchboards should have some kind of mild background UI so that they actually feel like they're a part of the
>   same circuitboard rather than just switches in a group, and that background UI should also show at all times
>   when the board is fully green/which switches in the order are red while keeping the UI minimal and clean (small
>   red and green dots in a row would do it; if there's too many switches to display with dots on that Switchboard,
>   have a backup UI plan).
> * Adding Switches on iOS makes them expand and contract like crazy for a moment before they settle.
>
> Please work freely and prepare 0.9.8 for release.

## How it is read
- **Rain, on all eight**: water is blue now. Three water inks are on master (`p`, `h`, `u`; `COMMON.md` has the
  recipe): beads that stay on the creature, a drop that runs off it now and then, a small puddle at its feet, awake
  and asleep. What each creature does about the rain (round 23) stays; the water is why it does it.
- **Glim, Hush, Button**: done. Only their rain gets water (his "for all creatures"), Glim's lantern gets a real
  glow (his question: yes, it can be real light), and Button moves to the floor of his swatch in Settings.
- **Gargle**: left alone, but for his rain's water and a deep snow he can be recognised under.
- **Phase**: see-through for the eye (not only in the numbers), with opacity that shifts in his moves; his eyes
  lit and glowing, in the style they have; tiny touches to the body's shading and tail; one mound of snow. The
  engine learns a real glow and a per-frame fade for it.
- **Tuck**: asleep he is resting, not sad: stalks bowed gently apart, soft, no mouth. In the rain he is himself, in
  a puddle with water in his pot.
- **Quill**: 0.9.6's face back on every frame, a touch friendlier and no more. **Nod**: eyes that are not single
  pixels, with great care; in the rain 0.9.6's canopy again, now with a handle in his hand and drops off its rim.
- **The style rule he names**: no creature has a single pixel for an open eye.
- **Flipboard**: each Switchboard is one row that scrolls sideways on a panel of its own, its Add switch outline at
  the right end, a strip of small lights (one a switch, in order, red or green) always in view, with a fallback when
  there are too many for dots. The ungrouped switches stay a two-across grid at the top and fold away. The jitter
  when a switch is added on iPhone is found and fixed.
- 0.9.7 was never uploaded: its notes fold into **0.9.8**, which is this round. No schema change.

## What the supervisor sees in the app (0.9.7, enlarged)
- Rain: every drop is in the theme's pale text colour or grey. Nod, Tuck, Glim, Button and Gargle have no water on
  them at all; only Nod has a still for rain while asleep.
- Nod's 0.9.7 umbrella is a one-pixel outline of a dome with a hooked wire round his left side: a wire, not an
  umbrella. 0.9.6's was a small striped canopy with a peak, sitting over his cap: that one George liked.
- Nod's eyes are one dark pixel each; Quill's (0.9.7) too.
- Tuck asleep (the supervisor's own drawing in round 23): stalks folded flat, eyes hanging at cheek level: limp.
  In rain: stalks stretched up tall, eyes wide: alarmed, and no water anywhere.
- Phase: a solid mauve sheet; `seeThrough: 0.25` over a dark window is only a dimmer mauve. Three small heaps of
  snow under him.
- Gargle at `snow3`: snow over the brow, the horns and the snout: the profile is gone.
- Flipboard: a Switchboard is a header ("3 of 5") and a grid that grows downward; nothing ties its switches
  together, and what is red is known only by scrolling.

## Sessions (all Opus 5.5; six at once)
| Brief | Session | Effort | What |
|---|---|---|---|
| 121 | `phase-ether` | xhigh | Phase see-through and ethereal, glowing eyes, opacity in his moves, one snow mound; the engine's glow and fade; Glim's lantern glow |
| 122 | `tuck-rest` | xhigh | Tuck asleep and at rest; in the rain, in a puddle with water in his pot |
| 123 | `quill-nod` | xhigh | Quill's 0.9.6 face, a touch friendlier; Nod's eyes; Nod holds 0.9.6's canopy; their rain's water |
| 124 | `gargle-button-rain` | xhigh | Water on Gargle and Button; Gargle recognisable in deep snow; Button on the floor of his swatch |
| 125 | `hush-glim-rain` | xhigh | Water on Hush and Glim, and nothing else of theirs |
| 126 | `flipboard-rows` | xhigh | Switchboards as sideways rows on a panel with lights; ungrouped switches fold away; the add jitter |

All xhigh: every item is judged by George's eye at real size, three rounds of drawings have come back, and the one
drawing session run at high last round made the umbrella he calls terrible. 126 redesigns a screen he uses daily.

## The supervisor's own
- The three water inks, on master before any session starts.
- Its own sketches where words failed before: Tuck asleep, Nod's eyes, Nod's held canopy, Quill's friendlier face;
  sent to the sessions as rows and to George as pictures, at once.
- Every concept sheet looked at at real size and forwarded to George as it arrives.
- The merge, the cast photographed in the app (0.9.7 beside 0.9.8), the suites, the UI suite (the Flipboard
  changed), a Release archive and export, `## 0.9.8`, `Entry(version: "0.9.8")`, the pin, the record, the hand-over.
