# Apple HIG: what applies to HITList (supervisor's notes, 2026-11-05)

George asked every round to follow Apple's Human Interface Guidelines (https://developer.apple.com/design/human-interface-guidelines/).
These are the supervisor's own summaries of the pages that touch HITList, read on 2026-11-05; open the page itself
when your brief touches its area. George's explicit decisions (SUPERVISOR.md §7, the briefs) win over a guideline;
say so in your report when one does.

## iPhone Duo (`designing-for-iphone-duo`, new 2026-09-09)
- Two displays: compact width outside, regular width inside. Build one layout that resizes (size classes, layout
  margins, safe areas); no per-pose layouts, no fixed widths, nothing tied to one display.
- Same functionality and state on both displays; the inner display may show one more level of hierarchy (list +
  detail side by side, as Mail does).
- **Vertical controls:** on the outer display (and the inner one in landscape) the system moves the status bar,
  toolbars and tab bars to the trailing edge. Standard components get this for free; custom bars should follow it
  (`traitCollection.verticalBarEdge`, SwiftUI `toolbarVerticalEdge` / `toolbarVerticalBehavior`). Primary navigation
  (Back/Close) at the top of the vertical axis, prominent actions next; give each toolbar item a title and a symbol;
  prefer symbols over text; use the system overflow menu, keep "…" for overflow only.
- **Reserved regions:** the outer camera, the inner camera when active, and the fold when the device is partly open
  (`ReservedRegion` in SwiftUI, `UIView.ReservedRegion` in UIKit, kinds occlusion and division). Alerts, menus,
  sheets and split views adapt on their own; custom views move out of the way. Grids: prefer an even column count.
- Avoid big layout jumps while folding; small adjustments only. `ArrangementView` (split/overlay) for two-pane
  content; keep navigation containers outside it. Hinge state: `UIHinge` / SwiftUI `DeviceHinge`, `onHingeChange`
  (prefer `status` over the raw angle). Test poses with Xcode's Device Hub.

## Pointers (`pointing-devices`)
- macOS pointer meanings: arrow by default, I-beam over text, pointing hand means "link". (George chose the pointing
  hand over quick-add highlights; that stands.) Don't flicker or decorate pointers; custom pointer behaviour must be
  consistent everywhere it appears.
- iPad: highlight/lift/hover effects; contiguous hit regions so a highlight doesn't blink between neighbours.
- Macs can have touch now: anything revealed only on hover needs a touch path (tap the area, or a context menu).

## Modality, alerts, popovers (`modality`, `alerts`, `popovers`)
- Confirm before closing something that would lose typing ("help people avoid data loss"); always an obvious way out
  (Esc / Cmd-. on Mac and iPad keyboards cancel).
- Alerts sparingly; never for undoable actions; no alert at launch; destructive button styled destructive with a
  Cancel. On iOS an action sheet (not an alert) offers choices about an intentional action.
- A popover is not for warnings, one at a time, never a view on top of a popover, positioned near what it's about.
  Hence: the Discard question belongs inside the card it concerns, not floating above it.

## Settings (`settings`)
- Best defaults for most people; few settings; task options where the task is, not in Settings. Don't duplicate
  system settings (Reduce Motion, silent switch, appearance).
- macOS: a Settings item in the app menu (⌘,), the window title names the visible pane, reopen on the last pane.

## Accounts (`managing-accounts`)
- Ask for an account only if the core feature needs one; delay sign-in; otherwise none. HITList: no login, the
  Apple account is the identity (George, 2026-11-05).

## Generative AI (`generative-ai`)
- People stay in control: say where AI is used, set expectations, ask permission before personal data is used,
  disclose how it's used and stored, get confirmation before irreversible actions, make results easy to undo.
  HITList: the Claude integration is off and hidden until switched on; its privacy choices appear only then.

## Collaboration and sharing (`collaboration-and-sharing`)
- System sharing UI (share sheet, `UICloudSharingController` / `ShareLink` with a CKShare), Messages integration,
  a Collaboration button shown as soon as something is shared, short plain wording for permissions, few options.

## Audio (`playing-audio`)
- Pick the audio session category by intent: Ambient = not essential, mixes with other audio, honours the silent
  switch. Short UI sounds: system sound services or a small pre-warmed engine; never change system volume.

## Text entry, keyboards (`entering-data`, `text-fields`, `keyboards`)
- Offer choices instead of typing where possible, validate as people type, support paste. Respect standard
  shortcuts (Esc cancels; don't repurpose standard keys). Mac: Full Keyboard Access.

## Siri, iCloud, tab bars, sidebars, onboarding
- Siri: familiar terms, short spoken + visual responses, omit the app name from responses, explain failures; donate
  entities to Spotlight so tasks show in search.
- iCloud: transparent, works when iCloud is unavailable, respects storage, includes content in search.
- Tab bars: navigation only (no actions), a symbol and a label per tab, a search tab may sit at the trailing end.
- Sidebars (Mac): row and icon size follow the system's sidebar size setting; nothing critical at the very bottom.
- Onboarding: teach by doing; context-specific tips beat a tour (TipKit); postpone setup; no splash unless needed.
