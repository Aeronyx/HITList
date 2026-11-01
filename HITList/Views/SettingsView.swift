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

    @State private var exportDocument: SnapshotDocument?
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var lastBackup = AppGroup.defaults.object(forKey: LocalBackup.lastBackupKey) as? Date
    @State private var backupMessage: String?
    @State private var showWhatsNew = false
    @State private var diagnosticsCopied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        page
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
        GeneralSettingsSection()

        ICloudSyncGroup()
        ResetLocalCacheGroup()

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

        RemindersSettingsSection()

        DelightSettingsSection()

        AppearanceSettingsSection()

        HITGroup("About") {
            HITMenuRow("Version", systemImage: "info.circle", value: AppInfo.versionLabel)
                .accessibilityIdentifier("settings-version")
            HITMenuRow("Copy diagnostics", systemImage: "doc.on.doc", value: diagnosticsCopied ? "Copied" : nil,
                       accessory: .none) { copyDiagnostics() }
                .accessibilityIdentifier("settings-copy-diagnostics")
            HITMenuRow("What's new", systemImage: "sparkles") { showWhatsNew = true }
                .accessibilityIdentifier("settings-whats-new")
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet().slateSheet()
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

    private func copyDiagnostics() {
        let store = context.container.configurations.first?.url.path ?? "unknown"
        Task {
            Diagnostics.copy(await Diagnostics.current(storePath: store).text)
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { diagnosticsCopied = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { diagnosticsCopied = false }
        }
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
