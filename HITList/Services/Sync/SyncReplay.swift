import Foundation
import CloudKit
import OSLog

/// A scripted run of raw sync states (brief 78, item 6), so the bolt and every other sync mark can be recorded
/// through a believable stretch of syncing without iCloud: launch with `-syncReplay YES` (Debug only; pair it with
/// `-disableCloudKit YES` and your own `HITLIST_STORE_SUFFIX`). From the first bolt's appearance (plus
/// `-syncReplayDelay <seconds>`, to start a recording first) `CloudSyncMonitor.state` follows `script` at real speed,
/// `lastChangeAt` advances on each finished sync as a real one would (so the strike gate plays as it does for real),
/// and the account status follows the blip. Each step is logged (category "sync", "Sync replay: …"), so a
/// recording's frames can be matched to the script.
///
/// The timings come from George's Mac on 2026-11-10 (the sync log of 0.9.0 (20) and (21)): a launch's setup and five
/// events in under three seconds; typing's exports, each 0.01–0.6 s apart from the save; a 7.7 s import; the account
/// blip of 18:11:18–18:11:47 with its own gaps; then two network drops of the kind a Wi-Fi hand-over or a wake gives.
enum SyncReplay {
    /// One raw state, as `CloudSyncMonitor.state` would derive it.
    enum Raw: Equatable, Sendable {
        /// An import, export or setup is running.
        case syncing
        /// An import or export finished: the last good sync is now (`lastChangeAt` advances).
        case finished
        /// Nothing running and nothing wrong, the last good sync unchanged (a setup finished).
        case idle
        case offline
        case error(String)
        case notSignedIn
    }

    struct Step: Equatable, Sendable {
        /// Seconds from the start of the replay.
        var at: TimeInterval
        var raw: Raw
        /// What the step stands for, for the log.
        var note: String
        /// The iCloud account status from this step on (nil: unchanged).
        var account: CKAccountStatus? = nil
    }

    /// The last good sync before the replay starts: the app was away for three hours, as on 2026-11-10 at 18:11.
    static let launchAfter: TimeInterval = 3 * 3600

    /// About four minutes, in seven parts.
    static let script: [Step] = {
        var steps: [Step] = []
        func add(_ at: TimeInterval, _ raw: Raw, _ note: String, account: CKAccountStatus? = nil) {
            steps.append(Step(at: at, raw: raw, note: note, account: account))
        }
        // A. Launch after three hours: setup, then five events in under three seconds (18:11:18, 14:27:09).
        add(0, .syncing, "A launch: setup started", account: .available)
        add(0.62, .idle, "A setup finished")
        add(0.67, .syncing, "A export started")
        add(0.82, .finished, "A export finished")
        add(0.84, .syncing, "A import started")
        add(1.75, .finished, "A import finished")
        add(1.77, .syncing, "A import started")
        add(2.06, .finished, "A import finished")
        add(2.21, .syncing, "A import started")
        add(2.45, .finished, "A import finished")
        add(2.6, .syncing, "A export started")
        add(2.75, .finished, "A export finished")
        // B. Typing: an export after each autosave, each well under a second (18:15:06–18:15:31).
        for (start, length) in [(8.0, 0.14), (8.6, 0.06), (9.3, 0.58), (10.5, 0.85), (12.0, 0.53)] {
            add(start, .syncing, "B export started")
            add(start + length, .finished, "B export finished")
        }
        // C. A slow import straight after (7.7 s, like 18:11:39).
        add(13.0, .syncing, "C slow import started")
        add(20.7, .finished, "C slow import finished after 7.7 s")
        // D. A quiet half minute, then a slow import with nothing synced for a while (9 s).
        add(55.0, .syncing, "D slow import after a quiet spell started")
        add(64.0, .finished, "D slow import finished after 9 s")
        // E. George's account blip, to the millisecond (74 s here is 18:11:18.435, the setup that followed his launch): an
        // export, an import cut off after 6.9 s by the account going "temporarily unavailable" for 14 s, a 7.7 s import
        // once it is back, an export, then an import failing with badContainer. Here that mends after 45 s (on George's
        // Mac nothing synced again until he relaunched).
        add(74.0, .syncing, "E setup started")
        add(74.066, .idle, "E setup finished")
        add(74.116, .syncing, "E export started")
        add(74.267, .finished, "E export finished")
        add(74.283, .syncing, "E import D589BCF1 started")
        add(81.19, .error("iCloud needs you to sign in again"), "E account temporarily unavailable", account: .temporarilyUnavailable)
        add(95.308, .syncing, "E account available again, import 73B6CAE9 running", account: .available)
        add(102.664, .finished, "E import finished after 7.7 s")
        add(102.681, .syncing, "E export started")
        add(102.775, .finished, "E export finished")
        add(102.9, .syncing, "E import F5FBC4BD started")
        add(103.218, .error("app can't use iCloud"), "E import failed: badContainer")
        add(148.2, .syncing, "E import started")
        add(148.5, .finished, "E import finished: mended")
        // F. A network wobble: 8 s offline, then the waiting export.
        add(160.0, .offline, "F offline")
        add(168.0, .syncing, "F online, export started")
        add(168.2, .finished, "F export finished")
        // G. Offline for 45 s.
        add(180.0, .offline, "G offline")
        add(225.0, .syncing, "G online, export started")
        add(225.4, .finished, "G export finished")
        add(240.0, .idle, "end of the replay")
        return steps
    }()

