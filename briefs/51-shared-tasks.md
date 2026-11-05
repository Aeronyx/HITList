# Brief 51: Shared Tasks, a careful foundation (branch `shared-tasks`, effort max)

Read `briefs/COMMON.md` (Round 11 block), `briefs/HIG-NOTES.md` (collaboration and sharing) and
https://developer.apple.com/design/human-interface-guidelines/collaboration-and-sharing first. Five sessions run at
the same time.

George's words (2026-11-04 backburner note, and 2026-11-05):

> Group/Shared Tasks (with it's own, forced Shared Tasks tab and tag) would be awesome, so we can post/complete group
> tasks together.

> If logins aren't needed for iCloud, let's avoid a login system altogether, and we'll just use the profile/accounts
> system for Shared Tasks and such. Sounds easier and frictionless.

## Constraints (non-negotiable)
- The existing private store and its sync are George's daily driver and must not change behaviour. Whatever you
  add is isolated from it: its own store file(s), and no second mirror of the same CloudKit zone the SwiftData store
  uses (`com.apple.coredata.cloudkit.zone` in the private database). Read `ModelContainerFactory`, `SyncEnvironment`,
  `SchemaVersions.swift`'s rules and COMMON's CloudKit rules before designing.
- Off by default: a "Shared Tasks (preview)" switch (a row at the top of Browse that opens an explainer with the
  switch, so it needs no Settings file) initialises nothing until it is on. A Release build with it off behaves
  exactly like 0.6.0.
- No login: identity is the Apple account; people appear by their HITList profile (name, picture) where they have
  one, else the name iCloud sharing gives.

## Items (one commit each, failing test first where there is logic)
1. **Research and design, first hour**: what the Xcode 27.1 SDK offers (does SwiftData support CloudKit sharing or a
   shared database scope now? Core Data `NSPersistentCloudKitContainer` with a private + shared store pair and
   `share(_:to:)`, `UICloudSharingController` / `ShareLink` with `CKShare`, `NSSharingService` on the Mac, accepting a
   share via the app/scene delegate). Decide: same CloudKit container in separate zones handled by a separate Core
   Data container (check whether that is safe next to the SwiftData mirror), or a second CloudKit container
   (`iCloud.com.trammells.hitlist.shared`, needs registering: give George the exact steps if Xcode's automatic
   signing cannot). Write the decision, the risks and the record types into your report before building.
2. **Data layer**: shared lists (a Group you share) with tasks, completion state, who completed it and when, and
   members (profile name/picture copied into the share, refreshed when they change it). Owner and participants can
   add, complete, uncomplete, edit; only the owner removes members or stops sharing. Conflict rule: last writer wins
   per field, completion keeps who and when. Tests on in-memory stores.
3. **Sharing flow**: create a shared list from Browse, invite with the system share UI (Messages, Mail, link),
   accept on another device (scene/app delegate `userDidAcceptCloudKitShareWith`), leave, stop sharing; the
   Collaboration-style indicator on a shared list. Mac and iPhone.
4. **Screens**: a Shared screen (list of shared lists, each with its tasks, avatars of members, "completed by Sam"),
   reached from Browse and the Mac sidebar's Browse equivalent (one row; George's "forced Shared Tasks tab" comes
   once George has tried it: list in the report what the tab and the `#shared` tag would take). Use the existing row,
   card and chip components; quick add into a shared list.
5. **Schema**: the new record types reach CloudKit Development through a Debug run (own store suffix, never the real
   store); give George the Production deploy step.
6. **Test plan for George**: you cannot sign in to two Apple accounts. Write the exact steps for George and a friend
   (or two simulators George signs in to two Apple IDs, Debug builds use the Development environment so no real data
   is involved) to try share, accept, add, complete, leave.

## Ownership
New `HITList/Services/Sharing/*`, new `HITList/Views/Shared/*`, a new model/schema of its own (not `Models.swift`,
`SchemaVersions.swift`: session 48 owns those this round), `Services/Sync/SyncAppDelegate.swift` (share acceptance
only), `Views/Tabs/BrowseView.swift` (the preview row and the Shared entry), the Mac sidebar entry as one line in
`SidebarView.swift` (session 49 changes its spacing), `HITList/HITList.entitlements` / `project.yml` /
`HITList-macOS.entitlements` only if a second container is needed (never the development-container key); tests new
`SharedTasksTests`; ROADMAP row "Shared Tasks preview (brief 51)".

## Done
All three suites green; the design and risks; screenshots of the Shared screens in the simulator; the Development
schema push log; the test plan. If the safe architecture turns out to need more than this round, stop at a solid,
switched-off data layer plus the design and say so: that is a fine outcome.
