import XCTest
import CloudKit
@testable import HITList

/// The bolt with inertia (brief 78; George, 2026-11-10: "The point of the bolt is to visually tell a user 'Status is
/// green', not to inform them every single time something happens in the background").
final class SyncSteadinessTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: The Debug replay (item 6)

    func testTheReplayIsInOrderAndAboutFourMinutes() {
        let times = SyncReplay.script.map(\.at)
        XCTAssertEqual(times, times.sorted(), "steps in time order")
        XCTAssertEqual(Set(times).count, times.count, "no two steps at the same moment")
        XCTAssertEqual(SyncReplay.duration, 240, accuracy: 1)
    }

    func testTheReplayStartsLikeALaunchAfterThreeHoursAndAdvancesOnEachFinishedSync() {
        let before = SyncReplay.position(at: -1, start: start)
        XCTAssertEqual(before.state, .synced(start.addingTimeInterval(-3 * 3600)))
        XCTAssertNil(before.lastChange)
        XCTAssertEqual(SyncReplay.position(at: 0.3, start: start).state, .syncing, "setup")
        XCTAssertEqual(SyncReplay.position(at: 0.64, start: start).state, .synced(start.addingTimeInterval(-3 * 3600)),
                       "a setup ends without a sync")
        let firstExport = SyncReplay.position(at: 0.83, start: start)
        XCTAssertEqual(firstExport.state, .synced(start.addingTimeInterval(0.82)))
        XCTAssertEqual(firstExport.lastChange, start.addingTimeInterval(0.82))
    }

    func testTheReplayPlaysGeorgesAccountBlipAndTwoNetworkDrops() {
        let blip = SyncReplay.position(at: 85, start: start)
        XCTAssertEqual(blip.state, .error("iCloud needs you to sign in again", start.addingTimeInterval(81.19)))
        XCTAssertEqual(blip.account, .temporarilyUnavailable)
        let back = SyncReplay.position(at: 100, start: start)
        XCTAssertEqual(back.state, .syncing)
        XCTAssertEqual(back.account, .available)
        XCTAssertEqual(SyncReplay.position(at: 120, start: start).state, .error("app can't use iCloud", start.addingTimeInterval(103.218)))
        XCTAssertEqual(SyncReplay.position(at: 165, start: start).state, .offline)
        XCTAssertEqual(SyncReplay.position(at: 200, start: start).state, .offline)
        XCTAssertEqual(SyncReplay.position(at: 241, start: start).state, .synced(start.addingTimeInterval(225.4)))
    }
}
