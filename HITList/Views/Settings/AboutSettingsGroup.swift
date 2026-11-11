import SwiftUI
import SwiftData

/// Settings → About: the version, Copy diagnostics, What's New (a page of its own, `SettingsPage.whatsNew`), Show
/// tips again and the privacy policy. The iPhone sheet's page; the Mac page's About section builds on the same rows.
struct AboutSettingsGroup: View {
    @Environment(\.hitPages) private var pages

    var body: some View {
        HITGroup("About") {
            HITMenuRow("Version", systemImage: "info.circle", value: AppInfo.versionLabel)
                .accessibilityIdentifier("settings-version")
            CopyDiagnosticsRow()
            HITMenuRow("What's new", systemImage: "sparkles") { pages(SettingsPage.whatsNew) }
                .accessibilityIdentifier("settings-whats-new")
            ShowTipsAgainRow()
            PrivacyPolicyRow()
        }
    }
}

/// What's New as groups: this version's list, then the earlier versions behind a disclosure row. About → What's New
/// on iPhone and iPad, and inline in the Mac's About section.
struct WhatsNewGroups: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEarlier = false

    var body: some View {
        if let current = WhatsNew.current {
            HITGroup("What's new in \(current.label)") {
                WhatsNewItems(entry: current)
            }
            .accessibilityIdentifier("settings-whats-new-inline")

            let earlier = Array(WhatsNew.entries.dropFirst())
            if !earlier.isEmpty {
                HITGroup {
                    HITMenuRow("Earlier versions", systemImage: "clock.arrow.circlepath",
                               value: earlier.map(\.label).joined(separator: ", "),
                               accessory: .expand(isExpanded: showEarlier)) {
                        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { showEarlier.toggle() }
                    }
                    .accessibilityIdentifier("settings-whats-new-earlier")
                }
                if showEarlier {
                    ForEach(earlier) { entry in
                        HITGroup("Version \(entry.label)") { WhatsNewItems(entry: entry) }
                    }
                }
            }
        }
    }
}

/// "Privacy policy": opens the policy page in the browser. In About on the iPhone and the Mac.
struct PrivacyPolicyRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HITMenuRow("Privacy policy", subtitle: "HITList collects nothing; your data stays in your iCloud",
                   systemImage: "hand.raised", accessory: .chevron) {
            openURL(AboutInfo.privacyPolicyURL)
        }
        #if os(macOS)
        .help(AboutInfo.privacyPolicyURL.absoluteString)
        #endif
        .accessibilityIdentifier("settings-privacy-policy")
    }
}

/// "Show tips again": every first-run tip (`HITTips`) shows once more, the next time its moment comes.
/// Says "Done" for two seconds.
struct ShowTipsAgainRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done = false

    var body: some View {
        HITMenuRow("Show tips again", subtitle: "The short tips new people see, once each",
                   systemImage: "lightbulb", value: done ? "Done" : nil, accessory: .none) {
            HITTips.showAgain()
            Task {
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { done = true }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { done = false }
            }
        }
        .accessibilityIdentifier("settings-show-tips")
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
            Diagnostics.copy(await Diagnostics.current(storePath: store, context: context).text)
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { copied = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { copied = false }
        }
    }
}
