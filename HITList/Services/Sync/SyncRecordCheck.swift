import Foundation

/// Whether this device and iCloud hold the same records, as far as HITList has checked: the second thing the sync
/// bolt waits on (0.9.11), after the mirror's own events (`SyncSessionGate`).
///
/// George, 2026-11-14, on 0.9.10, which let the bolt fill on the mirror's word alone: "the bolt should not be able to
/// be filled while the three records differ; doesn't that defeat the purpose of the bolt?" A filled bolt therefore
/// means two things: the mirror has fetched from iCloud in this session and nothing has failed since, and the last
/// comparison of the two record lists (`SyncAudit.compare`: every record's kind, id and change stamp, read fresh
/// from iCloud) found them the same.
///
/// What it must never become again is 0.9.4 to 0.9.9's version of that (brief 95: a request of HITList's own every
/// 15 s, a copy of iCloud's index kept between launches, a hollow bolt that breathed while it waited, and "Sending 3
/// changes…" about records nothing was sending). So:
/// - **A read happens because something happened**, never because time passed: the session's first import; coming
///   back to the app when the last read is older than `Rules.recheckAfter`; trouble that cleared; Check iCloud… or
///   one of its repairs; and, only while the two differ, an import or export that finished (the one thing that can
///   change the answer). At rest nothing is read and no timer runs.
/// - **Every read is the whole zone, fresh.** Nothing is kept between reads, so no stale copy can disagree for good.
/// - **A difference is believed only when two reads `Rules.confirmAfter` apart both find it**, with the mirror quiet
///   before each (`Rules.settle`) and during it. A change that is still on its way is not a difference.
/// - **Nothing is repaired by itself.** A record here that iCloud lacks was either never sent, or was deleted on
///   another device and the deletion never arrived; only the person knows which, and what the mirror does with a
///   record it believes it already sent is not something to learn on someone's data. Check iCloud… names the
///   records and offers both repairs, as it has since brief 95.
/// - **The words say what differs** ("1 label and 2 filters on this device aren't in iCloud"), drawn as waiting for
///   `Rules.patience` after it was first seen or last sent from Check iCloud…, then as trouble.
/// - **If iCloud won't answer the read** after its few retries, the bolt goes back to the mirror's own word until
///   something asks again: a check that can't run must not hold the bolt hollow for good.
///
/// Pure: `CloudSyncMonitor` feeds it, starts a read when `shouldRead(at:)` says so and sleeps once until
/// `nextDeadline(after:)`.
struct SyncRecordCheck: Equatable {
    struct Rules: Equatable {
        /// The mirror quiet this long (nothing running, no save waiting to go) before a read begins.
        var settle: TimeInterval = 1.5
        /// A read that found a difference is repeated this long after it before the difference is believed.
        var confirmAfter: TimeInterval = 4
        /// Back in the app with the last read older than this: read again. (A read is every record's id and stamp:
        /// small, but the whole zone. Half an hour keeps a day of use to a handful.)
        var recheckAfter: TimeInterval = 1800
        /// While the two differ, a finished import or export asks for another read, no sooner than this after the last.
        var whileDiffering: TimeInterval = 30
        /// After a read iCloud didn't answer: again after each of these, then not until something else asks.
        var retryDelays: [TimeInterval] = [20, 120]
        /// A difference is drawn as waiting this long after it was first seen, or after records were last sent from
        /// Check iCloud…, then as trouble.
        var patience: TimeInterval = 120
    }

    /// One record that differs, and how.
    struct Item: Hashable, Sendable {
        var kind: SyncComparison.Difference.Kind
        var entity: String
        var id: UUID

        /// "TaskItem/<id>".
        var identifier: String { "\(entity)/\(id.uuidString)" }
    }

    /// What a comparison found.
    struct Difference: Equatable, Sendable {
        var items: Set<Item> = []

        init(items: Set<Item> = []) { self.items = items }

        init(_ result: SyncComparison.Result) {
            items = Set(result.differences.map { Item(kind: $0.kind, entity: $0.entity, id: $0.id) })
        }

        var isEmpty: Bool { items.isEmpty }

        /// How many records of each entity differ in `kind`'s way.
        func counts(_ kind: SyncComparison.Difference.Kind) -> [String: Int] {
            var counts: [String: Int] = [:]
            for item in items where item.kind == kind { counts[item.entity, default: 0] += 1 }
            return counts
        }

