# HITList (Human-in-the-List) — Design

> The original design, written 2026-10-26 before the first build and kept as written. The app has since
> grown past it (accounts, sub-tasks, Shared Tasks, the Claude connector), and the home-server backup in
> section 5 was prototyped but never wired in; the prototype was removed from the tree on 2026-11-05 and is
> in history before `v0.7.1`. The current picture is in the top-level README and `CHANGELOG.md`.

A personal, Todoist-flavored task manager for Apple devices with three priorities:

1. **Robust priority and date filtering** via a small, composable query language.
2. **Task keyword autofill**: natural-language quick add plus learned suggestions.
3. **Effortless sync across iPhone, iPad, and Mac**, with an optional backup
   channel to a personal home server.

Everything else Todoist does (comments, collaboration, sections, boards, karma,
integrations, AI, templates) is deliberately out of scope.

---

## 1. Scope

| Keep | Drop |
|------|------|
| Tasks: title, notes, due date, optional due time, priority P1–P4 | Comments, attachments, file uploads |
| Projects (flat list, color) | Sections, boards, nested projects |
| Labels (tags) | Sharing / collaborators / assignees |
| Quick Add with natural-language parsing | Karma, productivity stats |
| Saved filters with a query language | Templates, integrations, email-to-task |
| Simple recurrence (daily, weekly, monthly, yearly, weekdays, every N) | Complex recurrence ("every 3rd Friday") |
| Local reminder notification at due time | Location reminders |
| Today / Upcoming / Inbox / Completed views | Activity log |
| JSON export/import + home-server backup | — |

Subtasks are intentionally not in v1. A task either exists or it doesn't.

---

## 2. Architecture

```
HITList/
├── HITListCore/          Swift Package, no UI, no SwiftData. Fully unit tested.
│   ├── FilterQuery       Tokenizer → parser → AST → evaluator
│   ├── DateExpression    "tomorrow", "next mon", "in 3 days", "jan 5", ISO
│   ├── QuickAddParser    Natural-language task entry
│   ├── AutocompleteEngine  Keyword / project / label suggestions and attribute autofill
│   ├── RecurrenceRule    next occurrence math
│   └── Snapshot          Codable export/import format (also the backup payload)
├── HITList/              SwiftUI multiplatform app (iOS 18+, macOS 15+)
│   ├── Models/           SwiftData @Model classes (CloudKit-compatible)
│   ├── Views/            Sidebar, task list, quick-add bar, task editor, settings
│   ├── Services/         BackupClient, NotificationScheduler, SnapshotBuilder
│   └── Resources/        Entitlements, Info.plist, assets
├── server/               Optional home-server backup receiver (Python stdlib, Docker)
└── project.yml           XcodeGen spec that produces HITList.xcodeproj
```

**Why a separate core package.** Filtering and parsing are the parts most likely
to have bugs and the parts that benefit most from fast `swift test` runs on the
Mac without a simulator. The app conforms its SwiftData model to a tiny
`FilterableTask` protocol so the core never depends on persistence.

**Why SwiftData + CloudKit.** It is the only option that gives sync across every
Apple device with zero servers, zero accounts beyond the user's Apple ID, offline
support, and conflict handling, all for free with an Apple Developer account.

### Data model

```
Project   id, name, colorHex, sortOrder, createdAt, updatedAt
Label     id, name, colorHex, createdAt, updatedAt
Task      id, title, notes, priority(1–4, 4 = none), dueDate?, hasDueTime,
          isCompleted, completedAt?, recurrenceRule? (encoded string),
          sortOrder, createdAt, updatedAt, project? (to-one), labels (to-many)
SavedFilter id, name, query, colorHex, sortOrder
```

CloudKit constraints shaped the model: every stored property has a default or is
optional, relationships are optional, and there are no unique constraints. IDs
are UUIDs generated on the device. `updatedAt` is maintained on every edit; that
field plus soft-deletion semantics in the snapshot format are what make a future
home-server sync protocol possible without a migration.

