import Foundation
import HITListCore

/// A device that the app moved to the new sync checks itself afterwards, once (round 34): the first time the engine
/// comes to rest with nothing waiting, Check iCloud… runs by itself (`SyncEngineAudit`: every record of iCloud's
/// read afresh by a second road and compared with this device's, field by field), and what it found is written in
/// the sync log and kept for Settings. Nobody is asked to do anything; if a friend ever reports trouble, their sync
/// log already says whether iCloud and their device agreed after the move.
///
/// It repairs nothing. A check that found differences is made again at the next launches (five at most): right
/// after a first send another device may be writing, and a difference that stays is the thing to know about.
@MainActor
enum SyncEngineMoveCheck {
    static func resultKey(_ store: String) -> String { "syncEngine.autoMove.check.result.\(store)" }
    static func sameKey(_ store: String) -> String { "syncEngine.autoMove.check.same.\(store)" }
    static func atKey(_ store: String) -> String { "syncEngine.autoMove.check.at.\(store)" }
    static func triesKey(_ store: String) -> String { "syncEngine.autoMove.check.tries.\(store)" }
    static let maxTries = 5

    private static var observer: NSObjectProtocol?
    private static var ranThisLaunch = false

    /// Whether this launch checks: on the engine, on a store the app moved by itself, with no check that agreed yet
    /// and tries left.
    static func isDue(engine: SyncEngineBoard.Engine, movedByItself: Bool, agreed: Bool, tries: Int) -> Bool {
        engine == .own && movedByItself && !agreed && tries < maxTries
    }

    /// The engine is at rest: idle, its first whole fetch done, nothing waiting, nothing held.
    static func isAtRest(_ status: SyncStatus?) -> Bool {
        guard let status else { return false }
        return status.state == .idle && status.firstFetchDone && status.waiting == 0 && status.lastError == nil
    }

    /// What Settings says of the check, or nil when none was made.
    static func line(store: String = ModelContainerFactory.storeName, defaults: UserDefaults = AppGroup.defaults) -> String? {
        guard let result = defaults.string(forKey: resultKey(store)) else { return nil }
        let day = (defaults.object(forKey: atKey(store)) as? Date).map { $0.formatted(date: .abbreviated, time: .omitted) }
        return "Checked after the move\(day.map { " (\($0))" } ?? ""): \(result)"
    }

    /// From `HITListApp.init`, after the engine's launch. Arms one observer when a check is due, and nothing else.
    static func startIfDue(store: String = ModelContainerFactory.storeName, defaults: UserDefaults = AppGroup.defaults,
                           board: SyncEngineBoard = .shared, center: NotificationCenter = .default) {
        guard observer == nil,
              isDue(engine: board.engine, movedByItself: SyncEngineAutoMove.movedByItself(store: store, defaults: defaults),
                    agreed: defaults.bool(forKey: sameKey(store)), tries: defaults.integer(forKey: triesKey(store))) else { return }
        observer = center.addObserver(forName: SyncEngineBoard.statusChanged, object: board, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard !ranThisLaunch, isAtRest(board.status), board.actions?.check != nil else { return }
                ranThisLaunch = true
                if let observer { center.removeObserver(observer) }
                Task { await run(store: store, defaults: defaults, board: board) }
            }
        }
    }

    /// The check itself: returns whether it agreed (nil when it could not be made; that does not use up a try).
    @discardableResult
    static func run(store: String, defaults: UserDefaults, board: SyncEngineBoard, now: Date = Date()) async -> Bool? {
        guard let check = board.actions?.check else { return nil }
        do {
            let report = try await check { _ in }
            defaults.set(defaults.integer(forKey: triesKey(store)) + 1, forKey: triesKey(store))
            defaults.set(report.summary, forKey: resultKey(store))
            defaults.set(report.isSame, forKey: sameKey(store))
            defaults.set(now, forKey: atKey(store))
            board.log("Checked after the move to the new sync: \(report.summary)")
            if !report.isSame { for line in report.logLines { board.log(line) } }
            return report.isSame
        } catch {
            board.log("The check after the move to the new sync couldn't be made: \(SyncEngineWords.error(error))")
            return nil
        }
    }
}
