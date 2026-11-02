import Foundation
#if os(macOS)
import Security
#endif

/// Which CloudKit environment this binary syncs with and how it reached the device (brief 25, item 4).
///
/// Development and Production are two separate databases: a build signed for one never sees the
/// other's records. Builds run from Xcode (and the simulator) use Development; TestFlight and App Store
/// builds use Production (the export step rewrites the entitlement).
///
/// The answer comes from what the binary was signed with, the entitlements `codesign -d --entitlements`
/// prints for it (`resolve`): `SecTaskCopyValueForEntitlement` on the Mac, the code signature's
/// entitlements blob in the executable on iOS (`CodeSignature`). An export for App Store Connect carries
/// `beta-reports-active` and a Production `icloud-container-environment` (checked 2026-11-02 on the
/// TestFlight Mac app and on release.sh's iOS export); development signing carries `get-task-allow` and
/// Development. The receipt tells TestFlight from the App Store. The provisioning profile is only a
/// fallback for a binary whose signature can't be read.
///
/// One rule is absolute: a TestFlight or App Store build is never Development, whatever else is read. A
/// Development verdict there would open HITList-Development.store (`SyncStoreGuard`), an empty side
/// store, and look as though every task had been lost.
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

        /// Exported for App Store Connect: always Production.
        var isDistribution: Bool { self == .testFlight || self == .appStore }
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

    static let current: SyncEnvironment = resolve(Signals.gathered(), build: AppInfo.build)

    // MARK: - Detection

    static let cloudKitEnvironmentKey = "com.apple.developer.icloud-container-environment"
    static let iOSPushKey = "aps-environment"
    static let macPushKey = "com.apple.developer.aps-environment"
    /// Present in builds exported for App Store Connect (TestFlight, App Store), never in development signing.
    static let betaReportsKey = "beta-reports-active"
    static let iOSGetTaskAllowKey = "get-task-allow"
    static let macGetTaskAllowKey = "com.apple.security.get-task-allow"

    enum Platform: Sendable { case macOS, iOSDevice, iOSSimulator }

    /// Everything detection reads, gathered once at launch (`gathered()`), so every channel can be tested.
    struct Signals {
        var platform: Platform
        var isDebugBuild: Bool
        /// The binary's own signed entitlements; nil when they couldn't be read (an unsigned build).
        var entitlements: [String: Any]?
        /// Whether the bundle holds a provisioning profile, and the profile when it parsed (iOS only).
        var hasProfile: Bool
        var profile: ProvisioningProfile?
        var receipt: Receipt

        static func gathered() -> Signals {
            #if DEBUG
            let isDebug = true
            #else
            let isDebug = false
            #endif
            let receipt = SyncEnvironment.receiptKind(url: (Bundle.main as ReceiptLocating).appStoreReceiptURL)
            #if os(macOS)
            let profile = Bundle.main.bundleURL.appending(path: "Contents/embedded.provisionprofile")
            let entitlements = SyncEnvironment.processEntitlements()
                ?? Bundle.main.executableURL.flatMap(CodeSignature.entitlements(ofExecutableAt:))
            return Signals(platform: .macOS, isDebugBuild: isDebug, entitlements: entitlements,
                           hasProfile: FileManager.default.fileExists(atPath: profile.path), profile: nil, receipt: receipt)
            #else
            #if targetEnvironment(simulator)
            let platform = Platform.iOSSimulator
            #else
            let platform = Platform.iOSDevice
            #endif
            let profileData = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
            return Signals(platform: platform, isDebugBuild: isDebug,
                           entitlements: Bundle.main.executableURL.flatMap(CodeSignature.entitlements(ofExecutableAt:)),
                           hasProfile: profileData != nil, profile: profileData.flatMap(ProvisioningProfile.parse), receipt: receipt)
            #endif
        }
    }

    /// The environment and channel `signals` describe (see the type's comment for the rules).
    static func resolve(_ signals: Signals, build: String) -> SyncEnvironment {
        let entitlements = signals.entitlements
        let distribution = entitlements?[betaReportsKey] as? Bool == true
        let developmentSigned = entitlements?[iOSGetTaskAllowKey] as? Bool == true
            || entitlements?[macGetTaskAllowKey] as? Bool == true

        let channel: Channel
        if signals.isDebugBuild {
            channel = .debug
        } else if signals.receipt == .sandbox {
            channel = .testFlight
        } else if distribution {
            channel = signals.receipt == .production ? .appStore : .testFlight
        } else if developmentSigned {
            channel = .xcode
        } else {
            channel = Self.channel(isDebug: false, hasProfile: signals.hasProfile, receipt: signals.receipt)
        }

        let declared = cloudKitEnvironment(from: entitlements?[cloudKitEnvironmentKey])
        let iOSFallback = signals.platform == .iOSDevice ? resolveIOS(profile: signals.profile, hasProfile: signals.hasProfile) : nil
        let cloudKit: CloudKit
        if channel.isDistribution || distribution {
            cloudKit = .production
        } else if declared != .unknown {
            cloudKit = declared
        } else if signals.platform == .iOSSimulator {
            cloudKit = .development
        } else {
            cloudKit = iOSFallback?.cloudKit ?? .unknown
        }

        let pushKey = signals.platform == .macOS ? macPushKey : iOSPushKey
        var push = entitlements?[pushKey] as? String
        if push == nil { push = signals.platform == .iOSSimulator ? "development" : iOSFallback?.push }
        return SyncEnvironment(cloudKit: cloudKit, push: push, channel: channel, build: build)
    }

    #if os(macOS)
    /// The keys `resolve` reads, from the running process's signed entitlements; nil when none can be read.
    private static func processEntitlements() -> [String: Any]? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        var values: [String: Any] = [:]
        for key in [cloudKitEnvironmentKey, macPushKey, betaReportsKey, macGetTaskAllowKey] {
            if let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) { values[key] = value }
        }
        return values.isEmpty ? nil : values
    }
    #endif

    /// The entitlement's value: "Production" / "Development", or (in a development provisioning profile)
    /// an array of the environments allowed, which only says which one when it holds exactly one.
    static func cloudKitEnvironment(from value: Any?) -> CloudKit {
        if let string = value as? String { return CloudKit(rawValue: string) ?? .unknown }
        if let values = value as? [String], values.count == 1 { return CloudKit(rawValue: values[0]) ?? .unknown }
        return .unknown
    }

    /// iOS device builds whose signature couldn't be read: no profile means App Store or TestFlight
    /// (Production). With a profile, its entitlements decide; a development profile allows both
    /// environments, and this app's entitlements file asks for Development, so a profile with
    /// `get-task-allow` (development signing) means Development.
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

    /// The channel from the build type, the profile and the receipt alone: the fallback for a binary
    /// whose entitlements couldn't be read.
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

