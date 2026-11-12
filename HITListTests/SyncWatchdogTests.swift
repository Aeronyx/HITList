import XCTest
@testable import HITList

/// The 5-second rule (brief 25, item 3): exports after saves, imports after pushes, stuck events, and no
/// false alarms while sync can't happen (offline, signed out, suspended).
final class SyncWatchdogTests: XCTestCase {
    /// At the reference date, so `at(0.9) - at(0)` is exactly 0.9 and findings compare equal.
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private let exportID = UUID()
    private let importID = UUID()

    private func started(_ id: UUID, _ type: SyncEventType, _ time: TimeInterval) -> SyncSignal {
        .eventStarted(id: id, type: type, at: at(time))
    }

    private func ended(_ id: UUID, _ type: SyncEventType, from start: TimeInterval, at end: TimeInterval,
                       succeeded: Bool = true, error: String? = nil) -> SyncSignal {
        .eventEnded(id: id, type: type, startedAt: at(start), succeeded: succeeded, error: error, at: at(end))
    }

    /// A watchdog that has seen the network, the account and a successful CloudKit setup, as the app's
    /// does within a second or two of launch, on a store that has imported before (`lastImportAt`; nil is
    /// a store's first import: a new device, a reinstall, a reset).
    private func makeWatchdog(lastImportAt: Date? = Date(timeIntervalSinceReferenceDate: -3600)) -> SyncWatchdog {
        var dog = SyncWatchdog(lastImportAt: lastImportAt)
        _ = dog.handle(.network(online: true, at: at(-100)))
        _ = dog.handle(.account(available: true, description: "available", at: at(-100)))
        let setup = UUID()
        _ = dog.handle(started(setup, .setup, -101))
        _ = dog.handle(ended(setup, .setup, from: -101, at: -100))
        return dog
    }

    // MARK: Exports after saves

    func testAnExportWithinFiveSecondsIsOnTime() {
        var dog = makeWatchdog()
        XCTAssertEqual(dog.handle(.localSave(at: at(0))), [])
        XCTAssertEqual(dog.handle(started(exportID, .exporting, 0.1)), [])
        XCTAssertEqual(dog.handle(ended(exportID, .exporting, from: 0.1, at: 0.3)), [.exportOnTime(latency: 0.3, saves: 1)])
        XCTAssertEqual(dog.tick(at(10)), [])
        XCTAssertNil(dog.nextDeadline(after: at(0.3)), "nothing left to watch, so no timer")
        XCTAssertEqual(dog.waitingSaves, 0)
    }

