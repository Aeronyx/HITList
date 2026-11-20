import SwiftUI
import SwiftData

// Round 35 (brief 174): Settings → iCloud & data is for a person who never heard how HITList syncs. What was put
// there for George and the supervisor while the sync was built (the environment row, Details, the Sync log's page,
// the engine's last fetch and send, and the switch between the engines) is one group, "For troubleshooting", at the
// page's foot, shown only where it was revealed: seven taps on Settings → About → Version (`SevenTaps`, the key
// `SyncEngineSwitch.revealedKey`, which George's Mac already holds). About then shows "Troubleshooting rows:
// Showing", which hides them again.

/// Where the troubleshooting rows show, and their words.
enum Troubleshooting {
    static let title = "For troubleshooting"
    static let footer = "Shown because this device was set to show them: Settings → About."
    /// About's row once revealed: pressed, it hides them again (it asks nothing; seven taps bring them back).
    static let aboutTitle = "Troubleshooting rows"
    static let aboutValue = "Showing"
    static let aboutSubtitle = "Hides them from iCloud & data"

    /// `-settingsAsFriend YES` (Debug builds): a side store shows the page as a friend's device does, so the gesture
    /// and the page a friend sees can be tested and pictured. Without it a Debug side store shows the rows, as the UI
    /// tests need.
    static let asFriendKey = "settingsAsFriend"

    /// Revealed by hand, or a Debug build on a side store (unless it plays a friend's device).
    nonisolated static func isShown(revealed: Bool, isDebugSideStore: Bool) -> Bool {
        revealed || isDebugSideStore
    }

    /// The live answer. A move asked for by hand that waits for a reopen keeps the group, so it can be cancelled.
    @MainActor
    static func isShown(revealed: Bool) -> Bool {
        isShown(revealed: revealed, isDebugSideStore: isDebugSideStore) || SyncEngineSwitchRows.handMoveWaits
    }

    static var isDebugSideStore: Bool {
        SyncEngineSwitchRows.isDebugSideStore && !UserDefaults.standard.bool(forKey: asFriendKey)
    }

    static func reveal(defaults: UserDefaults = AppGroup.defaults) { SyncEngineSwitch.revealSwitch(defaults: defaults) }

    static func hide(defaults: UserDefaults = AppGroup.defaults) { defaults.set(false, forKey: SyncEngineSwitch.revealedKey) }
}

/// The group itself: which iCloud this build talks to, Details, the Sync log (a page on the iPhone; the Mac shows it
/// inline under the group, `SyncLogSection`), when the last changes were received and sent, then the switch between
/// the engines.
struct TroubleshootingGroup: View {
    @Environment(\.hitPages) private var pages
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSyncDetails = false

    var body: some View {
        HITGroup(Troubleshooting.title, footer: Troubleshooting.footer) {
            SyncEnvironmentRow()
            HITMenuRow("Details", systemImage: "info.circle", accessory: .expand(isExpanded: showSyncDetails)) {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showSyncDetails.toggle() }
            }
            .accessibilityIdentifier("settings-sync-details")
            if showSyncDetails {
                SyncDetails()
                    .padding(.horizontal, HITSpacing.l)
                    .padding(.vertical, HITSpacing.m)
            }
            #if os(iOS)
            HITMenuRow("Sync log", systemImage: "list.bullet.rectangle") { pages(SettingsPage.syncLog) }
                .accessibilityIdentifier("settings-sync-log-row")
            #endif
            if CloudSyncMonitor.shared.isOnEngine {
                SyncEngineTimesRows()
            } else {
                LastSyncChangeRow()
            }
            SyncEngineSwitchRows()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-troubleshooting")
    }
}

/// Details: the account, network, last import and export (or the engine's fetch and send), push, which CloudKit
/// environment, the store.
struct SyncDetails: View {
    @Environment(\.modelContext) private var context

    /// What Details calls the app's own sync. It said "(early access)" until round 35: from 0.9.16 every device is
    /// moved to it, so the words told a person their tasks were on something unfinished.
    static let engineName = "the new sync"

