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

    /// "iOS 26.1 (Build 23B85)" / "macOS 26.7.1 (Build 25G…)".
    static var osVersion: String {
        #if os(iOS)
        let name = "iOS"
        #else
        let name = "macOS"
        #endif
        return "\(name) \(ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: ""))"
    }

    /// The hardware model identifier: "iPhone17,3", "Mac16,10"; a simulator reports the model it simulates.
    static let deviceModel: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return "\(simulated) (Simulator)" }
        #if os(macOS)
        return sysctlString("hw.model") ?? "Mac"
        #else
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "iPhone" : machine
        #endif
    }()

    #if os(macOS)
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    #endif

    private static func string(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
