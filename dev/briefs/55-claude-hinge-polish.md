# Brief 55: Claude wording and default, a quiet wooden hinge (branch `claude-hinge-polish`, effort High)

Read `briefs/COMMON.md` (Round 11 block) and `briefs/HIG-NOTES.md` (audio). Sessions 53, 54, 56 run at the same time.
Last build before friends join.

George's words, 2026-11-05:

> Please use the official Claude icon on the Claude integration in the Settings page unless we're not allowed to for
> whatever reason. Also, change "All but @private" and "None but @claude" to say "All tasks but @private" and "Only
> tasks with @claude", and make "Only tasks with @claude" the default/leftmost option (the entire Claude integration
> itself should of course stay off by default).

> Include no random audio effects; themes and holiday events should be visual only (besides the iPhone Duo hinge
> noise, which is really just a gag for one friend; it should have an option to disable it, but it should be on by
> default for iPhone Duos; ensure it is rather quiet so it's funny and not annoying; the hinge sound effect should
> sound more like a door/cabinet/chest creaking open and not like squeaky metal).

The supervisor checked the icon: Anthropic's trademark guidelines allow its logos only as Anthropic specifically
permits, in materials it approves beforehand, so the official Claude logo is NOT used; keep a neutral SF Symbol and
never draw a lookalike of the Claude spark.

## Items (one commit each, failing test first where there is logic)
1. **Claude wording**: the segmented choice reads "Only tasks with @claude" (left, the default) and "All tasks but
   @private" (right), using the editable label names. Default mode becomes `onlyShared` when nothing is stored
   (HITListCore `ClaudeAccessRule` default and `ClaudeSettings` fallback); a stored choice stays as it is. The
   integration stays off by default. Update texts that describe the modes (confirmation sheet, footers,
   `docs/connect-claude.md`, the helper's descriptions if they name them) and the tests that pin them.
2. **Audio audit**: list every sound the app can make (completion sound, Flipboard flip, hinge) with its switch; make
   sure holiday effects, the rare visitor and themes are silent (they should be; prove it) and that nothing plays a
   sound George didn't ask for. Report the list.
3. **The hinge, wooden and quiet** (`Support/Delight/HingeCreak*.swift`): re-voice the procedural creak as an old
   wooden door / cabinet / chest lid: low, irregular stick-slip pulses (fundamental roughly 80–350 Hz drifting with the
   hinge speed), body resonances in the low mids, a dry woody tail; no bright pure tones above ~1.5 kHz (that is what
   reads as squeaky metal). Noticeably quieter than now (aim around −18 dBFS peaks at the fastest movement, softer when
   slow), still instant. On by default only on devices with a hinge (the Extras row shows only there), with its switch
   ("Creaky hinge"). Render WAVs of an open, a close and a slow creep, compare spectra before/after in the report (you
   cannot listen: show the numbers), and put the WAVs in the shared notes folder for George.

## Ownership
`Views/Settings/ClaudeSettingsSection.swift`, `Services/Claude/ClaudeSettings.swift`, `Services/Claude/ClaudeIntegration*`,
HITListCore `ClaudeAccess.swift` (default only) and their tests, `docs/connect-claude.md`; `Support/Delight/HingeCreak*.swift`,
`Views/Delight/DelightSettingsSection.swift` (the hinge row only); tests `ClaudeGatingTests`, `HingeCreakTests`; ROADMAP
row "Claude wording and default, wooden hinge (brief 55)". Not yours: `ProfileMenu.swift` (53), `SyncStatusViews.swift`
(54), `Views/Tips/*`, `UpcomingBoard.swift`, `TaskRow.swift` (56).

## Done
All three suites green; iPhone screenshots of Settings → Claude off and on (UI test or simulator); the audio list; the
WAVs and spectra.