    var body: some View {
        let monitor = CloudSyncMonitor.shared
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            detailRow("Account", "\(AccountState.current.label) (iCloud says \(CloudSyncMonitor.describe(monitor.rawAccountStatus)))")
            detailRow("Network", monitor.isOnline.map { $0 ? "reachable" : "unreachable" } ?? "checking")
            if monitor.isOnEngine {
                let status = SyncEngineBoard.shared.status
                detailRow("Syncs through", Self.engineName)
                detailRow("Last fetch", timestamp(status?.lastFetchEnded))
                detailRow("Last accepted send", timestamp(status?.lastSendEnded))
                if let error = status?.lastError { detailBlock("Last error", error) }
            } else {
                detailRow("Last import", timestamp(monitor.lastImportAt))
                detailRow("Last export", timestamp(monitor.lastExportAt))
            }
            detailRow("Push", monitor.pushRegistration ?? "not registered yet")
            detailRow("CloudKit", "\(SyncEnvironment.current.cloudKit.rawValue), push \(SyncEnvironment.current.push ?? "unknown")")
            if let err = ModelContainerFactory.startupError {
                detailBlock("Startup error", err)
            }
            if let detail = monitor.lastErrorDetail {
                detailBlock("Last error, \(timestamp(monitor.lastErrorAt))", detail)
            }
            detailBlock("Store", context.container.configurations.first?.url.path ?? "unknown")
        }
    }

    private func timestamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "never"
    }

    // LabeledContent wraps badly in this sheet; a plain HStack with fixedSize lays out reliably.
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.trailing)
        }
        .font(HITType.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detailBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(value).foregroundStyle(Theme.secondaryText).textSelection(.enabled)
        }
        .font(HITType.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// About's Version row, which counts seven taps in a row and reveals the troubleshooting rows; once they show, the
/// row under it that hides them again. Rows for About's `HITGroup` (iPhone, iPad and the Mac).
struct VersionAndTroubleshootingRows: View {
    @AppStorage(SyncEngineSwitch.revealedKey, store: AppGroup.defaults) private var revealed = false
    @State private var taps = SevenTaps()

    var body: some View {
        HITMenuRow("Version", systemImage: "info.circle", value: AppInfo.versionLabel)
            .contentShape(Rectangle())
            .onTapGesture { if taps.tap() { Troubleshooting.reveal() } }
            .accessibilityIdentifier("settings-version")
        if revealed {
            HITMenuRow(Troubleshooting.aboutTitle, subtitle: Troubleshooting.aboutSubtitle, systemImage: "wrench.and.screwdriver",
                       value: Troubleshooting.aboutValue, accessory: .none) { Troubleshooting.hide() }
                .accessibilityIdentifier("settings-troubleshooting-hide")
        }
    }
}

/// What a move the app made by itself tells, in the Sync group under the status line: its one line while the device
/// waits to join or to finish (`SyncEngineAutoMove.Runner.line`), and afterwards, for fourteen days, that the other
/// devices need the update, with the check the device made of itself (`SyncEngineMoveCheck.line()`).
struct AutoMoveRows: View {
    var body: some View {
        if let line = SyncEngineAutoMove.Runner.shared?.line {
            SettingsNote(text: line)
                .accessibilityIdentifier("settings-engine-auto-move")
        } else if CloudSyncMonitor.shared.isOnEngine, AutoMoveNote.shows() {
            SettingsNote(text: SyncEngineAutoMove.otherDevicesNote)
                .accessibilityIdentifier("settings-engine-auto-moved")
            if let checked = SyncEngineMoveCheck.line() {
                SettingsNote(text: checked)
                    .accessibilityIdentifier("settings-engine-auto-move-check")
            }
        }
    }
}

/// How long the words after a move made by itself stay: fourteen days from the move (`SyncEngineAutoMove.movedAtKey`
/// holds its date). Where no date is stored, from the first time the words were shown (a key of this page's own).
enum AutoMoveNote {
    static let days = 14

    static func firstShownKey(_ store: String) -> String { "settings.autoMoveNote.firstShown.\(store)" }

    /// Pure: whether the words show at `now`.
    static func isShown(movedByItself: Bool, movedAt: Date?, firstShown: Date?, now: Date) -> Bool {
        guard movedByItself else { return false }
        guard let since = movedAt ?? firstShown else { return true }
        return now.timeIntervalSince(since) < TimeInterval(days) * 86_400
    }

    /// The live answer; stores the first showing when the move left no date.
    static func shows(store: String = ModelContainerFactory.storeName, defaults: UserDefaults = AppGroup.defaults,
                      now: Date = Date()) -> Bool {
        let moved = SyncEngineAutoMove.movedByItself(store: store, defaults: defaults)
        let movedAt = defaults.object(forKey: SyncEngineAutoMove.movedAtKey(store)) as? Date
        var firstShown = defaults.object(forKey: firstShownKey(store)) as? Date
        if moved, movedAt == nil, firstShown == nil {
            defaults.set(now, forKey: firstShownKey(store))
            firstShown = now
        }
        return isShown(movedByItself: moved, movedAt: movedAt, firstShown: firstShown, now: now)
    }
}
