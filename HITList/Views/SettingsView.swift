import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HITListCore

/// Settings. On iPhone and iPad, a sheet with Done holding every group in one column. On the Mac,
/// Settings is a page inside the window (`MacSettingsPage`, `SidebarItem.settings`) built from the same
/// groups, one section at a time; this view shows that page there.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        HITSheetChrome("Settings", primaryTitle: "Done", cancelTitle: nil, background: Theme.background,
                       onPrimary: { dismiss() }) {
            Self.allGroups
        }
        #else
        MacSettingsPage()
        #endif
    }

    /// Every group, in the iPhone sheet's order. The Mac page shows the same pieces per section
    /// (`MacSettingsSectionContent`).
    @ViewBuilder
    static var allGroups: some View {
        AccountSettingsSection()
        GeneralSettingsSection()
        ICloudSyncGroup()
        ResetLocalCacheGroup()
        ExportImportGroup()
        BackupsGroup()
        RemindersSettingsSection()
        DelightSettingsSection()
        AppearanceSettingsSection()
        AboutSettingsGroup()
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
