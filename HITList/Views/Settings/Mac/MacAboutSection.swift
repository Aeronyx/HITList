import SwiftUI

/// Settings → About on the Mac: the version and build date, the Changelog on GitHub, the privacy policy, Show tips
/// again, then Send Beta Feedback… with Copy diagnostics beside it, and What's New inline (this version's list, earlier
/// versions behind a disclosure row) instead of a page. No header: the page's title says About.
struct MacAboutSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HITGroup {
            HITMenuRow("Version", systemImage: "info.circle", value: AppInfo.versionLabel)
                .accessibilityIdentifier("settings-version")
            HITMenuRow("Built", systemImage: "hammer", value: AboutInfo.buildDate().map(AboutInfo.buildDateText) ?? "Unknown")
                .accessibilityIdentifier("settings-build-date")
            HITMenuRow("Changelog", subtitle: "Every version's notes, on GitHub", systemImage: "list.bullet.rectangle",
                       accessory: .chevron) {
                openURL(AboutInfo.changelogURL(version: AppInfo.version))
            }
            .help(AboutInfo.changelogURL(version: AppInfo.version).absoluteString)
            .accessibilityIdentifier("settings-changelog")
            PrivacyPolicyRow()
            ShowTipsAgainRow()
        }
        HITGroup {
            SendFeedbackRow()
            CopyDiagnosticsRow()
        }

        WhatsNewGroups()
    }
}

/// The About section's facts that don't belong to `AppInfo`'s version strings.
enum AboutInfo {
    /// The repository's releases, one per version tag (`v0.3.0`); the page lists the CHANGELOG notes.
    static let releasesURL = URL(string: "https://github.com/Aeronyx/HITList/releases")!

    /// The privacy policy (`docs/privacy.md`, published by GitHub Pages from master's `docs/`).
    static let privacyPolicyURL = URL(string: "https://aeronyx.github.io/HITList/privacy/")!

    /// The GitHub release for `version` ("…/releases/tag/v0.3.0"); the releases list for an unusable one.
    static func changelogURL(version: String) -> URL {
        let allowed = version.allSatisfy { $0.isNumber || $0 == "." }
        guard !version.isEmpty, allowed, version.first?.isNumber == true else { return releasesURL }
        return releasesURL.appending(path: "tag").appending(path: "v\(version)")
    }

    /// When this build was made: the modification date of the bundle's executable (set by the linker).
    static func buildDate(bundle: Bundle = .main, fileManager: FileManager = .default) -> Date? {
        guard let path = bundle.executableURL?.path else { return nil }
        return (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// "Nov 1, 2026 at 4:20 PM" in the user's locale.
    static func buildDateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
