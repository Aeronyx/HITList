import SwiftUI
import SwiftData
import HITListCore

// Settings → iCloud on HITList's own engine (round 28, brief 144): the status, "Sync now", what is waiting and when
// the last fetch and send ended, a hold's own group with its buttons, the items iCloud refused, and (Debug builds on
// a side store only) the switch between the engines. Everything here reads `SyncEngineBoard` and asks it; nothing
// here runs the engine. On the mirror none of it shows, except the Debug switch.

/// The Sync group's rows under the status line while the engine syncs (`ICloudSyncGroup`): "Sync now", what is
/// waiting, when the last fetch and accepted send ended, and the items iCloud refused for good.
struct SyncEngineStatusRows: View {
    private var board: SyncEngineBoard { .shared }
    @State private var isSyncing = false
    @State private var message: String?

    var body: some View {
        let status = board.status
        HITMenuRow("Sync now", subtitle: Self.syncNowSubtitle, systemImage: "arrow.triangle.2.circlepath",
                   iconTint: Theme.accent, accessory: .none) { syncNow() }
            .disabled(isSyncing || board.actions == nil)
            .accessibilityIdentifier("settings-engine-sync-now")
        if let message {
            SettingsMessage(text: message)
                .padding(.leading, HITRowMetrics.titleInset)
                .accessibilityIdentifier("settings-engine-sync-now-message")
        }
        HITMenuRow("Waiting to go", systemImage: "icloud.and.arrow.up", value: Self.waitingValue(status))
            .accessibilityIdentifier("settings-engine-waiting")
        // One row each, so the group draws its separator between them; each ages every 30 s, as "Last change" does.
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            HITMenuRow("Last received", systemImage: "icloud.and.arrow.down",
                       value: Self.when(status?.lastFetchEnded, now: tick.date))
        }
        .accessibilityIdentifier("settings-engine-last-fetch")
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            HITMenuRow("Last sent", systemImage: "checkmark.icloud",
                       value: Self.when(status?.lastSendEnded, now: tick.date))
        }
        .accessibilityIdentifier("settings-engine-last-send")
        if let status, !status.refused.isEmpty {
            SyncEngineRefusedRows(keys: status.refused)
        }
    }

    static let syncNowSubtitle = "Fetches what changed in iCloud, then sends this device's changes"

    /// "3 changes", "1 change", "Nothing".
    static func waitingValue(_ status: SyncStatus?) -> String {
        guard let status, status.waiting > 0 else { return "Nothing" }
        return status.waiting == 1 ? "1 change" : "\(status.waiting) changes"
    }

    /// "3 min ago", "Not yet".
    static func when(_ date: Date?, now: Date) -> String {
        date.map { SyncState.relative($0, now: now) } ?? "Not yet"
    }

    private func syncNow() {
        guard let actions = board.actions, !isSyncing else { return }
        isSyncing = true
        message = "Asking iCloud…"
        Task { @MainActor in
            defer { isSyncing = false }
            do {
                try await actions.syncNow()
                message = "Done."
            } catch {
                message = "Nothing was synced: \(SyncEngineWords.error(error))"
            }
        }
    }
}

/// Items iCloud refused for good (too large, or rejected), by name: kept out of what is sent until they change.
struct SyncEngineRefusedRows: View {
    let keys: [SyncKey]
    @Environment(\.modelContext) private var context

    var body: some View {
        let names = keys.map { SyncEngineWords.name(of: $0, in: context) }
        HITMenuRow(SyncEngineWords.refusedTitle(keys.count), subtitle: SyncEngineWords.refusedNote,
                   systemImage: "exclamationmark.icloud", iconTint: HITColor.dueTomorrow)
            .accessibilityIdentifier("settings-engine-refused")
        SettingsNote(text: names.joined(separator: "\n"))
            .accessibilityIdentifier("settings-engine-refused-names")
    }
}

/// A hold's own group, with what each button will do said before it is pressed. Shown only while the engine holds
/// for something other than a sign-out (that one is today's signed-out state, on the Account row and the banner).
struct SyncEngineHoldGroup: View {
    private var board: SyncEngineBoard { .shared }
    @State private var confirmDeletions = false
    @State private var confirmKeep = false
    @State private var confirmRemove = false
    @State private var isBusy = false
    @State private var message: String?
    @State private var showReopenAlert = false

