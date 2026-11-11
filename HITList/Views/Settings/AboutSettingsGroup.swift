import SwiftUI
import SwiftData

/// Settings → About on iPhone and iPad: the version and What's New (a page of its own, `SettingsPage.whatsNew`), the
/// privacy policy, Show tips again, then Send Beta Feedback… with Copy diagnostics beside it. No header: the page's
/// title says About. The Mac's About section (`MacAboutSection`) builds on the same rows.
struct AboutSettingsGroup: View {
    @Environment(\.hitPages) private var pages

    var body: some View {
        HITGroup {
            HITMenuRow("Version", systemImage: "info.circle", value: AppInfo.versionLabel)
                .accessibilityIdentifier("settings-version")
            HITMenuRow("What's New", systemImage: "sparkles") { pages(SettingsPage.whatsNew) }
                .accessibilityIdentifier("settings-whats-new")
            PrivacyPolicyRow()
            ShowTipsAgainRow()
        }
        HITGroup {
            SendFeedbackRow()
            CopyDiagnosticsRow()
        }
    }
}

/// "Send Beta Feedback…", as the profile menu's row does it (`SendBetaFeedbackAction`): a mail to George on iPhone
/// and iPad (the card with the address when no mail app opens it), the address copied and the card at once on the Mac.
struct SendFeedbackRow: View {
    @Environment(\.openURL) private var openURL
    @State private var showsCard = false

    var body: some View {
        HITMenuRow(ProfileMenuModel.feedbackTitle, systemImage: "envelope", accessory: .none) {
            SendBetaFeedbackAction(openURL: openURL) { showsCard = true }()
        }
        .betaFeedbackCard(isPresented: $showsCard)
        .accessibilityIdentifier("settings-feedback")
    }
}

/// What's New as one group: this version's list only (brief 99, George: "Earlier versions isn't even a necessary
/// feature"; the Mac's About links every version's notes on GitHub). About → What's New on iPhone and iPad (a page
/// titled What's New, so its group says "Version 0.9.3"), and inline in the Mac's About section ("What's new in 0.9.3").
struct WhatsNewGroups: View {
    #if os(macOS)
    private static let inline = true
    #else
    private static let inline = false
    #endif

    var body: some View {
        if let current = WhatsNew.current {
            HITGroup(Self.inline ? "What's new in \(current.label)" : "Version \(current.label)") {
                WhatsNewItems(entry: current)
            }
            .accessibilityIdentifier("settings-whats-new-inline")
        }
    }
}

/// "Privacy policy": opens the policy page in the browser. In About on the iPhone and the Mac.
struct PrivacyPolicyRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HITMenuRow("Privacy policy", subtitle: "HITList collects nothing",
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
