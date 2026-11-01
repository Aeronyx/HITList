import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HITListCore
#if os(macOS)
import AppKit
#endif

/// Settings → Export & Import: a JSON snapshot out, or one back in (merged by `SnapshotBuilder.restore`).
/// Shared by the iPhone sheet and the Mac page's Data section.
struct ExportImportGroup: View {
    @Environment(\.modelContext) private var context
    @State private var exportDocument: SnapshotDocument?
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        HITGroup("Export & Import") {
            HITMenuRow("Export JSON…", systemImage: "square.and.arrow.up", accessory: .none) {
                if let snap = try? SnapshotBuilder.build(from: context) { exportDocument = SnapshotDocument(snapshot: snap) }
            }
            HITMenuRow("Import JSON…", systemImage: "square.and.arrow.down", accessory: .none) { showImporter = true }
            if let importMessage { SettingsMessage(text: importMessage) }
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
}

/// Settings → Backups: the daily local copy, Back up now, and (Mac) Show backups in Finder.
struct BackupsGroup: View {
    @Environment(\.modelContext) private var context
    @State private var lastBackup = AppGroup.defaults.object(forKey: LocalBackup.lastBackupKey) as? Date
    @State private var backupMessage: String?

    #if os(macOS)
    static let footer = "A copy of your data is saved once a day; the newest \(LocalBackup.keep) are kept. Restore one with Import JSON."
    #else
    static let footer = "A copy of your data is saved once a day in Files → On My iPhone → HITList; the newest \(LocalBackup.keep) are kept. Restore one with Import JSON."
    #endif

    var body: some View {
        HITGroup("Backups", footer: Self.footer) {
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
            if let backupMessage { SettingsMessage(text: backupMessage) }
        }
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
}

/// The result of the last export, import or backup, under its buttons.
struct SettingsMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HITType.caption)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hitRowPadding()
    }
}