    /// Brief 95, George's logs: the 0.9.3 launch on his Mac saved 46 tasks in one save (M1676). The bolt's words
    /// count what is waiting by records, so they said "Sending 1 change to iCloud…" for 46 before this.
    func testWaitingRecordsCountEachSavesRecordsUntilTheExportThatCoversThem() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0), records: 46))
        _ = dog.handle(.localSave(at: at(1)))
        XCTAssertEqual(dog.waitingSaves, 2)
        XCTAssertEqual(dog.waitingRecords, 47)
        // An export that started after the first save but before the second covers the first only.
        _ = dog.handle(started(exportID, .exporting, 0.5))
        _ = dog.handle(ended(exportID, .exporting, from: 0.5, at: 1.5))
        XCTAssertEqual(dog.waitingRecords, 1)
        XCTAssertEqual(dog.oldestWaitingSave, at(1))
        let next = UUID()
        _ = dog.handle(started(next, .exporting, 2))
        _ = dog.handle(ended(next, .exporting, from: 2, at: 2.2))
        XCTAssertEqual(dog.waitingRecords, 0)
    }

    func testPastTheCapTheRecordsLeaveWithTheirSaves() {
        var dog = makeWatchdog()
        let cap = dog.rules.maxWaiting
        for i in 0..<(cap + 5) { _ = dog.handle(.localSave(at: at(Double(i) * 0.01), records: i == 1 ? 1000 : 2)) }
        XCTAssertEqual(dog.waitingSaves, cap)
        XCTAssertEqual(dog.waitingRecords, cap * 2, "the dropped saves (the second onwards) take their records with them")
    }

    func testNoExportWithinFiveSecondsIsOverdueOnce() throws {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.nextDeadline(after: at(0)), at(5))
        XCTAssertEqual(dog.tick(at(4.9)), [])
        let findings = dog.tick(at(5))
        guard case let .exportOverdue(saves, context)? = findings.first, findings.count == 1 else {
            return XCTFail("expected one overdue export, got \(findings)")
        }
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(context.online, true)
        XCTAssertEqual(context.account, "available")
        XCTAssertEqual(findings[0].level, .error)
        XCTAssertEqual(findings[0].message(rules: dog.rules), "Export overdue: nothing exported within 5.0 s of a local save")
        XCTAssertEqual(dog.tick(at(30)), [], "reported once")
        XCTAssertEqual(dog.waitingSaves, 1)
    }

    func testTheOverdueExportReportsHowLateItWas() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        _ = dog.tick(at(5))
        _ = dog.handle(started(exportID, .exporting, 11))
        let late = dog.handle(ended(exportID, .exporting, from: 11, at: 12))
        XCTAssertEqual(late, [.exportLate(latency: 12, saves: 1)])
        XCTAssertEqual(late.first?.level, .notice)
        XCTAssertEqual(late.first?.message(rules: dog.rules), "Late export: finished 12 s after the save, 7.0 s past the limit")
        XCTAssertEqual(late.first?.fields, ["waited": "12 s", "saves": "1"])
    }

    func testSavesDuringAnOverdueWaitAreCountedNotReportedAgain() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.tick(at(5)).count, 1)
        XCTAssertEqual(dog.handle(.localSave(at: at(6))), [])
        XCTAssertEqual(dog.handle(.localSave(at: at(7))), [])
        XCTAssertEqual(dog.tick(at(20)), [])
        XCTAssertEqual(dog.handle(ended(exportID, .exporting, from: 30, at: 31)), [.exportLate(latency: 31, saves: 3)])
    }

    func testANewSaveAfterALateExportStartsANewEpisode() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        _ = dog.tick(at(5))
        _ = dog.handle(ended(exportID, .exporting, from: 9, at: 10))
        _ = dog.handle(.localSave(at: at(20)))
        XCTAssertEqual(dog.tick(at(24.9)), [])
        XCTAssertEqual(dog.tick(at(25)).count, 1, "overdue again: a second episode")
    }

    func testAnExportThatStartedBeforeTheSaveDoesNotCoverIt() {
        var dog = makeWatchdog()
        _ = dog.handle(started(exportID, .exporting, -1))
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.handle(ended(exportID, .exporting, from: -1, at: 0.5)), [])
        XCTAssertEqual(dog.tick(at(5)).count, 1, "the save still needs its own export")
    }

    func testASaveReportedAfterItsExportEndedIsCovered() {
        // The save notification and the export race; the export may end before the save reaches the watchdog.
        var dog = makeWatchdog()
        _ = dog.handle(started(exportID, .exporting, 0.05))
        _ = dog.handle(ended(exportID, .exporting, from: 0.05, at: 0.1))
        XCTAssertEqual(dog.handle(.localSave(at: at(0))), [.exportOnTime(latency: 0.1, saves: 1)])
        XCTAssertEqual(dog.tick(at(10)), [])
    }

    func testAFailedExportDoesNotCoverTheSave() throws {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.handle(ended(exportID, .exporting, from: 0.1, at: 1, succeeded: false, error: "network unavailable")), [])
        let findings = dog.tick(at(5))
        guard case let .exportOverdue(_, context)? = findings.first else { return XCTFail("\(findings)") }
        XCTAssertEqual(context.lastError, "export: network unavailable")
        XCTAssertEqual(context.fields["lastError"], "export: network unavailable")
    }

    func testSavesMadeWhileAnExportRunsGetTheNextOneWithAFullWindow() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        _ = dog.handle(started(exportID, .exporting, 0.1))
        _ = dog.handle(.localSave(at: at(1)))
        XCTAssertEqual(dog.handle(ended(exportID, .exporting, from: 0.1, at: 2)), [.exportOnTime(latency: 2, saves: 1)])
        XCTAssertEqual(dog.waitingSaves, 1)
        XCTAssertEqual(dog.nextDeadline(after: at(2)), at(7), "five seconds from the end of the export that missed it")
        XCTAssertEqual(dog.tick(at(6.9)), [])
        XCTAssertEqual(dog.tick(at(7)).count, 1)
    }

    func testSetupEventsDontCoverSaves() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.handle(ended(UUID(), .setup, from: 0.1, at: 0.5)), [])
        XCTAssertEqual(dog.waitingSaves, 1)
    }

    // MARK: Imports after pushes

    func testAnImportAfterAPushIsMeasured() {
        var dog = makeWatchdog()
        _ = dog.handle(.push(at: at(0)))
        _ = dog.handle(started(importID, .importing, 0.4))
        let findings = dog.handle(ended(importID, .importing, from: 0.4, at: 0.8))
        XCTAssertEqual(findings, [.importAfterPush(latency: 0.8, pushes: 1)])
        XCTAssertEqual(findings.first?.isLogged, true, "every push gets its latency in the log")
        XCTAssertEqual(findings.first?.message(rules: dog.rules), "Import finished 0.80 s after the push")
    }

    func testAPushWithoutAnImportIsOverdueAndThenLate() {
        var dog = makeWatchdog()
        _ = dog.handle(.push(at: at(0)))
        let overdue = dog.tick(at(5))
        guard case .importOverdue(1, _)? = overdue.first else { return XCTFail("\(overdue)") }
        XCTAssertEqual(overdue.first?.message(rules: dog.rules), "Import overdue: nothing imported within 5.0 s of a push")
        XCTAssertEqual(dog.handle(ended(importID, .importing, from: 39, at: 40)), [.importLate(latency: 40, pushes: 1)])
    }

    /// Brief 95, George's iPhone at 13:36:01 on 2026-11-11 (I2259–2268): a push with the app in the background, no
    /// import while it stayed there, "Import overdue" as an error at 5 s; the import came 1.4 s after he brought the app
    /// to the front. All five "Import overdue" errors in his phone's log were this: iOS decides when the mirror imports
    /// while the app is in the background. Here 0 s is the push.
    func testAPushInTheBackgroundWaitsForTheFrontWithoutAnError() {
        var dog = makeWatchdog()
        _ = dog.handle(.suspended(at: at(-65)))
        _ = dog.handle(.resumed(at: at(0)))  // woken for the push (`CloudSyncMonitor.pushReceived`)
        _ = dog.handle(.push(at: at(0), inBackground: true))
        let waiting = dog.tick(at(5))
        XCTAssertEqual(waiting, [.waiting(.import, reason: SyncWatchdog.inBackgroundReason, count: 1)])
        XCTAssertEqual(waiting.first?.level, .info)
        XCTAssertEqual(waiting.first?.message(rules: dog.rules),
                       "Import waiting: the app is in the background; iOS chooses when the mirror imports")
        XCTAssertNil(dog.nextDeadline(after: at(5)), "no clock runs until the app is in front")
        XCTAssertEqual(dog.tick(at(17)), [])
        _ = dog.handle(.resumed(at: at(18)))
        _ = dog.handle(.activated(at: at(18), idle: 84))
        XCTAssertEqual(dog.nextDeadline(after: at(18)), at(23), "five seconds from coming to the front")
        _ = dog.handle(started(importID, .importing, 18.25))
        let findings = dog.handle(ended(importID, .importing, from: 18.25, at: 19.4))
        XCTAssertEqual(findings.first, .importAfterPush(latency: 19.4, pushes: 1), "on time: within five seconds of the front")
        guard case .importAfterActivation? = findings.last, findings.count == 2 else {
            return XCTFail("and, as at I2269, how long after the app came to the front: \(findings)")
        }
        XCTAssertFalse(findings.contains { $0.level == .error })
    }

    func testAPushInTheBackgroundImportedThereSaysNothingMore() {
        var dog = makeWatchdog()
        _ = dog.handle(.push(at: at(0), inBackground: true))
        _ = dog.handle(started(importID, .importing, 0.01))
        XCTAssertEqual(dog.handle(ended(importID, .importing, from: 0.01, at: 0.7)), [.importAfterPush(latency: 0.7, pushes: 1)])
        XCTAssertEqual(dog.tick(at(10)), [])
    }

    func testInFrontAPushStillHasFiveSeconds() {
        var dog = makeWatchdog()
        _ = dog.handle(.push(at: at(-30), inBackground: true))
        _ = dog.tick(at(-25))
        _ = dog.handle(.activated(at: at(0), idle: 120))
        let overdue = dog.tick(at(5))
        guard case .importOverdue(1, _)? = overdue.first else { return XCTFail("in front and nothing imported: \(overdue)") }
    }

    func testAnImportThatStartedJustBeforeThePushArrivedCounts() {
        var dog = makeWatchdog()
        _ = dog.handle(started(importID, .importing, -1.5))
        _ = dog.handle(.push(at: at(0)))
        XCTAssertEqual(dog.handle(ended(importID, .importing, from: -1.5, at: 0.5)), [.importAfterPush(latency: 0.5, pushes: 1)])
    }

    func testAPushReportedAfterItsImportEndedIsCovered() {
        var dog = makeWatchdog()
        _ = dog.handle(ended(importID, .importing, from: 0.1, at: 0.5))
        XCTAssertEqual(dog.handle(.push(at: at(0))), [.importAfterPush(latency: 0.5, pushes: 1)])
        XCTAssertEqual(dog.tick(at(10)), [])
    }

    // MARK: Stuck events

    func testAnEventRunningSixtySecondsIsStuckAndItsEndIsReported() {
        // Brief 25's own case: on Nov 1 an import started at 18:51:54 and never ended; the app quit at 18:59:31.
        var dog = makeWatchdog()
        _ = dog.handle(started(importID, .importing, 0))
        XCTAssertEqual(dog.nextDeadline(after: at(0)), at(60))
        XCTAssertEqual(dog.tick(at(59)), [])
        let stuck = dog.tick(at(60))
        guard case let .eventStuck(type, running, context)? = stuck.first, stuck.count == 1 else { return XCTFail("\(stuck)") }
        XCTAssertEqual(type, .importing)
        XCTAssertEqual(running, 60)
        XCTAssertEqual(context.inFlight, ["import 1 min"])
        XCTAssertEqual(stuck.first?.level, .error)
        XCTAssertEqual(stuck.first?.message(rules: dog.rules), "Import still running after 1 min")
        XCTAssertEqual(dog.tick(at(120)), [], "reported once")
        let recovered = dog.handle(ended(importID, .importing, from: 0, at: 452))
        XCTAssertEqual(recovered, [.eventRecovered(type: .importing, duration: 452, succeeded: true)])
        XCTAssertEqual(recovered.first?.message(rules: dog.rules), "Stuck import finished after 7 min 32 s")
    }

    func testStalledNeedsTwoMinutesOfRunningWhileNothingStoodInTheWay() {
        var dog = makeWatchdog()
        _ = dog.handle(started(importID, .importing, 0))
        XCTAssertNil(dog.stalledSince(now: at(119)))
        XCTAssertEqual(dog.stalledSince(now: at(120)), at(0))
        _ = dog.handle(.network(online: false, at: at(130)))
        XCTAssertNil(dog.stalledSince(now: at(200)), "offline: of course it can't finish")
        _ = dog.handle(.network(online: true, at: at(300)))
        XCTAssertNil(dog.stalledSince(now: at(419)), "the clock restarts when the network returns")
        XCTAssertEqual(dog.stalledSince(now: at(420)), at(0), "and reports when the event began")
        _ = dog.handle(ended(importID, .importing, from: 0, at: 430))
        XCTAssertNil(dog.stalledSince(now: at(500)))
    }

    // MARK: No false alarms

    func testNothingIsOverdueWhileOfflineIsAlreadyKnown() {
        var dog = makeWatchdog()
        _ = dog.handle(.network(online: false, at: at(-10)))
        XCTAssertEqual(dog.handle(.localSave(at: at(0))), [.waiting(.export, reason: "offline", count: 1)])
        XCTAssertEqual(dog.handle(.localSave(at: at(1))), [], "said once per wait")
        _ = dog.handle(started(exportID, .exporting, 2))
        XCTAssertEqual(dog.tick(at(500)), [], "neither overdue nor stuck while offline")
        XCTAssertEqual(dog.handle(.network(online: true, at: at(600))), [])
        XCTAssertEqual(dog.nextDeadline(after: at(600)), at(605), "a full window after the network returns")
        XCTAssertEqual(dog.handle(ended(exportID, .exporting, from: 601, at: 602)), [.exportOnTime(latency: 602, saves: 2)])
        XCTAssertEqual(dog.tick(at(700)), [])
    }

    func testGoingOfflinePausesARunningClock() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.handle(.network(online: false, at: at(2))), [.waiting(.export, reason: "offline", count: 1)])
        XCTAssertEqual(dog.tick(at(10)), [])
        XCTAssertNil(dog.nextDeadline(after: at(10)))
        _ = dog.handle(.network(online: true, at: at(100)))
        XCTAssertEqual(dog.tick(at(104.9)), [])
        XCTAssertEqual(dog.tick(at(105)).count, 1, "overdue if nothing came within five seconds of reconnecting")
    }

    func testNoICloudAccountBlocksLikeOffline() {
        var dog = makeWatchdog()
        _ = dog.handle(.account(available: false, description: "no account", at: at(-1)))
        XCTAssertEqual(dog.handle(.localSave(at: at(0))), [.waiting(.export, reason: "iCloud not available", count: 1)])
        XCTAssertEqual(dog.handle(.push(at: at(0))), [.waiting(.import, reason: "iCloud not available", count: 1)])
        XCTAssertEqual(dog.tick(at(100)), [])
    }

    func testAnUnknownNetworkOrAccountDoesntBlock() {
        var dog = SyncWatchdog()
        let setup = UUID()
        _ = dog.handle(ended(setup, .setup, from: -1, at: 0))
        XCTAssertNil(dog.blockedReason)
        XCTAssertNil(dog.waitBlockedReason)
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.tick(at(5)).count, 1)
    }

    func testNothingIsOverdueBeforeCloudKitIsSetUp() {
        // The simulator, 2026-11-02: the launch's seeding save reached the watchdog 25 s late, while setup was
        // still waiting for an account that wasn't there. That was reported as an overdue export.
        var dog = SyncWatchdog()
        XCTAssertEqual(dog.waitBlockedReason, "CloudKit not set up yet")
        let setup = UUID()
        _ = dog.handle(started(setup, .setup, 0))
        XCTAssertEqual(dog.handle(.localSave(at: at(0.1))), [.waiting(.export, reason: "CloudKit not set up yet", count: 1)])
        XCTAssertEqual(dog.tick(at(25)), [])
        _ = dog.handle(.account(available: false, description: "no account", at: at(25)))
        XCTAssertEqual(dog.handle(ended(setup, .setup, from: 0, at: 26, succeeded: false, error: "not signed in to iCloud")), [])
        XCTAssertEqual(dog.waitBlockedReason, "iCloud not available")
        XCTAssertEqual(dog.tick(at(500)), [], "no account: nothing can export, so nothing is overdue")
    }

    func testTheWaitsStartWhenSetupSucceeds() {
        var dog = SyncWatchdog()
        _ = dog.handle(.network(online: true, at: at(-1)))
        _ = dog.handle(.account(available: true, description: "available", at: at(-1)))
        let setup = UUID()
        _ = dog.handle(started(setup, .setup, 0))
        _ = dog.handle(.localSave(at: at(0.5)))
        XCTAssertEqual(dog.handle(ended(setup, .setup, from: 0, at: 2)), [])
        XCTAssertNil(dog.waitBlockedReason)
        XCTAssertEqual(dog.nextDeadline(after: at(2)), at(7), "a full window from the setup")
        XCTAssertEqual(dog.handle(ended(exportID, .exporting, from: 2.1, at: 2.6)), [.exportOnTime(latency: 2.1, saves: 1)])
    }

    func testAFailedSetupPausesTheWaitsUntilTheNextOneSucceeds() {
        var dog = makeWatchdog()
        let retry = UUID()
        _ = dog.handle(started(retry, .setup, 10))
        XCTAssertEqual(dog.handle(ended(retry, .setup, from: 10, at: 11, succeeded: false, error: "iCloud is busy, will retry")), [])
        XCTAssertEqual(dog.handle(.localSave(at: at(12))), [.waiting(.export, reason: "CloudKit setup failed", count: 1)])
        XCTAssertEqual(dog.tick(at(60)), [])
        let again = UUID()
        _ = dog.handle(started(again, .setup, 70))
        _ = dog.handle(ended(again, .setup, from: 70, at: 71))
        XCTAssertEqual(dog.tick(at(75.9)), [])
        XCTAssertEqual(dog.tick(at(76)).count, 1, "overdue once five seconds pass after a working setup")
    }

    func testAStuckSetupIsStillCaught() {
        // Setup gates the 5-second waits, not the stuck clock: a setup that hangs (cloudd unreachable) is reported.
        var dog = SyncWatchdog()
        _ = dog.handle(started(UUID(), .setup, 0))
        guard case .eventStuck(.setup, 60, _)? = dog.tick(at(60)).first else { return XCTFail() }
        XCTAssertEqual(dog.stalledSince(now: at(120)), at(0))
    }

    func testSuspensionPausesTheClocksAndResumingRestartsThem() {
        var dog = makeWatchdog()
        _ = dog.handle(started(exportID, .exporting, 0))
        _ = dog.handle(.suspended(at: at(10)))
        XCTAssertEqual(dog.blockedReason, "app not running")
        XCTAssertEqual(dog.tick(at(1000)), [], "a phone in a pocket isn't stuck")
        _ = dog.handle(.resumed(at: at(1000)))
        XCTAssertEqual(dog.tick(at(1059)), [])
        guard case let .eventStuck(_, running, _)? = dog.tick(at(1060)).first else { return XCTFail() }
        XCTAssertEqual(running, 1060, "the message says how long since it began")
    }

    // MARK: Activation

    func testAnImportAfterComingBackIsMeasuredButAQuickClickIsnt() {
        var dog = makeWatchdog()
        _ = dog.handle(.activated(at: at(0), idle: 300))
        XCTAssertEqual(dog.nextDeadline(after: at(0)), at(60))
        XCTAssertEqual(dog.handle(ended(importID, .importing, from: 0.2, at: 0.9)), [.importAfterActivation(latency: 0.9)])
        _ = dog.handle(.activated(at: at(100), idle: 5))
        _ = dog.handle(.activated(at: at(200), idle: nil))
        XCTAssertNil(dog.nextDeadline(after: at(200)), "short or unknown absences aren't measured")
        _ = dog.handle(.activated(at: at(300), idle: 120))
        let none = dog.tick(at(360))
        XCTAssertEqual(none, [.noImportAfterActivation(window: 60)])
        XCTAssertEqual(none.first?.level, .info, "data, not an error: SwiftData decides when to import")
        XCTAssertEqual(none.first?.message(rules: dog.rules), "No import within 1 min of the app becoming active")
    }

    // MARK: Bookkeeping

    func testTheNextDeadlineIsTheEarliestPendingOne() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        _ = dog.handle(.push(at: at(2)))
        _ = dog.handle(started(importID, .importing, 1))
        XCTAssertEqual(dog.nextDeadline(after: at(0)), at(5))
        XCTAssertEqual(dog.nextDeadline(after: at(5)), at(7))
        XCTAssertEqual(dog.nextDeadline(after: at(7)), at(61))
        XCTAssertEqual(dog.nextDeadline(after: at(61)), at(121))
    }

    func testTheContextSaysWhatWasKnown() {
        var dog = SyncWatchdog(lastExportAt: at(-180), lastImportAt: nil)
        _ = dog.handle(.network(online: true, at: at(-100)))
        _ = dog.handle(.account(available: true, description: "available", at: at(-100)))
        _ = dog.handle(started(importID, .importing, -62))
        XCTAssertEqual(dog.context(at(0)).fields, [
            "online": "yes", "account": "available", "inFlight": "import 1 min 2 s", "lastError": "none",
            "sinceLastExport": "3 min", "sinceLastImport": "never",
        ])
    }

    func testAnEndWithoutAStartIsHandled() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.handle(ended(exportID, .exporting, from: 0.5, at: 1)), [.exportOnTime(latency: 1, saves: 1)])
        XCTAssertEqual(dog.inFlightCount, 0)
    }

    func testGeorgesNovemberFirstSessionWouldHaveBeenCaught() throws {
        // The TestFlight Mac app, pid 41015: an import started 2 s after launch and never ended; tasks were
        // edited at +13 s and created at +4 min 7 s; George quit at +7 min 37 s. Nothing synced after launch.
        var dog = makeWatchdog()
        _ = dog.handle(started(importID, .importing, 0))
        _ = dog.handle(.localSave(at: at(13)))
        let overdue = dog.tick(at(18))
        guard case .exportOverdue(1, let context)? = overdue.first else { return XCTFail("\(overdue)") }
        XCTAssertEqual(context.inFlight, ["import 18 s"], "the context names the import holding everything up")
        guard case .eventStuck(.importing, 60, _)? = dog.tick(at(60)).first else { return XCTFail() }
        XCTAssertEqual(dog.stalledSince(now: at(120)), at(0), "from two minutes the state says stuck and Settings offers a relaunch")
        _ = dog.handle(.localSave(at: at(247)))
        XCTAssertEqual(dog.tick(at(457)), [], "nothing new to report until something finishes")
        XCTAssertEqual(dog.waitingSaves, 2, "the Quitting line says two saves never left")
    }

    // MARK: A store's first import (beta review)

    /// A new device, a reinstall or a reset downloads every task in its first import, one event that can
    /// run for minutes with nothing wrong. At two minutes the state said "Sync paused: stuck" and offered a
    /// relaunch, which starts the download over. A store's first import now gets ten minutes.
    // MARK: George's sync blip of 0.9.0 (21) (brief 78)

    /// George's Mac, 2026-11-10, first launch of build 21 (seconds after 18:11:18.435, the first setup): setup, an
    /// export, an import cut off by the account going "temporarily unavailable", a failed setup, the account back,
    /// two setups, a 7.7 s import, an export, an import failing with badContainer; then six local saves from 18:13:48
    /// that were never exported (CloudKit's mirroring stopped; George quit at 18:14:11 and relaunched).
    private func georgesBlip(_ dog: inout SyncWatchdog) -> [SyncWatchdog.Finding] {
        let s1 = UUID(), e1 = UUID(), i1 = UUID(), s2 = UUID(), s3 = UUID(), s4 = UUID(), i2 = UUID(), e2 = UUID(), i3 = UUID()
        let signals: [SyncSignal] = [
            .network(online: true, at: at(-0.001)), .account(available: true, description: "available", at: at(-0.002)),
            started(s1, .setup, 0), ended(s1, .setup, from: 0, at: 0.066),
            started(e1, .exporting, 0.116), ended(e1, .exporting, from: 0.116, at: 0.267),
            started(i1, .importing, 0.283),
            .account(available: false, description: "temporarily unavailable", at: at(7.19)),
            ended(i1, .importing, from: 0.283, at: 9.845, succeeded: false, error: "iCloud needs you to sign in again"),
            started(s2, .setup, 9.864), ended(s2, .setup, from: 9.864, at: 9.952, succeeded: false, error: "not signed in to iCloud"),
            started(s3, .setup, 20.837), ended(s3, .setup, from: 20.837, at: 20.85),
            started(s4, .setup, 20.866), ended(s4, .setup, from: 20.866, at: 20.876),
            started(i2, .importing, 21.007),
            .account(available: true, description: "available", at: at(21.308)),
            ended(i2, .importing, from: 21.007, at: 28.664),
            started(e2, .exporting, 28.681), ended(e2, .exporting, from: 28.681, at: 28.775),
            started(i3, .importing, 28.9), ended(i3, .importing, from: 28.9, at: 29.218, succeeded: false, error: "app can't use iCloud"),
            .localSave(at: at(150.434)), .localSave(at: at(150.434)), .localSave(at: at(150.434)),
            .localSave(at: at(154.446)), .localSave(at: at(161.519)), .localSave(at: at(161.519)),
        ]
        var findings: [SyncWatchdog.Finding] = []
        var stalls: [Date] = []
        for signal in signals {
            findings += dog.handle(signal)
            if let stall = dog.stall(now: signalTime(signal)) { stalls.append(stall.since) }
        }
        XCTAssertEqual(stalls, [], "nothing in the blip itself looks stuck")
        return findings
    }

    private func signalTime(_ signal: SyncSignal) -> Date {
        switch signal {
        case let .eventStarted(_, _, at), let .eventEnded(_, _, _, _, _, at), let .localSave(at, _), let .push(at, _),
             let .activated(at, _), let .network(_, at), let .account(_, _, at), let .suspended(at), let .resumed(at):
            return at
        }
    }

    func testAfterGeorgesBlipTheSavesThatNeverExportedAreCalledStuckAfterTwoMinutes() throws {
        var dog = makeWatchdog()
        _ = georgesBlip(&dog)
        XCTAssertEqual(dog.tick(at(155.434)).count, 1, "the 5-second rule's overdue export, as the log had at 18:13:52")
        XCTAssertNil(dog.stall(now: at(270)), "under two minutes of waiting")
        XCTAssertEqual(try XCTUnwrap(dog.nextDeadline(after: at(270))).timeIntervalSince(at(270.434)), 0, accuracy: 1e-6,
                       "one timer, for the moment it becomes stuck")
        let findings = dog.tick(at(270.434))
        guard case let .exportStopped(saves, waited, _)? = findings.first, findings.count == 1 else {
            return XCTFail("expected the export to be reported stopped, got \(findings)")
        }
        XCTAssertEqual(saves, 6)
        XCTAssertEqual(waited, 120, accuracy: 0.01)
        XCTAssertEqual(findings[0].level, .error)
        XCTAssertEqual(findings[0].message(rules: dog.rules),
                       "Export still not started 2 min after a local save, with nothing running: iCloud sync has stopped; relaunching starts it again")
        XCTAssertEqual(dog.stall(now: at(270.434)), .quiet(since: at(150.434), saves: 6))
        XCTAssertEqual(dog.stalledSince(now: at(270.434)), at(150.434))
        XCTAssertEqual(dog.tick(at(400)), [], "reported once")
    }

    func testTheStuckRowSaysWhichKindOfStuck() {
        let quiet = SyncStuckRow.detail(for: .quiet(since: at(0), saves: 6))
        XCTAssertTrue(quiet.hasPrefix("iCloud sync stopped answering: 6 changes made since "), quiet)
        XCTAssertTrue(quiet.contains("haven't been sent."), quiet)
        XCTAssertTrue(SyncStuckRow.detail(for: .quiet(since: at(0), saves: 1)).contains("1 change made since"))
        XCTAssertTrue(SyncStuckRow.detail(for: .busy(since: at(0))).hasPrefix("iCloud sync has been busy with one request since "))
    }

    func testAQuietStallEndsWhenTheExportFinallyComes() {
        var dog = makeWatchdog()
        _ = dog.handle(.localSave(at: at(0)))
        _ = dog.tick(at(5))
        XCTAssertEqual(dog.stall(now: at(120)), .quiet(since: at(0), saves: 1))
        _ = dog.handle(started(exportID, .exporting, 121))
        XCTAssertNil(dog.stall(now: at(121)), "something is running again")
        _ = dog.handle(ended(exportID, .exporting, from: 121, at: 121.2))
        XCTAssertNil(dog.stall(now: at(122)))
        XCTAssertEqual(dog.waitingSaves, 0)
    }

    func testOnlyTimeWithNothingRunningCountsTowardsAQuietStall() {
        var dog = makeWatchdog()
        _ = dog.handle(started(importID, .importing, 0))
        _ = dog.handle(.localSave(at: at(1)))
        _ = dog.handle(ended(importID, .importing, from: 0, at: 100))
        XCTAssertNil(dog.stall(now: at(150)), "the export waited behind the import until 100 s")
        XCTAssertEqual(dog.stall(now: at(220)), .quiet(since: at(1), saves: 1))
    }

    func testSavesWaitingWhileSyncCantHappenAreNeverAQuietStall() {
        var dog = makeWatchdog()
        _ = dog.handle(.network(online: false, at: at(0)))
        _ = dog.handle(.localSave(at: at(1)))
        XCTAssertNil(dog.stall(now: at(600)), "offline: the export can't happen")
        _ = dog.handle(.network(online: true, at: at(600)))
        XCTAssertNil(dog.stall(now: at(700)), "the clock starts again when the network comes back")
        XCTAssertEqual(dog.stall(now: at(720)), .quiet(since: at(1), saves: 1))
        var importing = makeWatchdog()
        _ = importing.handle(started(importID, .importing, 0))
        _ = importing.handle(.localSave(at: at(1)))
        XCTAssertNil(importing.stall(now: at(119)), "an import is running: the export waits its turn")
    }

    func testAFirstImportGetsTenMinutesBeforeTheStateSaysStuck() {
        var dog = makeWatchdog(lastImportAt: nil)
        _ = dog.handle(started(importID, .importing, 0))
        XCTAssertNil(dog.stalledSince(now: at(121)))
        XCTAssertNil(dog.stalledSince(now: at(599)))
        XCTAssertEqual(dog.stalledSince(now: at(600)), at(0))
        XCTAssertEqual(dog.nextDeadline(after: at(60)), at(600), "the one timer wakes for the longer deadline")
        guard case .eventStuck(.importing, 60, _)? = dog.tick(at(60)).first else {
            return XCTFail("the log still notes a long first import at one minute")
        }
    }

    func testLaterImportsStillCountAsStuckAfterTwoMinutes() {
        var dog = makeWatchdog(lastImportAt: nil)
        _ = dog.handle(started(importID, .importing, 0))
        _ = dog.handle(ended(importID, .importing, from: 0, at: 300))
        let second = UUID()
        _ = dog.handle(started(second, .importing, 400))
        XCTAssertEqual(dog.stalledSince(now: at(520)), at(400))
    }

    func testOnlyImportsGetTheLongerWait() {
        var dog = makeWatchdog(lastImportAt: nil)
        _ = dog.handle(started(exportID, .exporting, 0))
        XCTAssertEqual(dog.stalledSince(now: at(120)), at(0))
    }

    /// After Settings → Reset local cache the new store has never synced: its first import is a first
    /// import again, and the context stops quoting the old store's times.
    func testForgettingTheLastSyncMakesTheNextImportAFirstImport() {
        var dog = makeWatchdog()
        dog.forgetLastSync()
        _ = dog.handle(started(importID, .importing, 0))
        XCTAssertNil(dog.stalledSince(now: at(300)))
        XCTAssertNil(dog.context(at(0)).sinceLastImport)
        XCTAssertNil(dog.lastExportAt)
    }

    /// The status line's "Synced 3 min ago" is remembered per store: a Debug build's own store
    /// (HITList-Development.store) shares the app group's defaults with the TestFlight app's.
    @MainActor
    func testEachStoreRemembersItsOwnSyncTimes() {
        XCTAssertEqual(CloudSyncMonitor.syncTimeKey(CloudSyncMonitor.lastImportKey, storeName: "HITList.store"), "sync.lastImportAt",
                       "the real store keeps the key 0.3.5 wrote")
        XCTAssertEqual(CloudSyncMonitor.syncTimeKey(CloudSyncMonitor.lastExportKey, storeName: "HITList-Development.store"),
                       "sync.lastExportAt.HITList-Development.store")
    }

    func testOnTimeExportsGetNoLineOfTheirOwn() {
        XCTAssertFalse(SyncWatchdog.Finding.exportOnTime(latency: 0.3, saves: 1).isLogged)
        XCTAssertEqual(SyncWatchdog.Finding.exportOnTime(latency: 0.3, saves: 1).fields["afterSave"], "0.30 s")
        XCTAssertTrue(SyncWatchdog.Finding.waiting(.import, reason: "offline", count: 2).isLogged)
        XCTAssertEqual(SyncWatchdog.Finding.waiting(.import, reason: "offline", count: 2).message(rules: .init()),
                       "Import waiting: offline")
    }
}

