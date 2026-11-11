import SwiftUI
import SwiftData

/// Settings → iCloud & data → Sync: the status line, a warning while sync is stuck, and on the iPhone the Sync log
/// (a page of its own, `SettingsPage.syncLog`; the Mac page shows the log inline, `SyncLogSection`). Shared by the
/// iPhone's iCloud & data page and the Mac page's iCloud section, which adds the "Last change" row
/// (`showsLastChange`). What only matters when something doesn't sync is in `ICloudCheckGroup`, further down.
struct ICloudSyncGroup: View {
    var showsLastChange = false
    @Environment(\.hitPages) private var pages

    static let title = "Sync"
    static let footer = "Tasks sync through your private iCloud database at no cost. Sign in to iCloud on each device and the data follows."

    var body: some View {
        HITGroup(Self.title, footer: Self.footer) {
            SyncStatusLine()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hitRowPadding()
            if let stall = CloudSyncMonitor.shared.stall {
                SyncStuckRow(stall: stall)
            }
            if showsLastChange {
                LastSyncChangeRow()
            }
            #if os(iOS)
            HITMenuRow("Sync log", systemImage: "list.bullet.rectangle") { pages(SettingsPage.syncLog) }
                .accessibilityIdentifier("settings-sync-log-row")
            #endif
        }
    }
}

