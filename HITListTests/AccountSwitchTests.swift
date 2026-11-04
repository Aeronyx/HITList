import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 42, item 2: one device, two Apple accounts in turn. Two made-up accounts ("_alice", "_bob"); no
/// test touches the device's real notifications, backups or app-group defaults (the macOS test host shares
/// the TestFlight app's bundle ID, and with it its pending reminders).
@MainActor
final class AccountSwitchTests: XCTestCase {
    private let fm = FileManager.default
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let alice = AccountIdentity.key(recordName: "_alice")
    private let bob = AccountIdentity.key(recordName: "_bob")

    override func setUp() async throws {
        suiteName = "HITListTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func tempDir() throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "HITListTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: Account identity

    func testAccountKeyIsAStableSaltedHashThatNeverContainsTheRecordName() {
        let name = "_8f2a1c0d9e7b6a5f4e3d2c1b0a998877"
        let key = AccountIdentity.key(recordName: name)
        XCTAssertEqual(key, AccountIdentity.key(recordName: name), "the same account always gives the same key")
        XCTAssertTrue(key.hasPrefix("acct1:"))
        XCTAssertEqual(key.count, "acct1:".count + 32)
        XCTAssertFalse(key.contains(name.dropFirst()), "one-way: the record name isn't in it")
        XCTAssertNotEqual(alice, bob)
    }

    func testTheWatchStoresOnlyTheHash() {
        let watch = AccountWatch(defaults: defaults, storeName: ModelContainerFactory.mainStoreName)
        _ = watch.identify(userRecordName: "_alice")
        let stored = defaults.string(forKey: AccountWatch.recordNameKey)
        XCTAssertEqual(stored, alice)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { "\($0)".contains("_alice") },
                       "no raw record name anywhere in defaults")
    }

    func testARawRecordNameFromAnOlderBuildStillCountsAsTheSameAccount() {
        defaults.set("_alice", forKey: AccountWatch.recordNameKey)  // 0.5.0 stored the raw name
        let watch = AccountWatch(defaults: defaults, storeName: ModelContainerFactory.mainStoreName)
        XCTAssertFalse(watch.identify(userRecordName: "_alice").isSwitch, "upgrading isn't a switch")
        XCTAssertEqual(defaults.string(forKey: AccountWatch.recordNameKey), alice, "rewritten as the hash")
        let next = watch.identify(userRecordName: "_bob")
        XCTAssertTrue(next.isSwitch)
        XCTAssertEqual(next.previous, alice)
        XCTAssertEqual(next.account, bob)
    }

    func testEachStoreRemembersItsOwnAccount() {
        let real = AccountWatch(defaults: defaults, storeName: ModelContainerFactory.mainStoreName)
        let debug = AccountWatch(defaults: defaults, storeName: "HITList-Development.store")
        _ = real.identify(userRecordName: "_alice")
        _ = debug.identify(userRecordName: "_alice")
        XCTAssertTrue(debug.identify(userRecordName: "_bob").isSwitch, "the Debug build notices first…")
        XCTAssertTrue(real.identify(userRecordName: "_bob").isSwitch, "…and the TestFlight build still notices too")
        XCTAssertEqual(real.accountKeyName, AccountWatch.recordNameKey, "the real store keeps 0.5.0's key")
    }

    func testFirstAccountEverSeenIsNotASwitch() {
        let watch = AccountWatch(defaults: defaults)
        let first = watch.identify(userRecordName: "_alice")
        XCTAssertFalse(first.isSwitch)
        XCTAssertNil(first.previous)
        XCTAssertEqual(watch.update(userRecordName: "_alice", shown: nil), nil)
        XCTAssertEqual(watch.update(userRecordName: "_bob", shown: nil), .switched)
    }

    // MARK: The switch

    private final class Calls {
        var draft = 0, reminders = 0, backups: [(String, String)] = [], caches = 0
        var lines: [(String, SyncLogEntry.Level, [String: String])] = []
    }

    private func cleanup(_ calls: Calls, hadDraft: Bool = true) -> AccountSwitch.Cleanup {
        AccountSwitch.Cleanup(
            clearDraft: { calls.draft += 1; return hadDraft },
            clearReminders: { calls.reminders += 1 },
            setAsideBackups: { calls.backups.append(($0, $1)); return LocalBackup.SetAside(movedAside: 3, restored: 1) },
            forgetCaches: { calls.caches += 1 })
    }

