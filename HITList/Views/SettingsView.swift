import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HITListCore
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var notificationsEnabled = NotificationScheduler.isEnabled
    @State private var exportDocument: SnapshotDocument?
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var confirmReset = false
    @State private var showReopenAlert = false
    @State private var lastBackup = AppGroup.defaults.object(forKey: LocalBackup.lastBackupKey) as? Date
    @State private var backupMessage: String?
    @State private var showSyncDetails = false
    @State private var isCheckingICloud = false
    @State private var iCloudCheck: ICloudCheck?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        page
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
            .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                          document: exportDocument, contentType: .json,
                          defaultFilename: "HITList-\(Date().formatted(.iso8601.year().month().day()))") { _ in }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let snapshot = try Snapshot.from(json: try Data(contentsOf: url))
                    let summary = try SnapshotBuilder.restore(snapshot, into: context)
                    importMessage = "Imported from \(snapshot.deviceName): \(summary.description)"
                } catch {
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
            }
    }

    /// A sheet with Done on iPhone; the Settings window's own frame on the Mac.
    @ViewBuilder
    private var page: some View {
        #if os(iOS)
        HITSheetChrome("Settings", primaryTitle: "Done", cancelTitle: nil, background: Theme.background,
                       onPrimary: { dismiss() }) {
            groups
        }
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: HITSpacing.xl) { groups }
                .padding(HITSpacing.xl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(HITColor.text)
        .navigationTitle("Settings")
        #endif
    }

    @ViewBuilder
    private var groups: some View {
        HITGroup("iCloud Sync", footer: "Tasks sync through your private iCloud database at no cost. Sign in to iCloud on each device and the data follows.") {
            SyncStatusLine()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hitRowPadding()
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
            HITMenuRow("Reset local cache and re-download…", systemImage: "arrow.counterclockwise",
                       role: .destructive, accessory: .none) { confirmReset = true }
                .disabled(!LocalCacheReset.isAvailable)
        }

        HITGroup("Export & Import") {
            HITMenuRow("Export JSON…", systemImage: "square.and.arrow.up", accessory: .none) {
                if let snap = try? SnapshotBuilder.build(from: context) { exportDocument = SnapshotDocument(snapshot: snap) }
            }
            HITMenuRow("Import JSON…", systemImage: "square.and.arrow.down", accessory: .none) { showImporter = true }
            if let importMessage { message(importMessage) }
        }

        HITGroup("Backups", footer: backupsFooter) {
            TimelineView(.periodic(from: .now, by: 60)) { tick in
                HITMenuRow("Last backup", systemImage: "clock",
                           value: lastBackup.map { SyncState.relative($0, now: tick.date) } ?? "never")
            }
            HITMenuRow("Back up now", systemImage: "externaldrive", accessory: .none) { backUpNow() }
            #if os(macOS)
            HITMenuRow("Show backups in Finder", systemImage: "folder", accessory: .none) {
                let newest = LocalBackup.backups(in: LocalBackup.directory).last
                NSWorkspace.shared.activateFileViewerSelecting([newest ?? LocalBackup.directory])
            }
            #endif
            if let backupMessage { message(backupMessage) }
        }

        HITGroup("Reminders") {
            Toggle(isOn: $notificationsEnabled) {
                HITMenuRowLabel("Notify at due time", subtitle: "Only tasks with a specific time get a notification.",
                                systemImage: "bell")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            .onChange(of: notificationsEnabled) { _, on in
                Task {
                    if on, !(await NotificationScheduler.requestPermission()) { notificationsEnabled = false }
                    NotificationScheduler.isEnabled = notificationsEnabled
                    await NotificationScheduler.reschedule(context: context)
                }
            }
        }

        DelightSettingsSection()

        AppearanceSettingsSection()

        HITGroup("About") {
            HITMenuRow("Version", systemImage: "info.circle", value: AppInfo.versionLabel)
                .accessibilityIdentifier("settings-version")
        }
    }

    #if os(macOS)
    private let backupsFooter = "A copy of your data is saved once a day; the newest \(LocalBackup.keep) are kept. Restore one with Import JSON."
    #else
    private let backupsFooter = "A copy of your data is saved once a day in Files → On My iPhone → HITList; the newest \(LocalBackup.keep) are kept. Restore one with Import JSON."
    #endif

    /// The result of the last export, import or backup, under its buttons.
    private func message(_ text: String) -> some View {
        Text(text)
            .font(HITType.caption)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
    }

    #if os(macOS)
    private let resetActionTitle = "Reset and Relaunch"
    private let reopenMessage = "HITList couldn't relaunch itself. Quit it and open it again to download a fresh copy."
    #else
    private let resetActionTitle = "Reset"
    private let reopenMessage = "Swipe HITList away in the app switcher, then open it again. It downloads a fresh copy from iCloud when it starts."
    #endif

    private func backUpNow() {
        do {
            if let url = try LocalBackup.run(context: context) {
                lastBackup = AppGroup.defaults.object(forKey: LocalBackup.lastBackupKey) as? Date
                backupMessage = "Saved \(url.lastPathComponent)"
            } else {
                backupMessage = "Nothing to back up yet."
            }
        } catch {
            backupMessage = "Backup failed: \(error.localizedDescription)"
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

    private func resetLocalCache() {
        LocalCacheReset.request()
        #if os(macOS)
        LocalCacheReset.relaunch { showReopenAlert = true }
        #else
        showReopenAlert = true
        #endif
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

struct SnapshotDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var snapshot: Snapshot

    init(snapshot: Snapshot) { self.snapshot = snapshot }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        snapshot = try Snapshot.from(json: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.jsonData())
    }
}
