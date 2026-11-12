import Foundation

/// Brief 95, Part 1: when the sync bolt may be filled. George, 2026-11-11: "The bolt should never, ever display as
/// full/filled in unless it actually successfully synced within the last real-time 30 seconds."
///
/// CloudKit's mirror syncs only when something changed, so a filled bolt used to mean "nothing has gone wrong that I
/// heard of". On George's Mac it said "Synced 18 hr ago" through a launch whose account was "temporarily unavailable"
/// (13:33:38 on 2026-11-11), and again the instant iCloud let the account back in (13:35:28), before anything had been
/// fetched. Now the app asks iCloud itself (`SyncBeat`, every 15 s while a bolt can be seen), and a beat *confirms* only
/// when all of these hold at its answer:
/// - the iCloud account is available (a `Blocker` otherwise);
/// - iCloud answered a request that needs the account and the network: the beat's own fetch, never the account status;
/// - nothing on this device is waiting to be sent: no save older than `Rules.exportGrace` that no export has covered,
///   and no record here that iCloud lacks or holds older (`SyncComparison`), but for saves younger than the grace;
/// - nothing known to be in iCloud is waiting to come in: no record there that is missing or older here.
///
/// The bolt is filled while the last confirmation is at most `Rules.window` old and fewer than `Rules.misses` beats in
/// a row have failed to confirm since it: one lost answer keeps a good state, two end it. Leaving filled is immediate;
/// returning needs a confirmation. A known blocker (no account, no network, sync off) ends it at once.
///
/// Trouble (the struck-through bolt) comes from the raw state as before (`SyncSteadiness`), and from two things only a
/// beat can see: this device and iCloud apart, beat after beat with nothing in flight, for `Rules.troubleAfter`; or no
/// answer from iCloud for as long.
///
/// Pure: `CloudSyncMonitor` feeds it each beat's outcome and the blockers, and wakes it at `nextDeadline(after:)`; tests
/// feed it whole timelines.
struct BoltTruth: Equatable {
    struct Rules: Equatable {
        /// A confirmation holds this long: George's 30 seconds.
        var window: TimeInterval = 30
        /// This many beats in a row that confirmed nothing end a confirmation before its window does.
        var misses: Int = 2
        /// A local save younger than this isn't waiting yet: its export may not have started (the watchdog's 5 s rule).
        var exportGrace: TimeInterval = SyncWatchdog.Rules().exportWithin
        /// This device and iCloud apart, or iCloud not answering, this long with nothing in flight is trouble: the
        /// watchdog's two minutes before it calls sync stuck (`SyncWatchdog.Rules.stalledAfter`).
        var troubleAfter: TimeInterval = SyncWatchdog.Rules().stalledAfter
    }

    /// What stops sync outright and is known without a beat.
    enum Blocker: Equatable, Sendable {
        /// The iCloud account isn't available (signed out, restricted, "sign in again", or not known yet).
        case account
        /// The network is unreachable.
        case offline
        /// The store runs without CloudKit.
        case syncOff
    }

    /// What a beat found when iCloud answered, judged by the monitor at the answer (`findings`).
    struct Findings: Equatable, Sendable {
        /// Changes on this device that iCloud doesn't have yet, past the grace: records, or saves no export covered.
        var sending = 0
        /// Changes in iCloud this device doesn't have: records missing here or older here.
        var receiving = 0
        /// A mirror import, export or setup is running: what differs may be on its way.
        var inFlight = false
        /// The first read of iCloud's records hasn't finished, so nothing could be compared.
        var reading = false

        var agree: Bool { !reading && sending == 0 && receiving == 0 }
    }

    enum Outcome: Equatable, Sendable {
        case answered(Findings)
        case failed(SyncBeatFailure)
    }

    /// Why the last beat didn't confirm.
    enum Miss: Equatable, Sendable {
        case noAnswer(SyncBeatFailure)
        case sending(Int)
        case receiving(Int)
        case reading
    }

    /// Why the bolt isn't filled.
    enum Why: Equatable, Sendable {
        case blocked(Blocker)
        /// No confirmation in the window and no beat has missed since: a beat is on its way (a launch, a return).
        case checking
        case missed(Miss)
    }

    /// What only the beats can call trouble.
    enum Trouble: Equatable, Sendable {
        /// This device and iCloud have differed since `since`, beat after beat, with nothing in flight.
        case apart(since: Date, sending: Int, receiving: Int)
        /// iCloud hasn't answered a beat since `since`.
        case noAnswer(since: Date, SyncBeatFailure)
    }

    /// What the bolt may say at one moment.
    struct Verdict: Equatable, Sendable {
        var filled: Bool
        /// The latest confirmation, however old.
        var confirmedAt: Date?
        /// Nil while filled.
        var why: Why?
        var trouble: Trouble?

        /// Before the first beat of a launch: not filled, checking.
        static let unknown = Verdict(filled: false, confirmedAt: nil, why: .checking, trouble: nil)