    func testASwitchClearsDraftRemindersBackupsAndCachesAndSaysSoWithoutIDs() async {
        let calls = Calls()
        let center = NotificationCenter()
        var posted = 0
        let observer = center.addObserver(forName: .accountDidSwitch, object: nil, queue: nil) { _ in posted += 1 }
        defer { center.removeObserver(observer) }

        let report = await AccountSwitch.handleSwitch(from: alice, to: bob, ownsDeviceState: true, cleanup: cleanup(calls),
                                                      log: { calls.lines.append(($0, $1, $2)) }, center: center)

        XCTAssertEqual(calls.draft, 1)
        XCTAssertEqual(calls.reminders, 1)
        XCTAssertEqual(calls.caches, 1)
        XCTAssertEqual(calls.backups.map(\.0), [alice])
        XCTAssertEqual(calls.backups.map(\.1), [bob])
        XCTAssertEqual(report.backups, LocalBackup.SetAside(movedAside: 3, restored: 1))
        XCTAssertEqual(posted, 1, "views holding the other account's card or toast are told")
        XCTAssertEqual(calls.lines.count, 1)
        let line = calls.lines[0]
        XCTAssertEqual(line.0, "Account changed: local drafts and reminders cleared")
        XCTAssertEqual(line.1, .notice)
        XCTAssertEqual(line.2, ["draft": "cleared", "reminders": "cleared", "backups": "3 set aside, 1 restored"])
        let text = ([line.0] + line.2.keys + line.2.values).joined(separator: " ")
        XCTAssertFalse(text.contains("acct1:") || text.contains("_alice") || text.contains("_bob"), "never an id")
    }

    func testASideStoreClearsOnlyItsOwnDraft() async {
        let calls = Calls()
        let report = await AccountSwitch.handleSwitch(from: alice, to: bob, ownsDeviceState: false, cleanup: cleanup(calls, hadDraft: false),
                                                      log: { calls.lines.append(($0, $1, $2)) }, center: NotificationCenter())
        XCTAssertEqual(calls.draft, 1)
        XCTAssertEqual(calls.reminders, 0, "a Debug build's run never touches the TestFlight app's reminders")
        XCTAssertTrue(calls.backups.isEmpty, "nor its backups")
        XCTAssertFalse(report.ownsDeviceState)
        XCTAssertEqual(calls.lines.first?.0, "Account changed: local drafts cleared")
        XCTAssertEqual(calls.lines.first?.2["draft"], "none")
    }

    func testSignOutClearsRemindersOnly() async {
        let calls = Calls()
        await AccountSwitch.handleSignOut(ownsDeviceState: true, cleanup: cleanup(calls), log: { calls.lines.append(($0, $1, $2)) })
        XCTAssertEqual(calls.reminders, 1)
        XCTAssertEqual(calls.draft, 0, "the same person usually signs back in: the card stays")
        XCTAssertTrue(calls.backups.isEmpty)
        XCTAssertEqual(calls.lines.map(\.0), ["Signed out of iCloud: reminders and badge cleared"])

        let other = Calls()
        await AccountSwitch.handleSignOut(ownsDeviceState: false, cleanup: cleanup(other), log: { other.lines.append(($0, $1, $2)) })
        XCTAssertEqual(other.reminders, 0)
        XCTAssertTrue(other.lines.isEmpty)
    }

    // MARK: Drafts

    func testAlicesStickyDraftIsGoneForBob() {
        let store = ModelContainerFactory.mainStoreName
        let card = UUID()
        QuickAddDraftStore.save(QuickAddDraft(context: .inbox, text: "Alice's surprise party"), card: card, to: defaults, storeName: store)
        XCTAssertNotNil(QuickAddDraftStore.draft(for: card, from: defaults, storeName: store))
        XCTAssertTrue(AccountSwitch.clearDraft(defaults: defaults, storeName: store))
        XCTAssertNil(QuickAddDraftStore.load(from: defaults, storeName: store), "Bob's next launch doesn't reopen it")
        XCTAssertFalse(AccountSwitch.clearDraft(defaults: defaults, storeName: store), "nothing left")
    }

    // MARK: Reminders

