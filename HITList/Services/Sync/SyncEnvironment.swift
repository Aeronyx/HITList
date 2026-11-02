import Foundation
#if os(macOS)
import Security
#endif

/// Which CloudKit environment this binary syncs with and how it reached the device (brief 25, item 4).
///
/// Development and Production are two separate databases: a build signed for one never sees the
/// other's records. Builds run from Xcode (and the simulator) use Development; TestFlight and App Store
/// builds use Production (the export step rewrites the entitlement). The environment is read from the
/// signed entitlement on macOS (`SecTaskCopyValueForEntitlement`) and from `embedded.mobileprovision`
/// on iOS (a TestFlight or App Store build has no profile and is always Production).
struct SyncEnvironment: Equatable, Sendable {
    enum CloudKit: String, Sendable {
        case production = "Production"
        case development = "Development"
        case unknown = "Unknown"
    }

    enum Channel: String, Sendable {
        /// A Debug build from Xcode.
        case debug = "Debug"
        /// A Release build signed for development (run from Xcode, or copied out of DerivedData).
        case xcode = "Xcode"
        case testFlight = "TestFlight"
        case appStore = "App Store"
        case unknown = "Unknown"
    }

    var cloudKit: CloudKit
    /// `aps-environment`: "production" or "development"; nil when it couldn't be read.
    var push: String?
    var channel: Channel
    var build: String

    /// "Production · TestFlight build 11".
    var summary: String { "\(cloudKit.rawValue) · \(channel.rawValue) build \(build)" }

    var isDevelopment: Bool { cloudKit == .development }

    /// Settings → iCloud's line under the environment row.
    static let explanation = "A Mac run from Xcode syncs with Development; TestFlight builds sync with Production, so the two don't see each other."

    static let current: SyncEnvironment = detect()

    // MARK: - Detection

    static let cloudKitEnvironmentKey = "com.apple.developer.icloud-container-environment"
    static let iOSPushKey = "aps-environment"
    static let macPushKey = "com.apple.developer.aps-environment"

    private static func detect() -> SyncEnvironment {
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        let build = AppInfo.build
        let receipt = receiptKind(url: (Bundle.main as ReceiptLocating).appStoreReceiptURL)
        #if os(macOS)
        let cloudKit = cloudKitEnvironment(from: entitlement(cloudKitEnvironmentKey))
        let push = entitlement(macPushKey) as? String
        return SyncEnvironment(cloudKit: cloudKit, push: push,
                               channel: channel(isDebug: isDebug, hasProfile: hasMacProfile, receipt: receipt), build: build)
        #elseif targetEnvironment(simulator)
        // Simulator builds carry no profile and always run against Development; count them as Xcode's.
        return SyncEnvironment(cloudKit: .development, push: "development",
                               channel: channel(isDebug: isDebug, hasProfile: true, receipt: receipt), build: build)
        #else
        let profileData = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        let profile = profileData.flatMap(ProvisioningProfile.parse)
        let resolved = resolveIOS(profile: profile, hasProfile: profileData != nil)
        return SyncEnvironment(cloudKit: resolved.cloudKit, push: resolved.push,
                               channel: channel(isDebug: isDebug, hasProfile: profileData != nil, receipt: receipt), build: build)
        #endif
    }

    #if os(macOS)
    private static func entitlement(_ key: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }

    private static var hasMacProfile: Bool {
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appending(path: "Contents/embedded.provisionprofile").path)
    }
    #endif

    /// The entitlement's value: "Production" / "Development", or (in a development provisioning profile)
    /// an array of the environments allowed, which only says which one when it holds exactly one.
    static func cloudKitEnvironment(from value: Any?) -> CloudKit {
        if let string = value as? String { return CloudKit(rawValue: string) ?? .unknown }
        if let values = value as? [String], values.count == 1 { return CloudKit(rawValue: values[0]) ?? .unknown }
        return .unknown
    }

    /// iOS device builds: no profile means App Store or TestFlight (Production). With a profile, its
    /// entitlements decide; a development profile allows both environments, and this app's entitlements
    /// file asks for Development, so a profile with `get-task-allow` (development signing) means Development.
    static func resolveIOS(profile: ProvisioningProfile?, hasProfile: Bool) -> (cloudKit: CloudKit, push: String?) {
        guard hasProfile else { return (.production, "production") }
        guard let profile else { return (.unknown, nil) }
        var cloudKit = cloudKitEnvironment(from: profile.entitlements[cloudKitEnvironmentKey])
        if cloudKit == .unknown, profile.entitlements[cloudKitEnvironmentKey] != nil {
            cloudKit = profile.getTaskAllow ? .development : .production
        }
        return (cloudKit, profile.entitlements[iOSPushKey] as? String)
    }

    enum Receipt: Equatable, Sendable {
        case none
        /// TestFlight: iOS names the file "sandboxReceipt"; a Mac TestFlight receipt says "ProductionSandbox".
        case sandbox
        case production
    }

    /// Reads only the file name and, for a Mac receipt, whether its bytes name the sandbox environment.
    static func receiptKind(url: URL?, fileManager: FileManager = .default) -> Receipt {
        guard let url else { return .none }
        if url.lastPathComponent == "sandboxReceipt" { return .sandbox }
        guard let data = fileManager.contents(atPath: url.path), !data.isEmpty else { return .none }
        return receiptKind(contents: data)
    }

    static func receiptKind(contents data: Data) -> Receipt {
        data.range(of: Data("ProductionSandbox".utf8)) != nil ? .sandbox : .production
    }

    static func channel(isDebug: Bool, hasProfile: Bool, receipt: Receipt) -> Channel {
        if isDebug { return .debug }
        switch receipt {
        case .sandbox: return .testFlight
        case .production: return hasProfile ? .xcode : .appStore
        case .none: return hasProfile ? .xcode : .unknown
        }
    }
}

/// `Bundle.appStoreReceiptURL` is deprecated in favour of StoreKit's `AppTransaction`, which may go to
/// the network; the receipt's name and bytes are all the channel needs, read through this protocol so
/// the deprecation doesn't warn.
private protocol ReceiptLocating {
    var appStoreReceiptURL: URL? { get }
}

extension Bundle: ReceiptLocating {}

/// The parts of an `embedded.mobileprovision` the environment needs. The file is a CMS envelope around
/// an XML property list; the plist is cut out between `<?xml` and `</plist>`.
struct ProvisioningProfile: Equatable {
    var name: String?
    var entitlements: [String: Any]
    var getTaskAllow: Bool { entitlements["get-task-allow"] as? Bool ?? false }

    static func parse(_ data: Data) -> ProvisioningProfile? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let root = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any] else { return nil }
        return ProvisioningProfile(name: root["Name"] as? String, entitlements: root["Entitlements"] as? [String: Any] ?? [:])
    }

    static func == (a: ProvisioningProfile, b: ProvisioningProfile) -> Bool {
        a.name == b.name && NSDictionary(dictionary: a.entitlements).isEqual(to: b.entitlements)
    }
}