**Flipboard switches.** A switch is an open recurring task without a time of day that carries the
`flipboard` label (HITListCore `FlipboardSwitch`): green while due after today, red when due today,
overdue or never flipped. It is a visual aid for chores that repeat within an interval, not on a
date, so it stays off every list until it is due: green, it is on the Flipboard only; red, it is a
task for today in Today and the Inbox (never "overdue"; the board keeps the days late) until it is
flipped (brief 59, George 2026-11-07; `FlipboardSwitch.listing`, used by every list).

---

## 3. Filter query language

Modeled on Todoist's filters but with a formal grammar and a real parser so the
behavior is predictable and testable.

```
query    := or
or       := and ( "|" and )*
and      := not ( ( "&" | "," ) not )*
not      := "!" not | primary
primary  := "(" query ")" | term
```

Terms:

| Term | Meaning |
|------|---------|
| `p1` `p2` `p3` `p4` | priority equals |
| `priority >= 2`, `priority < 3` | priority comparison (1 is highest) |
| `today`, `tomorrow`, `yesterday` | due on that day |
| `overdue` | due before start of today and not completed |
| `no date`, `no due date` | no due date |
| `has time`, `no time` | due time set / not set |
| `next 7 days`, `7 days`, `next 30 days` | due today through N days ahead |
| `this week`, `next week`, `weekend` | due within that span |
| `due: <expr>`, `due before: <expr>`, `due after: <expr>` | date expression comparisons |
| `#Project`, `#"Two Words"` | in project (case-insensitive) |
| `@label` | has label |
| `no project`, `no labels` | unassigned |
| `search: text`, `"quoted text"` | title or notes contain text |
| `completed`, `!completed` | completion state (default views hide completed) |
| `recurring` | has a recurrence rule |
| `all` | matches everything |

Every query leaves green Flipboard switches out and sees red ones as due today, unless it names
`@flipboard` (then switches match by their own dates).

Examples that work out of the box:

```
overdue | today
(p1 | p2) & next 7 days & !@waiting
#Work & no date
due before: next mon & priority <= 2
search: dentist | @health
```

Evaluation is in-memory against the loaded task set. For a personal task list
(thousands of tasks at most) this is instantaneous and avoids the
expressiveness limits of `#Predicate`. Results are sorted by due date, then
priority, then title; the user can change the sort per view.

---

## 4. Quick Add and keyword autofill

### Parsing

Typing `Pay rent tomorrow 5pm p1 #Finance @bills every month` produces:

```
title:      "Pay rent"
dueDate:    tomorrow @ 17:00, hasDueTime = true
priority:   1
project:    Finance
labels:     [bills]
recurrence: monthly, interval 1
```

Recognized token classes, in order of extraction:

1. **Priority**: `p1`…`p4`, `!!1`…`!!4`
2. **Project**: `#Name`, `#"Name With Spaces"`, or `#home repairs` when a multi-word project of that name exists (longest known match wins). Unprefixed project words are never auto-applied; the attribute-autofill chips suggest them instead, so a task like "Fix home router" is not silently filed under a project named Home.
3. **Labels**: `@name` (multiple)
4. **Recurrence**: `every day|daily`, `every week|weekly`, `every month|monthly`, `every year|yearly`, `every weekday`, `every N days|weeks|months`, `every mon[day]`, `every mon, wed`
5. **Time**: `5pm`, `5:30pm`, `17:00`, `at 5`, `noon`, `midnight`
6. **Date**: `today|tod`, `tomorrow|tom|tmr`, `yesterday`, weekday names (`mon`, `monday`, meaning next occurrence), `next week`, `next month`, `in N days|weeks|months`, `N days`, `jan 5`, `5 jan`, `january 5th`, `1/5`, `2026-01-05`, `end of month`, `eom`
7. **Title**: whatever remains, whitespace-normalized

Each extracted token carries its string range; the quick-add bar renders the parsed
result as chips under the field so you can see exactly what will be saved before
pressing return. Wrapping a word in quotes (`"tomorrow"`) keeps it as literal title text.

### Autocomplete ("autofill")

`AutocompleteEngine` indexes all existing tasks. As the user types:

- Current word starts with `#` → project suggestions (prefix first, then substring).
- Current word starts with `@` → label suggestions.
- Otherwise → ranked suggestions from (a) previous task titles that start with
  the typed text, weighted by how often they were created, and (b) a fixed list
  of date/priority keywords when the current word looks like the start of one.

