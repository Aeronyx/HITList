import XCTest
@testable import HITList

/// Brief 95, part 2: George's two sync logs of 2026-11-11 (0.9.3 (24), Production), replayed through 0.9.4's rule with
/// the logs' own times. The logs stay out of git: only the moments and counts the replay needs are here, each with the
/// log line it comes from (I = the iPhone's log, M = the Mac's, the files' own line numbers). What the logs can't say,
/// whether iCloud or the iPhone held the "Shave" the Mac lacked, is replayed both ways.
///
/// The replay drives the real pieces the monitor drives: `SyncBeat.nextDue` for when beats go out (and the early beat
/// after an import or export while the bolt isn't filled), `SyncWatchdog` for what is unsent, `BoltTruth.findings`,
/// `BoltTruth`, `SyncSteadiness`, `BoltTruth.gate` and `SyncWords`. A beat takes 0.1 s (60 to 90 ms on this Mac).
@MainActor
final class BoltTruthReplayTests: XCTestCase {

    // MARK: The Mac, signed out ("temporarily unavailable") from M1634 to M1694

    func testTheMacWasNeverFilledWhileSignedOut() {
        let replay = Replay(mac(), clock: clock)
        // M1635/1637: the 0.9.1 launch at 21:28:04.931 drew "Synced 2 hr ago", filled.
        XCTAssertEqual(replay.look("2026-11-10 21:28:04.950").words, "Last synced 2 hr ago, checking…")
        // M1641: the account is known unavailable 0.12 s later: no beat asks while it stays so.
        XCTAssertEqual(replay.look("2026-11-10 21:28:05.200").words, "Last synced 2 hr ago, checking the iCloud account…")
        XCTAssertEqual(replay.look("2026-11-10 21:28:36.000").words, "Sync paused: iCloud needs you to sign in again")
        // M1655/1657: 0.9.2 at 01:11:10, "Synced 5 hr ago" filled. M1673/1675: 0.9.3 at 13:33:38, "Synced 18 hr ago".
        XCTAssertEqual(replay.look("2026-11-11 01:11:10.130").words, "Last synced 5 hr ago, checking…")
        XCTAssertEqual(replay.look("2026-11-11 01:11:41.000").words, "Sync paused: iCloud needs you to sign in again")
        XCTAssertEqual(replay.look("2026-11-11 13:33:38.950").words, "Last synced 18 hr ago, checking…")
        XCTAssertEqual(replay.look("2026-11-11 13:34:10.000").words, "Sync paused: iCloud needs you to sign in again")
        XCTAssertEqual(replay.filledMoments, [], "no beat confirmed anything while the account was unavailable")
    }

    // MARK: The Mac when the account came back (M1694, 13:35:28.747)

    func testTheMacWhenTheAccountCameBackWithBothSidesAgreeing() {
        let replay = Replay(mac(), clock: clock)
        // 0.9.3 drew "Synced 18 hr ago", filled, at 13:35:28.747 (M1696), before anything was fetched.
        let back = replay.look("2026-11-11 13:35:28.800")
        XCTAssertFalse(back.filled)
        XCTAssertEqual(back.state, .syncing, "hollow")
        // The first beat finds the 46 dates the 0.9.3 launch rewrote (M1676) unsent: no export since, and 1 min 50 s old.
        // One save of 46 records: the words count the records, not the saves ("Sending 1 change" before this).
        let first = replay.look("2026-11-11 13:35:29.000")
        XCTAssertFalse(first.filled)
        XCTAssertEqual(replay.unsentAtFirstBeatAfterReturn, 46)
        XCTAssertEqual(first.words, "Sending 46 changes to iCloud…")
        // The export that sends them ends at 13:35:31.829 (M1701); the beat that follows at once finds nothing apart.
        XCTAssertFalse(replay.look("2026-11-11 13:35:31.800").filled)
        let sent = replay.look("2026-11-11 13:35:33.000")
        XCTAssertTrue(sent.filled)
        XCTAssertEqual(sent.words, "Up to date, checked just now")
        XCTAssertEqual(replay.look("2026-11-11 13:37:40.000").words, "Up to date, checked just now")
        // M1718/1719: quit at 13:37:49.595 and launched again at 13:38:12.865: "Synced just now" filled (M1721).
        XCTAssertEqual(replay.look("2026-11-11 13:38:12.900").words, "Last synced just now, checking…")
        XCTAssertTrue(replay.look("2026-11-11 13:38:14.000").filled, "the relaunch's first beat agrees")
        XCTAssertTrue(replay.look("2026-11-11 13:38:30.000").filled, "George's screenshot")
    }