    var body: some View {
        if let hold = board.status?.hold, hold != .noAccount {
            let waiting = board.status?.waiting ?? 0
            // The hold's own words are the status line's, just above; the group says what stands still and what each
            // button will do.
            HITGroup(SyncEngineWords.holdTitle(hold)) {
                HITMenuRowLabel(SyncEngineWords.holdNote(hold, waiting: waiting),
                                systemImage: SyncEngineWords.needsYou(hold) ? "exclamationmark.icloud" : "arrow.triangle.2.circlepath.icloud",
                                iconTint: SyncEngineWords.needsYou(hold) ? HITColor.dueOverdue : Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hitRowPadding()
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings-engine-hold")
                buttons(for: hold)
                if let message {
                    SettingsMessage(text: message)
                        .padding(.leading, HITRowMetrics.titleInset)
                        .accessibilityIdentifier("settings-engine-hold-message")
                }
            }
            .disabled(isBusy)
            .confirmationDialog(SyncEngineWords.confirmDeletionsQuestion(hold), isPresented: $confirmDeletions,
                                titleVisibility: .visible) {
                Button("Delete from iCloud", role: .destructive) { run { try await $0.confirmDeletions() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SyncEngineWords.confirmDeletionsMessage)
            }
            .confirmationDialog("Keep them in iCloud?", isPresented: $confirmKeep, titleVisibility: .visible) {
                Button("Download them again") { run { try await $0.restore() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SyncEngineWords.keepMessage)
            }
            .confirmationDialog("Remove from this device too?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Save a backup and remove", role: .destructive) { run { try await $0.answerPurge(.removeHere) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SyncEngineWords.removeMessage)
            }
            .alert("Quit and reopen HITList to finish", isPresented: $showReopenAlert) {
                Button("OK") {}
            } message: {
                Text(SyncEngineWords.reopenMessage)
            }
        }
    }

    @ViewBuilder
    private func buttons(for hold: SyncHold) -> some View {
        switch hold {
        case .massDeletion:
            HITMenuRow("I deleted them", subtitle: SyncEngineWords.deletedThemSubtitle, systemImage: "trash",
                       role: .destructive, accessory: .none) { confirmDeletions = true }
                .accessibilityIdentifier("settings-engine-deleted-them")
            HITMenuRow("Keep them in iCloud", subtitle: SyncEngineWords.keepSubtitle, systemImage: "arrow.counterclockwise",
                       iconTint: Theme.accent, accessory: .none) { confirmKeep = true }
                .accessibilityIdentifier("settings-engine-keep")
        case .zonePurged:
            HITMenuRow("Remove from this device too", subtitle: SyncEngineWords.removeSubtitle, systemImage: "trash",
                       role: .destructive, accessory: .none) { confirmRemove = true }
                .accessibilityIdentifier("settings-engine-remove-here")
            HITMenuRow("Keep here and send to iCloud again", subtitle: SyncEngineWords.sendAgainSubtitle,
                       systemImage: "icloud.and.arrow.up", iconTint: Theme.accent, accessory: .none) {
                run { try await $0.answerPurge(.keepAndSendAgain) }
            }
            .accessibilityIdentifier("settings-engine-send-again")
        case .storageFull, .failed:
            HITMenuRow("Try again", subtitle: SyncEngineWords.tryAgainSubtitle(hold), systemImage: "arrow.clockwise",
                       iconTint: Theme.accent, accessory: .none) {
                run { actions in
                    await actions.resume()
                    // A try that changed nothing says so, and what is left to try (146's finding 6: a memory that
                    // can't be read stays held until the next start).
                    if SyncEngineBoard.shared.status?.hold == hold { message = SyncEngineWords.stillHeld }
                }
            }
            .accessibilityIdentifier("settings-engine-try-again")
        case .needsUpdate, .duplicates, .noAccount:
            // Nothing to press: an update, or HITList tidying up by itself.
            EmptyView()
        }
    }

    /// Runs one of the board's actions, its error in words under the buttons.
    private func run(_ action: @escaping @MainActor (SyncEngineBoard.Actions) async throws -> Void) {
        guard let actions = board.actions, !isBusy else {
            message = SyncEngineWords.notWired
            return
        }
        isBusy = true
        message = nil
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await action(actions)
            } catch {
                message = "Nothing changed: \(SyncEngineWords.error(error))"
            }
        }
    }
}

/// The switch between the engines, for Debug builds on a side store only this round. Showing it to testers is George's
/// decision (`dev/SYNC-ENGINE.md` section 12): until he says so it is hidden in every other build, the real store
/// included.
struct SyncEngineSwitchGroup: View {
    private var board: SyncEngineBoard { .shared }
    @State private var confirmMove = false
    @State private var isMoving = false
    @State private var message: String?

