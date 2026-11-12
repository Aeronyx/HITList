# Round 22: 0.9.6, the creatures again and spacing on the cards (2026-11-12, before dawn)

0.9.5 was prepared and handed over; George did not release it. His message at 04:55 Eastern, verbatim (one picture
attached, of a character that belongs to someone else: it is not in this repository or the notes folder, and what to
take from it is written in brief 110):

> I haven't deployed 0.9.5 as I'm not quite satisfied with it yet. Some feedback:
>
> * Please completely revert to the previous mushroom creature, the new one is much worse/much less unique. I
>   actually kind of liked his creepy-but-slightly-endearing big-eyed smile and rosy cheeks. His sleeping sprite was
>   also great.
> * I don't love that three of the characters have the same style of large black eyes (the bat, the mushroom and
>   Mocha); they fit best on the mushroom (meaning the previous mushroom, not the new one, which we're scrapping), so
>   perhaps change the eyes on the bat and ghost to be more custom. The ghost (Phase) also looks like a Pac-Man ghost
>   instead of like Shuppet. I've attached a picture of Shuppet, which I understand you can't copy directly, but you
>   can definitely be inspired by it. Phase also looks weird "behind" the button as it just causes him to have a
>   weird darker underside. He's a ghost anyways, it probably doesn't make sense for him to be the "behind" character
>   unless you can execute it much better. In general, Glim needs an improvement.
> * Gargle looks like he's throwing up, but I don't mind all of his animations, his nighttime sprite is quite cute,
>   I like that he's side-on for some postures. Perhaps turn him into a bit more of a dragon with a different eye
>   and mouth style.
> * Hush (and Quill to some extent) is starting to look a bit basic now that the other characters are so well done.
>   Give them minor tweaks and updates to improve their designs while maintaining their styles/postures.
> * The snow effects just looks like hats for many characters (especially Quill). Fix it to look more like powdery,
>   pixelated fallen snow than just white globs. Be artistic with the pixelated snow and add some blue hues to make
>   it look professional.
> * Why do the snail's eyes become lines at night?
> * Glim should hide his tali in the snow/rain, and Phase should be largely unaffected by snow and rain given he's
>   a ghost, so come up with something clever there.
>
> UI feedback:
>
> * Some of the screens in your screenshots still look concerning in terms of text/button spacing, primarily on the
>   iPhone Duo. It is most obvious in the "Add task" popout and "Reminders" dropdowns, where some text is right next
>   to a border. This looks lazy and unprofessional. However, many of your edits were still in the right direction,
>   the UI just needs a bit more work.
>
> Please work freely and prepare build 0.9.6 by 9am ET.

## How it is read
- "Mocha" is Phase (Mocha's ghost); "the bat" is Gargle; "the snail" is Tuck; "tali" is tail.
- "In general, Glim needs an improvement" closes the paragraph about Phase and may be a slip for Phase. Both are
  done: Phase is redrawn whole, and Glim gets a design pass of his own beside hiding his tail.
- **Button**: the creature is 0.9.4's again, pixel for pixel (drawing, size, face, sleeping sprite). What stays from
  round 21 is what was never about his look and George has not withdrawn: no boot swinging, and he stands on top of
  the bar. The hand-over says so and offers the plain 0.9.4 file as the alternative.
- "Prepare build 0.9.6 by 9am ET": as every round, prepared and proven, George releases ("I haven't deployed").
  0.9.5 never reached anyone, so 0.9.6's notes carry 0.9.5's as well.
- The pictures George judged are the hand-over's eleven (`round-22/george-saw/` in the shared notes folder). What
  the supervisor sees in them now, and passed last night: on the reminder card the section labels, the last chip of
  a row, the "Add time" field and the footnote sit on or within 6 pt of the card's border; on the date card the five
  quick choices' labels fill their chips border to border and the chips nearly touch each other and the card; quick
  add's chip row is cut through a word at the card's edge; on the Duo's Browse the avatar, the bolt and the pill are
  packed beside the title and the filter chips are cut at the column; the Flipboard's tiles start 3 pt left of the
  title; the switch card's Discard buttons sit by its border.

## Sessions (all Opus 5.5; seven at once; the clock is short)
| Brief | Session | Effort | What | Report due (Eastern) |
|---|---|---|---|---|
| 109 | `button-back` | high | Button as in 0.9.4, standing, with a mushroom's idles; Button's and Nod's snow | 07:20 |
| 110 | `phase-cloth` | xhigh | Phase redrawn as a cloth ghost with eyes of its own, on top of the bar; weather passes through it | 07:20 |
| 111 | `gargle-dragon` | xhigh | Gargle as a small stone dragon, new eyes and mouth; his snow | 07:20 |
| 112 | `hush-quill` | xhigh | Hush and Quill, small design improvements; their snow | 07:20 |
| 113 | `glim-tuck` | xhigh | Glim improved, his tail hidden in rain and snow; Tuck's eyes at night; their snow | 07:20 |
| 114 | `card-insets` | xhigh | Spacing inside quick add, the editor and every picker card (the Duo first, then the iPhone 16) | 07:05 |
| 115 | `screen-insets` | xhigh | Spacing on the screens themselves, the Flipboard's cards, Settings, Review (the Duo first) | 07:05 |

Effort: xhigh where George judges the result by eye and has just sent work back (four drawings, two spacing passes);
high for 109, which restores a drawing that exists and adds a few idles to it. Nothing touches stored data.

## The supervisor's own
- Three snow inks on master before the sessions start (`s`, `b`, `c`), so nobody edits the ink table.
- Concept sheets looked at as they arrive; the merge; the three suites; the UI suite on the merged tree; brief 93's
  walk on the Duo and an iPhone 16, **every picture looked at for the spacing rule before it is sent**; a Release
  archive and export of both platforms; `## 0.9.6` (with 0.9.5's notes folded in), `Entry(version: "0.9.6")`, the
  pin; the record; the hand-over with `scripts/release.sh --version 0.9.6 --quick`.