    func testIfICloudHeldAShaveTheMacLackedTheMacSaidSoBeforeTheScreenshot() {
        var day = mac()
        day.onlyThere = 1
        let replay = Replay(day, clock: clock)
        let sent = replay.look("2026-11-11 13:35:33.000")
        XCTAssertFalse(sent.filled)
        XCTAssertEqual(sent.words, "Receiving 1 change from iCloud…")
        // Two minutes apart with nothing in flight (the apart clock starts at the beat after the export, 13:35:32.75).
        XCTAssertEqual(replay.look("2026-11-11 13:37:31.000").state, .syncing)
        let apart = replay.look("2026-11-11 13:37:40.000")
        XCTAssertEqual(apart.state.summary(now: clock("2026-11-11 13:37:40.000")), "Sync paused: this device and iCloud differ")
        XCTAssertEqual(apart.words, SyncWords.apartWords)
        // The relaunch starts over: hollow and receiving, then apart again two minutes after the first quiet beat.
        XCTAssertEqual(replay.look("2026-11-11 13:38:30.000").words, "Receiving 1 change from iCloud…")
        XCTAssertEqual(replay.look("2026-11-11 13:40:30.000").words, SyncWords.apartWords)
        XCTAssertEqual(replay.filledMoments, [])
    }

    // MARK: The iPhone

    func testThePhoneWhenBothSidesAgree() {
        let replay = Replay(phone(), clock: clock)
        // I2070/2072: 0.9.1 launched at 21:40:59.380, "Synced just now" filled; the app is in front from 21:40:59.910.
        XCTAssertEqual(replay.look("2026-11-10 21:40:59.700").words, "Last synced just now, checking…")
        XCTAssertTrue(replay.look("2026-11-10 21:41:00.100").filled, "its first beat agrees: the Mac changes nothing")
        // I2130–2134: 0.9.3 at 10:30:10.131, "Synced 12 hr ago" filled; 44 dates rewritten at 10:30:10.215, exported
        // 10:30:10.547–11.957 (I2145–2146). The first beat, 0.3 s after the save, excuses it: its export has started.
        XCTAssertEqual(replay.look("2026-11-11 10:30:10.200").words, "Last synced 12 hr ago, checking…")
        XCTAssertTrue(replay.look("2026-11-11 10:30:10.700").filled)
        XCTAssertTrue(replay.look("2026-11-11 10:30:12.000").filled)
        // I2177–2179: 12:29:38, "Synced 1 hr ago" filled.
        XCTAssertEqual(replay.look("2026-11-11 12:29:39.000").words, "Last synced 1 hr ago, checking…")
        XCTAssertTrue(replay.look("2026-11-11 12:29:40.000").filled)
        // I2264: back in front at 13:36:19.073, as the Mac's export of 13:35:31 (M1701) came in (I2265–2267).
        XCTAssertFalse(replay.look("2026-11-11 13:36:19.100").filled, "coming back is hollow until the first answer")
        XCTAssertTrue(replay.look("2026-11-11 13:36:19.300").filled)
        XCTAssertTrue(replay.look("2026-11-11 13:41:00.000").filled)
        // I2331–2333: 17:27:47, "Synced 2 hr ago" filled.
        XCTAssertEqual(replay.look("2026-11-11 17:27:48.000").words, "Last synced 2 hr ago, checking…")
        XCTAssertTrue(replay.look("2026-11-11 17:27:48.600").filled)
    }