    private final class FakeCenter: NotificationScheduler.Clearing {
        var pendingRemoved = 0, deliveredRemoved = 0
        var badge: Int?
        func removeAllPendingNotificationRequests() { pendingRemoved += 1 }
        func removeAllDeliveredNotifications() { deliveredRemoved += 1 }
        func setBadgeCount(_ newBadgeCount: Int) async throws { badge = newBadgeCount }
    }

    func testRemindersBadgeAndLedgerAreCleared() async {
        defaults.set(["\(UUID().uuidString)@800000000"], forKey: NotificationScheduler.ledgerKey)
        let center = FakeCenter()
        await NotificationScheduler.clearForAccountChange(center: center, defaults: defaults)
        XCTAssertEqual(center.pendingRemoved, 1, "Alice's reminders and morning summary")
        XCTAssertEqual(center.deliveredRemoved, 1, "and the ones already in Notification Center")
        XCTAssertEqual(center.badge, 0)
        XCTAssertNil(defaults.object(forKey: NotificationScheduler.ledgerKey), "her task ids are forgotten")
    }

    // MARK: Backups

    private func backup(_ name: String, in dir: URL, _ text: String = "{}") throws {
        try Data(text.utf8).write(to: dir.appending(path: name))
    }

    func testBackupsFollowTheirAccountAndNothingIsDeleted() throws {
        let documents = try tempDir(), root = try tempDir()
        try backup("HITList-2026-11-01.json", in: documents, "alice 1")
        try backup("HITList-2026-11-02.json", in: documents, "alice 2")
        try backup("notes.txt", in: documents)
        defaults.set(Date(), forKey: LocalBackup.lastBackupKey)

        // Alice → Bob: Alice's backups leave the visible folder.
        let toBob = LocalBackup.setAside(previousAccount: alice, currentAccount: bob, directory: documents, root: root, defaults: defaults)
        XCTAssertEqual(toBob, LocalBackup.SetAside(movedAside: 2, restored: 0))
        XCTAssertTrue(LocalBackup.backups(in: documents).isEmpty, "Bob can't open Alice's backups in Files")
        XCTAssertTrue(fm.fileExists(atPath: documents.appending(path: "notes.txt").path), "other files stay")
        let aliceFolder = LocalBackup.setAsideFolder(for: alice, in: root)
        XCTAssertEqual(LocalBackup.backups(in: aliceFolder).count, 2)
        XCTAssertFalse(aliceFolder.lastPathComponent.contains(":"))
        XCTAssertNil(defaults.object(forKey: LocalBackup.lastBackupKey), "Bob's data gets its own backup soon")

        // Bob backs up, then Alice signs back in: hers return, his are set aside.
        try backup("HITList-2026-11-03.json", in: documents, "bob 1")
        try backup("HITList-2026-11-02.json", in: documents, "bob same day")
        let toAlice = LocalBackup.setAside(previousAccount: bob, currentAccount: alice, directory: documents, root: root, defaults: defaults)
        XCTAssertEqual(toAlice, LocalBackup.SetAside(movedAside: 2, restored: 2))
        let names = LocalBackup.backups(in: documents).map(\.lastPathComponent)
        XCTAssertEqual(names, ["HITList-2026-11-01.json", "HITList-2026-11-02.json"])
        XCTAssertEqual(try String(contentsOf: documents.appending(path: "HITList-2026-11-02.json"), encoding: .utf8), "alice 2")
        XCTAssertEqual(LocalBackup.backups(in: LocalBackup.setAsideFolder(for: bob, in: root)).count, 2)
    }

    func testABackupNeverOverwritesOneOfTheSameName() throws {
        let documents = try tempDir(), root = try tempDir()
        let aliceFolder = LocalBackup.setAsideFolder(for: alice, in: root)
        try fm.createDirectory(at: aliceFolder, withIntermediateDirectories: true)
        try backup("HITList-2026-11-01.json", in: aliceFolder, "alice earlier")
        try backup("HITList-2026-11-01.json", in: documents, "alice today")
        let result = LocalBackup.setAside(previousAccount: alice, currentAccount: bob, directory: documents, root: root, defaults: defaults)
        XCTAssertEqual(result.movedAside, 0, "the name is taken: the file stays where it is")
        XCTAssertEqual(try String(contentsOf: aliceFolder.appending(path: "HITList-2026-11-01.json"), encoding: .utf8), "alice earlier")
        XCTAssertEqual(try String(contentsOf: documents.appending(path: "HITList-2026-11-01.json"), encoding: .utf8), "alice today")
    }
}
