import Foundation
import OSLog

/// One device, two Apple accounts in turn (brief 42, item 2). When the iCloud account changes, Core Data
/// purges the mirrored records, so the lists show the new account's tasks only. What lives outside the
/// store would survive and show the previous person's data to the next one. On a detected switch
/// (`AccountWatch.identify`) this clears or sets aside each such thing, locally only: nothing in iCloud
/// is touched, and nothing is deleted that can't come back.
///
/// - The open quick-add card's sticky draft (`QuickAddDraftStore`): cleared.
/// - Pending and delivered reminders, the morning summary, the app icon badge and the reminder ledger
///   (task ids): cleared. The next import reschedules the new account's.
/// - Daily backups (`LocalBackup`): moved out of the visible folder into a folder of the previous account's
///   own, keyed by its hashed id; the new account's earlier backups come back if it used this device before.
/// - The sync times ("Synced 3 hr ago" was the other account's).
/// - The open card and the undo toast on screen: `Notification.Name.accountDidSwitch` is posted for the
///   views that hold them.
///
/// There is no Spotlight index, widget or other cache of task data on the device (checked for 0.6.0).
///
/// A sign-out alone clears the reminders and the badge (their tasks were purged with the account); the
/// draft and the backups wait, since the same person usually signs back in.
@MainActor
enum AccountSwitch {
    /// What clearing does, injected so tests never touch the device's real notifications or files.
    struct Cleanup {
        /// Forgets the stored quick-add card; returns whether one was stored.
        var clearDraft: @MainActor () -> Bool
        /// Removes every pending and delivered reminder, zeroes the badge, forgets the ledger.
        var clearReminders: @MainActor () async -> Void
        /// Sets aside the previous account's backups, brings back the current one's.
        var setAsideBackups: @MainActor (_ previous: String, _ current: String) -> LocalBackup.SetAside
        /// Forgets the sync times.
        var forgetCaches: @MainActor () -> Void

        static var live: Cleanup {
            Cleanup(
                clearDraft: { AccountSwitch.clearDraft() },
                clearReminders: { await NotificationScheduler.clearForAccountChange() },
                setAsideBackups: { LocalBackup.setAside(previousAccount: $0, currentAccount: $1) },
                forgetCaches: {
                    CloudSyncMonitor.shared.forgetLastSync(reason: "iCloud account changed")
                })
        }
    }

    /// Forgets this store's stored quick-add card (`QuickAddDraftStore`, session 41's) and returns whether
    /// one was there.
    static func clearDraft(defaults: UserDefaults = AppGroup.defaults,
                           storeName: String = ModelContainerFactory.storeName) -> Bool {
        let had = QuickAddDraftStore.load(from: defaults, storeName: storeName) != nil
        QuickAddDraftStore.clear(from: defaults, storeName: storeName)
        return had
    }

    struct Report: Equatable {
        var draftCleared = false
        /// False when this launch doesn't own the device's reminders and backups (a Debug build's side store).
        var ownsDeviceState = true
        var backups = LocalBackup.SetAside()
    }

    typealias Log = @MainActor (_ message: String, _ level: SyncLogEntry.Level, _ fields: [String: String]) -> Void
    static let syncLog: Log = { CloudSyncMonitor.shared.write(.account, $0, level: $1, fields: $2) }

    /// The account changed from `previous` to `current` (both `AccountIdentity` keys). `ownsDeviceState`:
    /// this launch opened the real store, so the reminders, badge and backups are its to clear.
    @discardableResult
    static func handleSwitch(from previous: String, to current: String,
                             ownsDeviceState: Bool = ModelContainerFactory.isMainStoreOpen,
                             cleanup: Cleanup = .live, log: Log = syncLog,
                             center: NotificationCenter = .default) async -> Report {
        var report = Report(ownsDeviceState: ownsDeviceState)
        report.draftCleared = cleanup.clearDraft()
        cleanup.forgetCaches()
        if ownsDeviceState {
            await cleanup.clearReminders()
            report.backups = cleanup.setAsideBackups(previous, current)
        }
        log(message(for: report), .notice, fields(for: report))
        center.post(name: .accountDidSwitch, object: nil)
        return report
    }

    /// Signed out of iCloud (after an account was in use): the reminders go with the purged tasks.
    static func handleSignOut(ownsDeviceState: Bool = ModelContainerFactory.isMainStoreOpen,
                              cleanup: Cleanup = .live, log: Log = syncLog) async {
        guard ownsDeviceState else { return }
        await cleanup.clearReminders()
        log("Signed out of iCloud: reminders and badge cleared", .notice, [:])
    }

    /// "Account changed: local drafts and reminders cleared". Never a name or an id.
    static func message(for report: Report) -> String {
        report.ownsDeviceState
            ? "Account changed: local drafts and reminders cleared"
            : "Account changed: local drafts cleared"
    }

    static func fields(for report: Report) -> [String: String] {
        var fields = ["draft": report.draftCleared ? "cleared" : "none"]
        if report.ownsDeviceState {
            fields["reminders"] = "cleared"
            fields["backups"] = "\(report.backups.movedAside) set aside, \(report.backups.restored) restored"
        } else {
            fields["reminders"] = "left alone: this run uses \(ModelContainerFactory.openedStoreDescription)"
        }
        return fields
    }

    // MARK: Simulation (Debug only)

    /// `-simulateAccountSwitch`: a Debug launch plays a switch between two made-up accounts through the real
    /// handler, so the sync log lines can be seen without signing a device out of iCloud. The made-up keys
    /// live in a scratch defaults domain, never in the app group, so the next real launch sees no switch.
    static let simulateArgument = "-simulateAccountSwitch"

    static func simulateIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        guard arguments.contains(simulateArgument) else { return }
        let suite = "HITList.simulatedAccountSwitch"
        guard let scratch = UserDefaults(suiteName: suite) else { return }
        scratch.removePersistentDomain(forName: suite)
        let watch = AccountWatch(defaults: scratch)
        _ = watch.identify(userRecordName: "_simulatedAccountA")
        let second = watch.identify(userRecordName: "_simulatedAccountB")
        scratch.removePersistentDomain(forName: suite)
        guard second.isSwitch, let previous = second.previous else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            CloudSyncMonitor.shared.write(.note, "Simulating an iCloud account switch (\(simulateArgument))", level: .notice)
            #if targetEnvironment(simulator)
            // The simulator has no TestFlight build to share reminders with: play the whole path.
            let owns = true
            #else
            let owns = ModelContainerFactory.isMainStoreOpen
            #endif
            CloudSyncMonitor.shared.simulateSwitchNotice()
            await handleSwitch(from: previous, to: second.account, ownsDeviceState: owns)
        }
        #endif
    }
}

extension Notification.Name {
    /// Posted on the main actor after `AccountSwitch.handleSwitch` cleared this device's local state. Views
    /// that hold another account's things in memory (the open quick-add card, the undo toast) put them away.
    static let accountDidSwitch = Notification.Name("HITList.accountDidSwitch")
}