    func testIfOnlyThePhoneHeldShaveThePhoneSaidSoWithinTwoMinutesInFront() {
        var day = phone()
        day.onlyHere = 1
        let replay = Replay(day, clock: clock)
        XCTAssertEqual(replay.look("2026-11-10 21:41:00.100").words, "Sending 1 change to iCloud…")
        // In front from 21:40:59.910 to 21:43:40.586 (I2081, I2092): apart for two minutes before it left.
        XCTAssertEqual(replay.look("2026-11-10 21:43:30.000").words, SyncWords.apartWords)
        // 10:30: in front only for seconds at a time (I2143–2176): hollow each time, never long enough for trouble.
        XCTAssertEqual(replay.look("2026-11-11 10:30:12.000").words, "Sending 1 change to iCloud…")
        XCTAssertEqual(replay.look("2026-11-11 10:31:50.000").words, "Sending 1 change to iCloud…")
        // 12:29:39 to 12:36:59 in front (I2188–2201): apart from the first quiet beat, 12:29:41.2, so struck at 12:31:41.
        XCTAssertEqual(replay.look("2026-11-11 12:32:00.000").words, SyncWords.apartWords)
        // 13:32:48.932 to 13:34:56.560 (I2236–2258), the minutes before George's screenshots.
        XCTAssertEqual(replay.look("2026-11-11 13:33:30.000").words, "Sending 1 change to iCloud…")
        XCTAssertEqual(replay.look("2026-11-11 13:34:56.000").words, SyncWords.apartWords)
        XCTAssertEqual(replay.filledMoments, [])
    }

    func testTheRateLimitStormLeftTheBoltHollowNeverStruck() {
        let replay = Replay(phone(), clock: clock)
        // I1852–1866: launched at 18:12:01.693 after a day away; iCloud said "busy" (CK 6) at 18:12:02.349 and refused
        // every request until the import of 18:13:26–29 (I1981–1982). The beats ask on the same container: refused too.
        XCTAssertEqual(replay.look("2026-11-10 18:12:02.200").words,
                       "Last synced 1 day ago; iCloud didn't answer (iCloud is busy, will retry), asking again…")
        let late = replay.look("2026-11-10 18:13:25.000")
        XCTAssertFalse(late.filled)
        XCTAssertNil(late.verdict.trouble, "84 s without an answer: hollow, not struck through (two minutes is trouble)")
        // The import's end asks for a beat at once; iCloud answers again.
        XCTAssertTrue(replay.look("2026-11-10 18:13:29.200").filled)
        // I1991–2031: the Mac's ten changes came in by push within a second each; the beats every 15 s saw them agree.
        XCTAssertTrue(replay.look("2026-11-10 18:15:30.000").filled)
        XCTAssertEqual(replay.beatsThatFoundSomethingComing, 0, "no beat landed in the half-second gaps")
    }

    // MARK: The two devices, from their logs

