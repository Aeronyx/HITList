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

    /// A watchdog that has seen the network and the account, as the app's does within a second of launch.
    private func makeWatchdog() -> SyncWatchdog {
        var dog = SyncWatchdog()
        _ = dog.handle(.network(online: true, at: at(-100)))
        _ = dog.handle(.account(available: true, description: "available", at: at(-100)))
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
        XCTAssertNil(dog.blockedReason)
        _ = dog.handle(.localSave(at: at(0)))
        XCTAssertEqual(dog.tick(at(5)).count, 1)
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

    func testOnTimeExportsGetNoLineOfTheirOwn() {
        XCTAssertFalse(SyncWatchdog.Finding.exportOnTime(latency: 0.3, saves: 1).isLogged)
        XCTAssertEqual(SyncWatchdog.Finding.exportOnTime(latency: 0.3, saves: 1).fields["afterSave"], "0.30 s")
        XCTAssertTrue(SyncWatchdog.Finding.waiting(.import, reason: "offline", count: 2).isLogged)
        XCTAssertEqual(SyncWatchdog.Finding.waiting(.import, reason: "offline", count: 2).message(rules: .init()),
                       "Import waiting: offline")
    }
}
