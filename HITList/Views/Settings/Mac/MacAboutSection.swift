import SwiftUI

/// Settings → About on the Mac: version and build date, Copy diagnostics, the Changelog on GitHub, Show
/// tips again, then
/// What's new inline (this version's list, earlier versions behind a disclosure row) instead of a sheet.
struct MacAboutSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEarlier = false

    var body: some View {
        HITGroup("About") {
            HITMenuRow("Version", systemImage: "info.circle", value: AppInfo.versionLabel)
                .accessibilityIdentifier("settings-version")
            HITMenuRow("Built", systemImage: "hammer", value: AboutInfo.buildDate().map(AboutInfo.buildDateText) ?? "Unknown")
                .accessibilityIdentifier("settings-build-date")
            CopyDiagnosticsRow()
            HITMenuRow("Changelog", subtitle: "Every version's notes, on GitHub", systemImage: "list.bullet.rectangle",
                       accessory: .chevron) {
                openURL(AboutInfo.changelogURL(version: AppInfo.version))
            }
            .help(AboutInfo.changelogURL(version: AppInfo.version).absoluteString)
            .accessibilityIdentifier("settings-changelog")
            ShowTipsAgainRow()
            PrivacyPolicyRow()
        }

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