    /// The Mac from Nov 10 19:21 to Nov 11 13:42. A window is taken as visible while the app ran, but for 01:11 to
    /// 12:45:37, when the unified log had it windowless (`mac-unified-log-2026-11-11.md`).
    private func mac() -> Day {
        var day = Day(lastSynced: "2026-11-10 19:12:54.058")  // M1629–1630, "lastExport=2 hr ago" at M1635
        day.launches = ["2026-11-10 21:28:04.908", "2026-11-11 01:11:10.090", "2026-11-11 13:33:38.914", "2026-11-11 13:38:12.865"]
        day.seen = [("2026-11-10 21:28:04.931", "2026-11-10 21:42:19.442"),  // M1636 to M1654
                    ("2026-11-11 12:45:37.306", "2026-11-11 13:33:23.827"),  // M1669 to M1672
                    ("2026-11-11 13:33:38.933", "2026-11-11 13:37:49.595"),  // M1674 to M1718
                    ("2026-11-11 13:38:13.343", "2026-11-11 13:42:30.000")]  // M1725 on
        day.signedOut = ("2026-11-10 19:21:35.199", "2026-11-11 13:35:28.747")  // M1634, M1694
        day.accountLearned = ["2026-11-10 21:28:05.049", "2026-11-11 01:11:10.253", "2026-11-11 13:33:39.582"]  // M1641, 1661, 1685
        day.saves = [("2026-11-11 13:33:38.960", 46)]  // M1676
        day.events = [
            ("setup", "2026-11-11 13:35:28.725", "2026-11-11 13:35:28.731"),  // M1692–1693
            ("import", "2026-11-11 13:35:29.377", "2026-11-11 13:35:29.842"),  // M1697–1698
            ("export", "2026-11-11 13:35:30.685", "2026-11-11 13:35:31.829"),  // M1700–1701
            ("import", "2026-11-11 13:36:05.544", "2026-11-11 13:36:06.025"),  // M1704–1705
            ("export", "2026-11-11 13:36:06.042", "2026-11-11 13:36:06.078"),
            ("export", "2026-11-11 13:36:06.090", "2026-11-11 13:36:06.119"),
            ("export", "2026-11-11 13:36:59.777", "2026-11-11 13:36:59.814"),  // M1710–1711
            ("import", "2026-11-11 13:37:48.915", "2026-11-11 13:37:49.118"),  // M1712–1713
            ("export", "2026-11-11 13:37:49.136", "2026-11-11 13:37:49.153"),
            ("export", "2026-11-11 13:37:49.167", "2026-11-11 13:37:49.180"),  // M1716–1717
            ("setup", "2026-11-11 13:38:13.050", "2026-11-11 13:38:13.584"),  // M1724–1729
            ("export", "2026-11-11 13:38:13.585", "2026-11-11 13:38:13.616"),
            ("import", "2026-11-11 13:38:14.514", "2026-11-11 13:38:14.738"),  // M1732–1733
            ("export", "2026-11-11 13:38:14.758", "2026-11-11 13:38:14.789"),
            ("export", "2026-11-11 13:38:14.803", "2026-11-11 13:38:14.815"),
            ("export", "2026-11-11 13:38:19.683", "2026-11-11 13:38:19.707"),  // M1738–1739
        ].map { Event(kind: $0.0, start: $0.1, end: $0.2) }
        return day
    }