        func common(with other: Difference) -> Difference { Difference(items: items.intersection(other.items)) }
    }

    enum Verdict: Equatable {
        /// Nothing read yet for this session (a launch, an account that came back, a store that was reset).
        case unknown
        case agrees(at: Date)
        /// Found by two reads. `since`: when it was first believed, kept across launches.
        case differs(Difference, since: Date)
    }

    let rules: Rules
    private(set) var verdict: Verdict = .unknown
    /// A session has begun: before that (sync off, a test) nothing here holds anything.
    private(set) var hasBegun = false
    private(set) var beganAt: Date?
    /// A read is wanted, no sooner than this.
    private(set) var wantedAt: Date?
    private(set) var isReading = false
    /// The mirror did something while a read ran: its answer describes a moment that is gone.
    private(set) var isTainted = false
    /// What one read found, waiting for the next to find it too.
    private(set) var suspect: Difference?
    private(set) var lastFinishedAt: Date?
    /// When the last read ended, answered or not.
    private(set) var lastEndedAt: Date?
    private(set) var failures = 0
    /// The retries after a read iCloud didn't answer are used up: the mirror's own word stands until something asks.
    private(set) var hasGivenUp = false
    /// The mirror is running an event or has a save it hasn't sent.
    private(set) var isBusy = false
    private(set) var lastActivityAt: Date?
    private(set) var isBlocked = false
    private(set) var isSuspended = false
    /// When Check iCloud… last sent records again in this session, and the read their export should prompt.
    private(set) var resentAt: Date?
    private var readsAfterNextExchange = false
    /// The session's first import hasn't finished: nothing is read before the mirror has fetched.
    private(set) var awaitsImport = false
    /// Since when the two have differed, across launches (`CloudSyncMonitor` keeps it in the defaults).
    var differingSince: Date?

    init(rules: Rules = Rules(), differingSince: Date? = nil) {
        self.rules = rules
        self.differingSince = differingSince
    }

    // MARK: Feeding it

    /// A launch with CloudKit on, an iCloud account that came back, a store that was reset: nothing is known about
    /// what is on screen now.
    mutating func begin(at now: Date) {
        hasBegun = true
        beganAt = now
        verdict = .unknown
        suspect = nil
        failures = 0
        hasGivenUp = false
        resentAt = nil
        readsAfterNextExchange = false
        // The first read follows the session's first import: before it, this device may simply not have fetched yet.
        awaitsImport = true
        wantedAt = nil
    }

    /// The mirror started or ended an event, or the app saved: `busy` while an event runs or a save waits to go.
    mutating func mirror(busy: Bool, at now: Date) {
        isBusy = busy
        lastActivityAt = now
        if isReading { isTainted = true }
    }

    /// An import or export finished well: the session's first import asks for the first read; later, an exchange is
    /// the only thing that can change a difference.
    mutating func exchanged(imported: Bool, at now: Date) {
        guard hasBegun else { return }
        if awaitsImport {
            guard imported else { return }
            awaitsImport = false
            want(now)
        } else if readsAfterNextExchange {
            readsAfterNextExchange = false
            want(now)
        } else if case .differs = verdict {
            want(max(now, (lastFinishedAt ?? now).addingTimeInterval(rules.whileDiffering)))
        }
    }

    /// Back in the app (activated, woken): read again if the last read is old.
    mutating func returned(at now: Date) {
        // A read that is running or already wanted (the session's first, a retry) answers this too.
        guard hasBegun, !isReading, wantedAt == nil, !awaitsImport else { return }
        // Not sooner after the last one, answered or not: a Mac comes to the front at every click into its window.
        if let lastEndedAt, now.timeIntervalSince(lastEndedAt) < rules.recheckAfter { return }
        retryAfresh(now)
    }

    /// Offline, an error or a missing account has cleared: what happened meanwhile is unknown.
    mutating func troubleCleared(at now: Date) {
        guard hasBegun else { return }
        retryAfresh(now)
    }

    /// The person ran Check iCloud… or one of its repairs.
    mutating func asked(at now: Date) {
        guard hasBegun else { return }
        retryAfresh(now)
    }

    /// The person had Check iCloud… send records again: the export that follows prompts a read at once.
    mutating func resent(at now: Date) {
        resentAt = now
        readsAfterNextExchange = true
    }

