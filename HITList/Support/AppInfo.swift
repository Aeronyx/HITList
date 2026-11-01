import Foundation

/// The running build's version, read once from the bundle. Settings shows it; bug reports quote it.
enum AppInfo {
    /// The marketing version, e.g. "0.1.0" (`MARKETING_VERSION` in project.yml).
    static let version = string("CFBundleShortVersionString") ?? "0"
    /// The build number, e.g. "6" (`CURRENT_PROJECT_VERSION`; `scripts/release.sh` bumps it every upload).
    static let build = string("CFBundleVersion") ?? "0"
    /// "0.1.0 (6)", the form TestFlight uses.
    static var versionLabel: String { label(version: version, build: build) }

    static func label(version: String, build: String) -> String { "\(version) (\(build))" }

    private static func string(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
