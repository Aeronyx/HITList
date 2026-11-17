# 157: the task card and the actions behind it: what can crash, and what an undo or a move silently drops (code)

Round 32's reviews 152, 151 and 155. The reports are in the notes folder: `round-32/152-crash-concurrency-review/
REPORT.md`, `151-data-safety-review/REPORT.md`, `155-privacy-security-review/REPORT.md`. Each fix with a test written
first and seen to fail, where a test can reach it.

**Yours**: `HITList/Views/Popouts/`, `HITList/Services/TaskActions.swift` (not its `seed…` functions),
`HITList/Services/Spotlight/SpotlightSync.swift`, `HITList/Services/Intents/IntentStore.swift`,
`HITList/Services/Weather/CoreLocationSource.swift`, `HITList/Views/Flipboard/SwitchCard.swift`,
`SwitchboardCard.swift`, `FlipboardRules.swift` (the undo record only), core's `ClaudeAccess.swift` if finding 7 needs
it. **Not yours**: the list views (`TaskListView`, `InboxView`, `UpcomingView`, `Search/`, `SidebarView`, `BrowseView`:
agent 158 is rewriting their queries; where a finding names a call site there, make the fix inside the popout or
the action so the call site need not change), the editors of Groups, labels and filters and `Deduplicator` (agent
156), anything under `HITList/Services/SyncEngine/`.

1. **Spotlight indexing reads task models after awaiting** (152 finding 1): turn the models into values before the
   first await.
2. **Delayed deletes and completions carry the model, not its id** (152 finding 4): after the delay, fetch by id and
   act on what comes back; `closeTaskIfDeleted` clears `pendingDelete`.
3. **The switch and Switchboard cards save into the model they opened with** (152 finding 2's "same shape"): keep the
   id, fetch on Save, close with one line if it is gone.
4. **A task's typed title or description is lost if iOS ends the app with its card open** (151 B9): commit, without
   closing or confirming, when the scene goes to the background.
5. **Undo of a repeating task's completion loses its reminder and the checklist's ticks** (151 B6): record both and
   put both back, as `RowFlip` does for switches.
6. **Moving a task to Shared Tasks silently drops what a shared task cannot hold** (151 B7): one confirmation that
   names what will stay behind, only when the task has any of it.
7. **Nesting a task that carries the label hidden from Claude under a visible task shows it to Claude** (155 finding
   2): the smallest rule that keeps the promise ("All tasks but @private" never shows a task the person marked
   private, wherever it sits) and say which you chose.
8. **On the in-memory fallback Siri and Shortcuts say "Added" for a task that is gone at quit** (151 B10):
   `IntentStore` throws plain words while the app runs on the fallback.
9. **The delete question does not mention sub-tasks** (151 C13). **The wait for location permission has no end**
   (152 finding 6): the timeout `approximateLocation` has.
10. **A description has no limit** (151 A4): `TaskLimits.clampedNotes` (on master) where the card commits its draft.

Proof: the Mac's hosted tests for the classes you touched and the whole of `HITListTests` once at the end
(`-derivedDataPath build.noindex/157`); for 4, 6 and 9 a look at the running app (a simulator of your own,
`HITList-157`, an iPhone 16; or the Debug Mac app on a side store), pictures in your notes folder; the popouts' own
UI tests on your simulator (`-scheme HITListUITests -only-testing:HITListUITests/…`: say which you ran). Words a
person reads are plain and short; text keeps 12 pt from a card's edge.