    static var duration: TimeInterval { script.last?.at ?? 0 }

    /// Where the replay stands `elapsed` seconds in: the raw state, the last good sync and the last finished sync
    /// (both nil before the first), and the account status. `start` is when the replay began.
    struct Position: Equatable {
        var state: SyncState
        var lastGood: Date
        var lastChange: Date?
        var account: CKAccountStatus?
        var step: Int?
    }

    static func position(at elapsed: TimeInterval, start: Date, script: [Step] = script) -> Position {
        var lastGood = start.addingTimeInterval(-launchAfter)
        var lastChange: Date?
        var account: CKAccountStatus?
        var raw: Raw = .idle
        var index: Int?
        for (i, step) in script.enumerated() where step.at <= elapsed {
            raw = step.raw
            index = i
            if let status = step.account { account = status }
            if step.raw == .finished {
                lastGood = start.addingTimeInterval(step.at)
                lastChange = lastGood
            }
        }
        return Position(state: state(for: raw, lastGood: lastGood, start: start, at: index.map { script[$0].at } ?? 0),
                        lastGood: lastGood, lastChange: lastChange, account: account, step: index)
    }

    private static func state(for raw: Raw, lastGood: Date, start: Date, at: TimeInterval) -> SyncState {
        switch raw {
        case .syncing: .syncing
        case .finished, .idle: .synced(lastGood)
        case .offline: .offline
        case .error(let reason): .error(reason, start.addingTimeInterval(at))
        case .notSignedIn: .notSignedIn
        }
    }
}

#if DEBUG
/// Plays `SyncReplay.script` once per process, from the first bolt's appearance.
@MainActor
@Observable
final class SyncReplayPlayer {
    static let shared = SyncReplayPlayer()
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "syncReplay") }
    static var delay: TimeInterval { max(0, UserDefaults.standard.double(forKey: "syncReplayDelay")) }
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// The replay's raw state while it runs (and its last state once it ended); nil when not requested.
    private(set) var state: SyncState?
    @ObservationIgnored private var task: Task<Void, Never>?

    func startIfRequested() {
        guard Self.isRequested, task == nil else { return }
        let start = Date().addingTimeInterval(Self.delay)
        state = SyncReplay.position(at: -1, start: start).state
        CloudSyncMonitor.shared.replayStarted()
        // A Debug Mac app recorded from behind other windows would otherwise be napped and play its steps late.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                             reason: "Sync replay keeps its timing")
        task = Task { @MainActor in
            defer { ProcessInfo.processInfo.endActivity(activity) }
            for (index, step) in SyncReplay.script.enumerated() {
                let wait = start.addingTimeInterval(step.at).timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                let position = SyncReplay.position(at: step.at, start: start)
                Self.log.notice("Sync replay: +\(step.at, format: .fixed(precision: 2), privacy: .public) s \(step.note, privacy: .public) (step \(index))")
                if let account = step.account { CloudSyncMonitor.shared.replayAccount(account) }
                if step.raw == .finished, let change = position.lastChange {
                    CloudSyncMonitor.shared.replayChange(at: change, phase: step.note.contains("import") ? .importing : .exporting)
                }
                state = position.state
                CloudSyncMonitor.shared.replayStateChanged()
            }
        }
    }
}
#endif