    /// The iPhone from Nov 10 18:12 to Nov 11 17:29: in front from each "App active" to the next "App in background".
    private func phone() -> Day {
        var day = Day(lastSynced: "2026-11-09 12:37:56.315")  // I1851, "lastExport=1 day ago" at I1852
        day.launches = ["2026-11-10 18:12:01.693", "2026-11-10 21:40:59.380", "2026-11-11 10:30:10.131",
                        "2026-11-11 12:29:38.764", "2026-11-11 17:27:47.924"]
        day.seen = [("2026-11-10 18:12:02.023", "2026-11-10 18:18:54.537"),  // I1862, I2036
                    ("2026-11-10 21:40:43.699", "2026-11-10 21:40:47.389"),  // I2055, I2068
                    ("2026-11-10 21:40:59.910", "2026-11-10 21:43:40.586"),  // I2081, I2092
                    ("2026-11-10 21:50:09.617", "2026-11-10 21:56:58.929"),  // I2096, I2108
                    ("2026-11-10 22:14:17.452", "2026-11-10 22:14:18.232"),  // I2115, I2122
                    ("2026-11-11 10:30:10.527", "2026-11-11 10:30:19.699"),  // I2143, I2164
                    ("2026-11-11 10:30:47.748", "2026-11-11 10:31:55.972"),  // I2168, I2176
                    ("2026-11-11 12:29:39.175", "2026-11-11 12:36:59.516"),  // I2188, I2201
                    ("2026-11-11 12:37:45.235", "2026-11-11 12:39:55.108"),  // I2205, I2216
                    ("2026-11-11 12:44:14.741", "2026-11-11 12:49:47.325"),  // I2220, I2232
                    ("2026-11-11 13:32:48.932", "2026-11-11 13:34:56.560"),  // I2236, I2258
                    ("2026-11-11 13:36:19.073", "2026-11-11 13:36:20.640"),  // I2264, I2273
                    ("2026-11-11 13:36:26.859", "2026-11-11 13:37:02.427"),  // I2281, I2299
                    ("2026-11-11 13:40:00.726", "2026-11-11 13:42:16.058"),  // I2303, I2312
                    ("2026-11-11 14:46:22.399", "2026-11-11 14:50:14.461"),  // I2316, I2329
                    ("2026-11-11 17:27:48.422", "2026-11-11 17:28:32.973")]  // I2341, I2356
        day.busyUntil = "2026-11-10 18:13:26.363"  // I1866–1980, then I1981
        day.saves = [("2026-11-11 10:30:10.215", 44)]  // I2133
        day.events = [
            ("setup", "2026-11-10 18:12:01.968", "2026-11-10 18:12:02.002"),
            ("import", "2026-11-10 18:13:26.363", "2026-11-10 18:13:29.029"),  // I1981–1982
            ("import", "2026-11-10 18:13:29.075", "2026-11-10 18:13:29.349"),
            ("import", "2026-11-10 18:14:39.835", "2026-11-10 18:14:40.401"),  // I1992–1993
            ("import", "2026-11-10 18:15:07.875", "2026-11-10 18:15:08.281"),
            ("import", "2026-11-10 18:15:14.737", "2026-11-10 18:15:15.186"),
            ("import", "2026-11-10 18:15:24.904", "2026-11-10 18:15:25.319"),
            ("import", "2026-11-10 18:15:26.902", "2026-11-10 18:15:27.211"),  // I2030–2031
            ("setup", "2026-11-10 21:40:59.886", "2026-11-10 21:40:59.897"),
            ("import", "2026-11-10 21:40:44.532", "2026-11-10 21:40:45.022"),  // I2056–2057
            ("import", "2026-11-10 21:40:45.044", "2026-11-10 21:40:45.600"),  // I2061–2062
            ("export", "2026-11-10 21:40:59.986", "2026-11-10 21:40:59.992"),
            ("import", "2026-11-10 21:41:00.017", "2026-11-10 21:41:01.659"),  // I2084–2085
            ("import", "2026-11-10 21:41:01.674", "2026-11-10 21:41:01.768"),
            ("setup", "2026-11-11 10:30:10.256", "2026-11-11 10:30:10.534"),  // I2138–2144
            ("export", "2026-11-11 10:30:10.547", "2026-11-11 10:30:11.957"),  // I2145–2146
            ("import", "2026-11-11 10:30:11.966", "2026-11-11 10:30:12.341"),
            ("import", "2026-11-11 10:30:17.036", "2026-11-11 10:30:17.215"),  // I2157–2158
            ("import", "2026-11-11 10:30:48.454", "2026-11-11 10:30:48.605"),  // I2169–2170
            ("setup", "2026-11-11 12:29:38.831", "2026-11-11 12:29:39.152"),
            ("export", "2026-11-11 12:29:39.163", "2026-11-11 12:29:39.233"),
            ("import", "2026-11-11 12:29:39.237", "2026-11-11 12:29:39.937"),
            ("import", "2026-11-11 12:29:39.956", "2026-11-11 12:29:40.234"),
            ("import", "2026-11-11 12:29:40.250", "2026-11-11 12:29:40.343"),
            ("import", "2026-11-11 13:32:49.202", "2026-11-11 13:32:49.465"),
            ("import", "2026-11-11 13:32:49.619", "2026-11-11 13:32:49.936"),
            ("import", "2026-11-11 13:32:51.970", "2026-11-11 13:32:52.302"),
            ("import", "2026-11-11 13:36:19.336", "2026-11-11 13:36:20.458"),  // I2265–2267
            ("import", "2026-11-11 13:36:20.468", "2026-11-11 13:36:20.578"),
            ("import", "2026-11-11 13:36:27.423", "2026-11-11 13:36:27.584"),
            ("import", "2026-11-11 13:36:47.538", "2026-11-11 13:36:47.706"),
            ("import", "2026-11-11 13:40:01.533", "2026-11-11 13:40:01.886"),
            ("import", "2026-11-11 14:46:23.245", "2026-11-11 14:46:23.529"),  // I2317–2318
            ("import", "2026-11-11 14:46:23.586", "2026-11-11 14:46:23.873"),
            ("setup", "2026-11-11 17:27:48.403", "2026-11-11 17:27:48.437"),
            ("import", "2026-11-11 17:27:48.781", "2026-11-11 17:27:49.659"),
        ].map { Event(kind: $0.0, start: $0.1, end: $0.2) }
        // The Mac's changes of Nov 10, from its export's end (M1462, 1479, 1482, 1485, 1488) to the phone's import (I1993…2031).
        day.coming = [("2026-11-10 18:14:39.653", "2026-11-10 18:14:40.401", 6), ("2026-11-10 18:15:07.794", "2026-11-10 18:15:08.281", 1),
                      ("2026-11-10 18:15:14.636", "2026-11-10 18:15:15.186", 1), ("2026-11-10 18:15:24.845", "2026-11-10 18:15:25.319", 1),
                      ("2026-11-10 18:15:26.835", "2026-11-10 18:15:27.211", 1)]
        return day
    }

