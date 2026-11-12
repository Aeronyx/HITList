# Round 25: 0.9.9, a reminder a friend could not set, a gryphon for Graphite, and the creatures' seats (2026-11-12, late afternoon)

0.9.8 was prepared (round 24) and not released. George's message at about 15:50 Eastern, verbatim, with a friend's
screenshot of the task editor (title "PNHP Working Group tonight !30mb", the caret after it, nothing highlighted;
"Inbox"; "Today 8:00 PM"):

> Good work; I'm going to hold off on releasing this build as I already have enough feedback for you to prepare
> 0.9.9.
>
> First, one of my friends noticed an issue where, when editing a task, typing !0mb wouldn't register a reminder
> even though that task already had a time (screenshot attached). I'm guessing this is because we made it so that
> quickadd reminders only work when a quickadd time is present, but they must also work when editing a task that
> already has a time associated with it. This same edge case could cause issues with other interactions as well;
> please scan for and fix any problems.
>
> As for the creatures:
> We must iterate on Gargle once more; he's the only creature that doesn't fit the theme. He needs to have more
> cartoonish eyes and appearance (not necessarily sillier, just less real), and perhaps make him a Gryffin or
> something more fantastical instead of a straight dragon. Once you have him ready, make sure his weather
> animations fit alongside the new ones we have now. (Also, please rename him; Gargle is a bad name).
>
> Please put Phase's black eyes back! The new white eyes you added for him ruin his entire vibe. Please make them
> majority black with a white pupil again and have him once again looking down to the right by default/day and
> also have him looking at the snow pile with mild concern instead of away from it during deep snow (looking
> away/up left during rain is still good). The other opacity and design changes you made for him are great.
>
> Nod's umbrella was supposed to be a wooden stick he holds with his right hand and... hm, nevermind, just restore
> his 0.9.6 canopy. It'll just be a little floating canopy over his head.
>
> Why does Tuck now have no mouth when sleeping? I just said the smile was weird, not to remove the mouth
> entirely! Please put back a little line mouth to show when he's resting. His eyes can also droop a bit more now
> that they're bowing out just a bit; I just want him to look at peace.
>
> Hush, Quill, Glim, and Button are all looking good along with the new weather effects.
>
> For the Appearance/Theme boxes in Settings:
>
> * Have Quill asleep and almost falling/slumping off the top right corner.
> * Position Tuck in the bottom left similar to Button, but perhaps center one of them so they look slightly
>   different in terms of positioning.
> * Position Glim in the bottom right, having his tail almost hanging over the "Tokyo Night" text.
> * Put Gargle somewhere more interesting, like flying in the middle left slightly extended outside of his box or
>   maybe just in the bottom left of his box facing right, but definitely not behind his box; only Hush should be
>   hiding like that.

## How it is read
- **The reminder.** The editor already tells the parser that the task has a time (`dueTimeIsSet`, brief 65), so
  the plain case should work and the friend's did not: the cause is found in the running app first, then fixed,
  then every phrase of the same shape (one that leans on a value the task, the draft or a chip holds rather than
  the text) is checked at every place a parser is built. "!0mb" is not in the grammar and "!0" is: decided there.
- **Gargle** becomes **Flint**, a gryphon cub drawn as the other seven are drawn: a big head, facing you or
  three-quarters on, eyes of several pixels, flat tones, one idea. The name is the supervisor's pick (Graphite's
  stone; one syllable like the others) and one line to change. His weather follows round 24's recipes. He flies on
  his swatch.
- **Phase**: 0.9.7's eyes on 0.9.8's body. Black with one white pupil, down and to the right by day; at the snow
  pile, a little worried, in deep snow; up and to the left in rain. No white eyes in any move.
- **Nod**: 0.9.6's canopy with no handle. Its water (0.9.8) stays: he did not object to it and praised the others'.
- **Tuck asleep**: a short flat line for a mouth and eyes that droop a little further out and down. At peace.
- **Hush, Quill, Glim, Button**: not a pixel of theirs changes, but for the seats below.
- **Settings**: Quill asleep sliding off the top right corner; Tuck bottom left and Button bottom centre; Glim
  bottom right, his lantern hanging toward "Tokyo Night"; Flint flying at the middle left, partly outside his box;
  Hush alone behind a box; Nod and Phase as they are.
- 0.9.8 was never uploaded: its notes fold into **0.9.9**, which is this round. No schema change.

## Sessions (all Opus 5.5; five at once)
| Brief | Session | Effort | What |
|---|---|---|---|
| 127 | `phrases-on-a-task` | xhigh | The reminder typed in the editor, and every phrase that leans on the task: reproduce, fix, scan, table |
| 128 | `flint` | xhigh | Flint, a cartoon gryphon cub in Gargle's place: concept sheet, the whole creature, his weather, `fly` |
| 129 | `phase-eyes` | xhigh | Phase's black eyes on every frame; a worried look at the snow; no white eyes |
| 130 | `nod-tuck` | xhigh | Nod's canopy without its handle; Tuck asleep with a line mouth, drooping a little more |
| 131 | `swatch-seats` | xhigh | The Settings boxes: Quill, Tuck, Button, Glim and Flint each in a place of his own |

All xhigh: four are judged by George's eye at real size (the fifth send-back of the creatures), and 127 is a
friend's bug whose cause is not the obvious one and whose scan has to be complete.

## The supervisor's own
- The rename to Flint on master before any session starts, so all five branch from it.
- Its own sketches, sent as rows: Tuck asleep with a mouth; candidates for Flint.
- Every sheet looked at at real size and forwarded to George as it arrives.
- The merge, the cast photographed in the app (0.9.8 beside 0.9.9), the Settings grid on iPhone and Mac, the
  suites, the UI suite, a Release archive and export, `## 0.9.9`, `Entry(version: "0.9.9")`, the pin, the record,
  the hand-over.
