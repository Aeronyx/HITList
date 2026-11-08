# Round 14: 0.8.0 went out wrong (2026-11-07, evening)

George released 0.8.0 and found the Inbox's top a mess: a small title that is a button, two filter-looking buttons
beside the magnifying glass, "Inbox" twice (the title and the old "Inbox · 1" header), and a "Priority 4  1" section
header in a different type. His words are in brief 61. The friend on the iPhone Duo asked for slightly larger type
and more room around the side island (brief 63). And Shared Tasks, as a separate screen, miss the point: shared
tasks belong in the lists (brief 62).

How it happened, so it does not again: brief 57 put three new things on one screen (a title menu, a filter control
beside the view options, grouped section headers) and the supervisor merged them after looking at Today and the
Flipboard in the simulator, never the Inbox. Session 57's own report even said the two filter icons "look alike".
From now on the supervisor screenshots every main screen on both platforms before the hand-over and sends the
screenshots with it, and treats a session's doubt in its report as an item to fix (`dev/SUPERVISOR.md` §4, step 8).

## Rules that come out of it (also in SUPERVISOR §7)
- A screen's name appears once, as its title. iPhone titles are large and are never buttons.
- Beside the magnifying glass there is one control on a list: the view options (filter-lines icon). Nothing else.
- The Inbox sorts by Priority by default (a flat list, priority then date, as it always did). Group and Date are the
  other two sorts; within a Group or a day, priority then date. Today sorts by Priority or Group.
- Saved filters live in Browse's search field, not in a section of their own on iPhone; the Inbox has no filter control.
- Section headers in a list all use one style (`taskSectionHeader`), the count in grey after a middle dot.
- Groups are the first section of Browse, above Shared Tasks. Switching tabs returns the other tab to its first screen.

## The round
| Brief | Session | Effort | When | Owns, in short |
|---|---|---|---|---|
| 61 | `lists-cleanup` | xhigh | now | Inbox and Today chrome and sorts, Browse order and search-field filters: `TaskListView`, `InboxView`, `BrowseView`, `ListChrome`, `ScreenMenu`, `Views/Groups/*`, `GroupedOrdering`, `InboxText`, `SettingsPreferences` |
| 63 | `duo-and-shell` | high | now | Duo type size and island room, tab switch resets the stack: `MobileShell`, `MobileTabBar`, `TaskRow`, `HITTokens`, `Views/Duo/*` |
| 62 | `shared-in-lists` | xhigh | after 61 merges | Shared tasks as rows in Today, Upcoming, the Inbox and the Mac sidebar: `Views/Shared/*`, `Services/Sharing/*`, then the list views |

61 and 63 run together (disjoint files). 62 starts once 61 is merged, because it must change the same list views.
Merge order: 63, 61, then 62. The version is 0.8.1: the supervisor writes the section, the What's New entry and the
`SettingsTests` pin at the end from the sessions' changelog lines.

## What the supervisor checks before the hand-over, with screenshots in the message
iPhone (own simulator, demo data): Inbox in all three sorts, Today, Upcoming, Flipboard, Browse, a Group, the search
field with a saved filter and a typed `#Work` query, a tab switch after visiting Browse. Mac: Inbox and Today in each
sort, Browse's equivalents in the sidebar, a shared task in Today once 62 is in. Duo simulator: the outer display's
Today with the island.