/// The fixes around a stuck sync and mixed environments (brief 25, item 6).
final class SyncRecoveryTests: XCTestCase {
    private let development = SyncEnvironment(cloudKit: .development, push: "development", channel: .debug, build: "11")
    private let production = SyncEnvironment(cloudKit: .production, push: "production", channel: .testFlight, build: "11")

    func testADevelopmentBuildGetsItsOwnStore() {
        XCTAssertEqual(SyncStoreGuard.isolationSuffix(environment: development, processEnvironment: [:]), "Development")
        XCTAssertEqual(SyncStoreGuard.isolationSuffix(environment: development, processEnvironment: ["HITLIST_STORE_SUFFIX": ""]),
                       "Development", "an empty suffix is no suffix")
    }

    func testTheGuardMovesTheStoreTheFactoryOpens() throws {
        // The guard works by setting HITLIST_STORE_SUFFIX before ModelContainerFactory reads it through
        // ProcessInfo; this pins that the variable set in-process is the one the factory sees.
        XCTAssertNil(ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"], "the test host runs without a suffix")
        defer { unsetenv("HITLIST_STORE_SUFFIX") }
        XCTAssertEqual(SyncStoreGuard.isolateDevelopmentStore(environment: development,
                                                              processEnvironment: ProcessInfo.processInfo.environment), "Development")
        XCTAssertEqual(ModelContainerFactory.groupStoreURL?.lastPathComponent ?? "HITList-Development.store", "HITList-Development.store")
        XCTAssertEqual(ModelContainerFactory.legacyStoreURL.lastPathComponent, "HITList-Development.store")
        XCTAssertNil(SyncStoreGuard.isolateDevelopmentStore(environment: development,
                                                            processEnvironment: ProcessInfo.processInfo.environment),
                     "once set, a second call leaves it")
        unsetenv("HITLIST_STORE_SUFFIX")
        XCTAssertEqual(ModelContainerFactory.legacyStoreURL.lastPathComponent, "HITList.store")
    }

    func testAnExplicitSideStoreIsKept() {
        XCTAssertNil(SyncStoreGuard.isolationSuffix(environment: development, processEnvironment: ["HITLIST_STORE_SUFFIX": "schema"]),
                     "the schema-deployment workflow names its own store")
    }

    func testProductionAndUnknownBuildsKeepTheRealStore() {
        XCTAssertNil(SyncStoreGuard.isolationSuffix(environment: production, processEnvironment: [:]))
        var unknown = production
        unknown.cloudKit = .unknown
        XCTAssertNil(SyncStoreGuard.isolationSuffix(environment: unknown, processEnvironment: [:]),
                     "an unsigned or unreadable build changes nothing")
    }

    /// Scratch defaults, so the tests never touch the app group's.
    private func scratchDefaults() -> UserDefaults {
        let name = "SyncRecoveryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testARelaunchedInstanceKnowsWhomToWaitFor() {
        // The App Sandbox drops a relaunch's arguments and environment (seen on the Mac, 2026-11-02), so the
        // relaunching instance leaves its pid in the shared defaults.
        let defaults = scratchDefaults()
        let now = Date()
        defaults.set(41015, forKey: SyncRecovery.pidKey)
        defaults.set(now.addingTimeInterval(-2), forKey: SyncRecovery.atKey)
        XCTAssertEqual(SyncRecovery.previousInstance(defaults: defaults, now: now, me: 7), 41015)
        XCTAssertNil(defaults.object(forKey: SyncRecovery.pidKey), "consumed by the first launch that reads it")
        XCTAssertNil(SyncRecovery.previousInstance(defaults: defaults, now: now, me: 7))
    }

    func testAStaleOrOwnHandoffIsIgnored() {
        let defaults = scratchDefaults()
        let now = Date()
        defaults.set(41015, forKey: SyncRecovery.pidKey)
        defaults.set(now.addingTimeInterval(-31), forKey: SyncRecovery.atKey)
        XCTAssertNil(SyncRecovery.previousInstance(defaults: defaults, now: now, me: 7), "older than 30 s: the relaunch failed")
        XCTAssertNil(defaults.object(forKey: SyncRecovery.atKey), "and it is cleared")
        defaults.set(7, forKey: SyncRecovery.pidKey)
        defaults.set(now, forKey: SyncRecovery.atKey)
        XCTAssertNil(SyncRecovery.previousInstance(defaults: defaults, now: now, me: 7), "never wait for yourself")
        XCTAssertNil(SyncRecovery.waitForPreviousInstance(defaults: scratchDefaults()), "a normal launch doesn't wait")
    }
}

/// The iOS push handler's wait (George, 2026-11-02): it ends as soon as the import answering the push
/// has finished, at once if that already happened, and only times out when the clock says so.
@MainActor
final class ImportWaiterTests: XCTestCase {
    private let push = Date(timeIntervalSinceReferenceDate: 1_000)
    private func at(_ seconds: TimeInterval) -> Date { push.addingTimeInterval(seconds) }