    /// Debug builds, a side store (never HITList.store).
    static var isShown: Bool {
        #if DEBUG
        return !ModelContainerFactory.isMainStoreOpen
        #else
        return false
        #endif
    }

    static let title = "Sync engine"
    static let footer = "Debug builds on a side store only."

    var body: some View {
        let target: SyncEngineBoard.Engine = board.engine == .own ? .mirror : .own
        HITGroup(Self.title, footer: Self.footer) {
            HITMenuRow("Sync engine", systemImage: "gearshape.2", value: SyncEngineWords.engineName(board.engine))
                .accessibilityIdentifier("settings-engine-switch")
            SettingsNote(text: SyncEngineWords.moveNote)
            HITMenuRow(SyncEngineWords.moveTitle(to: target), subtitle: board.actions == nil ? SyncEngineWords.notWired : nil,
                       systemImage: "arrow.left.arrow.right", iconTint: Theme.accent, accessory: .none) { confirmMove = true }
                .disabled(board.actions == nil || isMoving)
                .accessibilityIdentifier("settings-engine-move")
            if let message {
                SettingsMessage(text: message)
                    .padding(.leading, HITRowMetrics.titleInset)
                    .accessibilityIdentifier("settings-engine-move-message")
            }
        }
        .confirmationDialog("\(SyncEngineWords.moveTitle(to: target))?", isPresented: $confirmMove, titleVisibility: .visible) {
            Button(SyncEngineWords.moveTitle(to: target)) { move(to: target) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SyncEngineWords.moveNote)
        }
    }

    private func move(to target: SyncEngineBoard.Engine) {
        guard let actions = board.actions, !isMoving else { return }
        isMoving = true
        message = nil
        Task { @MainActor in
            defer { isMoving = false }
            do {
                try await actions.move(target)
            } catch {
                message = "Nothing moved: \(SyncEngineWords.error(error))"
            }
        }
    }
}

/// The words of the engine's settings, in one place so they can be tested.
enum SyncEngineWords {
    /// Red holds: the ones a person must act on (`dev/SYNC-ENGINE.md` section 10). Not a sign-out (today's signed-out
    /// state), not tidying up.
    static func needsYou(_ hold: SyncHold) -> Bool {
        switch hold {
        case .massDeletion, .zonePurged, .needsUpdate, .storageFull, .failed: true
        case .noAccount, .duplicates: false
        }
    }

    static func holdTitle(_ hold: SyncHold) -> String {
        switch hold {
        case .massDeletion: "Items missing from this device"
        case .zonePurged: "Removed from iCloud"
        case .needsUpdate: "Update HITList"
        case .storageFull: "iCloud is full"
        case .failed: "Sync stopped"
        case .duplicates: "Tidying up"
        case .noAccount: "Not signed in"
        }
    }

    /// What stands still and why, in the hold's group (the hold's own words are the status line's).
    static func holdNote(_ hold: SyncHold, waiting: Int = 0) -> String {
        switch hold {
        case .massDeletion:
            return "HITList stopped sending and receiving, so that a device that reads empty by mistake can't empty iCloud "
                + "for every device. If they come back here, sync starts again by itself."
        case .zonePurged:
            return "Nothing has been deleted on this device. Nothing is sent or received until you choose."
        case .needsUpdate:
            return "Nothing is sent or received until this device runs the newer HITList, from TestFlight or the App Store."
        case .storageFull:
            #if os(macOS)
            let where_ = "System Settings → your name → iCloud"
            #else
            let where_ = "Settings → your name → iCloud"
            #endif
            let kept = waiting == 0 ? "Nothing is lost." : "Nothing is lost: what is waiting stays waiting."
            return "\(kept) Free up space in \(where_), then try again."
        case .failed:
            return "HITList couldn't read or write what it keeps on this device for sync. Nothing was sent or deleted."
        case .duplicates:
            return "Nothing to do: HITList merges them, then sync starts again by itself."
        case .noAccount:
            return ""
        }
    }

    static let deletedThemSubtitle = "iCloud deletes them too, on every device"
    static let keepSubtitle = "Puts back on this device what iCloud holds; nothing is deleted anywhere"
    static let removeSubtitle = "Saves a backup first, then what came from iCloud leaves this device"
    static let sendAgainSubtitle = "Everything on this device goes back to iCloud"

    static func tryAgainSubtitle(_ hold: SyncHold) -> String {
        if case .storageFull = hold { return "Sends what is waiting, once iCloud has room" }
        return "Reads this device's items and HITList's sync records again"
    }