    // MARK: The replay

    /// "2026-11-11 13:35:28.747": the logs' clock, UTC−5 ("Times are local (UTC-05:00)" in both headers).
    private let clock: (String) -> Date = { text in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: -5 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.date(from: text)!
    }

    struct Event {
        var kind: String
        var start: String
        var end: String
    }

    /// One device's stretch of its log, as the beats would have met it.
    struct Day {
        var lastSynced: String
        /// Each launch starts a fresh truth (the monitor's is in memory) and steadiness.
        var launches: [String] = []
        /// A bolt could be seen: the iPhone's app in front; a Mac window.
        var seen: [(String, String)] = []
        /// The account "temporarily unavailable" in fact; and when each launch in it learned so (the blocker).
        var signedOut: (String, String)?
        var accountLearned: [String] = []
        /// iCloud refused every request before this ("iCloud is busy").
        var busyUntil: String?
        var saves: [(String, Int)] = []
        var events: [Event] = []
        /// Changes in iCloud on their way here: from the other device's export's end to this device's import's end.
        var coming: [(String, String, Int)] = []
        /// What the logs can't see: records here iCloud lacks, records in iCloud missing here (old ones).
        var onlyHere = 0
        var onlyThere = 0
    }

    struct Look {
        var filled: Bool
        var state: SyncState
        var verdict: BoltTruth.Verdict
        var words: String
    }

    /// Runs the beats forward to each look, in order.
    @MainActor
    final class Replay {
        private let day: Day
        private let clock: (String) -> Date
        private let rules = SyncBeat.Rules()
        private var now: Date = .distantPast
        private var truth = BoltTruth()
        private var watchdog = SyncWatchdog()
        private var steadiness = SyncSteadiness()
        private var lastSynced: Date
        private var blocked = false
        private var isSeen = false
        private var eligible = false
        /// When the next beat goes out (`SyncBeat.schedule`), and the beat waiting for its answer.
        private var due: Date?
        private var running: (start: Date, answerAt: Date)?
        private var lastStart: Date?, lastEnd: Date?, last: SyncBeat.LastResult?
        private var failures = 0, misses = 0
        private var moments: [(at: Date, order: Int, apply: (Replay) -> Void)] = []
        private var returnedAt: Date?
        /// Every moment the verdict was filled, as the replay passed it.
        private(set) var filledMoments: [Date] = []
        private(set) var beatsThatFoundSomethingComing = 0
        /// What the first beat after the account came back found waiting to be sent.
        private(set) var unsentAtFirstBeatAfterReturn: Int?