    /// A clock the test advances by hand.
    @MainActor
    private final class ManualClock {
        private var sleepers: [CheckedContinuation<Void, Never>] = []
        private(set) var requested: [Duration] = []
        var sleeping: Int { sleepers.count }

        func sleep(_ duration: Duration) async {
            requested.append(duration)
            await withCheckedContinuation { sleepers.append($0) }
        }

        func fire() {
            let woken = sleepers
            sleepers.removeAll()
            for sleeper in woken { sleeper.resume() }
        }
    }

    private func makeWaiter() -> (ImportWaiter, ManualClock) {
        let clock = ManualClock()
        return (ImportWaiter(sleep: { await clock.sleep($0) }), clock)
    }

    /// Lets a started wait reach its suspension point.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func testAnImportThatFinishedAfterThePushAnswersAtOnce() async {
        let (waiter, clock) = makeWaiter()
        // CloudKit took the push and imported before the handler's task started waiting.
        waiter.importEnded(startedAt: at(0.1), at: at(0.6), outcome: .succeeded)
        let outcome = await waiter.next(after: push, within: .seconds(25))
        XCTAssertEqual(outcome, .succeeded)
        XCTAssertTrue(clock.requested.isEmpty, "no timer: the app is released straight away")
        XCTAssertEqual(waiter.waitingCount, 0)
    }

