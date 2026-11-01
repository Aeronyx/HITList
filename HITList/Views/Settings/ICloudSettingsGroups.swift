import SwiftUI
import SwiftData

/// Settings → iCloud Sync: the status line, Details, Check iCloud…. Shared by the iPhone sheet and the
/// Mac page's iCloud section, which adds the "Last change" row (`showsLastChange`).
struct ICloudSyncGroup: View {
    var showsLastChange = false
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSyncDetails = false
    @State private var isCheckingICloud = false
    @State private var iCloudCheck: ICloudCheck?

    static let footer = "Tasks sync through your private iCloud database at no cost. Sign in to iCloud on each device and the data follows."

    var body: some View {
        HITGroup("iCloud Sync", footer: Self.footer) {
            SyncStatusLine()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hitRowPadding()
            if showsLastChange {
                LastSyncChangeRow()
            }
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
    }

    private func runICloudCheck() {
        guard !isCheckingICloud else { return }
        isCheckingICloud = true
        Task {
            let result = await ICloudCheck.run()
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
