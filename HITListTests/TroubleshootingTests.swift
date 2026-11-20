import XCTest
import CloudKit
import HITListCore
@testable import HITList

/// Round 35, brief 174: Settings → iCloud & data for a person who never heard how HITList syncs. The rows for
/// troubleshooting show only where revealed (or a Debug side store); the words after a move made by itself stay
/// fourteen days; nothing a friend can read on the page says CloudKit, environment, Production, Development, engine,
/// zone, mirror, ledger or transport.
@MainActor
final class TroubleshootingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "troubleshooting-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: What shows

    func testTheRowsShowOnlyWhereRevealedOrOnADebugSideStore() {
        XCTAssertFalse(Troubleshooting.isShown(revealed: false, isDebugSideStore: false), "a friend's device, either sync")
        XCTAssertTrue(Troubleshooting.isShown(revealed: true, isDebugSideStore: false))
        XCTAssertTrue(Troubleshooting.isShown(revealed: false, isDebugSideStore: true), "UI tests depend on it")
    }

    /// About's row hides them again with one press and asks nothing; seven taps bring them back, under the key George's
    /// Mac already holds.
    func testRevealAndHideUseTheSwitchKey() {
        XCTAssertEqual(SyncEngineSwitch.revealedKey, "syncEngine.switchRevealed", "George's Mac is revealed under this key")
        var taps = SevenTaps()
        let start = Date(timeIntervalSince1970: 1_000)
        var revealed = false
        for n in 0..<7 where taps.tap(at: start.addingTimeInterval(Double(n) * 1.5)) { revealed = true }
        XCTAssertTrue(revealed, "seven taps, each within two seconds")
        Troubleshooting.reveal(defaults: defaults)
        XCTAssertTrue(SyncEngineSwitch.isSwitchRevealed(defaults: defaults))
        Troubleshooting.hide(defaults: defaults)
        XCTAssertFalse(SyncEngineSwitch.isSwitchRevealed(defaults: defaults))
        Troubleshooting.reveal(defaults: defaults)
        XCTAssertTrue(SyncEngineSwitch.isSwitchRevealed(defaults: defaults), "and back")
    }

    func testTheGroupSaysWhatItIs() {
        XCTAssertEqual(Troubleshooting.title, "For troubleshooting")
        XCTAssertEqual(Troubleshooting.footer, "Shown because this device was set to show them: Settings → About.")
        XCTAssertEqual("\(Troubleshooting.aboutTitle): \(Troubleshooting.aboutValue)", "Troubleshooting rows: Showing")
    }

    /// On the new sync a friend sees what waits only while something does.
    func testWaitingShowsOnlyWhileSomethingWaits() {
        XCTAssertFalse(SyncEngineStatusRows.showsWaiting(nil))
        XCTAssertFalse(SyncEngineStatusRows.showsWaiting(SyncStatus(state: .idle, waiting: 0, firstFetchDone: true)))
        XCTAssertTrue(SyncEngineStatusRows.showsWaiting(SyncStatus(state: .idle, waiting: 3, firstFetchDone: true)))
    }

    // MARK: Fourteen days

    func testTheWordsAfterAMoveByItselfStayFourteenDays() {
        let moved = Date(timeIntervalSince1970: 2_000_000)
        let day: TimeInterval = 86_400
        XCTAssertFalse(AutoMoveNote.isShown(movedByItself: false, movedAt: nil, firstShown: nil, now: moved))
        XCTAssertTrue(AutoMoveNote.isShown(movedByItself: true, movedAt: moved, firstShown: nil, now: moved))
        XCTAssertTrue(AutoMoveNote.isShown(movedByItself: true, movedAt: moved, firstShown: nil, now: moved + 13.9 * day))
        XCTAssertFalse(AutoMoveNote.isShown(movedByItself: true, movedAt: moved, firstShown: nil, now: moved + 14 * day))
        XCTAssertFalse(AutoMoveNote.isShown(movedByItself: true, movedAt: moved, firstShown: moved + 10 * day,
                                            now: moved + 15 * day), "the move's own date wins")
    }

    func testTheMovesDateIsReadAndOtherwiseTheFirstShowingIsStored() {
        let store = "HITList-t174.store"
        let now = Date(timeIntervalSince1970: 3_000_000)
        XCTAssertFalse(AutoMoveNote.shows(store: store, defaults: defaults, now: now), "never moved by itself")
        XCTAssertNil(defaults.object(forKey: AutoMoveNote.firstShownKey(store)), "nothing stored for a device never moved")

        // The move stores its date (`SyncEngineAutoMove.movedAtKey`): counted from there.
        defaults.set(now, forKey: SyncEngineAutoMove.movedAtKey(store))
        XCTAssertTrue(AutoMoveNote.shows(store: store, defaults: defaults, now: now + 86_400))
        XCTAssertFalse(AutoMoveNote.shows(store: store, defaults: defaults, now: now + 15 * 86_400))
        XCTAssertNil(defaults.object(forKey: AutoMoveNote.firstShownKey(store)))

        // A move whose key holds no date: from the first showing, stored once.
        defaults.set(true, forKey: SyncEngineAutoMove.movedAtKey(store))
        XCTAssertTrue(AutoMoveNote.shows(store: store, defaults: defaults, now: now))
        XCTAssertEqual(defaults.object(forKey: AutoMoveNote.firstShownKey(store)) as? Date, now)
        XCTAssertTrue(AutoMoveNote.shows(store: store, defaults: defaults, now: now + 13 * 86_400))
        XCTAssertEqual(defaults.object(forKey: AutoMoveNote.firstShownKey(store)) as? Date, now, "stored once")
        XCTAssertFalse(AutoMoveNote.shows(store: store, defaults: defaults, now: now + 14 * 86_400))
    }

    // MARK: Words

    static let forbidden = ["cloudkit", "environment", "production", "development", "engine", "zone", "mirror",
                            "ledger", "transport"]

    /// Every string a friend can reach on iCloud & data (and the Mac's iCloud section), in every state these tests
    /// can name: none says a developer's word. (The UI test `TroubleshootingRowsUITests` reads the page itself.)
    func testNothingAFriendReadsSaysADevelopersWord() {
        let now = Date()
        var words: [String] = [
            ICloudSyncGroup.title, ICloudSyncGroup.footer, ICloudCheckGroup.title,
            SyncWords.differenceNote, SyncWords.differenceWaitingNote, SyncWords.engineChecking,
            SyncEngineStatusRows.syncNowSubtitle, SyncEngineWords.refusedNote, SyncEngineWords.refusedTitle(1),
            SyncEngineWords.refusedTitle(2), SyncWords.engineRefused(1), SyncWords.engineRefused(3),
            SyncEngineWords.removeSubtitle, SyncEngineWords.sendAgainSubtitle, SyncEngineWords.removeMessage,
            SyncEngineWords.reopenMessage, SyncEngineWords.stillHeld, SyncEngineWords.checkDifferenceNote,
            SyncEngineCheckRows.subtitle, ICloudAuditRows.subtitle, SyncAuditWords.onlyHereNote,
            SyncAuditWords.onlyThereNote, SyncAuditWords.onlyThereWaitNote,
            SendSyncLogRow.title, SendSyncLogRow.subtitle, ResetLocalCacheGroup.subtitle, AccountCopy.deleteAll,
            BackupsGroup.footer, ExportImportGroup.todoistFooter,
            SyncStuckRow.detail(for: .busy(since: now)), SyncStuckRow.detail(for: .quiet(since: now, saves: 3)), SyncStuckRow.reopen,
            SyncEngineAutoMove.movingLine, SyncEngineAutoMove.otherDevicesNote,
            SyncEngineAutoMove.line(zone: .found, moved: false) ?? "",
            SyncEngineWords.moveTitle(to: .own), SyncEngineWords.waitingNote(.own),
            SettingsPage.iCloud.summary, SettingsPageRow.stuckWords,
        ]
        for n in [0, 1, 4] {
            words += [SyncWords.engineWaiting(max(n, 1)), SyncWords.engineOffline(waiting: n, firstFetchDone: true),
                      SyncWords.engineOffline(waiting: n, firstFetchDone: false)]
        }
        let holds: [SyncHold] = [.noAccount, .needsUpdate, .zonePurged, .storageFull, .iCloudNotReady,
                                 .failed("this device's sync records could not be read"),
                                 .duplicates([SyncKey(type: "TaskItem", name: "a")])]
        for hold in holds {
            words += [SyncWords.engineHold(hold, waiting: 0), SyncWords.engineHold(hold, waiting: 2),
                      SyncEngineWords.holdTitle(hold), SyncEngineWords.holdNote(hold, waiting: 0),
                      SyncEngineWords.holdNote(hold, waiting: 2), SyncEngineWords.tryAgainSubtitle(hold)]
        }
        let states: [SyncState] = [.notSignedIn, .restricted, .offline, .syncing, .synced(now), .retrying(since: now),
                                   .error("iCloud storage is full", now), .differs("1 task on this device isn't in iCloud", stuck: true)]
        for state in states {
            words += [state.summary(now: now), SyncWords.status(state: state, waiting: true, lastSynced: now, now: now)]
        }
        for account in [CKAccountStatusLike.available, .noAccount] {
            for reachable in [true, false] {
                for zone in [true, false] {
                    for dev in [true, false] {
                        words.append(ICloudCheck(account: account.status, reachable: reachable, zoneExists: zone,
                                                 failure: nil, duration: 0.5, isDevelopmentEnvironment: dev).summary)
                    }
                }
            }
        }
        let one = SyncComparison.Difference(kind: .onlyHere, entity: "TaskItem", id: UUID())
        words += [SyncAuditModel.sendResult(sent: [one], missing: [], exported: true),
                  SyncAuditModel.sendResult(sent: [one], missing: [one], exported: true),
                  SyncAuditModel.sendResult(sent: [one], missing: [one], exported: false)]
        for text in words {
            let lower = text.lowercased()
            for word in Self.forbidden {
                XCTAssertFalse(lower.contains(word), "“\(text)” says \(word)")
            }
        }
    }

    /// The question before a move and the rows behind the gesture may name things; they are George's. Their two
    /// rewordings of 2026-11-20 hold.
    func testTheRevealedGroupsTwoRewordings() {
        XCTAssertEqual(SyncEngineWords.everyoneTitle, "Friends' devices")
        XCTAssertEqual(SyncEngineWords.everyoneValue(.notYet), "Not moving yet: you have not given the word")
        XCTAssertEqual(SyncEngineWords.everyoneValue(.go), "Moving by themselves")
        XCTAssertFalse(SyncEngineWords.notComparedWarning.contains("wait for the bolt"))
        XCTAssertTrue(SyncEngineWords.notComparedWarning.hasPrefix("HITList has not compared this device with iCloud since it was opened"))
    }
}

/// `CKAccountStatus` without importing CloudKit's names into every line above.
private enum CKAccountStatusLike {
    case available, noAccount
    var status: CKAccountStatus { self == .available ? .available : .noAccount }
}