    func testAnImportStartedJustBeforeThePushCounts() async {
        let (waiter, clock) = makeWaiter()
        waiter.importEnded(startedAt: at(-1.5), at: at(-0.2), outcome: .succeeded)
        let outcome = await waiter.next(after: push, within: .seconds(25))
        XCTAssertEqual(outcome, .succeeded, "within the watchdog's import slack of the push")
        XCTAssertTrue(clock.requested.isEmpty)
    }

    func testAnOlderImportDoesNotAnswerAndTheNextOneDoes() async {
        let (waiter, clock) = makeWaiter()
        waiter.importEnded(startedAt: at(-30), at: at(-20), outcome: .succeeded)
        let wait = Task { await waiter.next(after: push, within: .seconds(25)) }
        await settle { waiter.waitingCount == 1 && clock.sleeping == 1 }
        XCTAssertEqual(waiter.waitingCount, 1, "an import from before the push doesn't answer it")
        XCTAssertEqual(clock.requested, [.seconds(25)])

        waiter.importEnded(startedAt: at(0.3), at: at(1.2), outcome: .succeeded)
        let outcome = await wait.value
        XCTAssertEqual(outcome, .succeeded, "released when the import ends, not after 25 s")
        XCTAssertEqual(waiter.waitingCount, 0)
        clock.fire()   // the cancelled timer waking later changes nothing
        await settle { false }
        XCTAssertEqual(waiter.waitingCount, 0)
    }