        init(_ day: Day, clock: @escaping (String) -> Date) {
            self.day = day
            self.clock = clock
            lastSynced = clock(day.lastSynced)
            for launch in day.launches { add(clock(launch), 0) { $0.launch(at: clock(launch)) } }
            for learned in day.accountLearned { add(clock(learned), 1) { $0.learnSignedOut(at: clock(learned)) } }
            if let out = day.signedOut { add(clock(out.1), 1) { $0.accountBack(at: clock(out.1)) } }
            for span in day.seen {
                add(clock(span.0), 2) { $0.seen(true, at: clock(span.0)) }
                add(clock(span.1), 2) { $0.seen(false, at: clock(span.1)) }
            }
            for save in day.saves { add(clock(save.0), 3) { $0.saved(save.1, at: clock(save.0)) } }
            for event in day.events { add(clock(event.end), 3) { $0.ended(event) } }
            moments.sort { ($0.at, $0.order) < ($1.at, $1.order) }
        }

        private func add(_ at: Date, _ order: Int, _ apply: @escaping (Replay) -> Void) {
            moments.append((at, order, apply))
        }

        // The moments.

        private func launch(at t: Date) {
            truth = BoltTruth()
            watchdog = SyncWatchdog(lastExportAt: lastSynced, lastImportAt: lastSynced)
            steadiness = SyncSteadiness()
            steadiness.observe(.synced(lastSynced), at: t)
            blocked = false
            isSeen = false
            eligible = false
            due = nil
            running = nil
            lastStart = nil; lastEnd = nil; last = nil; failures = 0; misses = 0
        }

        private func learnSignedOut(at t: Date) {
            blocked = true
            truth.block(.account)
            steadiness.observe(.error(SyncSteadiness.signInAgainReason, t), at: t)
            updateEligibility(at: t)
        }

        private func accountBack(at t: Date) {
            blocked = false
            truth.block(nil)
            steadiness.observe(.synced(lastSynced), at: t)
            returnedAt = t
            updateEligibility(at: t)
        }

        private func seen(_ visible: Bool, at t: Date) {
            isSeen = visible
            if visible { steadiness.resumed(at: t) }
            updateEligibility(at: t)
        }

        /// `CloudSyncMonitor.updateBeats` and `SyncBeat.setEligible`: becoming eligible starts the counts over and
        /// sends one beat at once; a running beat still finishes.
        private func updateEligibility(at t: Date) {
            let next = isSeen && !blocked
            guard next != eligible else { return }
            eligible = next
            if next {
                truth.restart()
                last = nil; failures = 0; misses = 0
                if running == nil { schedule(at: t) }
            } else {
                due = nil
            }
        }

        private func saved(_ records: Int, at t: Date) {
            _ = watchdog.handle(.localSave(at: t, records: records))
        }

        private func ended(_ event: Event) {
            let start = clock(event.start), end = clock(event.end)
            let type: SyncEventType = event.kind == "import" ? .importing : event.kind == "export" ? .exporting : .setup
            _ = watchdog.handle(.eventEnded(id: UUID(), type: type, startedAt: start, succeeded: true, error: nil, at: end))
            guard type != .setup else { return }
            lastSynced = max(lastSynced, end)
            // An import changed the store, an export may have sent what the bolt waits for: `SyncBeat.beatSoon`, at
            // once while the bolt isn't filled and no beat is running.
            if eligible, running == nil, !truth.verdict(at: end).filled {
                last = nil
                schedule(at: end)
            }
        }

        private func schedule(at t: Date) {
            due = SyncBeat.nextDue(rules: rules, now: t, lastStart: lastStart, lastEnd: lastEnd, last: last,
                                   failures: failures, misses: misses, retryAfterUntil: nil)
        }

        private func startBeat(at t: Date) {
            due = nil
            running = (t, t.addingTimeInterval(0.1))
        }

