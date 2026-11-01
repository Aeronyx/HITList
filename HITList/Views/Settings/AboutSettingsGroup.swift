import SwiftUI
import SwiftData

/// Settings → About: the version, Copy diagnostics and What's new (a sheet). The iPhone sheet's group;
/// the Mac page's About section builds on the same rows.
struct AboutSettingsGroup: View {
    @State private var showWhatsNew = false

    var body: some View {
        HITGroup("About") {
            HITMenuRow("Version", systemImage: "info.circle", value: AppInfo.versionLabel)
                .accessibilityIdentifier("settings-version")
            CopyDiagnosticsRow()
            HITMenuRow("What's new", systemImage: "sparkles") { showWhatsNew = true }
                .accessibilityIdentifier("settings-whats-new")
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet().slateSheet()
        }
    }
}

/// "Copy diagnostics": puts `Diagnostics.text` on the pasteboard and says "Copied" for two seconds.
struct CopyDiagnosticsRow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        HITMenuRow("Copy diagnostics", systemImage: "doc.on.doc", value: copied ? "Copied" : nil,
                   accessory: .none) { copy() }
            .accessibilityIdentifier("settings-copy-diagnostics")
    }

    private func copy() {
        let store = context.container.configurations.first?.url.path ?? "unknown"
        Task {
            Diagnostics.copy(await Diagnostics.current(storePath: store).text)
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { copied = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { copied = false }
        }
    }
}
