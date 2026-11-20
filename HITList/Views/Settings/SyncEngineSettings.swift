import SwiftUI
import SwiftData
import HITListCore

// Settings → iCloud on HITList's own engine (round 28, brief 144): the status, "Sync now", what is waiting, a hold's
// own group with its buttons, the items iCloud refused, and (in the troubleshooting group only) when the last fetch
// and send ended and the switch between the engines. Everything here reads `SyncEngineBoard` and asks it; nothing
// here runs the engine. On the mirror none of it shows, except the Debug switch.

/// The Sync group's rows under the status line while the engine syncs (`ICloudSyncGroup`): "Sync now", what is
/// waiting while something is, and the items iCloud refused for good. When the last fetch and send ended is for
/// troubleshooting (`SyncEngineTimesRows`, round 35).
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
        if Self.showsWaiting(status) {
            HITMenuRow("Waiting to go", systemImage: "icloud.and.arrow.up", value: Self.waitingValue(status))
                .accessibilityIdentifier("settings-engine-waiting")
        }
        if let status, !status.refused.isEmpty {
            SyncEngineRefusedRows(keys: status.refused)
        }
    }

    static let syncNowSubtitle = "Fetches what changed in iCloud, then sends this device's changes"

    /// "Waiting to go" shows only while something waits (round 35: "Nothing" told a person nothing).
    static func showsWaiting(_ status: SyncStatus?) -> Bool { (status?.waiting ?? 0) > 0 }

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

/// When the engine's last fetch and accepted send ended, in the troubleshooting group: one row each, so the group
/// draws its separator between them; each ages every 30 s, as "Last change" does.
struct SyncEngineTimesRows: View {
    private var board: SyncEngineBoard { .shared }

    var body: some View {
        let status = board.status
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            HITMenuRow("Last received", systemImage: "icloud.and.arrow.down",
                       value: SyncEngineStatusRows.when(status?.lastFetchEnded, now: tick.date))
        }
        .accessibilityIdentifier("settings-engine-last-fetch")
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            HITMenuRow("Last sent", systemImage: "checkmark.icloud",
                       value: SyncEngineStatusRows.when(status?.lastSendEnded, now: tick.date))
        }
        .accessibilityIdentifier("settings-engine-last-send")
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
        case .zonePurged:
            HITMenuRow("Remove from this device too", subtitle: SyncEngineWords.removeSubtitle, systemImage: "trash",
                       role: .destructive, accessory: .none) { confirmRemove = true }
                .accessibilityIdentifier("settings-engine-remove-here")
            HITMenuRow("Keep here and send to iCloud again", subtitle: SyncEngineWords.sendAgainSubtitle,
                       systemImage: "icloud.and.arrow.up", iconTint: Theme.accent, accessory: .none) {
                run { try await $0.answerPurge(.keepAndSendAgain) }
            }
            .accessibilityIdentifier("settings-engine-send-again")
        case .storageFull, .iCloudNotReady, .failed:
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

/// The switch between the engines (`dev/SYNC-ENGINE.md` section 14, stage 5), as rows of the "For troubleshooting"
/// group (`TroubleshootingGroup`, round 35): which sync the device is on, George's word for his friends' devices, and
/// the row that moves the store with its note. From 0.9.14 it is in every build and hidden: it shows only where the
/// troubleshooting rows were revealed (seven taps on About's Version row, `SevenTaps`) and in a Debug build on a side
/// store. A device on the new sync that was never revealed no longer shows any of it (round 35; round 34 had it
/// "telling only"): what a friend needs of the move made by itself is in the Sync group (`AutoMoveRows`).
struct SyncEngineSwitchRows: View {
    private var board: SyncEngineBoard { .shared }
    @State private var confirmMove = false
    /// George's word, as iCloud answered when the rows appeared.
    @State private var everyone: SyncEngineAutoMove.Word = .notAsked
    @State private var isMoving = false
    @State private var message: String?
    /// The engine the store opens on next, re-read after each move (a move on the iPhone waits for a reopen).
    @State private var next = SyncEngineSwitch.nextEngine()