    /// Nothing can sync at all (offline, no usable account), or can again.
    mutating func block(_ blocked: Bool) { isBlocked = blocked }

    /// The process stopped running (iPhone and iPad in the background, a Mac asleep), or runs again.
    mutating func suspend(_ suspended: Bool) { isSuspended = suspended }

    private mutating func want(_ at: Date) {
        wantedAt = wantedAt.map { min($0, at) } ?? at
    }

    private mutating func retryAfresh(_ now: Date) {
        // Still before the session's first import: its end asks.
        guard !awaitsImport else { return }
        failures = 0
        hasGivenUp = false
        want(now)
    }

    // MARK: Reading iCloud

    private var canRead: Bool { hasBegun && !isReading && !isBusy && !isBlocked && !isSuspended }

    /// The moment a wanted read may begin: wanted, and the mirror quiet for `Rules.settle`.
    private func readyAt(_ wanted: Date) -> Date {
        max(wanted, (lastActivityAt ?? .distantPast).addingTimeInterval(rules.settle))
    }

    func shouldRead(at now: Date) -> Bool {
        guard canRead, let wantedAt else { return false }
        return now >= readyAt(wantedAt)
    }

    mutating func started(at now: Date) {
        isReading = true
        isTainted = false
    }

    /// A read finished: `found` is what differed, nil when nothing did.
    mutating func finished(_ found: Difference?, at now: Date) {
        isReading = false
        if isTainted {
            // The mirror moved under the read: read again once it is quiet.
            isTainted = false
            want(now)
            return
        }
        lastFinishedAt = now
        lastEndedAt = now
        failures = 0
        hasGivenUp = false
        wantedAt = nil
        guard let found, !found.isEmpty else {
            verdict = .agrees(at: now)
            suspect = nil
            differingSince = nil
            return
        }
        if case .differs(let known, let since) = verdict, !known.common(with: found).isEmpty {
            // Still differing: what this read found stands (some may have been settled, some may be new).
            verdict = .differs(found, since: since)
            suspect = nil
            return
        }
        if let earlier = suspect {
            let both = earlier.common(with: found)
            if !both.isEmpty {
                let since = differingSince ?? now
                differingSince = since
                verdict = .differs(both, since: since)
                suspect = nil
                return
            }
        }
        suspect = found
        wantedAt = now.addingTimeInterval(rules.confirmAfter)
    }

    /// iCloud didn't answer the read.
    mutating func failed(at now: Date) {
        isReading = false
        isTainted = false
        lastEndedAt = now
        failures += 1
        if rules.retryDelays.indices.contains(failures - 1) {
            wantedAt = now.addingTimeInterval(rules.retryDelays[failures - 1])
        } else {
            wantedAt = nil
            suspect = nil
            hasGivenUp = true
        }
    }

    // MARK: What the marks show

    /// Nothing is known yet for this session and HITList is still finding out: the bolt isn't filled.
    var isChecking: Bool {
        guard hasBegun, !hasGivenUp else { return false }
        return verdict == .unknown
    }

    /// When a difference stops being drawn as waiting and is drawn as trouble.
    private var troubleAt: Date? {
        guard case .differs(_, let since) = verdict else { return nil }
        return max(since, resentAt ?? .distantPast).addingTimeInterval(rules.patience)
    }

    func isStuck(at now: Date) -> Bool { troubleAt.map { now >= $0 } ?? false }

    /// The state every mark draws, after the session gate: never "synced" until a read has found the two the same.
    /// Trouble the mirror reports, work it is doing and "local only" keep their own words.
    func gate(_ state: SyncState, at now: Date) -> SyncState {
        guard hasBegun, case .synced = state else { return state }
        switch verdict {
        case .unknown:
            if hasGivenUp { return state }
            return failures > 0 ? .retrying(since: beganAt ?? now) : .syncing
        case .agrees:
            return state
        case .differs(let difference, _):
            return .differs(SyncWords.difference(difference), stuck: isStuck(at: now))
        }
    }

    /// The next moment something here changes with nothing new fed in, strictly after `now`; nil when none.
    func nextDeadline(after now: Date) -> Date? {
        var moments: [Date] = []
        // A read that may begin now has no deadline: `shouldRead` is true and the caller starts it.
        if canRead, let wantedAt { moments.append(readyAt(wantedAt)) }
        if let troubleAt { moments.append(troubleAt) }
        return moments.filter { $0 > now }.min()
    }
}
