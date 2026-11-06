# Brief: Completion sound alternatives + custom sound

Effort: Medium. Model: Opus 5.5. Read `briefs/COMMON.md` first. Your worktree is cut from the
`completion-delight` branch (not master), so `CompletionFeedback`, `DelightSettingsSection` and
`HITList/Resources/CompletionSound.caf` exist. George disliked the tick-ding.

## Files you own
The completion-feedback service file(s) under `HITList/Support/Delight/`, `DelightSettingsSection`,
`HITList/Resources/Sounds/` (new), new test files in `HITListTests/`. Nothing else.

## Task, two commits
1. **Five built-in sounds**, each ≤ 350 ms, -14 LUFS-ish, 44.1 kHz caf, generated with numpy +
   `afconvert` and committed under `HITList/Resources/Sounds/`: `pop` (short filtered noise burst with
   a pitch drop, like a cork), `wood` (xylophone-like single struck note with woody decay), `glass`
   (bright bell partials, fast decay), `swish` (filtered noise sweep, paper sliding), `marimba` (two
   warm notes, a fifth apart). Remove the old tick-ding or keep it as `tick`. A `CompletionSound` enum
   with display names and a `none` case; the setting `delight.soundName` in `AppGroup.defaults`
   (default `pop`). The feedback service loads the selected sound lazily and re-loads on change.
2. **Picker + custom file.** In `DelightSettingsSection`: a Picker of the built-ins with a ▶ preview
   button beside it, plus "Choose your own…" using `.fileImporter` (audio types: caf, wav, aiff, m4a,
   mp3). Copy the chosen file into `<app group container>/Sounds/custom.<ext>` (security-scoped
   access on macOS), reject files longer than 2 s with a message, store `delight.soundName = custom`
   and show the file name with a "Remove" button. Tests: enum round-trip, selection persistence,
   duration gate on a generated long file, fallback to `pop` when the custom file is missing.

## Verify
Signed simulator and Mac builds: switch sounds and preview each; import a short wav; delete the file
behind the app's back and confirm fallback. Report per COMMON.md; list the five files with durations.