    func testAFailedImportEndsTheWaitToo() async {
        let (waiter, clock) = makeWaiter()
        let wait = Task { await waiter.next(after: push, within: .seconds(25)) }
        await settle { clock.sleeping == 1 }
        waiter.importEnded(startedAt: at(0.5), at: at(2), outcome: .failed)
        let outcome = await wait.value
        XCTAssertEqual(outcome, .failed)
    }

    func testWithNoImportItTimesOutOnlyWhenTheClockSaysSo() async {
        let (waiter, clock) = makeWaiter()
        let wait = Task { await waiter.next(after: push, within: .seconds(25)) }
        await settle { clock.sleeping == 1 }
        XCTAssertEqual(waiter.waitingCount, 1)
        clock.fire()
        let outcome = await wait.value
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertEqual(waiter.waitingCount, 0)
    }

    /// Two pushes close together: one import answers both; a later push still waits for its own.
    func testOneImportAnswersEveryPushItCovers() async {
        let (waiter, clock) = makeWaiter()
        let first = Task { await waiter.next(after: push, within: .seconds(25)) }
        let second = Task { await waiter.next(after: at(1), within: .seconds(25)) }
        let third = Task { await waiter.next(after: at(60), within: .seconds(25)) }
        await settle { clock.sleeping == 3 }
        waiter.importEnded(startedAt: at(0.5), at: at(3), outcome: .succeeded)
        let firstOutcome = await first.value
        let secondOutcome = await second.value
        XCTAssertEqual(firstOutcome, .succeeded)
        XCTAssertEqual(secondOutcome, .succeeded)
        XCTAssertEqual(waiter.waitingCount, 1, "the push at +60 s isn't answered by an import that ended at +3 s")
        clock.fire()
        let thirdOutcome = await third.value
        XCTAssertEqual(thirdOutcome, .timedOut)
    }

    func testCoverageRule() {
        let ended = ImportWaiter.Ended(startedAt: at(-10), endedAt: at(0.01), outcome: .succeeded)
        XCTAssertTrue(ImportWaiter.covers(ended, pushAt: push), "finished after the push arrived")
        let before = ImportWaiter.Ended(startedAt: at(-3), endedAt: at(-1), outcome: .succeeded)
        XCTAssertFalse(ImportWaiter.covers(before, pushAt: push), "started more than the slack before, ended before")
        XCTAssertEqual(ImportWaiter.slack, SyncWatchdog.Rules().importSlack)
    }
}
