import SwiftUI
import SwiftData

/// Settings → iCloud Sync: the status line, the CloudKit environment, Details, Check iCloud…, and on
/// the iPhone the Sync log (a sheet; the Mac page shows the log inline, `SyncLogSection`). Shared by the
/// iPhone sheet and the Mac page's iCloud section, which adds the "Last change" row (`showsLastChange`).
struct ICloudSyncGroup: View {
    var showsLastChange = false
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSyncDetails = false
    @State private var isCheckingICloud = false
    @State private var iCloudCheck: ICloudCheck?
    @State private var showSyncLog = false

    static let footer = "Tasks sync through your private iCloud database at no cost. Sign in to iCloud on each device and the data follows."

    var body: some View {
        HITGroup("iCloud Sync", footer: Self.footer) {
            SyncStatusLine()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hitRowPadding()
            if let stalled = CloudSyncMonitor.shared.stalledSince {
                SyncStuckRow(since: stalled)
            }
            if showsLastChange {
                LastSyncChangeRow()
            }
            SyncEnvironmentRow()
            #if os(iOS)
            HITMenuRow("Sync log", systemImage: "list.bullet.rectangle") { showSyncLog = true }
                .accessibilityIdentifier("settings-sync-log-row")
            #endif
            HITMenuRow("Details", systemImage: "info.circle", accessory: .expand(isExpanded: showSyncDetails)) {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showSyncDetails.toggle() }
            }
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
        .sheet(isPresented: $showSyncLog) {
            SyncLogSheet().slateSheet()
        }
    }

    private func runICloudCheck() {
        guard !isCheckingICloud else { return }
        isCheckingICloud = true
        Task {
            var result = await ICloudCheck.run()
            // ICloudCheck assumes every Mac build is Development; a TestFlight Mac build is Production. The
            // environment row above says which, so the check's own line leaves it out.
            result.isDevelopmentEnvironment = false
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
        detailRow("Account", CloudSyncMonitor.describe(monitor.accountStatus))
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

/// Shown while an import, export or setup has run for two minutes with nothing in its way
/// (`CloudSyncMonitor.stalledSince`): CloudKit syncs nothing else until it ends, and only a fresh process
/// gets it going again. The Mac relaunches in one click; the iPhone says how to reopen the app.
struct SyncStuckRow: View {
    let since: Date
    @State private var relaunchFailed = false

    var body: some View {
        #if os(macOS)
        HITMenuRow("Sync is stuck", subtitle: Self.detail(since: since), systemImage: "exclamationmark.arrow.circlepath",
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
        HITMenuRow("Sync is stuck", subtitle: Self.detail(since: since) + " " + Self.reopen,
                   systemImage: "exclamationmark.arrow.circlepath", iconTint: HITColor.danger)
            .accessibilityIdentifier("settings-sync-stuck")
        #endif
    }

    static let reopen = "Swipe HITList away in the app switcher and open it again."

    /// "iCloud sync has been busy with one request since 6:51 PM. Relaunching starts it afresh; your
    /// changes are kept and upload right after."
    static func detail(since: Date) -> String {
        let time = since.formatted(date: .omitted, time: .shortened)
        #if os(macOS)
        let verb = "Relaunching"
        #else
        let verb = "Reopening"
        #endif
        return "iCloud sync has been busy with one request since \(time). \(verb) starts it afresh; your changes are kept and upload right after."
    }
}

/// Which CloudKit environment and build this is ("Production · TestFlight build 11"), with the line
/// that explains why two devices on different environments never see each other's tasks.
struct SyncEnvironmentRow: View {
    var environment: SyncEnvironment = .current

    var body: some View {
        HITMenuRowLabel(environment.summary, subtitle: SyncEnvironment.explanation, systemImage: "server.rack",
                        iconTint: environment.cloudKit == .production ? Theme.secondaryText : HITColor.dueTomorrow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CloudKit environment: \(environment.summary). \(SyncEnvironment.explanation)")
            .accessibilityIdentifier("settings-sync-environment")
    }
}

/// The end of the iCloud block, set apart so it isn't tapped on the way to Check iCloud: Reset local
/// cache and re-download, with its confirmation and the "reopen" alert.
struct ResetLocalCacheGroup: View {
    @State private var confirmReset = false
    @State private var showReopenAlert = false

    static let footer = "Danger: this throws away this device's copy and downloads everything again from iCloud. Changes that haven't synced yet are lost."

    var body: some View {
        HITGroup(footer: Self.footer) {
            HITMenuRow("Reset local cache and re-download…", systemImage: "arrow.counterclockwise",
                       role: .destructive, accessory: .none) { confirmReset = true }
                .disabled(!LocalCacheReset.isAvailable)
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
