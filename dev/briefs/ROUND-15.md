# Round 15: George's notes on 0.8.1 (2026-11-08)

Rounds 13 and 14 ran in Fable's chat; 0.8.1 is out as build 19 and several friends use it. George's notes on it are
quoted in each brief. The screenshots he sent are in `/Users/gtrammell/Desktop/HITList/build.noindex/round-15/` (outside
git; read them by that absolute path):
- `george-1-mac-toolbar.png`: a saved filter's toolbar on the Mac: the query in a capsule with no inner padding, the
  bolt, the view-options pill, and the "+" drawn as two ovals, one inside the other.
- `george-2-type-ours-top-target-bottom.png`: our Mac Inbox row on top ("call mom", "Friday"), the target below
  ("check backlog/longterm", "Nov 5"), both captured on the same Mac at the same scale.
- `george-3-mac-editor.png`: the Mac task editor with "test today" typed in the title and the date still "No date".

## Before the round (supervisor, on master)
- **Invisible Mac cards (0.8.2).** On the Mac every picker card (date, Group, priority, labels, reminder, repeat) opened
  invisibly: built with the Xcode 27.2 SDK, a SwiftUI content view draws over any view added inside it, and the card
  layer (`PickerLayerHost`) was added inside `window.contentView`. Accessibility saw each card in place; nothing drew
  it. The layer now sits in the window's frame view beside the content view (`PickerLayerHost.host(in: window)`,
  pinned by `PickerTests.testTheCardLayerSitsAboveTheWindowsContentNotInsideIt`). Never add an AppKit view inside a
  SwiftUI window's content view to draw over it.
- **Filters below Groups** in the Mac sidebar.
Both are in 0.8.2's notes; George may release 0.8.2 before this round merges. The round ships as **0.9.0**.

## Rules (into SUPERVISOR §7 when the round merges)
- Shared tasks are tasks in one forced Group, **Shared Tasks**: no Shared section in the Mac sidebar or Browse. A shared
  task looks like a task of yours, with the people's pictures where labels go, and opens in the same editor.
- The task editor's title understands quick-add phrases the way the quick-add card does.
- Every Mac toolbar control is one oval; the trailing pill keeps its width on every screen; a filter's query in the
  toolbar reads "Search: …" with room inside its capsule.
- The Mac sidebar from the top: room, the profile, room, a search field, then Inbox …; Groups (Shared Tasks last),
  Filters, Labels.
- Rows read larger on iPhone and Mac, with weight and spacing matched to George's target (brief 67). The Duo's outer
  display is right as it is.
- The bolt has two styles (Settings → Extras): today's strike, and a twirl, bounce and slam with a tiny buzz of sparks,
  all within a second. Both keep 0.7.1's rule: rare, a "you're good to go".
- Adding a Flipboard switch is a small, cute card like the Mac board's Add task card, tactile to set.

## The round
| Brief | Session | Effort | Owns, in short |
|---|---|---|---|
| 64 | `shared-group` | xhigh | Shared Tasks as one forced Group, rows and editor like yours, counts: `Views/Shared/*`, `Services/Sharing/*`, `Views/Groups/*`, `TaskRow` (meta line, Group slot), `SidebarView` (sections), `BrowseView`, `PopoutHost`, `PopoutController`, `PopoutPickers`, `TaskListView`, the badge and morning summary |
| 65 | `editor-quick-add` | xhigh | The editor's title reads quick-add phrases; every Mac card checked: `TaskPopout` (title card), `Popouts/Editor/*`, `Pickers/*`, `TokenHighlightField`, `HighlightText/*` |
| 66 | `mac-chrome` | high | Mac toolbar ("+" one oval, "Search:" query, steady pill) and the sidebar's search field and spacing: `QuickAddEntry`, `ScreenMenu`, `SidebarView` (header), `ContentView` (search), new `Views/Search/*` |
| 67 | `type-scale` | xhigh | The type on iPhone and Mac: `HITTokens`, `ListChrome` (`ListMetrics`), `TaskRowMetrics` in `TaskRow` |
| 68 | `bolt-slam` | xhigh | The second bolt style and its Extras setting: `SyncStatusViews`, new `BoltSlamMotion`, `DelightSettingsSection` |
| 69 | `flipboard-add` | xhigh | Adding and editing switches: `Views/Flipboard/*` |

All six run at once. Merge order: 68, 69, 67, 65, 66, then 64 (it touches the most shared files). Conflicts to expect
and keep both sides of: `TaskRow` (64's meta line, 67's `TaskRowMetrics`), `SidebarView` (64's sections, 66's header),
`ContentView` (64's and 66's `SidebarItem` cases), `TaskListView` (64's Group screen, 66's one-line query view),
`TaskPopout` (65's title card, 64's Group row), `HITListUITests.swift` and `dev/ROADMAP.md` (one addition each).

## What the supervisor checks before the hand-over (screenshots in the message)
iPhone (own simulator, `-seedDemoData`): Inbox, Today, Upcoming, Flipboard and adding a switch, Browse (Groups with
Shared Tasks last), the Shared Tasks Group, the editor with "tomorrow p1" typed into a title, Settings → Extras.
Mac: Inbox, Today, the Upcoming board, the Flipboard and adding a switch, a saved filter's toolbar, the sidebar search
with a typed `#Work`, the editor's date and Group cards, the Shared Tasks Group and a shared task's editor, Settings →
Extras; the toolbar on Upcoming and the Flipboard (same pill width). The type side by side with George's target.
Both bolt styles recorded frame by frame.