    static func confirmDeletionsQuestion(_ hold: SyncHold) -> String {
        guard case .massDeletion(let count) = hold else { return "Delete them from iCloud?" }
        return count == 1 ? "Delete 1 item from iCloud?" : "Delete \(count) items from iCloud?"
    }

    static let confirmDeletionsMessage = "They are deleted on every device signed in to this iCloud account. "
        + "Everything else stays as it is."
    static let keepMessage = "HITList puts back on this device everything iCloud holds, and sync starts again. "
        + "Nothing is deleted, here or in iCloud."
    static let removeMessage = "HITList saves a backup first (iCloud & data → Backups), then removes what came from "
        + "iCloud from this device. Items made here that iCloud never had are kept."

    #if os(macOS)
    static let resetActionTitle = "Reset and Relaunch"
    static let reopenMessage = "HITList couldn't relaunch itself. Quit it and open it again to download a fresh copy."
    #else
    static let resetActionTitle = "Reset"
    static let reopenMessage = "Swipe HITList away in the app switcher, then open it again. It downloads a fresh copy "
        + "from iCloud when it starts."
    #endif

    #if os(macOS)
    static let stillHeld = "Tried again; it didn't help yet. Quitting and reopening HITList tries again from the start."
    #else
    static let stillHeld = "Tried again; it didn't help yet. Swiping HITList away and opening it again tries again from the start."
    #endif

    /// The board's actions are wired by the side that runs the engine; a build without them can only show.
    static let notWired = "Needs a build that runs the engine"

    static func engineName(_ engine: SyncEngineBoard.Engine) -> String {
        engine == .own ? "HITList's own" : "iCloud's mirror"
    }

    static func moveTitle(to engine: SyncEngineBoard.Engine) -> String {
        engine == .own ? "Move to HITList's own" : "Move back to iCloud's mirror"
    }

    static let moveNote = "Moving saves a backup, merges items saved twice and reopens this device's tasks under the "
        + "other engine, then HITList relaunches. Devices on different engines don't see each other's changes until "
        + "they have all moved."

    static func refusedTitle(_ count: Int) -> String {
        count == 1 ? "1 item couldn't go to iCloud" : "\(count) items couldn't go to iCloud"
    }

    static let refusedNote = "iCloud refused them for good (too large, or rejected). Change one and HITList sends it again."

