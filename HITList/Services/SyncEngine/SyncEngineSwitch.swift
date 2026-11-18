import Foundation
import HITListCore

/// Which engine syncs this launch's store (round 28, brief 143): SwiftData's CloudKit mirror, as every released build
/// so far, or HITList's own engine (`dev/SYNC-ENGINE.md`). One answer per launch, decided before the container opens,
/// because the answer decides how it opens (the engine needs the same file without the mirror).
///
/// **`own` only for a store that was moved** (round 32; George, 2026-11-16: "Please work freely and complete the sync
/// engine … I also won't feel comfortable launching until we have at least a few days of experience with the new
/// sync system"). From 0.9.14 a released build may run the engine (`isAvailable`), and nothing moves by itself: a
/// store syncs on the engine only when its own preference says so (`AppGroup.defaults`, a key per store name), and
/// only the move writes that preference (`SyncEngine.move(to:)`), from a group in Settings → iCloud that stays hidden
/// until it is revealed on that device (`isSwitchRevealed`). Every other store, on every device, opens on the mirror
/// exactly as before.
///
/// In a Debug build also when launched on a side store with `-syncEngine own` (`-syncEngine mirror` wins the other
/// way, over the preference). Never under hosted tests (the tests call `decide` themselves), and the engine never
/// runs on the in-memory fallback (`SyncEngine.launch` says why instead).
enum SyncEngineSwitch {
    typealias Engine = SyncEngineBoard.Engine

    /// The container the engine's zone lives in: **one of its own**, a third beside the tasks' (the mirror's) and Shared
    /// Tasks'. George, 2026-11-16: "continue freely on the separate container for the iCloud engine if you think that's
    /// the best approach for a professional and robust (yet not overengineered) iCloud sync setup."
    ///
    /// Why it is: SwiftData's mirror imports every zone of its own container's private database
    /// (`dev/SYNC-ENGINE.md` section 3), and builds on the mirror stay in people's hands for as long as they do not
    /// update. In a container no mirror was ever pointed at, nothing an old build does can reach the engine's records,
    /// the mirror's zone stays exactly as it was at the move (the way back), and the two schemas are deployed apart.
    /// It costs one identifier in the entitlements and no code. The records keep their `HL` types there all the same
    /// (`CloudRecordCodec`): a second lock that costs a prefix.
    static let containerID = "iCloud.com.trammells.hitlist.sync"

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

    /// Whether this build may run the engine at all: every build, from the release George said switches it on
    /// (0.9.14, `dev/SYNC-ENGINE.md` section 14, stage 5). The one line that takes every device back to the mirror
    /// at its next launch, should that ever be needed: answer `isDebug` again. (Until 0.9.13 it did.)
    static func isAvailable(isDebug: Bool) -> Bool { true }

    /// Whether a store on the mirror moves to the engine by itself (`SyncEngineAutoMove`; `dev/SYNC-ENGINE.md` section
    /// 14, stage 6). **False in 0.9.15**: George's own week on the engine comes first, and while it is false nothing a
    /// build does differs from 0.9.14 (`SyncEngineAutoMoveTests.testGeorgesWeekComesFirst_movesByItselfIsFalse`).
    /// Flipped only after the rehearsal of each rule on two devices.
    static let movesByItself = false

    // MARK: - The hidden switch

    /// Whether Settings → iCloud shows the group that moves a store between the engines on this device. Off until
    /// someone taps the environment row seven times (`SevenTaps`): the engine is George's alone for its first days,
    /// and a friend who never hears of the gesture never sees the row. A store already on the engine always shows
    /// the group (it is the way back), and so does a Debug build on a side store.
    static let revealedKey = "syncEngine.switchRevealed"

    static func isSwitchRevealed(defaults: UserDefaults = AppGroup.defaults) -> Bool { defaults.bool(forKey: revealedKey) }

    static func revealSwitch(defaults: UserDefaults = AppGroup.defaults) { defaults.set(true, forKey: revealedKey) }

    /// The engine the store named `storeName` will open on at its next launch: what a move asked for, which is this
    /// launch's engine unless a move is waiting for the app to be reopened.
    static func nextEngine(storeName: String = ModelContainerFactory.storeName,
                           defaults: UserDefaults = AppGroup.defaults) -> Engine {
        defaults.string(forKey: preferenceKey(storeName: storeName)) == Engine.own.rawValue ? .own : .mirror
    }

    /// The answer, from what the launch was given. Pure, for the tests.
    static func decide(storeName: String, isTesting: Bool, isDebug: Bool, arguments: [String],
                       defaults: UserDefaults) -> Engine {
        guard isAvailable(isDebug: isDebug) else { return .mirror }
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
    /// Whether a Debug argument chose this launch's engine against the store's own preference (`-syncEngine own` on
    /// a side store that was never moved): the preference then says nothing about a move.
    nonisolated(unsafe) private(set) static var launchedByArgument = false

    /// The engine a move asked for that this launch does not run yet (the app must be reopened), or nil: the store's
    /// preference when it differs from the engine this launch runs, unless an argument chose the engine.
    static func pendingMove(current: Engine, preferred: Engine, byArgument: Bool) -> Engine? {
        byArgument || preferred == current ? nil : preferred
    }

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
        launchedByArgument = current != decide(storeName: storeName, isTesting: isTesting, isDebug: isDebugBuild,
                                               arguments: [], defaults: AppGroup.defaults)
        // The move made by the app itself (R3): when it is on, a store whose file is not there yet is noted as fresh,
        // so a later launch can tell that nothing in it is this device's own. Off: nothing is read or written.
        if !isTesting, current == .mirror, SyncEngineAutoMove.isOn(storeName: storeName) {
            let exists = ModelContainerFactory.groupStoreURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? true
            SyncEngineAutoMove.noteFreshStore(store: storeName, fileExists: exists, isOn: true, defaults: AppGroup.defaults)
        }
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