**Attribute autofill.** When the typed title shares its significant keywords with
past tasks (e.g. "Buy milk" was always `#Groceries @errand`), the engine proposes
the most common project, labels, and priority from those tasks. The quick-add bar
shows them as a dismissible chip row; one tap applies them. This is the
"keyword autofill" feature: the app learns your vocabulary instead of making you
retype metadata.

---

## 5. Sync: options, costs, recommendation

### Option A — iCloud / CloudKit (built in, default)

| Item | Cost |
|------|------|
| CloudKit usage with an Apple Developer account | $0. Private-database data counts against the *user's own* iCloud storage, not the developer's quota. |
| Storage consumed | A task record is roughly 0.5–1 KB. 10,000 tasks ≈ 5–10 MB. Negligible against even the free 5 GB iCloud tier. |
| Push notifications for sync | $0 (CloudKit silent pushes are included). |
| Installing on your own devices | $0 beyond the $99/yr developer membership you already pay. With a paid account, builds installed from Xcode stay valid for 1 year instead of 7 days, and TestFlight is available if you want over-the-air installs. |
| Server maintenance | None. |

Trade-offs: requires iCloud signed in on each device; sync latency is usually
seconds but can be a minute or more; data lives in Apple's cloud (encrypted at
rest, but not end-to-end for standard CloudKit private DB unless Advanced Data
Protection is enabled on the Apple ID, which does cover CloudKit private data).

### Option B — Home server as a backup target (built in, optional)

The app periodically (and on demand) pushes a full JSON snapshot to an HTTPS
endpoint you control. The included `server/` is a ~150-line Python service that
stores timestamped snapshots on disk and keeps the last N. Because your home
server already backs itself up to Backblaze B2, your task history rides along
with that pipeline.

| Item | Cost |
|------|------|
| Compute | Effectively zero; the service idles and handles one request every few minutes at most. |
| Storage | Snapshots are tens of KB each. 1,000 retained snapshots ≈ 50 MB. |
| B2 | $6/TB-month → fractions of a cent. |
| Exposure | Put it behind your existing reverse proxy or a Tailscale/WireGuard network; the service itself requires a bearer token. |

### Option C — Home server as the *primary* sync (designed, not built)

Replacing CloudKit entirely means building a sync protocol: per-record
`updatedAt`, tombstones for deletes, a change-feed endpoint, and last-writer-wins
merge on the client. The snapshot format and model fields in v1 already carry
`updatedAt` and stable UUIDs, so this is an additive phase 2, not a rewrite. It
costs engineering time, not money, and loses the "it just works when I sign in on
a new iPhone" property. Not recommended unless you want to leave iCloud.

### Decision (2026-10-26)

**iCloud only.** George's family storage lives on iCloud and it serves this app's needs, so
Option B is not wired into the UI. `server/` and `HITList/Services/BackupService.swift`
remain in the tree as an unused, documented relic in case that ever changes. The JSON
export/import in Settings still gives a manual backup path.

### Original recommendation

Ship with **A + B**: CloudKit for live sync between devices, the home server for
an independent, versioned, B2-backed history that doesn't depend on Apple. Total
recurring cost: $0 beyond what you already pay.

---

## 6. Build and run

Prerequisites: Xcode 27 (installed), XcodeGen (`brew install xcodegen`), signed
into Xcode with your Apple ID so automatic signing can create the CloudKit
container `iCloud.com.trammells.hitlist` on first build.

```
xcodegen generate                       # produces HITList.xcodeproj
cd HITListCore && swift test            # core logic tests, no simulator needed
open HITList.xcodeproj                  # build & run on iPhone / Mac
```

First launch after enabling iCloud on a device may take a minute to pull data.
In development, CloudKit uses the Development environment; before installing on
devices via TestFlight, deploy the schema to Production in the CloudKit Console
(Xcode's "Deploy Schema Changes" button).

### Home server

```
cd server
cp .env.example .env     # set HITLIST_TOKEN to a long random string
docker compose up -d     # listens on :8787, stores snapshots in ./data
```

In the app: Settings → Backup → enter `https://your-host/hitlist` and the token.