/// Settings → iCloud & data → "If something doesn't sync": which CloudKit environment this build uses, Details (the
/// account, network, last import and export, push, the store) and Check iCloud…, near the page's foot because they
/// matter only when something is wrong.
struct ICloudCheckGroup: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSyncDetails = false
    @State private var isCheckingICloud = false
    @State private var iCloudCheck: ICloudCheck?

    static let title = "If something doesn't sync"

    var body: some View {
        HITGroup(Self.title) {
            SyncEnvironmentRow()
            HITMenuRow("Details", systemImage: "info.circle", accessory: .expand(isExpanded: showSyncDetails)) {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showSyncDetails.toggle() }
            }
            .accessibilityIdentifier("settings-sync-details")
            if showSyncDetails {
                VStack(alignment: .leading, spacing: HITSpacing.s) { syncDetails }
                    .padding(.horizontal, HITSpacing.l)
                    .padding(.vertical, HITSpacing.m)
            }
            HITMenuRow("Check iCloud…", systemImage: "checkmark.icloud", accessory: .none) { runICloudCheck() }
                .disabled(isCheckingICloud)
                .overlay(alignment: .trailing) {
                    if isCheckingICloud { ProgressView().controlSize(.small).padding(.trailing, HITSpacing.l) }
                }
                .accessibilityIdentifier("settings-check-icloud")
            if let iCloudCheck {
                Label(iCloudCheck.summary, systemImage: iCloudCheck.isHealthy ? "checkmark.circle" : "exclamationmark.circle")
                    .font(HITType.caption)
                    .foregroundStyle(iCloudCheck.isHealthy ? Theme.secondaryText : HITColor.dueTomorrow)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hitRowPadding()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings-check-icloud-result")
            }
        }
    }

    private func runICloudCheck() {
        guard !isCheckingICloud else { return }
        isCheckingICloud = true
        Task {
            let result = await ICloudCheck.run()
            CloudSyncMonitor.shared.write(.note, "Check iCloud: \(result.summary)",
                                          level: result.isHealthy ? .info : .notice,
                                          fields: ["environment": SyncEnvironment.current.summary])
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
                iCloudCheck = result
                isCheckingICloud = false
            }
        }
    }

    @ViewBuilder
    private var syncDetails: some View {
        let monitor = CloudSyncMonitor.shared
        detailRow("Account", "\(AccountState.current.label) (iCloud says \(CloudSyncMonitor.describe(monitor.rawAccountStatus)))")
        detailRow("Network", monitor.isOnline.map { $0 ? "reachable" : "unreachable" } ?? "checking")
        detailRow("Last import", timestamp(monitor.lastImportAt))
        detailRow("Last export", timestamp(monitor.lastExportAt))
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

/// Shown while sync is stuck (`CloudSyncMonitor.stall`): an import, export or setup has run for two minutes with
/// nothing in its way, or local changes have waited two minutes for an export with nothing running (CloudKit's
/// mirroring stopped, as on George's Mac after a badContainer on 2026-11-10). Either way only a fresh process gets it
/// going again. The Mac relaunches in one click; the iPhone says how to reopen the app.
struct SyncStuckRow: View {
    let stall: SyncWatchdog.Stall
    @State private var relaunchFailed = false

    var body: some View {
        #if os(macOS)
        HITMenuRow("Sync is stuck", subtitle: Self.detail(for: stall), systemImage: "exclamationmark.arrow.circlepath",
                   iconTint: HITColor.danger) {
            Button("Relaunch") { SyncRecovery.relaunch { relaunchFailed = true } }
                .buttonStyle(HITButtonStyle(.primary, size: .small))
                .accessibilityIdentifier("settings-sync-relaunch")
        }
        .accessibilityIdentifier("settings-sync-stuck")
        .alert("Quit and reopen HITList", isPresented: $relaunchFailed) {
            Button("OK") {}
        } message: {
            Text("HITList couldn't relaunch itself. Quit it and open it again; your changes are kept and upload when it starts.")
        }
        #else
        HITMenuRow("Sync is stuck", subtitle: Self.detail(for: stall) + " " + Self.reopen,
                   systemImage: "exclamationmark.arrow.circlepath", iconTint: HITColor.danger)
            .accessibilityIdentifier("settings-sync-stuck")
        #endif
    }

    static let reopen = "Swipe HITList away in the app switcher and open it again."

    /// "iCloud sync has been busy with one request since 6:51 PM. Relaunching starts it afresh; your changes are kept
    /// and upload right after." or "iCloud sync stopped answering: 6 changes made since 6:13 PM haven't been sent.
    /// Relaunching …".
    static func detail(for stall: SyncWatchdog.Stall) -> String {
        let time = stall.since.formatted(date: .omitted, time: .shortened)
        #if os(macOS)
        let verb = "Relaunching"
        #else
        let verb = "Reopening"
        #endif
        let fix = "\(verb) starts it afresh; your changes are kept and upload right after."
        switch stall {
        case .busy:
            return "iCloud sync has been busy with one request since \(time). \(fix)"
        case .quiet(_, let saves):
            let changes = saves == 1 ? "1 change" : "\(saves) changes"
            return "iCloud sync stopped answering: \(changes) made since \(time) haven't been sent. \(fix)"
        }
    }

    /// The busy wording, as before (tests and the iPhone's row).
    static func detail(since: Date) -> String { detail(for: .busy(since: since)) }
}

/// Which CloudKit environment and build this is ("Production · TestFlight build 11") and which account state
/// it is in, in the Account screen's words ("iCloud: Signed in"), with the line that explains why two devices
/// on different environments never see each other's tasks.
struct SyncEnvironmentRow: View {
    var environment: SyncEnvironment = .current
    /// Nil: the live state (`AccountState.current`).
    var account: AccountState?

    static func subtitle(account: AccountState) -> String { "\(account.title). \(SyncEnvironment.explanation)" }

    var body: some View {
        let account = account ?? .current
        HITMenuRowLabel(environment.summary, subtitle: Self.subtitle(account: account), systemImage: "server.rack",
                        iconTint: environment.cloudKit == .production ? Theme.secondaryText : HITColor.dueTomorrow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CloudKit environment: \(environment.summary). \(Self.subtitle(account: account))")
            .accessibilityIdentifier("settings-sync-environment")
    }
}

/// Settings → iCloud & data on iPhone and iPad: sync, backups, export and import, what to look at when something
/// doesn't sync, then, last and apart, the two that throw something away. (The Mac splits it into its iCloud and
/// Data sections.)
struct ICloudDataPage: View {
    var body: some View {
        ICloudSyncGroup()
        BackupsGroup()
        ExportImportGroup()
        ICloudCheckGroup()
        ResetLocalCacheGroup(includesDeleteAll: true)
    }
}

/// The end of the iCloud block, set apart so it isn't tapped on the way to anything else: Reset local cache and
/// re-download, with its confirmation and the "reopen" alert; on iPhone and iPad also Delete all data from iCloud
/// (`includesDeleteAll`), whose words say how (the Mac keeps that one at the foot of its Data section).
struct ResetLocalCacheGroup: View {
    var includesDeleteAll = false
    @State private var confirmReset = false
    @State private var showReopenAlert = false

    /// Under the reset row: what it does and what it costs.
    static let subtitle = "Downloads everything again; changes not synced yet are lost"

    var body: some View {
        HITGroup {
            HITMenuRow("Reset local cache and re-download…", subtitle: Self.subtitle, systemImage: "arrow.counterclockwise",
                       role: .destructive, accessory: .none) { confirmReset = true }
                .disabled(!LocalCacheReset.isAvailable)
                .accessibilityIdentifier("settings-reset-cache")
            if includesDeleteAll {
                DeleteAllFromICloudRows()
            }
        }
        .confirmationDialog("Reset local cache?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button(resetActionTitle, role: .destructive) { resetLocalCache() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your tasks stay in iCloud and are downloaded again into a fresh copy on this device. Changes made here that haven't synced yet won't come back.")
        }
        .alert("Quit and reopen HITList to finish", isPresented: $showReopenAlert) {
            Button("OK") {}
        } message: {
            Text(reopenMessage)
        }
    }

    #if os(macOS)
    private let resetActionTitle = "Reset and Relaunch"
    private let reopenMessage = "HITList couldn't relaunch itself. Quit it and open it again to download a fresh copy."
    #else
    private let resetActionTitle = "Reset"
    private let reopenMessage = "Swipe HITList away in the app switcher, then open it again. It downloads a fresh copy from iCloud when it starts."
    #endif

    private func resetLocalCache() {
        LocalCacheReset.request()
        #if os(macOS)
        LocalCacheReset.relaunch { showReopenAlert = true }
        #else
        showReopenAlert = true
        #endif
    }
}

/// "Delete all data from iCloud": HITList never deletes in bulk itself, so the row opens the words that say where the
/// system does it (`AccountCopy.deleteAll`). Rows for a `HITGroup`.
struct DeleteAllFromICloudRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false

    var body: some View {
        HITMenuRow("Delete all data from iCloud", systemImage: "trash.slash", accessory: .expand(isExpanded: isOpen)) {
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { isOpen.toggle() }
        }
        .accessibilityIdentifier("settings-account-delete-all")
        if isOpen {
            SettingsNote(text: AccountCopy.deleteAll)
        }
    }
}