    /// Whether the rows that act (the move, its cancel, George's word) show: where the rows were revealed by hand, or
    /// a Debug build on a side store. A waiting move keeps its row whatever else, so it can be cancelled where it was
    /// asked for.
    nonisolated static func showsTheSwitch(revealed: Bool, isDebugSideStore: Bool, waiting: Bool = false) -> Bool {
        revealed || isDebugSideStore || waiting
    }

    /// Debug builds, a side store (never HITList.store).
    static var isDebugSideStore: Bool {
        #if DEBUG
        return !ModelContainerFactory.isMainStoreOpen
        #else
        return false
        #endif
    }

    /// Whether the rows ask iCloud for George's word: never where nothing may talk to iCloud (a launch with iCloud
    /// switched off, as every UI test is; the in-memory fallback).
    static var asksForTheWord: Bool {
        !AppGroup.defaults.bool(forKey: "disableCloudKit") && !ModelContainerFactory.isRunningInMemory
    }

    /// Whether a move asked for by hand waits for the app to be reopened (one made by the app itself says so in the
    /// Sync group): the troubleshooting group then stays, so it can be cancelled.
    @MainActor
    static var handMoveWaits: Bool {
        let pending = SyncEngineSwitch.pendingMove(current: SyncEngineSwitch.current, preferred: SyncEngineSwitch.nextEngine(),
                                                   byArgument: SyncEngineSwitch.launchedByArgument)
        return pending != nil && SyncEngineAutoMove.Runner.shared?.line == nil
    }