        var isBlocked: Bool {
            if case .blocked? = why { return true }
            return false
        }
    }

    let rules: Rules
    /// When the latest confirming beat started: the answer can only vouch for iCloud from then on.
    private(set) var lastConfirmedAt: Date?
    /// Beats in a row since the last confirmation that didn't confirm.
    private(set) var misses = 0
    private(set) var lastMiss: Miss?
    /// The first beat since the last answer that got none.
    private(set) var failingSince: Date?
    /// The first beat, with nothing in flight, that found this device and iCloud apart; nil while they agree or work is
    /// in flight.
    private(set) var apartSince: Date?
    private(set) var apartCounts: (sending: Int, receiving: Int) = (0, 0)
    private(set) var blocker: Blocker?

    init(rules: Rules = Rules(), lastConfirmedAt: Date? = nil) {
        self.rules = rules
        self.lastConfirmedAt = lastConfirmedAt
    }

    static func == (a: BoltTruth, b: BoltTruth) -> Bool {
        a.rules == b.rules && a.lastConfirmedAt == b.lastConfirmedAt && a.misses == b.misses && a.lastMiss == b.lastMiss
            && a.failingSince == b.failingSince && a.apartSince == b.apartSince && a.apartCounts == b.apartCounts
            && a.blocker == b.blocker
    }

    // MARK: Feeding it

    /// A beat that started at `startedAt` ended with `outcome`.
    mutating func beat(startedAt: Date, outcome: Outcome) {
        switch outcome {
        case .answered(let findings):
            failingSince = nil
            if findings.agree {
                if lastConfirmedAt.map({ startedAt > $0 }) ?? true { lastConfirmedAt = startedAt }
                misses = 0
                lastMiss = nil
                apartSince = nil
                apartCounts = (0, 0)
                return
            }
            misses += 1
            if findings.reading {
                lastMiss = .reading
                return
            }
            lastMiss = findings.sending > 0 ? .sending(findings.sending) : .receiving(findings.receiving)
            apartCounts = (findings.sending, findings.receiving)
            if findings.inFlight {
                // Whatever differs may be on its way: the clock starts again once nothing runs.
                apartSince = nil
            } else if apartSince == nil {
                apartSince = startedAt
            }
        case .failed(let failure):
            misses += 1
            lastMiss = .noAnswer(failure)
            if failingSince == nil { failingSince = startedAt }
        }
    }

    /// What stops sync now, or nil. A blocker ends a filled bolt at once; its trouble shows through the raw state.
    mutating func block(_ blocker: Blocker?) {
        self.blocker = blocker
    }

    /// Beats start again after a pause (the app back in front on iPhone and iPad, a Mac window visible again, the
    /// network or the account back): what the last beats counted describes a time nothing could be checked, so it
    /// starts over, and coming back never shows trouble that accrued while away. The confirmation keeps its age.
    mutating func restart() {
        misses = 0
        lastMiss = nil
        failingSince = nil
        apartSince = nil
        apartCounts = (0, 0)
    }

    // MARK: Reading it

    func isConfirmed(at now: Date) -> Bool {
        guard let lastConfirmedAt else { return false }
        return now.timeIntervalSince(lastConfirmedAt) <= rules.window
    }

    func verdict(at now: Date) -> Verdict {
        var verdict = Verdict(filled: false, confirmedAt: lastConfirmedAt, why: nil, trouble: trouble(at: now))
        if let blocker {
            verdict.why = .blocked(blocker)
            return verdict
        }
        if isConfirmed(at: now), misses < rules.misses {
            verdict.filled = true
            return verdict
        }
        verdict.why = lastMiss.map(Why.missed) ?? .checking
        return verdict
    }

    private func trouble(at now: Date) -> Trouble? {
        if let apartSince, now.timeIntervalSince(apartSince) >= rules.troubleAfter {
            return .apart(since: apartSince, sending: apartCounts.sending, receiving: apartCounts.receiving)
        }
        if case .noAnswer(let failure)? = lastMiss, let failingSince,
           now.timeIntervalSince(failingSince) >= rules.troubleAfter {
            return .noAnswer(since: failingSince, failure)
        }
        return nil
    }

    /// The next moment the verdict can change with no new beat, strictly after `now`; nil when none.
    func nextDeadline(after now: Date) -> Date? {
        var candidates: [Date] = []
        // A hair past the window, so the moment it ends is on the far side of the comparison.
        if let lastConfirmedAt { candidates.append(lastConfirmedAt.addingTimeInterval(rules.window + 0.001)) }
        if let apartSince { candidates.append(apartSince.addingTimeInterval(rules.troubleAfter)) }
        if let failingSince { candidates.append(failingSince.addingTimeInterval(rules.troubleAfter)) }
        return candidates.filter { $0 > now }.min()
    }

