import Foundation

/// Brief 95, rule 5: the words every sync line speaks (the bolt's label, Settings' status line, the Account row), from
/// the same state and verdict as the bolt's look, so no words anywhere claim more than the bolt. Filled: "Up to date,
/// checked 12 s ago". Not filled: what the bolt is waiting for, in plain words ("Last synced 3 min ago, checking…",
/// "Sending 2 changes to iCloud…"). Trouble keeps its own words (`SyncState.summary`). Pure.
enum SyncWords {
    /// The status words for `state` (`CloudSyncMonitor.state`, already held to the truth) and `verdict`; `lastSynced` is
    /// the latest moment anything reached or came from iCloud, for "Last synced 3 min ago". `precise`: "checked 12 s
    /// ago" (Settings, which redraws every second) rather than "checked just now" (the bolt's label).
    static func status(state: SyncState, verdict: BoltTruth.Verdict?, lastSynced: Date?, now: Date,
                       precise: Bool = false) -> String {
        guard let verdict else { return state.summary(now: now) }
        switch state {
        case .synced(let at):
            return "Up to date, checked \(precise ? age(since: at, now: now) : "just now")"
        case .syncing:
            return working(verdict.why, lastSynced: lastSynced, now: now) ?? state.summary(now: now)
        case .error(let reason, _) where reason == BoltTruth.apartReason:
            return apartWords
        default:
            return state.summary(now: now)
        }
    }

    /// "This device and iCloud differ": the struck-through bolt's words when a beat found them apart for two minutes.
    static let apartWords = "This device and iCloud differ; Check iCloud… in Settings shows what"

    /// "just now" under five seconds, else "12 s ago", then "3 min ago" and on (`SyncState.relative`).
    static func age(since date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds) s ago" }
        return SyncState.relative(date, now: now)
    }

    /// The hollow bolt's words: what it waits for.
    private static func working(_ why: BoltTruth.Why?, lastSynced: Date?, now: Date) -> String? {
        let last = lastSynced.map { "Last synced \(SyncState.relative($0, now: now))" }
        switch why {
        case nil:
            return nil
        case .checking?:
            return last.map { "\($0), checking…" } ?? "Checking with iCloud…"
        case .blocked(.account)?:
            return (last.map { "\($0), " } ?? "") + "checking the iCloud account…"
        case .blocked(.offline)?:
            return (last.map { "\($0), " } ?? "") + "waiting for the network…"
        case .blocked(.syncOff)?:
            return nil
        case .missed(let miss)?:
            switch miss {
            case .reading:
                return "Reading what iCloud holds…"
            case .sending(let n):
                return "Sending \(changes(n)) to iCloud…"
            case .receiving(let n):
                return "Receiving \(changes(n)) from iCloud…"
            case .noAnswer(let failure):
                return (last.map { "\($0); " } ?? "") + "iCloud didn't answer (\(failure.reason)), asking again…"
            }
        }
    }

    private static func changes(_ n: Int) -> String { n == 1 ? "1 change" : "\(n) changes" }
}
