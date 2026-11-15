import Foundation
import HITListCore

/// Which engine syncs this launch's store (round 28, brief 143): SwiftData's CloudKit mirror, as every released build
/// so far, or HITList's own engine (`dev/SYNC-ENGINE.md`). One answer per launch, decided before the container opens,
/// because the answer decides how it opens (the engine needs the same file without the mirror).
///
/// `own` only when
/// - the store's own preference says so (`AppGroup.defaults`, a key per store name, written by the move,
///   `SyncEngine.move(to:)`), or
/// - a Debug build was launched on a side store with `-syncEngine own` (`-syncEngine mirror` wins the other way, over
///   the preference).
/// Never under hosted tests (the tests call `decide` themselves), and the engine never runs on the in-memory fallback
/// (`SyncEngine.launch` says why instead). Nothing writes the preference in a released build unless a person moves the
/// device, and no released build offers that yet, so every released build answers `mirror` and runs nothing of the
/// engine's.
enum SyncEngineSwitch {
    typealias Engine = SyncEngineBoard.Engine

    /// The container the engine's zone lives in: today the tasks' own container, under the `HL` record types and with
    /// the mirror off on the stores that use the engine. A container of its own (`iCloud.com.trammells.hitlist.sync`)
    /// waits for George (`dev/SYNC-ENGINE.md` section 12, decision 0).
    static let containerID = HITListSchema.cloudKitContainerID

    /// The launch argument a Debug build takes on a side store.
    static let argument = "-syncEngine"
    /// Debug, side stores only: the zone the engine uses instead of `SyncSchema.zoneName`, for the supervisor's runs on
    /// CloudKit Development (`-syncEngineZone HITList-run1`).
    static let zoneArgument = "-syncEngineZone"
    /// Debug, side stores only: the engine runs on a pretend iCloud kept in a file (`PretendCloud`), named by the
    /// argument's value (`-syncEnginePretend two-macs`): two Debug apps on two side stores with the same name sync with
    /// each other and never with iCloud.
    static let pretendArgument = "-syncEnginePretend"

    /// The preference's key for the store named `storeName` (`HITList.store`, `HITList-s143.store`): every build on a
    /// device shares the App Group's defaults, so the key names its store, as `resetLocalStoreOnNextLaunch` does.
    static func preferenceKey(storeName: String) -> String { "syncEngine.\(storeName)" }

    /// The answer, from what the launch was given. Pure, for the tests.
    static func decide(storeName: String, isTesting: Bool, isDebug: Bool, arguments: [String],
                       defaults: UserDefaults) -> Engine {
        if isTesting { return .mirror }
        let isSideStore = storeName != ModelContainerFactory.mainStoreName
        if isDebug, isSideStore, let asked = value(of: argument, in: arguments).flatMap(Engine.init(rawValue:)) {
            return asked
        }
        // A pretend iCloud is the engine's by definition; side stores in Debug builds only.
        if isDebug, isSideStore, value(of: pretendArgument, in: arguments) != nil { return .own }
        if defaults.string(forKey: preferenceKey(storeName: storeName)) == Engine.own.rawValue { return .own }
        return .mirror
    }

    /// The zone the engine uses: `SyncSchema.zoneName`, or a Debug side store's `-syncEngineZone`.
    static func zoneName(storeName: String, isDebug: Bool, arguments: [String]) -> String {
        guard isDebug, storeName != ModelContainerFactory.mainStoreName,
              let zone = value(of: zoneArgument, in: arguments), !zone.isEmpty,
              zone.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return SyncSchema.zoneName }
        return zone
    }

    /// The pretend iCloud's name, on a Debug side store that asked for one; nil otherwise.
    static func pretendName(storeName: String, isDebug: Bool, arguments: [String]) -> String? {
        guard isDebug, storeName != ModelContainerFactory.mainStoreName,
              let name = value(of: pretendArgument, in: arguments), !name.isEmpty,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return name
    }

    // MARK: - This launch

    /// This launch's answer, set once by `ModelContainerFactory.make()` before it opens the container.
    nonisolated(unsafe) private(set) static var current: Engine = .mirror

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Decides for this process and remembers it (`current`). Called once, by `ModelContainerFactory.make()`.
    @discardableResult
    static func decideForLaunch(storeName: String = ModelContainerFactory.storeName) -> Engine {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        current = decide(storeName: storeName, isTesting: isTesting, isDebug: isDebugBuild,
                         arguments: ProcessInfo.processInfo.arguments, defaults: AppGroup.defaults)
        return current
    }

    /// Writes the preference for `storeName` (the move, `SyncEngine.move(to:)`): `own`, or removed for the mirror, so
    /// a store that never moved and one that moved back read the same.
    static func setPreference(_ engine: Engine, storeName: String = ModelContainerFactory.storeName,
                              defaults: UserDefaults = AppGroup.defaults) {
        let key = preferenceKey(storeName: storeName)
        if engine == .own { defaults.set(Engine.own.rawValue, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// `-name value` from the arguments (the last one wins), or nil.
    private static func value(of name: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
