# Brief 90: "Add to HITList" from the share sheet (session `share-extension`, effort xhigh)

George, 2026-11-11, an hour into round 19:

> I've put you in Max mode to both continue on the roadmap after Round 19 completes and to hopefully create all the
> other creatures before I wake […] Don't rush anything, but please finish what you can by morning.

The roadmap's next item (`dev/ROADMAP.md`, Next, 1):

> **Share extension.** "Add to HITList" from any app's share sheet (a link, selected text) on iPhone and the Mac.
> With widgets it is what the App Group store was moved for on 2026-10-27; it reuses the widget round's extension
> setup.

Read `dev/briefs/COMMON.md` (Round 19 block first), `dev/briefs/ROUND-19.md`, `74-widgets.md` and
`81-widget-completion.md` (how an extension lives beside this app: it never opens the store; it writes a request
into the App Group and the app does the work; a tap is never lost), then `project.yml`'s `HITListWidgets` target
(copy its shape: sources compiled in, entitlements per platform, the version inherited), core's `WidgetOutbox`,
`HITList/Services/Widgets/WidgetCompletionCenter.swift` and `WidgetRefresh.swift`, `HITList/Services/Intents/*`
(`AddTaskIntent` is Siri's road to a new task), `TaskActions`, and the quick-add card
(`HITList/Views/Popouts/QuickAddPopout.swift`) for how adding a task looks and reads phrases.

## The rules
1. **Never lost** (George's principle: data resilience over speed; slow is fine, wrong is not). Pressing Add
   writes the request to disk in the App Group (an outbox of the widget outbox's kind: one file per request,
   written atomically, a request id) before the sheet closes. From then on it survives the extension being killed,
   the app not running, a reboot.
2. **The app makes the task.** The extension never opens the store (it mirrors to CloudKit; a second process must
   not touch it). The app turns each request into a task by the road quick add uses (the same parser, the same
   `TaskActions` call, so "Read this tomorrow p1 #Work" becomes what it would in the app) at launch, on activation,
   in the background refresh, and at once when it is running (the Mac: ring a bell as `WidgetOutboxBell` does).
   Once per request however often it is delivered; a damaged file is set aside and logged, never retried forever.
3. **The sheet tells the truth.** After Add: a tick and "Saved. It will be in your Inbox when HITList next opens."
   (or simply "Added to your Inbox" where you can prove the running app has taken it). Never a claim the store
   has not earned.
4. **What can be shared**: a web page (its address and title), a link, selected text, plain text. One item.
   Images and files are not offered this round (the activation rule accepts addresses and text only), so HITList
   does not appear where it cannot help.
5. **What the person sees**: a small card in HITList's own look, never the system's compose sheet: the person's
   theme (the App Group's defaults, as the widgets read it), Inter, the design system's controls compiled in. The
   title, prefilled (the page's title, or the text's first line) and focused with the keyboard up; the address
   and any selected text beneath, as they will be kept in the task's notes; one quiet line showing what quick-add
   phrases in the title will become (core's parser: the date, the priority, the Group); Add in the accent, and
   Cancel. Return adds. Long text is kept whole in the notes up to a sensible limit you choose and state.
6. **iPhone, iPad and the Mac**, one extension target for all three as the widgets are (the Mac's Share menu in
   Safari and anywhere text is selected). Its name in the share sheet is "HITList".
7. **Private**: the App Group and nothing else; no network, no iCloud, sandboxed on the Mac; the app's privacy
   manifest; one sentence for the privacy page.
8. **Testable without George's data**: a Debug build made with the widgets' side-store suffix writes to that side
   store's outbox, as the widget extension reads its side snapshot.

## Items (one commit each, failing test first where there is logic)
1. **The outbox** in core (reuse what `WidgetOutbox` has; do not change what it does for the widgets) and its
   tests: durable, once only, ordered, a damaged file, a request with no title, very long text.
2. **The app's side** (`HITList/Services/Share/*`): draining at launch, on activation, on the bell, in the
   background refresh; the quick-add road; tests with an in-memory container for every ending (the app killed
   between the write and the drain, delivered twice, the Group it names does not exist, the store unavailable).
3. **The target** in `project.yml`, embedded in the app, entitlements for each platform, the version inherited,
   the activation rule, the Info.plist; `xcodegen generate`.
4. **The card**, iPhone and iPad, then the Mac.
5. **Seen working**: in your own simulator, Safari → Share → HITList → Add → open HITList → the task is in the
   Inbox with its link (a UI test of your own if XCUITest can drive the share sheet; say what it could not). On
   the Mac, as far as you can drive Safari's Share menu on a Debug build without answering any system dialog; say
   exactly what you could not see. Unregister your Debug build's extensions when you finish (`pluginkit -r`).
6. **Packaging**: a Release archive and export of both platforms (no upload, never `scripts/release.sh`) with the
   extension inside, its entitlements pasted, and the list of checks `scripts/release.sh` should make for it (the
   supervisor adds them, as it did for the widgets).

## Ownership
A new `HITListShare/*`; a new core file for the outbox; a new `HITList/Services/Share/*`; one start-up line in
`HITList/HITListApp.swift` and one drain line in `HITList/Services/Widgets/WidgetRefresh.swift`; `project.yml`
(the new target and the lines that embed it; other sessions edit other lines tonight); one sentence in the
privacy page under `docs/` (brief 83 edits its location section: touch only your own sentence); new tests
(`Share*Tests`), a UI test file of your own.
Not yours: `TaskActions` and the parser (call them; brief 82 is changing how dates are written, so pass dates
through untouched), every Settings view (86), `Services/Weather/*` (83), `Support/Companions/*` and
`Views/Companions/*` (84, 85, 87 to 89), `HITListWidgets/*` and `WidgetOutbox`'s behaviour, the models (no schema
change), `scripts/`, `dev/ROADMAP.md`, `CHANGELOG.md`, `WhatsNew.swift`.

## How to work tonight
Nine sessions share one saturated Mac (swap is full). Run no baseline suite; prefer `-only-testing` while you
iterate; boot your simulator (`HITList-90`) only when you need it; run the three suites once, at the end. Nobody
answers questions or system dialogs tonight: decide by this brief and write down what you decided.

## Done
The table of endings and the test that pins each. Screenshots of the card on iPhone, iPad and the Mac, and of
the task it made. Which process did what, proved. The archive and export proof and the release checks to add.
What still depends on the app being opened, in words George can repeat to a friend. All three suites green. The
branch name, changelog lines in plain words, every decision George might want to reverse.