    // MARK: Judging a beat

    /// What a beat that iCloud answered found, from the comparison of this device with iCloud (nil while the first read
    /// of iCloud's records is still running) and the mirror's own state at the answer. A difference that its own recent
    /// change explains is not counted: the export that carries it may not have started.
    /// - `oldestUnsentSave`: the oldest local save no export has covered (`SyncWatchdog`), and `unsentSaves` how many
    ///   records those saves changed (`SyncWatchdog.waitingRecords`: one save of 46 tasks is 46 changes).
    /// - A record here that iCloud lacks or holds older is excused while its own `updatedAt` is younger than the grace (a
    ///   new task, an edit, on its way out). Another record's save excuses nothing (16:13:36 on 2026-11-11: a profile merge
    ///   at launch once excused six old records, and the bolt filled).
    /// - `deletedHere`: records this session deleted, by id, with when. A record iCloud still has and this device deleted
    ///   is a deletion on its way out (excused for the grace, then waiting to be sent), never a change to come in.
    /// - `lastLocalSaveAt` is kept for the callers' sake; only the records' own times count.
    static func findings(comparison: SyncComparison.Result?, unsentSaves: Int, oldestUnsentSave: Date?,
                         lastLocalSaveAt: Date?, deletedHere: [UUID: Date] = [:], inFlight: Bool, now: Date,
                         grace: TimeInterval = Rules().exportGrace) -> Findings {
        var findings = Findings(inFlight: inFlight)
        guard let comparison else {
            findings.reading = true
            return findings
        }
        var sending = 0
        var receiving = 0
        for difference in comparison.differences {
            switch difference.kind {
            case .onlyHere, .newerHere:
                let young = difference.local.map { now.timeIntervalSince($0.updatedAt) < grace } ?? false
                if !young { sending += 1 }
            case .onlyThere:
                if let deletedAt = deletedHere[difference.id] {
                    if now.timeIntervalSince(deletedAt) >= grace { sending += 1 }
                } else {
                    receiving += 1
                }
            case .newerThere:
                receiving += 1
            }
        }
        if sending == 0, unsentSaves > 0, let oldestUnsentSave, now.timeIntervalSince(oldestUnsentSave) >= grace {
            sending = unsentSaves
        }
        findings.sending = sending
        findings.receiving = receiving
        return findings
    }

    // MARK: What the marks show

    /// The state every mark draws (`CloudSyncMonitor.state`): the steadied state, held to the truth. A filled bolt
    /// (`.synced`) stays only while the verdict is filled, and then carries the confirmation's time ("Up to date,
    /// checked 12 s ago"); otherwise it becomes the working look (`.syncing`, hollow and breathing). What only the beats
    /// can call trouble shows as an error, struck through; trouble the steadiness already shows keeps its own words.
    static func gate(_ shown: SyncState, _ verdict: Verdict) -> SyncState {
        if case .localOnly = shown { return shown }
        if shown.showsTrouble { return shown }
        // A blocker's own trouble (signed out, offline) comes through the steadied state, in its own words.
        if let trouble = verdict.trouble, !verdict.isBlocked {
            switch trouble {
            case .apart(let since, _, _): return .error(apartReason, since)
            // No route to iCloud is the offline look (grey), whatever the network path says.
            case .noAnswer(_, let failure) where failure.kind == .network: return .offline
            case .noAnswer(let since, let failure): return .error(failure.reason, since)
            }
        }
        guard case .synced = shown else { return shown }
        guard verdict.filled, let confirmedAt = verdict.confirmedAt else { return .syncing }
        return .synced(confirmedAt)
    }

    /// "Sync paused: this device and iCloud differ": the words of `Trouble.apart` as an error.
    static let apartReason = "this device and iCloud differ"
}

/// Why a beat got no answer from iCloud, sorted the way the bolt and the log speak of it.
struct SyncBeatFailure: Error, Equatable, Hashable, Sendable {
    enum Kind: String, Equatable, Hashable, Sendable {
        /// No route to iCloud: the network is down or failing.
        case network
        /// iCloud refused the account: signed out, or "sign in again".
        case account
        /// iCloud is busy or asked HITList to slow down (`retryAfter`).
        case busy
        /// No answer within the beat's timeout.
        case timeout
        case other
    }

    var kind: Kind
    /// A few words (`SyncState.shortReason(for:)`): "network unavailable", "timed out".
    var reason: String
    /// The server asked for this long before the next request (`CKErrorRetryAfterKey`).
    var retryAfter: TimeInterval?

    init(_ kind: Kind, _ reason: String, retryAfter: TimeInterval? = nil) {
        self.kind = kind
        self.reason = reason
        self.retryAfter = retryAfter
    }

    static func timedOut(after seconds: TimeInterval) -> SyncBeatFailure {
        SyncBeatFailure(.timeout, "no answer within \(SyncLogFormat.duration(seconds))")
    }
}