    var body: some View {
        let running = board.engine
        // A move asked for and waiting for a reopen can be taken back: the button then offers the engine that runs.
        // Judged by the store's preference against the engine this launch was opened on, never by what the board
        // shows (the Debug demo of the engine's marks shows an engine that is not running).
        let pending = SyncEngineSwitch.pendingMove(current: SyncEngineSwitch.current, preferred: next,
                                                   byArgument: SyncEngineSwitch.launchedByArgument)
        let waiting = pending != nil
        let target: SyncEngineBoard.Engine = waiting ? SyncEngineSwitch.current : (running == .own ? .mirror : .own)
        let revealed = SyncEngineSwitch.isSwitchRevealed()
        let acts = Self.showsTheSwitch(revealed: revealed, isDebugSideStore: Self.isDebugSideStore, waiting: waiting)
        // A move made by hand that waits on a side store says how to finish it; everywhere else the app finishes it.
        let byItself = SyncEngineAutoMove.Runner.shared?.line != nil
        HITMenuRow("Syncs through", systemImage: "gearshape.2", value: SyncEngineWords.engineName(running))
            .accessibilityIdentifier("settings-engine-switch")
        // George's word as iCloud holds it now (`SyncEngineAutoMove` R0), asked when the rows appear: on his own
        // device he sees that the record he made in the CloudKit Console reads as he meant it.
        if Self.asksForTheWord, Self.showsTheSwitch(revealed: revealed, isDebugSideStore: Self.isDebugSideStore) {
            HITMenuRow(SyncEngineWords.everyoneTitle, subtitle: SyncEngineWords.everyoneValue(everyone),
                       systemImage: "person.3")
                .accessibilityIdentifier("settings-engine-everyone")
                .task { everyone = await CloudKitWord().ask() }
        }
        if acts, !(waiting && byItself) {
            SettingsNote(text: waiting ? SyncEngineWords.waitingNote(next) : SyncEngineWords.moveNote(to: target))
        }
        if acts {
            HITMenuRow(waiting ? SyncEngineWords.cancelTitle : SyncEngineWords.moveTitle(to: target),
                       subtitle: board.actions == nil ? SyncEngineWords.notWired : nil,
                       systemImage: "arrow.left.arrow.right", iconTint: Theme.accent, accessory: .none) {
                if waiting { move(to: target, freshCopy: false) } else { confirmMove = true }
            }
            .disabled(board.actions == nil || isMoving)
            .accessibilityIdentifier("settings-engine-move")
            // On the row, not on the rows: a modifier on a group of rows is applied to each of them.
            .confirmationDialog("\(SyncEngineWords.moveTitle(to: target))?", isPresented: $confirmMove, titleVisibility: .visible) {
                if target == .own {
                    Button(blocker == nil ? SyncEngineWords.moveTitle(to: target) : "Move anyway") { move(to: target, freshCopy: false) }
                } else {
                    // The way back: the first device sends what it holds; every other device takes a fresh copy, or
                    // each would send the items made meanwhile as its own and every device would hold them twice.
                    Button(SyncEngineWords.backFirstTitle) { move(to: target, freshCopy: false) }
                    Button(SyncEngineWords.backOtherTitle) { move(to: target, freshCopy: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(target == .own ? (blocker ?? SyncEngineWords.moveNote(to: target)) : SyncEngineWords.backMessage)
            }
        }
        if let message {
            SettingsMessage(text: message)
                .padding(.leading, HITRowMetrics.titleInset)
                .accessibilityIdentifier("settings-engine-move-message")
        }
    }

    /// Why moving to the new sync should wait, in what is known (round 35, `SyncEngineWords.moveBlocker`): nothing
    /// when the earlier sync has caught up (`SyncEngineAutoMove.caughtUp`), the count when a comparison found what
    /// iCloud holds and this device lacks, and otherwise that nothing was compared since the app was opened.
    private var blocker: String? {
        let monitor = CloudSyncMonitor.shared
        return SyncEngineWords.moveBlocker(mirrorRunning: ModelContainerFactory.isCloudKitEnabled,
                                           state: monitor.state, difference: monitor.recordDifference)
    }

    private func move(to target: SyncEngineBoard.Engine, freshCopy: Bool) {
        guard let actions = board.actions, !isMoving else { return }
        isMoving = true
        message = nil
        Task { @MainActor in
            defer {
                isMoving = false
                next = SyncEngineSwitch.nextEngine()
            }
            do {
                try await actions.move(target, freshCopy)
            } catch let error as SyncEngine.MoveError where error != .inMemory {
                // Not a failure: the move is made and waits for the app to be reopened.
                message = error.localizedDescription
            } catch {
                message = "Nothing moved: \(SyncEngineWords.error(error))"
            }
        }
    }
}

/// Seven taps in a row, each within two seconds of the one before: the gesture that reveals the engine's switch
/// (`SyncEngineSwitch.revealSwitch`). No timer: a tap that comes late starts the count again.
struct SevenTaps {
    static let needed = 7
    static let window: TimeInterval = 2

    private var count = 0
    private var last: Date?

    /// Counts a tap; true on the seventh.
    mutating func tap(at now: Date = Date()) -> Bool {
        if let last, now.timeIntervalSince(last) <= Self.window { count += 1 } else { count = 1 }
        last = now
        guard count >= Self.needed else { return false }
        count = 0
        self.last = nil
        return true
    }
}

/// Check iCloud… on HITList's own engine (`SyncEngineAudit`): a sync, then every record in iCloud read afresh and
/// compared with this device's, field by field. Nothing is repaired: what differs is the engine's to settle, and its
/// keys are in the sync log.
struct SyncEngineCheckRows: View {
    private var board: SyncEngineBoard { .shared }
    @State private var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        case reading(Int?)
        case done(SyncEngineAudit.Report)
        case failed(String)
    }

    static let subtitle = "Syncs, then compares every item in iCloud with this device"

    var body: some View {
        let isBusy = { if case .reading = phase { return true } else { return false } }()
        HITMenuRow("Check iCloud…", subtitle: Self.subtitle, systemImage: "checkmark.icloud", accessory: .none) { run() }
            .disabled(isBusy || board.actions?.check == nil)
            .overlay(alignment: .trailing) {
                if isBusy { ProgressView().controlSize(.small).padding(.trailing, HITSpacing.l) }
            }
            .accessibilityIdentifier("settings-engine-check")
        switch phase {
        case .idle:
            EmptyView()
        case .reading(let read):
            caption(read.map { "Reading iCloud… \($0) records" } ?? "Syncing, then reading iCloud…",
                    systemImage: "icloud.and.arrow.down")
                .accessibilityIdentifier("settings-engine-check-progress")
        case .done(let report):
            caption(report.summary, systemImage: report.isSame ? "checkmark.circle" : "exclamationmark.circle",
                    warning: !report.isSame)
                .accessibilityIdentifier("settings-engine-check-result")
            if !report.isSame {
                SettingsNote(text: SyncEngineWords.checkDifferenceNote)
            }
        case .failed(let words):
            caption("Couldn't compare with iCloud: \(words)", systemImage: "exclamationmark.circle", warning: true)
                .accessibilityIdentifier("settings-engine-check-result")
        }
    }

    private func run() {
        guard let check = board.actions?.check else { return }
        phase = .reading(nil)
        Task { @MainActor in
            do {
                let report = try await check { read in
                    Task { @MainActor in
                        if case .reading = phase { phase = .reading(read) }
                    }
                }
                phase = .done(report)
            } catch {
                phase = .failed(SyncEngineWords.error(error))
            }
        }
    }

    private func caption(_ text: String, systemImage: String, warning: Bool = false) -> some View {
        Label(text, systemImage: systemImage)
            .font(HITType.caption)
            .foregroundStyle(warning ? HITColor.dueTomorrow : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
            .textSelection(.enabled)
    }
}

/// The words of the engine's settings, in one place so they can be tested.
enum SyncEngineWords {
    /// Red holds: the ones a person must act on (`dev/SYNC-ENGINE.md` section 10). Not a sign-out (today's signed-out
    /// state), not tidying up.
    static func needsYou(_ hold: SyncHold) -> Bool {
        switch hold {
        case .zonePurged, .needsUpdate, .storageFull, .iCloudNotReady, .failed: true
        case .noAccount, .duplicates: false
        }
    }

    static func holdTitle(_ hold: SyncHold) -> String {
        switch hold {
        case .zonePurged: "Removed from iCloud"
        case .needsUpdate: "Update HITList"
        case .storageFull: "iCloud is full"
        case .iCloudNotReady: "iCloud isn't ready"
        case .failed: "Sync stopped"
        case .duplicates: "Tidying up"
        case .noAccount: "Not signed in"
        }
    }

    /// What stands still and why, in the hold's group (the hold's own words are the status line's).
    static func holdNote(_ hold: SyncHold, waiting: Int = 0) -> String {
        switch hold {
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
        case .iCloudNotReady:
            let kept = waiting == 0 ? "Nothing is lost." : "Nothing is lost: what is waiting stays waiting."
            return "\(kept) HITList tries again each time you come back to it, or now with Try again."
        case .failed:
            return "HITList couldn't read or write what it keeps on this device for sync. Nothing was sent or deleted."
        case .duplicates:
            return "Nothing to do: HITList merges them, then sync starts again by itself."
        case .noAccount:
            // Brief 165: a sign-out keeps every item here; the one sentence, the same as the hold's own words.
            return SyncHold.noAccountWords
        }
    }

    static let removeSubtitle = "Saves a backup first, then what came from iCloud leaves this device"
    static let sendAgainSubtitle = "Everything on this device goes back to iCloud"

    static func tryAgainSubtitle(_ hold: SyncHold) -> String {
        if case .storageFull = hold { return "Sends what is waiting, once iCloud has room" }
        if case .iCloudNotReady = hold { return "Sends what is waiting, if iCloud is ready now" }
        return "Reads this device's items and HITList's sync records again"
    }

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
        engine == .own ? "The new sync" : "The earlier sync"
    }

    static func moveTitle(to engine: SyncEngineBoard.Engine) -> String {
        engine == .own ? "Move to the new sync" : "Move back to the earlier sync"
    }

    static let cancelTitle = "Cancel the move"

    #if os(macOS)
    private static let reopens = "then HITList relaunches"
    #else
    private static let reopens = "then HITList finishes the move the next time you leave it"
    #endif

    /// Under the row, before the move: what moving does, in the direction it would go.
    static func moveNote(to engine: SyncEngineBoard.Engine) -> String {
        if engine == .own {
            return "Moving saves a backup first and keeps every task on this device, \(reopens). A device on the new "
                + "sync and one on the earlier sync don't see each other's changes: move every device you use, one "
                + "right after another, and change nothing on a device between the first move and its own. You can "
                + "move back."
        }
        return "Moving back saves a backup first, \(reopens). Move every device back, one right after another."
    }

    /// The hidden group's row for George's word that every device may move (`SyncEngineAutoMove` R0).
    /// Round 35: "Everyone's move: Not released" read to George as his own move having failed; it is the word he
    /// gives his friends' devices.
    static let everyoneTitle = "Friends' devices"
    static func everyoneValue(_ word: SyncEngineAutoMove.Word) -> String {
        switch word {
        case .notAsked: return "Asking iCloud…"
        case .go: return "Moving by themselves"
        case .notYet: return "Not moving yet: you have not given the word"
        case .paused: return "Paused"
        case .unknown: return "Couldn't ask iCloud"
        }
    }

    /// Moving to the new sync while the earlier sync may not have brought everything here: said in the confirmation,
    /// which then offers "Move anyway". Nil when nothing stands in the way (the earlier sync is off, or it has caught
    /// up as the move made by the app reads it, `SyncEngineAutoMove.caughtUp`). Round 35: it said "wait for the bolt"
    /// on a launch where nothing had been compared yet, on a Mac whose bolt could not fill; it now says what is known.
    static func moveBlocker(mirrorRunning: Bool, state: SyncState, difference: SyncRecordCheck.Difference?) -> String? {
        guard mirrorRunning, !SyncEngineAutoMove.caughtUp(state, difference: difference) else { return nil }
        let behind = SyncEngineAutoMove.leftBehind(difference)
        if behind > 0 { return leftBehindWarning(behind) }
        return notComparedWarning
    }

    /// A comparison found what iCloud holds and this device has not received.
    static func leftBehindWarning(_ count: Int) -> String {
        let what = count == 1 ? "1 item" : "\(count) items"
        return "iCloud sync hasn't finished on this device: iCloud holds \(what) it has not received yet. Moving "
            + "now can bring back something deleted on another device, or miss its latest changes. Better: wait "
            + "for the bolt, then move."
    }

    /// Nothing was compared since the app was opened.
    static let notComparedWarning = "HITList has not compared this device with iCloud since it was opened, so it "
        + "cannot say that everything has arrived. Check iCloud… (above) compares them now. Moving anyway is safe if "
        + "nothing was changed on another device in the last few minutes: a deletion made there would come back."

    static let backFirstTitle = "First device: send this device's tasks"
    static let backOtherTitle = "Another device already moved back: download"
    static let backMessage = "On the first device you move back, send its tasks. On every other device, download: "
        + "it takes a fresh copy from iCloud, so nothing is saved twice. A backup is saved first either way."

    /// While a move made by hand waits. The app finishes it itself (`SyncEngineMoveFinish`): a Mac when it is no
    /// longer the active app, an iPhone or iPad once it is left. (A side store on the Mac, which a relaunch would
    /// not reopen, is finished by quitting and opening it again: the move's own message says so there.)
    static func waitingNote(_ next: SyncEngineBoard.Engine) -> String {
        #if os(macOS)
        let how = "when you switch to another app"
        #else
        let how = "the next time you leave it"
        #endif
        return "HITList finishes moving to \(engineName(next).lowercased()) \(how). Nothing to do."
    }

    /// Round 35: it pointed at the Sync log, which only troubleshooting shows now; the file Send sync log… sends
    /// names them.
    static let checkDifferenceNote = "Nothing was changed. What is waiting to go is sent by itself; the file Send sync "
        + "log… sends names each item that differs."

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
            case .notStarted: return "sync hasn't started yet; try again in a moment."
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
    static let names = ["synced", "waiting3", "checking", "purged", "update", "full12", "failed", "refused2", "signedout"]

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
            move: { _, _ in
                note("Move")
                throw DemoError()
            })
    }

    struct DemoError: LocalizedError {
        var errorDescription: String? { "this is the demo of the engine's marks; nothing moves." }
    }
}
#endif
