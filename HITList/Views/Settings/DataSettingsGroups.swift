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
    // Brief 137: Import from Todoist, its preview and Undo last import.
    @State private var todoist = TodoistImportModel()
    @State private var showTodoistPicker = false
    @State private var confirmTodoistUndo = false

    static let todoistFooter = "From Todoist: Settings → Backups → Download (a .zip), or a project's ⋯ → Import & export → Export as CSV."

    var body: some View {
        Group {
            HITGroup("Export & Import", footer: Self.todoistFooter) {
                HITMenuRow("Export JSON…", systemImage: "square.and.arrow.up", accessory: .none) {
                    if let snap = try? SnapshotBuilder.build(from: context) { exportDocument = SnapshotDocument(snapshot: snap) }
                }
                HITMenuRow("Import JSON…", systemImage: "square.and.arrow.down", accessory: .none) { showImporter = true }
                if let importMessage { SettingsMessage(text: importMessage) }
                HITMenuRow("Import from Todoist…", systemImage: "tray.and.arrow.down", accessory: .none) { showTodoistPicker = true }
                    .accessibilityIdentifier("todoist-import-row")
                if let receipt = todoist.receipt {
                    HITMenuRow("Undo last import", subtitle: receipt.summary, systemImage: "arrow.uturn.backward",
                               role: .destructive, accessory: .none) { confirmTodoistUndo = true }
                        .accessibilityIdentifier("todoist-undo-row")
                }
                if let message = todoist.message {
                    SettingsMessage(text: message).accessibilityIdentifier("todoist-message")
                }
            }
            if let plan = todoist.plan {
                TodoistImportCard(model: todoist, plan: plan)
            }
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
        .fileImporter(isPresented: $showTodoistPicker, allowedContentTypes: [.zip, .commaSeparatedText, .plainText],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let files = urls.compactMap { url -> TodoistFiles.File? in
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                return (try? Data(contentsOf: url)).map { TodoistFiles.File(name: url.lastPathComponent, data: $0) }
            }
            todoist.load(files, context: context)
        }
        .confirmationDialog("Undo the last Todoist import?", isPresented: $confirmTodoistUndo, titleVisibility: .visible) {
            Button("Remove \(TodoistMapping.count(todoist.receipt?.taskIDs.count ?? 0, "task"))", role: .destructive) {
                todoist.undo(context: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(todoist.undoQuestion)
        }
        .onAppear {
            guard TodoistFixture.isRequested, !TodoistImportModel.fixtureShown else { return }
            TodoistImportModel.fixtureShown = true
            todoist.load(TodoistFixture.files, context: context)
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
    static let footer = "Saved once a day in Files → On My iPhone → HITList; the newest \(LocalBackup.keep) are kept. Restore one with Import JSON."
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

/// Words a disclosure row opens (how to sign out, how to delete everything from iCloud): the caption type, selectable,
/// lined up with the row titles above it.
struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HITType.caption)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, HITRowMetrics.titleInset)
            .hitRowPadding()
            .textSelection(.enabled)
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