/// The entitlements a Mach-O executable was signed with, read from its code signature: the
/// LC_CODE_SIGNATURE super blob's entitlements slot, an XML property list. What `codesign -d
/// --entitlements` prints; iOS has no SecTask to ask. Bounds-checked throughout: anything unexpected is nil.
enum CodeSignature {
    static func entitlements(ofExecutableAt url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return entitlements(inExecutable: data)
    }

    static func entitlements(inExecutable data: Data) -> [String: Any]? {
        let bytes = Bytes(data: data)
        guard let slice = firstSlice(bytes), let signature = signatureRange(bytes, slice: slice),
              let xml = entitlementsXML(bytes, superBlob: signature) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
    }

    private static let machHeader64: UInt32 = 0xFEED_FACF
    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fatMagic64: UInt32 = 0xCAFE_BABF
    private static let loadCodeSignature: UInt32 = 0x1D
    private static let superBlobMagic: UInt32 = 0xFADE_0CC0
    private static let entitlementsMagic: UInt32 = 0xFADE_7171
    private static let entitlementsSlot: UInt32 = 5

    /// Where the (first) 64-bit Mach-O starts: 0 for a thin binary, the first architecture of a fat one.
    private static func firstSlice(_ b: Bytes) -> Int? {
        if b.u32le(0) == machHeader64 { return 0 }
        switch b.u32be(0) {
        case fatMagic?:
            guard let count = b.u32be(4), count > 0, let offset = b.u32be(8 + 8) else { return nil }
            return b.u32le(Int(offset)) == machHeader64 ? Int(offset) : nil
        case fatMagic64?:
            guard let count = b.u32be(4), count > 0, let offset = b.u64be(8 + 8), offset < UInt64(Int.max) else { return nil }
            return b.u32le(Int(offset)) == machHeader64 ? Int(offset) : nil
        default:
            return nil
        }
    }

    /// The code signature's offset (from the file's start) and size, from LC_CODE_SIGNATURE.
    private static func signatureRange(_ b: Bytes, slice: Int) -> (offset: Int, size: Int)? {
        guard let commands = b.u32le(slice + 16), commands < 10_000 else { return nil }
        var at = slice + 32
        for _ in 0..<commands {
            guard let command = b.u32le(at), let size = b.u32le(at + 4), size >= 8 else { return nil }
            if command == loadCodeSignature {
                guard let offset = b.u32le(at + 8), let length = b.u32le(at + 12) else { return nil }
                return (slice + Int(offset), Int(length))
            }
            at += Int(size)
        }
        return nil
    }

    /// The entitlements blob's XML inside the signature's super blob (big-endian, offsets from its start).
    private static func entitlementsXML(_ b: Bytes, superBlob: (offset: Int, size: Int)) -> Data? {
        let start = superBlob.offset
        guard b.u32be(start) == superBlobMagic, let count = b.u32be(start + 8), count < 64 else { return nil }
        for i in 0..<Int(count) {
            let entry = start + 12 + 8 * i
            guard let type = b.u32be(entry), let offset = b.u32be(entry + 4) else { return nil }
            guard type == entitlementsSlot else { continue }
            let blob = start + Int(offset)
            guard b.u32be(blob) == entitlementsMagic, let length = b.u32be(blob + 4), length > 8 else { return nil }
            return b.data(blob + 8, Int(length) - 8)
        }
        return nil
    }

    /// Bounds-checked reads; nil past the end.
    private struct Bytes {
        let data: Data

        func data(_ offset: Int, _ count: Int) -> Data? {
            guard offset >= 0, count >= 0, offset <= data.count - count else { return nil }
            let start = data.startIndex + offset
            return data.subdata(in: start..<start + count)
        }

        func u32le(_ offset: Int) -> UInt32? {
            data(offset, 4).map { $0.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        }

        func u32be(_ offset: Int) -> UInt32? {
            data(offset, 4).map { $0.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        }

        func u64be(_ offset: Int) -> UInt64? {
            data(offset, 8).map { $0.reduce(UInt64(0)) { $0 << 8 | UInt64($1) } }
        }
    }
}

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
