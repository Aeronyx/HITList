# 176: Tasks said to the Stream ring arrive in HITList, phone in pocket

Read `dev/briefs/COMMON.md` first (the two sections at its top, the "Round 36" block, the "Round 35 record"), then
this.

George, 2026-11-23: he has a Sandbar **Stream** ring (a voice ring: hold its touchpad, whisper, and the Stream app on
the iPhone saves a note). "Would be able to build a tool or integration for HITList of some kind such that I could
add tasks to it while my phone is in my pocket? That's really what I bought it for. I want to be able to add tasks
to my todo list without even pulling out my phone." He does not want to pay for Stream's membership if he can
help it.

## What is known about Stream (2026-11-23; Sandbar's pages and one third-party bridge, nothing seen running)

- The ring's audio goes only to the Stream app (its own Bluetooth link). No other app can hear it, and its buttons
  are media controls (tap play/pause, double tap next, swipe volume): it cannot start Siri or a Shortcut.
- Free tier (Sandbar's shop FAQ): "Notes, lists, reminders, and 2,000 dictation words a week are always free."
  Paid ("Upstream", $14.99/mo after a 30-day trial): chat, memory, unlimited dictation, "connections to AI apps".
  Stream's MCP server exists (`https://api.sandbar.com/mcp`) but its tier is unclear and it is invite-only in beta.
  Not used here.
- **A webhook.** In the iPhone app: Stream → Settings → Other Tools → Developer (Webhook): an HTTPS URL, a "Sign
  requests" switch that gives a secret starting `swh_`, and a "Send interactions" switch. Whether it needs the paid
  tier is not stated anywhere; George will see.
- What it sends, as a third-party bridge's code reads it (github.com/jerryj6/stream-ring-notes, `src/routes/stream.ts`;
  observed behaviour, not Sandbar's spec):
  - `POST`, `Content-Type: application/json`, body at most a few KB. Fields read: `text` (the capture's words) and
    `interaction_id` (a string up to 256 characters). Nothing else is known about the body: keep it whole.
  - Header `X-Stream-Signature: t=<unix seconds>,v1=<64 lowercase hex>`, the two parts in either order.
    `v1 = hex(HMAC-SHA256(key: the full secret, message: t + "." + raw body bytes))`. The bridge refuses a `t` more
    than 300 s from its clock.
  - "Stream sends saved Capture and Chat interactions. Universal Dictation and Stream replies are excluded. Chat
    can be off for silent captures." Nothing says how to tell a capture from a chat, whether Stream retries, or
    how soon it sends. Stream does not follow redirects: the URL must be exact.

## The design

The ring needs no phone in hand: Stream saves the capture and posts the webhook from the phone in his pocket.
Nothing can write into HITList's iCloud from outside the app, so the webhook goes to a small **relay** of
George's own that holds captures until one of his devices running HITList takes them, turns each into a task with
the quick-add parser, and tells the relay it has them. iCloud then carries the task to his other devices.

```
ring → Stream app (pocket) → webhook → relay (Cloudflare Worker, his account, free) ← HITList (Mac, iPhone) → iCloud
```

### 1. The relay: `relay/stream-inbox/` (new; public repository: no account ids, no subdomains, no secrets)

A Cloudflare Worker with one SQLite Durable Object, in **plain JavaScript with no npm packages and no build step**
(this Mac has `wrangler` and Node 24; nothing new is downloaded). Files: `worker.js`, `wrangler.toml`
(`workers_dev = true`, the Durable Object binding and its `new_sqlite_classes` migration, a compatibility date the
installed wrangler accepts), `setup.sh`, `test.sh`, a short `README.md` (what it is, the endpoints, what it keeps).
Add `relay/**/.dev.vars` and `relay/**/node_modules/` to `.gitignore`.

Endpoints, every reply JSON:

- `POST /stream`: Stream's webhook. Verifies the signature against secret `STREAM_SECRET`, with a ±300 s window and
  a constant-time compare, **before** reading the JSON. Missing or bad signature: 401 (signing is required, never
  optional). Body over 16 KB: 413. Not JSON, `text` not a string, `interaction_id` missing or over 256: 400.
  `text` empty after trimming: 204, nothing kept. An `interaction_id` it holds or has handed over in the last 30
  days: 200 `{"status":"duplicate"}`. Otherwise kept (id, text, the whole body, received time): 202
  `{"status":"accepted"}`. Answers fast: no outbound calls.
- `POST /inbox/claim` with `Authorization: Bearer <INBOX_KEY>`, body `{"device":"<id>"}`: the captures not
  claimed, or claimed more than 10 minutes ago, oldest first, at most 50: `{"items":[{"id","text","receivedAt"}]}`.
  Marks them claimed by that device now, so two devices asking at once never both get one.
- `POST /inbox/ack`, same key, `{"ids":[…]}`: deletes those captures' text and keeps only their ids (30 days) to
  catch a redelivery. `{"acked":n}`.
- `GET /inbox/status`, same key: `{"pending":n,"lastReceivedAt":…,"lastFields":[the top-level keys of the last
  webhook body]}` (the keys only: that is how we learn what Stream really sends).
- `POST /inbox/test`, same key: keeps a capture `{"id":"test-…","text":"Test capture from your Stream ring"}` as if
  Stream had sent it, so the whole path can be proved without the ring.
- `GET /`: 200 `{"ok":true}`. Anything else: 404. A wrong or missing key: 401, after the same constant-time
  compare.
- Captures nobody claims are kept 30 days, then dropped (an alarm or a sweep on each request, as you prefer).

`setup.sh` is what George runs, once, in Terminal. It checks `wrangler whoami` (if not signed in, it says to run
`wrangler login` and stops), runs `wrangler deploy`, and prints the webhook URL (`https://…workers.dev/stream`)
with what to do in Stream: paste it, turn on Sign requests and Send interactions, copy the secret. It reads the
secret back without echoing it (`read -s`), stores it (`wrangler secret put STREAM_SECRET`), makes the inbox key
(`openssl rand -hex 32`, stored with `wrangler secret put INBOX_KEY`), and prints the **inbox link** for HITList,
`https://…workers.dev/#<key>`, copying it to the clipboard (`pbcopy`). Running it again redeploys and keeps the
secrets unless asked to replace them.

`test.sh` proves the relay with no Cloudflare account: `wrangler dev --local` on a port of its own with test
secrets in a temporary `.dev.vars` (deleted on exit), then `curl` with signatures made by `openssl`: signed → 202;
bad signature, old `t`, no header → 401; the same id again → 200 duplicate; claim → the item; a second device's
claim → nothing; ack → gone from status; test → an item. It exits non-zero on any failure.

### 2. HITList: the inbox (new `HITList/Services/Inbox/`, pure parts in `HITListCore`)

- **Pure, in HITListCore, tested there**: `InboxLink` (reads the pasted link: an `https` origin and the key from
  the fragment; `http` only for `127.0.0.1`/`localhost`, for tests; anything else is "That isn't an inbox link"),
  the protocol's request and reply types, and `SpokenTask`: what a capture becomes before the parser reads it.
  Trim; drop one leading "Task", "To do", "Todo", "New task", "Add", "HITList" or "Hit list" with a ":", "," or "-"
  after it; drop one trailing "." or "!" (not "?"); first letter capitalized; nil when nothing is left. Whether a
  capture counts when the "starts with Task" rule is on.
- **`StreamInbox`** (main actor, one at a time, a timeout of 15 s, no retry loops): claim → each item not already
  added on this device (a list of the last 500 ids in `AppGroup.defaults`) becomes a task through
  `IntentActions.addTask(text, group: nil, in:)` after `SpokenTask` (the same parser and save as Siri), on the
  app's main context → ack every id it handled (added, or skipped by the rule; an item it could not save is not
  acked) → status for Settings: last checked, last capture, how many added today, or the error in a person's
  words. A task's reminder from a capture must be scheduled like any other (check `NotificationScheduler` sees it).
- **The key in the Keychain** (generic password, this device only, after first unlock); the origin and the rule in
  `AppGroup.defaults`; a random device id kept there.
- **When it asks**, only while connected: a few seconds after launch (never in `App.init`; nothing slows the first
  frame), when the app comes forward (iPhone: the scene; Mac: `NSApplication.didBecomeActive`, see COMMON on the
  Mac's scene), every 60 s while the Mac app runs (a timer with tolerance; it may nap), in the iPhone's background
  refresh (`HITListApp`'s `.backgroundTask(.appRefresh)`; ask after `WidgetRefresh.run()`), and when the app is
  woken by a remote notification if there is a clean place to hook it. Say in your report how soon a capture
  reaches each device in each state, as far as you could see.
- **Siri's `AddTaskIntent`**: its text goes through `SpokenTask` too.

### 3. Settings → Stream Ring (iPhone and Mac)

A page of its own after Claude (`SettingsPage` in `SettingsView.swift`, the Mac's `MacSettingsSection` and
router): title "Stream Ring", subtitle "Tasks you say to the ring". Its words say nothing about CloudKit, engine,
zone and the rest (`TroubleshootingTests`).

- **Not connected**: one sentence ("Say a task to your Stream ring and it lands here, phone in your pocket. It
  needs a small relay of your own, set up once from a Mac."), a field for the inbox link with Paste, and Connect,
  which asks the relay's status before it says yes ("Connected" or what went wrong, in words).
- **Connected**: the status line ("Connected · last capture 5 min ago · 3 added today"), Check now, Send a test
  capture (then checks), a switch "Only captures that start with 'Task'" (off: every capture is a task; on, the
  others are left in Stream and not added), and Disconnect (asks; removes the key from this device only).
- Behind the troubleshooting gesture only (`Troubleshooting.isRevealed` or what Settings uses since brief 174):
  the relay's `lastFields`, and the device id.
- Each device connects on its own (paste the link on the Mac; on the iPhone, Universal Clipboard pastes the same
  link).

## Bounds

- **Yours**: `relay/stream-inbox/**` (new), `.gitignore`, `HITListCore/Sources/HITListCore/{InboxLink,InboxProtocol,SpokenTask}.swift`
  (new) and their tests, `HITList/Services/Inbox/**` (new), `HITList/Services/Intents/AddTaskIntent.swift`,
  `HITList/HITListApp.swift` and `HITList/Services/Widgets/WidgetRefresh.swift` (the hooks only),
  `HITList/Views/Settings/StreamRingSettingsSection.swift` (new) and the page's entries in `SettingsView.swift`,
  `Settings/Mac/MacSettingsSection.swift`, `MacSettingsPage.swift`, `SettingsRouter.swift`; hosted tests and a UI
  test of your own.
- **Not yours**: the quick-add parser and everything under `HITList/Views/Popouts/` (brief 175 is in them: it adds
  "remind me 30 minutes before", "5 p.m." and friends to the parser, so your tests should use phrases today's
  parser reads), `QuickAddGuide*`, the sync files, `CloudSyncMonitor.swift`, the version, `WhatsNew`,
  `CHANGELOG.md`. No entitlement changes: the Mac app already has `com.apple.security.network.client`; iOS needs
  none for HTTPS. If `http://127.0.0.1` for the local proof needs App Transport Security relaxed, do it for
  Debug builds only, and say so.
- **Never** deploy to Cloudflare, sign in to anything, or create an account: George runs `wrangler login` and
  `setup.sh` himself. Nothing you run reaches his iCloud, his devices or his store: side stores with
  `-disableCloudKit YES` only.
- A simulator of your own named `HITList-176` (iPhone 17) and a derived-data folder of your own
  (`build.noindex/176`); the Mac through `scripts/window-shot.sh` / `window-drive.sh` on your own Debug build with
  a side store (`HITLIST_STORE_SUFFIX=r36-176`, `-disableCloudKit YES`). Delete them when you finish, and stop any
  `wrangler dev` you started. Nobody's phone.

## Proof (yours to make and to look at)

- `relay/stream-inbox/test.sh` passes, run twice from a clean state.
- Core tests for `InboxLink`, `SpokenTask` and the protocol types; hosted tests for `StreamInbox` with a stubbed
  transport (`URLProtocol`): tasks made with their parsed dates, priority and #Group; the ack carries exactly the
  handled ids; an id seen before is not added twice; the "starts with Task" rule; a save that fails is not acked; a
  relay that is down leaves everything for next time and says so in words.
- **The whole path on this Mac**: `wrangler dev --local`, your Debug Mac app on its side store connected to it,
  a webhook signed with `openssl` and posted with `curl` ("Call the dentist tomorrow at 9am p2." with its
  `interaction_id`), and the task in the app's list within a minute without touching the app: a picture of it
  (`scripts/window-shot.sh`). The same on your simulator (it reaches the Mac's `127.0.0.1`).
- Pictures in the notes folder (`round-36/176/`): the page not connected, connected, revealed; iPhone and Mac.
  **Look at every one yourself** (12 pt floors, nothing cut off).
- `SIMULATOR=HITList-176 scripts/test.sh ios`, `scripts/test.sh core macos` green on your tree, and your UI class to
  its last test, before you report.
- Commit each item the moment it is whole. No push, no merge, no `scripts/release.sh`.

## Report

The relay's endpoints as built and what it keeps; George's steps from nothing to a capture in HITList, exactly as
he will run them (every command, every tap in Stream); how soon a capture reaches the Mac and the iPhone in each
state; what is not known about Stream that the first real capture will tell (`lastFields`); tests and their counts
before and after; pictures' folder and count; your branch and commits; your simulator, folder and `wrangler dev`
gone.

## Addendum (2026-11-23, sent to the agent after Sandbar's own help pages were read)

Sandbar's "Set up Stream Webhook" lists **"An active Upstream subscription"** under what you need; the request comes
from the iPhone over its own network, waits 5 s and is **never retried**. "Set up Stream MCP" lists no
subscription: Stream on iOS and an MCP client. So the relay gains George's free path: it **pulls** captures from
Stream's MCP (`https://api.sandbar.com/mcp`: Streamable HTTP, stateless, JSON; OAuth with dynamic client
registration, scopes `stream`/`stream.write`, access token 1 h, refresh token 30 days renewed with use, the
connection ends 90 days after approval; read tool `get_recent_interactions`, "last 7 days by default, up to 100").

- `POST /stream/connect-link` (inbox key) → a one-time `https://…/stream/connect?c=…` (10 minutes) → Stream's sign-in
  → `/stream/callback` keeps the tokens in the Durable Object. The inbox key never goes in a URL.
- A cron trigger every minute polls while connected; interactions go into the same table as the webhook's, one per
  `interaction_id`. The first poll after connecting takes nothing older than the approval (by time, or by
  recording the first poll's ids as seen). A refused refresh or a second 401 means disconnected.
- `GET /inbox/status` gains `stream: {connected, approvedAt, expiresAt, lastPollAt, lastError}`.
- `test.sh` proves the poller against a local fake MCP and OAuth server (no packages). `setup.sh` offers both
  sources and prints the HITList inbox link.
- Settings → Stream Ring says where captures come from, offers "Reconnect Stream…" in the last 14 days or after
  the end, and says to turn Chat off in Stream (Sandbar's own tip: the chat bubble in the Stream tab).
- `POST /stream` stays as built, for a time George has Upstream (a 30-day trial comes with the ring).
