import XCTest
import CloudKit
import SwiftUI
@testable import HITList
import HITListCore

/// Brief 144: the marks on HITList's own engine are one pure function of the engine's status, the account and the
/// network (`SyncEngineMarks.state`), with the words of `SyncWords`'s engine lines; the monitor shows it when the
/// board says `.own`, and nothing changes on the mirror. Every demo state (`SyncEngineDemo`) is checked here too.
@MainActor
final class SyncEngineStatusTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func marks(_ status: SyncStatus?, account: CKAccountStatus? = .available, online: Bool = true,
                       errorSince: Date? = nil) -> SyncState {
        SyncEngineMarks.state(status: status, account: account, isOnline: online, errorSince: errorSince, now: now)
    }

    private func words(_ state: SyncState) -> String {
        SyncWords.status(state: state, waiting: false, lastSynced: nil, now: now)
    }

    private func idle(waiting: Int = 0, firstFetchDone: Bool = true, lastError: String? = nil,
                      refused: [SyncKey] = [], refusal: String? = nil) -> SyncStatus {
        SyncStatus(state: .idle, waiting: waiting, firstFetchDone: firstFetchDone, lastFetchEnded: ago(5),
                   lastSendEnded: ago(30), lastError: lastError, refused: refused, refusal: refusal)
    }

    private func held(_ hold: SyncHold, waiting: Int = 0) -> SyncStatus {
        SyncStatus(state: .held(hold), waiting: waiting, firstFetchDone: true, lastFetchEnded: ago(5))
    }

    private func look(_ state: SyncState) -> SyncBolt.Look { SyncBolt.look(for: state, now: now, everSignedIn: true) }

    private let filled = SyncBolt.Look(symbol: "bolt.fill", color: Theme.bolt, opacity: 0.85)
    private let hollow = SyncBolt.Look(symbol: "bolt", color: Theme.bolt, opacity: 0.85)
    private let hollowRed = SyncBolt.Look(symbol: "bolt", color: HITColor.dueOverdue, opacity: 0.85)
    private let struckGrey = SyncBolt.Look(symbol: "bolt.slash.fill", color: Theme.secondaryText, opacity: 0.9)
    private let struckRed = SyncBolt.Look(symbol: "bolt.slash.fill", color: HITColor.dueOverdue, opacity: 0.85)

    // MARK: The bolt is filled exactly when the status says synced

    func testFilledExactlyWhenTheStatusIsSynced() {
        let synced = marks(idle())
        XCTAssertEqual(synced, .synced(ago(5)), "the last fetch or accepted send, whichever is later")
        XCTAssertEqual(look(synced), filled)
        XCTAssertEqual(words(synced), "Synced just now")
        // Every other status of a running engine is hollow, never filled.
        let notSynced: [SyncStatus] = [
            idle(waiting: 1), idle(firstFetchDone: false), idle(lastError: "network unavailable"),
            SyncStatus(state: .fetching, waiting: 0, firstFetchDone: true),
            SyncStatus(state: .sending, waiting: 0, firstFetchDone: true),
            SyncStatus(state: .starting), SyncStatus(state: .off),
        ]
        for status in notSynced {
            XCTAssertFalse(status.isSynced)
            XCTAssertNotEqual(look(marks(status)), filled, "\(status)")
        }
    }

    /// 0.9.17: the engine remembers across launches that its first whole fetch was made, so its first status of a
    /// launch reads "idle, nothing waiting" before it has asked iCloud anything. That is not synced yet: the marks
    /// said "Synced just now" for the half second before the launch's fetch began (George's Mac, 2026-11-20).
    func testSyncedWithNoSyncOfThisLaunchBehindItIsChecking() {
        let status = SyncStatus(state: .idle, waiting: 0, firstFetchDone: true)
        XCTAssertTrue(status.isSynced, "as the engine itself reads it")
        XCTAssertEqual(marks(status), .engine(SyncEngineMarks.checking))
        XCTAssertEqual(look(marks(status)), hollow)
        XCTAssertEqual(words(marks(status)), "Checking with iCloud…")
    }

    // MARK: Changes waiting

    func testChangesWaitingAreHollowWithTheExactCount() {
        XCTAssertEqual(words(marks(idle(waiting: 3))), "3 changes waiting to go to iCloud")
        XCTAssertEqual(words(marks(idle(waiting: 1))), "1 change waiting to go to iCloud")
        XCTAssertEqual(look(marks(idle(waiting: 3))), hollow)
        // While a send is under way: the same words.
        let sending = SyncStatus(state: .sending, waiting: 3, firstFetchDone: true)
        XCTAssertEqual(words(marks(sending)), "3 changes waiting to go to iCloud")
        XCTAssertEqual(look(marks(sending)), hollow)
    }

    func testOfflineIsStruckThroughAndSaysWhatGoesWhenBackOnline() {
        // Struck through whatever waits, as today's offline bolt; the words carry the exact count.
        let offline = marks(idle(waiting: 3), online: false)
        XCTAssertEqual(words(offline), "Offline: 3 changes go to iCloud when you are back online")
        XCTAssertEqual(look(offline), struckGrey)
        XCTAssertEqual(words(marks(idle(waiting: 1), online: false)), "Offline: 1 change goes to iCloud when you are back online")
        XCTAssertEqual(words(marks(idle(), online: false)), "Offline: nothing is waiting to go to iCloud")
        XCTAssertEqual(look(marks(idle(), online: false)), struckGrey)
        XCTAssertEqual(words(marks(idle(firstFetchDone: false), online: false)),
                       "Offline: HITList checks with iCloud when you are back online")
        XCTAssertFalse(marks(idle(waiting: 3), online: false).isHealthyForStrike)
    }

    func testNoSendingWordsAnywhere() {
        let statuses: [SyncStatus] = [SyncStatus(state: .sending, waiting: 0, firstFetchDone: true),
                                      SyncStatus(state: .sending, waiting: 5, firstFetchDone: true),
                                      SyncStatus(state: .fetching, waiting: 0, firstFetchDone: false)]
        for status in statuses {
            XCTAssertFalse(words(marks(status)).contains("Sending"), "retired: \"Sending N changes to iCloud…\"")
        }
    }

    // MARK: Before the first fetch

    func testBeforeTheFirstFetchItIsChecking() {
        for status in [SyncStatus(state: .fetching, waiting: 0, firstFetchDone: false),
                       SyncStatus(state: .idle, waiting: 2, firstFetchDone: false),
                       SyncStatus(state: .starting), SyncStatus(state: .off)] {
            XCTAssertEqual(words(marks(status)), "Checking with iCloud…", "\(status)")
            XCTAssertEqual(look(marks(status)), hollow)
        }
        XCTAssertEqual(words(marks(nil)), "Checking with iCloud…", "the engine has said nothing yet")
    }

    // MARK: Holds

    func testHoldsThePersonMustActOnAreRedAndHollow() {
        let cases: [(SyncHold, Int, String)] = [
            (.zonePurged, 0, "HITList's data was removed from iCloud in Settings."),
            (.needsUpdate, 0, "Update HITList to sync: iCloud holds data from a newer version."),
            (.storageFull, 12, "iCloud is full: 12 changes are waiting."),
            (.storageFull, 1, "iCloud is full: 1 change is waiting."),
            (.iCloudNotReady, 3, "iCloud isn't ready for this version of HITList yet: 3 changes are waiting."),
            (.iCloudNotReady, 0, "iCloud isn't ready for this version of HITList yet."),
            (.failed("this device's sync records could not be read"), 0,
             "Sync stopped: this device's sync records could not be read"),
        ]
        for (hold, waiting, expected) in cases {
            let state = marks(held(hold, waiting: waiting))
            XCTAssertEqual(words(state), expected)
            XCTAssertEqual(look(state), hollowRed, "\(hold)")
            XCTAssertTrue(state.showsTrouble)
            XCTAssertTrue(SyncEngineWords.needsYou(hold))
        }
    }

    func testSignedOutIsTodaysSignedOutState() {
        XCTAssertEqual(marks(held(.noAccount)), .notSignedIn)
        XCTAssertEqual(marks(idle(), account: .noAccount), .notSignedIn, "iCloud's own answer first, as on the mirror")
        XCTAssertEqual(marks(idle(), account: .restricted), .restricted)
        XCTAssertEqual(look(marks(held(.noAccount))), struckRed)
        XCTAssertFalse(SyncEngineWords.needsYou(.noAccount))
    }

    func testDuplicatesAreTidyingUpNotRed() {
        let keys = [SyncKey(type: "TaskItem", name: "a"), SyncKey(type: "TaskItem", name: "b")]
        let state = marks(held(.duplicates(keys)))
        XCTAssertEqual(words(state), "Tidying up 2 items saved twice on this device")
        XCTAssertEqual(look(state), hollow)
        XCTAssertFalse(SyncEngineWords.needsYou(.duplicates(keys)))
    }

    func testAHoldOutranksWaitingAndErrors() {
        let status = SyncStatus(state: .held(.zonePurged), waiting: 4, firstFetchDone: true, lastError: "boom")
        XCTAssertEqual(words(marks(status)), "HITList's data was removed from iCloud in Settings.")
    }

    // MARK: A sync that stopped early

    func testAnErrorIsRetryingNeverRedInTheFirstMinute() {
        let status = idle(lastError: "iCloud is busy, will retry")
        XCTAssertEqual(marks(status, errorSince: nil), .retrying(since: now))
        XCTAssertEqual(marks(status, errorSince: ago(59)), .retrying(since: ago(59)))
        XCTAssertEqual(look(marks(status, errorSince: ago(59))), hollow)
        XCTAssertEqual(words(marks(status, errorSince: ago(59))), SyncState.retryingWords)
        XCTAssertEqual(marks(status, errorSince: ago(SyncEngineMarks.errorWordsAfter - 1)),
                       .retrying(since: ago(SyncEngineMarks.errorWordsAfter - 1)))
        // After today's two minutes, its own words.
        let late = marks(status, errorSince: ago(SyncEngineMarks.errorWordsAfter))
        XCTAssertEqual(late, .error("iCloud is busy, will retry", ago(SyncEngineMarks.errorWordsAfter)))
        XCTAssertEqual(words(late), "Sync paused: iCloud is busy, will retry")
        XCTAssertGreaterThanOrEqual(SyncEngineMarks.errorWordsAfter, 60, "never red in the first minute")
    }

    func testOfflineOutranksAnError() {
        XCTAssertEqual(words(marks(idle(waiting: 2, lastError: "network unavailable"), online: false)),
                       "Offline: 2 changes go to iCloud when you are back online")
    }

    // MARK: Refused for good

    func testARefusalIsNotASyncThatKeepsTrying() {
        let keys = [SyncKey(type: "TaskItem", name: "A"), SyncKey(type: "TaskItem", name: "B")]
        // Core keeps a refusal's words apart from `lastError` (`SyncStatus.refusal`).
        let status = idle(refused: keys, refusal: "TaskItem/A: too large")
        XCTAssertNil(SyncEngineMarks.syncError(status), "a refusal is not an error that keeps trying")
        XCTAssertEqual(words(marks(status, errorSince: ago(600))), "2 items couldn't go to iCloud; Settings → \(SyncWords.settingsPage) names them")
        XCTAssertEqual(look(marks(status)), hollow)
        // Another error while items are refused is still an error.
        let both = idle(lastError: "network unavailable", refused: keys, refusal: "TaskItem/A: too large")
        XCTAssertEqual(SyncEngineMarks.syncError(both), "network unavailable")
        XCTAssertEqual(words(marks(idle(refused: [keys[0]], refusal: "TaskItem/A: too large"))),
                       "1 item couldn't go to iCloud; Settings → \(SyncWords.settingsPage) names it")
    }

    // MARK: Every demo state

    func testEveryDemoStateHasItsStatusAndWords() {
        let refused = [SyncKey(type: "TaskItem", name: UUID().uuidString), SyncKey(type: "TaskItem", name: UUID().uuidString)]
        let expected: [String: String] = [
            "synced": "Synced just now",
            "waiting3": "3 changes waiting to go to iCloud",
            "checking": "Checking with iCloud…",
            "purged": "HITList's data was removed from iCloud in Settings.",
            "update": "Update HITList to sync: iCloud holds data from a newer version.",
            "full12": "iCloud is full: 12 changes are waiting.",
            "failed": "Sync stopped: this device's sync records could not be read",
            "refused2": "2 items couldn't go to iCloud; Settings → \(SyncWords.settingsPage) names them",
            "signedout": "Not signed in to iCloud",
        ]
        XCTAssertEqual(Set(expected.keys), Set(SyncEngineDemo.names))
        for name in SyncEngineDemo.names {
            let status = SyncEngineDemo.status(name, now: now, refused: refused)
            XCTAssertNotNil(status, name)
            XCTAssertEqual(words(marks(status, account: nil)), expected[name], name)
        }
        XCTAssertNil(SyncEngineDemo.status("nonsense", now: now, refused: refused))
    }

    // MARK: Settings' words

    func testSettingsRowSubtitleWarnsOnlyForHoldsThatNeedThePerson() {
        let red = SettingsPageRow.subtitle(for: .iCloud, sync: marks(held(.zonePurged)), stuck: false)
        XCTAssertEqual(red.text, "HITList's data was removed from iCloud in Settings.")
        XCTAssertTrue(red.isWarning)
        let waiting = SettingsPageRow.subtitle(for: .iCloud, sync: marks(idle(waiting: 3)), stuck: false)
        XCTAssertEqual(waiting.text, SettingsPage.iCloud.summary)
        XCTAssertFalse(waiting.isWarning)
    }

    /// Brief 165: the sign-out's one sentence, the hold's own words and its group's alike.
    func testASignOutSaysTheTasksAreOnThisDeviceOnlyUntilTheSignIn() {
        let words = "Not signed in to iCloud: your tasks are on this device only until you sign in."
        XCTAssertEqual(SyncHold.noAccount.words, words)
        XCTAssertEqual(SyncEngineWords.holdNote(.noAccount), words)
        XCTAssertEqual(SyncEngineWords.holdNote(.noAccount, waiting: 3), words)
    }

    func testEveryHoldButtonSaysWhatItDoes() {
        XCTAssertTrue(SyncEngineWords.removeSubtitle.contains("backup"))
        XCTAssertFalse(SyncEngineWords.sendAgainSubtitle.isEmpty)
        for hold: SyncHold in [.zonePurged, .needsUpdate, .storageFull, .iCloudNotReady, .failed("x"), .duplicates([])] {
            XCTAssertFalse(SyncEngineWords.holdNote(hold).isEmpty, "\(hold)")
            XCTAssertFalse(SyncEngineWords.holdTitle(hold).isEmpty)
        }
        // Brief 160: iCloud not ready for this build reads as the brief words it, and its button tries again.
        let line = SyncWords.engineHold(.iCloudNotReady, waiting: 0) + " " + SyncEngineWords.holdNote(.iCloudNotReady, waiting: 2)
        XCTAssertTrue(line.hasPrefix("iCloud isn't ready for this version of HITList yet. Nothing is lost: what is waiting stays waiting."), line)
        XCTAssertEqual(SyncEngineWords.tryAgainSubtitle(.iCloudNotReady), "Sends what is waiting, if iCloud is ready now")
        // Brief 160 (147 F10): what a person reads names no engine, ledger or memory and carries no Swift error.
        XCTAssertEqual(SyncEngineWords.error(SyncCoreError.notStarted), "sync hasn't started yet; try again in a moment.")
        let backup = SyncEngineHost.BackupFailed(words: "The file “x” couldn’t be saved (NSCocoaErrorDomain 640)")
        XCTAssertEqual(SyncEngineWords.error(backup), "No backup could be written, so nothing was removed from this device.")
        for words in SyncFailureWords.all + [SyncEngine.notRunningWords(inMemory: true), SyncEngine.notRunningWords(inMemory: false)] {
            XCTAssertEqual(SyncWords.engineHold(.failed(words), waiting: 0), "Sync stopped: \(words)")
            for banned in ["engine", "ledger", "memory", "error", "("] {
                XCTAssertFalse(words.lowercased().contains(banned), "\(words)")
            }
        }
        XCTAssertEqual(SyncEngineWords.error(SyncCoreError.noBackup), "no backup could be written, so nothing was removed.")
        XCTAssertEqual(SyncEngineStatusRows.waitingValue(idle(waiting: 3)), "3 changes")
        XCTAssertEqual(SyncEngineStatusRows.waitingValue(idle(waiting: 1)), "1 change")
        XCTAssertEqual(SyncEngineStatusRows.waitingValue(nil), "Nothing")
    }

    func testTheSwitchNamesBothEngines() {
        XCTAssertEqual(SyncEngineWords.engineName(.mirror), "The earlier sync")
        XCTAssertEqual(SyncEngineWords.engineName(.own), "The new sync")
        XCTAssertEqual(SyncEngineWords.moveTitle(to: .own), "Move to the new sync")
        XCTAssertEqual(SyncEngineWords.moveTitle(to: .mirror), "Move back to the earlier sync")
    }

    func testTheEngineAccountIgnoresTheMirrorsSwitch() {
        XCTAssertEqual(SyncStatusLine.engineAccount(status: .available, notice: nil, sync: .synced(now), everSignedIn: true),
                       .signedIn)
        XCTAssertEqual(SyncStatusLine.engineAccount(status: .available, notice: nil, sync: .notSignedIn, everSignedIn: true),
                       .signedOut, "the engine's own sign-out hold")
    }

    // MARK: The monitor follows the board on the engine, and only there

    func testTheMonitorShowsTheBoardOnTheEngineAndTheMirrorOtherwise() throws {
        let board = SyncEngineBoard.shared
        let monitor = CloudSyncMonitor.shared
        // iCloud's own "signed out" comes first on the engine as on the mirror: a runner without an account can't show
        // the engine's words.
        if monitor.rawAccountStatus == .noAccount || monitor.rawAccountStatus == .restricted {
            throw XCTSkip("this Mac has no usable iCloud account")
        }
        XCTAssertEqual(board.engine, .mirror, "hosted tests run on the mirror")
        let before = monitor.state
        XCTAssertFalse(monitor.isOnEngine)
        defer { board.show(nil, engine: .mirror) }

        board.show(SyncStatus(state: .idle, waiting: 3, firstFetchDone: true))
        XCTAssertTrue(monitor.isOnEngine)
        XCTAssertEqual(monitor.statusWords(), "3 changes waiting to go to iCloud")
        XCTAssertEqual(monitor.rawState, monitor.state, "before a sync has ended in the session the marks are the engine's own")

        // A sync that ended in this session (one that ended before it began is not this session's: `SyncEngineSteadiness`).
        let fetched = Date()
        board.show(SyncStatus(state: .idle, waiting: 0, firstFetchDone: true, lastFetchEnded: fetched))
        XCTAssertEqual(monitor.state, .synced(fetched))
        XCTAssertEqual(monitor.lastSyncedAt, fetched)

        board.show(SyncStatus(state: .held(.storageFull), waiting: 7, firstFetchDone: true))
        XCTAssertEqual(monitor.statusWords(), "iCloud is full: 7 changes are waiting.")

        board.show(nil, engine: .mirror)
        XCTAssertFalse(monitor.isOnEngine)
        XCTAssertEqual(monitor.state, before, "back on the mirror, the mirror's state as it was")
    }

    /// Round 35 (George: "if HITList is currently syncing regularly and has been during that session, there's no need
    /// for the bolt to change"): through the monitor itself, a change waiting to go and the fetch after it leave the
    /// bolt filled once a sync has ended in the session; what the engine says is still there to read (`rawState`),
    /// and a hold shows at once.
    func testASessionsOrdinaryWorkLeavesTheMonitorsBoltFilled() throws {
        let board = SyncEngineBoard.shared
        let monitor = CloudSyncMonitor.shared
        if monitor.rawAccountStatus == .noAccount || monitor.rawAccountStatus == .restricted {
            throw XCTSkip("this Mac has no usable iCloud account")
        }
        defer {
            board.show(nil, engine: .mirror)
            monitor.boardChangedForTests()
        }
        /// The board says `status`, and the monitor hears it as the app's own observation tells it.
        func show(_ status: SyncStatus) {
            board.show(status)
            monitor.boardChangedForTests()
        }

        let fetched = Date()
        show(SyncStatus(state: .idle, waiting: 0, firstFetchDone: true, lastFetchEnded: fetched))
        XCTAssertEqual(monitor.state, .synced(fetched), "the session's first sync: filled")

        // The marks are read the moment the board changes, before the monitor has heard of it: nothing shows then
        // either.
        board.show(SyncStatus(state: .idle, waiting: 1, firstFetchDone: true, lastFetchEnded: fetched))
        XCTAssertEqual(monitor.state, .synced(fetched), "a task added: nothing shows, at the very moment")
        XCTAssertEqual(monitor.rawState.summary(), "1 change waiting to go to iCloud", "what the engine says is still there to read")
        monitor.boardChangedForTests()
        XCTAssertEqual(monitor.state, .synced(fetched))
        XCTAssertEqual(monitor.statusWords(), "Synced just now")

        show(SyncStatus(state: .sending, waiting: 1, firstFetchDone: true, lastFetchEnded: fetched))
        show(SyncStatus(state: .fetching, waiting: 0, firstFetchDone: true, lastFetchEnded: fetched))
        XCTAssertEqual(monitor.state, .synced(fetched), "the send and the fetch after it")
        let sent = Date()
        show(SyncStatus(state: .idle, waiting: 0, firstFetchDone: true, lastFetchEnded: fetched, lastSendEnded: sent))
        XCTAssertEqual(monitor.state, .synced(sent), "and the bolt names the newer sync")

        show(SyncStatus(state: .held(.storageFull), waiting: 7, firstFetchDone: true))
        XCTAssertEqual(monitor.statusWords(), "iCloud is full: 7 changes are waiting.", "what a person must see shows at once")
    }
}
