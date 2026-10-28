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

    func testBannerTexts() {
        XCTAssertEqual(AccountChangeBanner.message(for: .signedOut),
                       "Signed out of iCloud. Your tasks are safe in iCloud and come back when you sign in.")
    }
}