    /// A refused item by its name on this device: "Task “Buy milk”"; "A task no longer on this device".
    @MainActor
    static func name(of key: SyncKey, in context: ModelContext) -> String {
        let kind = kindName(key.type)
        guard let id = UUID(uuidString: key.name) else { return "\(kind.capitalizedFirst) (\(key.name))" }
        let found: String?
        switch key.type {
        case TaskItem.syncType.name:
            found = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })))?.first?.title
        case Project.syncType.name:
            found = (try? context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })))?.first?.name
        case TaskLabel.syncType.name:
            found = (try? context.fetch(FetchDescriptor<TaskLabel>(predicate: #Predicate { $0.id == id })))?.first?.name
        case SavedFilter.syncType.name:
            found = (try? context.fetch(FetchDescriptor<SavedFilter>(predicate: #Predicate { $0.id == id })))?.first?.name
        case Switchboard.syncType.name:
            found = (try? context.fetch(FetchDescriptor<Switchboard>(predicate: #Predicate { $0.id == id })))?.first?.name
        default:
            found = nil
        }
        guard let found else { return "A \(kind) no longer on this device" }
        return "\(kind.capitalizedFirst) “\(found)”"
    }

    static func kindName(_ type: String) -> String {
        switch type {
        case "TaskItem": "task"
        case "Project": "Group"
        case "TaskLabel": "label"
        case "SavedFilter": "filter"
        case "Switchboard": "switchboard"
        case "Profile": "profile"
        default: "item"
        }
    }

    /// An action's error in words.
    static func error(_ error: Error) -> String {
        if let core = error as? SyncCoreError {
            switch core {
            case .held(let hold): return SyncWords.engineHold(hold, waiting: 0)
            case .notStarted: return "the engine hasn't started yet; try again in a moment."
            case .noQuestion: return "iCloud isn't asking that any more."
            case .noBackup: return "no backup could be written, so nothing was removed."
            }
        }
        return error.localizedDescription
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#if DEBUG
/// `-syncEngineDemo <state>` (Debug builds, side stores only): the engine's marks with a made-up status, so the bolt
/// and Settings → iCloud can be seen and tested in every state without an engine (`SyncEngineBoard.show`). Applied when
/// the store is ready and again when the first bolt appears, so it stands whatever the launch said before it.
/// The buttons' actions only write a line to the sync log.
@MainActor
enum SyncEngineDemo {
    static let key = "syncEngineDemo"
    static let names = ["synced", "waiting3", "checking", "mass248", "purged", "update", "full12", "failed", "refused2",
                        "signedout"]

    static var requested: String? {
        guard let name = UserDefaults.standard.string(forKey: key), names.contains(name) else { return nil }
        return name
    }

    /// Two of the store's own tasks for `refused2`, so the iCloud page names real items (looked for again at the
    /// second call, once the store may have been seeded); made up, and kept, when there are none.
    private static var refusedKeys: [SyncKey] = []
    private static var madeUpKeys = [SyncKey(type: "TaskItem", name: UUID().uuidString),
                                     SyncKey(type: "TaskItem", name: UUID().uuidString)]
    private static weak var container: ModelContainer?

    static func applyIfRequested(container: ModelContainer?) {
        guard let name = requested, !ModelContainerFactory.isMainStoreOpen else { return }
        if let container { self.container = container }
        if refusedKeys.count < 2, let store = self.container {
            var descriptor = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.title)])
            descriptor.fetchLimit = 2
            let tasks = (try? store.mainContext.fetch(descriptor)) ?? []
            refusedKeys = tasks.map { SyncKey(type: TaskItem.syncType.name, name: $0.id.uuidString) }
        }
        let keys = refusedKeys.count == 2 ? refusedKeys : madeUpKeys
        guard let status = status(name, now: Date(), refused: keys) else { return }
        SyncEngineBoard.shared.show(status, engine: .own, actions: actions)
    }

    /// The made-up status for each name.
    static func status(_ name: String, now: Date, refused: [SyncKey]) -> SyncStatus? {
        let fetched = now.addingTimeInterval(-20)
        let sent = now.addingTimeInterval(-50)
        switch name {
        case "synced":
            return SyncStatus(state: .idle, waiting: 0, firstFetchDone: true, lastFetchEnded: fetched, lastSendEnded: sent)
        case "waiting3":
            return SyncStatus(state: .idle, waiting: 3, firstFetchDone: true, lastFetchEnded: fetched, lastSendEnded: sent)
        case "checking":
            return SyncStatus(state: .fetching, waiting: 0, firstFetchDone: false)
        case "mass248":
            return SyncStatus(state: .held(.massDeletion(248)), waiting: 0, firstFetchDone: true, lastFetchEnded: fetched,
                              lastSendEnded: sent)
        case "purged":
            return SyncStatus(state: .held(.zonePurged), waiting: 0, firstFetchDone: true, lastFetchEnded: fetched,
                              lastSendEnded: sent)
        case "update":
            return SyncStatus(state: .held(.needsUpdate), waiting: 0, firstFetchDone: true, lastFetchEnded: fetched,
                              lastSendEnded: sent)
        case "full12":
            return SyncStatus(state: .held(.storageFull), waiting: 12, firstFetchDone: true, lastFetchEnded: fetched,
                              lastSendEnded: sent)
        case "failed":
            return SyncStatus(state: .held(.failed("this device's sync records could not be read")), waiting: 0,
                              firstFetchDone: true, lastFetchEnded: fetched, lastSendEnded: sent)
        case "refused2":
            let first = refused.first.map { "\($0): too large" }
            return SyncStatus(state: .idle, waiting: 0, firstFetchDone: true, lastFetchEnded: fetched, lastSendEnded: sent,
                              refused: refused, refusal: first)
        case "signedout":
            return SyncStatus(state: .held(.noAccount), waiting: 0, firstFetchDone: true, lastFetchEnded: fetched,
                              lastSendEnded: sent)
        default:
            return nil
        }
    }

    private static var actions: SyncEngineBoard.Actions {
        func note(_ what: String) { CloudSyncMonitor.shared.write(.note, "Engine demo: \(what) pressed; nothing ran") }
        return SyncEngineBoard.Actions(
            syncNow: { note("Sync now") },
            resume: { note("Try again") },
            answerPurge: { note("Purge answer \($0.rawValue)") },
            confirmDeletions: { note("I deleted them") },
            restore: { note("Keep them in iCloud") },
            move: { _ in
                note("Move")
                throw DemoError()
            })
    }

    struct DemoError: LocalizedError {
        var errorDescription: String? { "this is the demo of the engine's marks; nothing moves." }
    }
}
#endif
