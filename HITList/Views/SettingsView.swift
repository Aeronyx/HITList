import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CloudKit
import HITListCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var notificationsEnabled = NotificationScheduler.isEnabled
    @State private var exportDocument: SnapshotDocument?
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    if ModelContainerFactory.isCloudKitEnabled {
                        Label("Syncing via iCloud", systemImage: "checkmark.icloud").foregroundStyle(.green)
                    } else {
                        Label("Local only", systemImage: "xmark.icloud").foregroundStyle(.orange)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if let err = ModelContainerFactory.startupError {
                    Text(err).font(.caption).foregroundStyle(.secondary)
                }
                if let status = CloudSyncMonitor.shared.accountStatus, status != .available {
                    Label(accountText(status), systemImage: "person.crop.circle.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
                }
                if let err = CloudSyncMonitor.shared.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        .textSelection(.enabled)
                } else if let ok = CloudSyncMonitor.shared.lastSuccess {
                    Text("Last \(ok.phase.rawValue) \(ok.at.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Tasks sync through your private iCloud database at no cost. Sign in to iCloud on each device and the data follows.")
            }
            .slateRow()

            Section("Export & Import") {
                Button("Export JSON…") {
                    if let snap = try? SnapshotBuilder.build(from: context) { exportDocument = SnapshotDocument(snapshot: snap) }
                }
                Button("Import JSON…") { showImporter = true }
                if let importMessage { Text(importMessage).font(.caption).foregroundStyle(.secondary) }
            }
            .slateRow()

            Section("Reminders") {
                Toggle("Notify at due time", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, on in
                        Task {
                            if on, !(await NotificationScheduler.requestPermission()) { notificationsEnabled = false }
                            NotificationScheduler.isEnabled = notificationsEnabled
                            await NotificationScheduler.reschedule(context: context)
                        }
                    }
                Text("Only tasks with a specific time get a notification.").font(.caption).foregroundStyle(.secondary)
            }
            .slateRow()
        }
        .formStyle(.grouped)
        .slateList()
        .navigationTitle("Settings")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            #endif
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

private func accountText(_ status: CKAccountStatus) -> String {
    switch status {
    case .noAccount: return "No iCloud account is signed in on this device."
    case .restricted: return "iCloud access is restricted on this device."
    case .couldNotDetermine: return "Couldn't determine iCloud account status."
    case .temporarilyUnavailable: return "iCloud is temporarily unavailable. Sync will resume automatically."
    default: return "iCloud available."
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