        private func answer(_ start: Date, at answeredAt: Date) {
            running = nil
            let outcome: BoltTruth.Outcome
            if let out = day.signedOut, start >= clock(out.0), start < clock(out.1) {
                outcome = .failed(SyncBeatFailure(.account, "iCloud needs you to sign in again"))
            } else if let busy = day.busyUntil, start < clock(busy) {
                outcome = .failed(SyncBeatFailure(.busy, "iCloud is busy, will retry"))
            } else {
                outcome = .answered(findings(at: answeredAt))
            }
            truth.beat(startedAt: start, outcome: outcome)
            switch outcome {
            case .answered(let found) where found.agree:
                last = .confirmed; misses = 0; failures = 0
                lastSynced = max(lastSynced, start)
            case .answered(let found):
                last = .missed; misses += 1; failures = 0
                if found.receiving > day.onlyThere { beatsThatFoundSomethingComing += 1 }
            case .failed:
                last = .failed; failures += 1
            }
            if case .answered(let found) = outcome, let returnedAt, start >= returnedAt, unsentAtFirstBeatAfterReturn == nil {
                unsentAtFirstBeatAfterReturn = found.sending
            }
            lastStart = start
            lastEnd = answeredAt
            if eligible { schedule(at: answeredAt) }
        }

        private func findings(at t: Date) -> BoltTruth.Findings {
            let inFlight = day.events.contains { clock($0.start) <= t && t < clock($0.end) }
            let coming = day.coming.filter { clock($0.0) <= t && t < clock($0.1) }.map(\.2).reduce(0, +)
            let old = clock("2026-11-08 16:23:22.074")  // older than every look: the phone's last own change (I1742)
            let entity = "TaskItem"
            var local: [SyncComparison.Local] = []
            var remote: [SyncComparison.Remote] = []
            func there(_ id: UUID) -> SyncComparison.Remote {
                SyncComparison.Remote(entity: entity, id: id, updatedAt: old, recordName: "CD_\(entity)_\(id)", modifiedAt: old)
            }
            for _ in 0..<3 {
                let id = UUID()
                local.append(SyncComparison.Local(entity: entity, id: id, updatedAt: old, createdAt: old))
                remote.append(there(id))
            }
            for _ in 0..<day.onlyHere { local.append(SyncComparison.Local(entity: entity, id: UUID(), updatedAt: old, createdAt: old)) }
            for _ in 0..<(day.onlyThere + coming) { remote.append(there(UUID())) }
            let comparison = SyncComparison.compare(remote: remote, local: local, entities: StoreInventory.entities)
            return BoltTruth.findings(comparison: comparison, unsentSaves: watchdog.waitingRecords,
                                      oldestUnsentSave: watchdog.oldestWaitingSave, lastLocalSaveAt: nil,
                                      inFlight: inFlight, now: t)
        }

        /// Advances to `t`: moments, beats and their answers in time order. Then reads what the marks say.
        func look(_ text: String) -> Look {
            let t = clock(text)
            precondition(t >= now, "looks go forward")
            while true {
                var candidates: [(at: Date, rank: Int)] = []
                if let at = moments.first?.at { candidates.append((at, 1)) }
                if let running { candidates.append((running.answerAt, 0)) }
                if eligible, running == nil, let due { candidates.append((due, 2)) }
                guard let next = candidates.min(by: { ($0.at, $0.rank) < ($1.at, $1.rank) }), next.at <= t else { break }
                now = next.at
                switch next.rank {
                case 0: answer(running!.start, at: next.at)
                case 1: moments.removeFirst().apply(self)
                default: startBeat(at: next.at)
                }
                if truth.verdict(at: now).filled { filledMoments.append(now) }
            }
            now = t
            steadiness.tick(t)
            let verdict = truth.verdict(at: t)
            if verdict.filled { filledMoments.append(t) }
            let shown = BoltTruth.gate(steadiness.shown ?? .synced(lastSynced), verdict)
            return Look(filled: verdict.filled, state: shown, verdict: verdict,
                        words: SyncWords.status(state: shown, verdict: verdict, lastSynced: lastSynced, now: t))
        }
    }
}
