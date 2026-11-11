import XCTest
import CloudKit
@testable import HITList

final class AccountWatchTests: XCTestCase {
    private var suiteName: String!
    private var watch: AccountWatch!

    override func setUp() {
        suiteName = "HITListTests.\(UUID().uuidString)"
        watch = AccountWatch(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testDeviceThatNeverHadICloudGetsNoBanner() {
        XCTAssertNil(watch.update(status: .noAccount, shown: nil, signedOutDismissed: false))
    }

    func testSignOutAfterSignInShowsBannerAndSignInClearsIt() {
        XCTAssertNil(watch.update(status: .available, shown: nil, signedOutDismissed: false))
        XCTAssertEqual(watch.update(status: .noAccount, shown: nil, signedOutDismissed: false), .signedOut)
        XCTAssertNil(watch.update(status: .available, shown: .signedOut, signedOutDismissed: false))
    }

    func testSignOutWhileTheAppWasClosedIsRemembered() {
        _ = watch.update(status: .available, shown: nil, signedOutDismissed: false)
        let nextLaunch = AccountWatch(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(nextLaunch.lastStatus, .available)
        XCTAssertEqual(nextLaunch.update(status: .noAccount, shown: nil, signedOutDismissed: false), .signedOut)
        XCTAssertEqual(nextLaunch.lastStatus, .noAccount)
    }

    func testDismissedSignOutBannerStaysHidden() {
        _ = watch.update(status: .available, shown: nil, signedOutDismissed: false)
        XCTAssertNil(watch.update(status: .noAccount, shown: nil, signedOutDismissed: true))
    }

    func testIndeterminateStatusChangesNothing() {
        _ = watch.update(status: .available, shown: nil, signedOutDismissed: false)
        XCTAssertEqual(watch.update(status: .couldNotDetermine, shown: .switched, signedOutDismissed: false), .switched)
        XCTAssertEqual(watch.update(status: .temporarilyUnavailable, shown: nil, signedOutDismissed: false), nil)
        XCTAssertEqual(watch.lastStatus, .available)
    }

    func testDifferentUserRecordMeansAccountSwitch() {
        XCTAssertNil(watch.update(userRecordName: "_alice", shown: nil), "first account seen")
        XCTAssertNil(watch.update(userRecordName: "_alice", shown: nil), "same account")
        XCTAssertEqual(watch.update(userRecordName: "_bob", shown: nil), .switched)
        XCTAssertNil(watch.update(userRecordName: "_bob", shown: nil), "remembered the new account")
    }

    // MARK: The account blip of 0.9.0 (21) (brief 78)

    /// Plays raw account statuses (seconds, status) through the steadiness the monitor uses and, as the monitor does,
    /// asks the watch what each change of the shown status asks for. Returns the changes, in order.
    private func play(_ statuses: [(TimeInterval, CKAccountStatus)], until end: TimeInterval,
                      remembered: CKAccountStatus? = .available) -> [AccountWatch.Change] {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var steady = AccountSteadiness(remembered: remembered)
        var shownBefore: CKAccountStatus?
        var notice: AccountWatch.Notice?
        var changes: [AccountWatch.Change] = []
        func apply() {
            guard let shown = steady.shown, shown != shownBefore else { return }
            let change = watch.change(from: shownBefore ?? remembered, to: shown, shown: notice, signedOutDismissed: false)
            notice = change.notice
            changes.append(change)
            shownBefore = shown
        }
        var queue = statuses
        var now = t0
        while true {
            let next = [queue.first.map { t0.addingTimeInterval($0.0) }, steady.nextDeadline(after: now)]
                .compactMap { $0 }.filter { $0 <= t0.addingTimeInterval(end) }.min()
            guard let next else { break }
            now = next
            if let first = queue.first, t0.addingTimeInterval(first.0) == next {
                queue.removeFirst()
                steady.observe(first.1, at: now)
            } else {
                steady.tick(now)
            }
            apply()
        }
        return changes
    }

    func testGeorgesBlipWhereTheAccountComesBackTheSameRunsNothing() {
        // George's Mac, 2026-11-10, seconds after 18:11:18.433: available, CKAccountChanged, "temporarily unavailable",
        // two bursts, available again (the same Apple account).
        _ = watch.identify(userRecordName: "_george")
        let changes = play([(0, .available), (7.192, .temporarilyUnavailable), (21.310, .available)], until: 600)
        XCTAssertEqual(changes, [AccountWatch.Change(notice: nil)], "one change: the launch's first answer")
        XCTAssertFalse(watch.identify(userRecordName: "_george").isSwitch, "the same account: no switch clean-up")
        XCTAssertEqual(watch.lastStatus, .available)
    }

    func testABriefNoAccountInsideABlipClearsNoRemindersAndShowsNoBanner() {
        let changes = play([(0, .available), (5, .noAccount), (8, .temporarilyUnavailable), (12, .available)], until: 600)
        XCTAssertFalse(changes.contains { $0.signsOut || $0.notice != nil || $0.forgetsAccount }, "\(changes)")
    }

    func testARealSignOutStillCleansUpWithinSeconds() {
        let changes = play([(0, .available), (5, .noAccount)], until: 60)
        XCTAssertEqual(changes.last, AccountWatch.Change(notice: .signedOut, signsOut: true, forgetsAccount: true))
        XCTAssertEqual(watch.lastStatus, .noAccount)
    }

    func testABlipThatStaysShowsButStillRunsNothing() {
        let changes = play([(0, .available), (5, .temporarilyUnavailable)], until: 600)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.last, AccountWatch.Change(notice: nil), "'sign in again' says so; nothing is cleared")
        XCTAssertEqual(watch.lastStatus, .available, "a blip is never remembered as the account's status")
    }

    func testTheAccountIsAskedAgainAFewTimesThenNotUntilSomethingElseAsks() {
        XCTAssertEqual(CloudSyncMonitor.accountRetryDelay(attempt: 0), 15)
        XCTAssertEqual(CloudSyncMonitor.accountRetryDelay(attempt: 1), 60)
        XCTAssertEqual(CloudSyncMonitor.accountRetryDelay(attempt: 2), 300)
        XCTAssertNil(CloudSyncMonitor.accountRetryDelay(attempt: 3), "bounded: no polling")
        XCTAssertTrue(AccountSteadiness.isBlip(.temporarilyUnavailable))
        XCTAssertTrue(AccountSteadiness.isBlip(.couldNotDetermine))
        XCTAssertFalse(AccountSteadiness.isBlip(.noAccount))
        XCTAssertFalse(AccountSteadiness.isBlip(.available))
    }

    func testBannerTexts() {
        XCTAssertEqual(AccountChangeBanner.message(for: .signedOut),
                       "Signed out of iCloud. Your tasks are safe in iCloud and come back when you sign in.")
    }
}
