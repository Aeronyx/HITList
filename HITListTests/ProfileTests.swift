import XCTest
import SwiftUI
import SwiftData
import CloudKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import HITList

/// Brief 34: the one profile per iCloud account (`ProfileStore`), its merge after two devices each made
/// one (`Deduplicator`), the picture's downscaling (`ProfileAvatar`), and the account state Settings shows
/// (`AccountState`).
@MainActor
final class ProfileTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var logged: [(message: String, level: SyncLogEntry.Level, fields: [String: String])] = []
    private var now = Date(timeIntervalSinceReferenceDate: 815_000_000)

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
        logged = []
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private var store: ProfileStore {
        ProfileStore(context: context, log: { [weak self] in self?.logged.append(($0, $1, $2)) }, clock: { [unowned self] in now })
    }

    private func dedupe() throws -> DedupeReport {
        try Deduplicator.run(in: context, profileLog: { [weak self] in self?.logged.append(($0, $1, $2)) })
    }

    private func profiles() throws -> [Profile] { try context.fetch(FetchDescriptor<Profile>()) }

    /// A profile as another device would have made it before the two synced.
    @discardableResult
    private func otherDevicesProfile(name: String = "", nameAt: TimeInterval? = nil, picture: Data? = nil,
                                     pictureAt: TimeInterval? = nil, createdAt: TimeInterval) -> Profile {
        let p = Profile()
        p.createdAt = now.addingTimeInterval(createdAt)
        p.displayName = name
        p.nameUpdatedAt = nameAt.map { now.addingTimeInterval($0) }
        p.avatarData = picture
        p.avatarUpdatedAt = pictureAt.map { now.addingTimeInterval($0) }
        p.updatedAt = [p.createdAt, p.nameUpdatedAt, p.avatarUpdatedAt].compactMap { $0 }.max()!
        context.insert(p)
        try? context.save()
        return p
    }

    // MARK: Create, update, delete

    func testNothingIsCreatedUntilSomethingIsSet() throws {
        XCTAssertNil(try store.current())
        XCTAssertEqual(try profiles().count, 0, "reading never creates a record (it would race another device's)")
    }

    func testFetchOrCreateCreatesOnce() throws {
        let first = try store.fetchOrCreate()
        let second = try store.fetchOrCreate()
        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(try profiles().count, 1)
        XCTAssertEqual(logged.filter { $0.message == "Profile created" }.count, 1, "the creation is logged once")
    }

    func testSettingTheNameTrimsSavesStampsAndLogsWithoutTheName() throws {
        try store.setName("  George Trammell \n")
        let profile = try XCTUnwrap(try store.current())
        XCTAssertEqual(profile.displayName, "George Trammell")
        XCTAssertEqual(profile.nameUpdatedAt, now)
        XCTAssertEqual(profile.updatedAt, now)
        XCTAssertFalse(context.hasChanges, "saved")
        let line = try XCTUnwrap(logged.last)
        XCTAssertEqual(line.message, "Profile name set")
        XCTAssertFalse("\(line.message)\(line.fields)".contains("George"), "the sync log never holds the name")
    }

    func testSettingTheSameNameAgainWritesNothing() throws {
        try store.setName("George")
        let stamped = try XCTUnwrap(try store.current()?.nameUpdatedAt)
        now = now.addingTimeInterval(60)
        let lines = logged.count
        try store.setName("George ")
        XCTAssertEqual(try store.current()?.nameUpdatedAt, stamped)
        XCTAssertEqual(logged.count, lines)
    }

    func testANameIsCappedAndClearing() throws {
        try store.setName(String(repeating: "x", count: 200))
        XCTAssertEqual(try store.current()?.displayName.count, ProfileStore.maxNameLength)
        try store.setName("   ")
        XCTAssertEqual(try store.current()?.displayName, "")
        XCTAssertEqual(logged.last?.message, "Profile name cleared")
    }

    func testSettingAPictureDownscalesIt() throws {
        try store.setAvatar(imageData: try Self.png(width: 2000, height: 1500))
        let profile = try XCTUnwrap(try store.current())
        let data = try XCTUnwrap(profile.avatarData)
        XCTAssertLessThanOrEqual(data.count, ProfileAvatar.maxBytes)
        let size = try XCTUnwrap(Self.pixelSize(of: data))
        XCTAssertEqual(max(size.width, size.height), 512)
        XCTAssertEqual(Self.type(of: data), UTType.jpeg.identifier)
        XCTAssertEqual(profile.avatarUpdatedAt, now)
        XCTAssertEqual(logged.last?.message, "Profile picture set")
        XCTAssertNotNil(logged.last?.fields["bytes"])
    }

    func testRemovingThePictureStampsTheRemoval() throws {
        try store.setAvatar(imageData: try Self.png(width: 300, height: 300))
        now = now.addingTimeInterval(10)
        try store.setAvatar(imageData: nil)
        let profile = try XCTUnwrap(try store.current())
        XCTAssertNil(profile.avatarData)
        XCTAssertEqual(profile.avatarUpdatedAt, now)
        XCTAssertEqual(logged.last?.message, "Profile picture removed")
    }

    func testAnUnreadablePictureIsRefusedAndChangesNothing() throws {
        try store.setName("George")
        XCTAssertThrowsError(try store.setAvatar(imageData: Data("not an image".utf8)))
        XCTAssertNil(try store.current()?.avatarData)
        XCTAssertEqual(logged.last?.level, .error)
    }

    func testDeleteRemovesEveryProfileAndLeavesTasksAlone() throws {
        let task = TaskItem(title: "Keep me")
        context.insert(task)
        try store.setName("George")
        otherDevicesProfile(name: "G", nameAt: -5, createdAt: -10)
        XCTAssertEqual(try store.delete(), 2)
        XCTAssertEqual(try profiles().count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Keep me"])
        XCTAssertEqual(logged.last?.message, "Profile deleted")
        XCTAssertEqual(logged.last?.fields["records"], "2")
        XCTAssertEqual(try store.delete(), 0, "nothing left to delete")
    }

    // MARK: Two devices

    func testTwoCreatesConvergeAfterDedupe() throws {
        try store.setName("George")                                    // this device, now
        otherDevicesProfile(name: "", createdAt: -30)                  // the other device, earlier, no name
        XCTAssertEqual(try profiles().count, 2)
        let report = try dedupe()
        XCTAssertEqual(report.profiles, 1)
        let survivors = try profiles()
        XCTAssertEqual(survivors.count, 1)
        XCTAssertEqual(survivors.first?.createdAt, now.addingTimeInterval(-30), "the earliest record survives, like every merge")
        XCTAssertEqual(survivors.first?.displayName, "George", "the newest name wins")
        XCTAssertEqual(survivors.first?.updatedAt, now)
        XCTAssertEqual(logged.last?.message, "Merged duplicate profiles")
        XCTAssertEqual(try dedupe().profiles, 0, "a second pass changes nothing")
    }

    func testTheNewestNameWinsPerField() throws {
        let picture = try ProfileAvatar.prepare(Self.png(width: 64, height: 64))
        otherDevicesProfile(name: "Old name", nameAt: -100, picture: picture, pictureAt: -50, createdAt: -200)
        otherDevicesProfile(name: "New name", nameAt: -10, createdAt: -150)
        try dedupe()
        let survivor = try XCTUnwrap(try profiles().first)
        XCTAssertEqual(survivor.displayName, "New name")
        XCTAssertEqual(survivor.nameUpdatedAt, now.addingTimeInterval(-10))
        XCTAssertEqual(survivor.avatarData, picture, "the picture comes from the other record")
        XCTAssertEqual(survivor.avatarUpdatedAt, now.addingTimeInterval(-50))
    }

    func testPictureSurvivesAMerge() throws {
        let picture = try ProfileAvatar.prepare(Self.png(width: 64, height: 64))
        // The later record has the picture; the earlier one (which survives) has none, and even a newer removal.
        otherDevicesProfile(name: "George", nameAt: -40, picture: nil, pictureAt: -1, createdAt: -100)
        otherDevicesProfile(picture: picture, pictureAt: -20, createdAt: -50)
        try dedupe()
        let survivor = try XCTUnwrap(try profiles().first)
        XCTAssertEqual(try profiles().count, 1)
        XCTAssertEqual(survivor.avatarData, picture, "a merge never loses a picture")
        XCTAssertEqual(survivor.displayName, "George")
    }

    func testTwoDevicesMergingTheSameDataPickTheSameSurvivor() throws {
        // Same createdAt: the id breaks the tie, as `Deduplicator.precedes` does for Groups.
        let a = otherDevicesProfile(name: "A", nameAt: -5, createdAt: -10)
        let b = otherDevicesProfile(name: "B", nameAt: -5, createdAt: -10)
        let expected = [a, b].min { $0.id.uuidString < $1.id.uuidString }!.id
        try dedupe()
        XCTAssertEqual(try profiles().map(\.id), [expected])
        XCTAssertEqual(try profiles().first?.displayName, expected == a.id ? "A" : "B", "a name tie goes to the survivor")
    }

    func testMergeLeavesTasksAndGroupsAlone() throws {
        let group = Project(name: "Home")
        context.insert(group)
        context.insert(TaskItem(title: "Laundry", project: group))
        otherDevicesProfile(name: "A", nameAt: -5, createdAt: -10)
        otherDevicesProfile(name: "B", nameAt: -3, createdAt: -8)
        let report = try dedupe()
        XCTAssertEqual(report.projects, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).first?.project?.name, "Home")
    }

    // MARK: Robustness (brief 42, item 3)

    /// Saves that reached the store (`ModelContext.didSave`) while `body` ran: each one is a CloudKit export.
    private func saves(during body: () throws -> Void) rethrows -> Int {
        var count = 0
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: nil) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        try body()
        return count
    }

    func testTheSameNameTwiceSavesNothing() throws {
        try store.setName("George")
        XCTAssertEqual(try saves { try store.setName("George") }, 0)
        XCTAssertEqual(try saves { try store.setName("  George\n") }, 0, "the same name once trimmed")
        XCTAssertEqual(try saves { try store.setName("") ; try store.setName("") }, 1, "clearing saves once")
    }

    func testTheSamePictureTwiceSavesNothing() throws {
        let png = try Self.png(width: 300, height: 300)
        try store.setAvatar(imageData: png)
        let stamped = try XCTUnwrap(try store.current()?.avatarUpdatedAt)
        now = now.addingTimeInterval(60)
        let lines = logged.count
        XCTAssertEqual(try saves { try store.setAvatar(imageData: png) }, 0, "the same photo chosen again")
        XCTAssertEqual(try store.current()?.avatarUpdatedAt, stamped)
        XCTAssertEqual(logged.count, lines)
        XCTAssertEqual(try saves { try store.setAvatar(imageData: nil); try store.setAvatar(imageData: nil) }, 1, "removing saves once")
    }

    /// A device of its own: an in-memory store, its own profile, its own clock.
    @MainActor private struct Device {
        let container = ModelContainerFactory.preview()
        var context: ModelContext { container.mainContext }
        func store(at time: Date) -> ProfileStore {
            ProfileStore(context: context, log: { _, _, _ in }, clock: { time })
        }
        func profiles() throws -> [Profile] { try context.fetch(FetchDescriptor<Profile>()).sorted(by: ProfileStore.precedes) }

        /// What CloudKit's import does with another device's record: the same record (same id, same values).
        func importRecord(_ other: Profile) throws {
            let id = other.id
            if let existing = try context.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })).first {
                existing.displayName = other.displayName
                existing.nameUpdatedAt = other.nameUpdatedAt
                existing.avatarData = other.avatarData
                existing.avatarUpdatedAt = other.avatarUpdatedAt
                existing.updatedAt = other.updatedAt
                existing.createdAt = other.createdAt
            } else {
                let copy = Profile()
                copy.id = other.id
                copy.createdAt = other.createdAt
                copy.displayName = other.displayName
                copy.nameUpdatedAt = other.nameUpdatedAt
                copy.avatarData = other.avatarData
                copy.avatarUpdatedAt = other.avatarUpdatedAt
                copy.updatedAt = other.updatedAt
                context.insert(copy)
            }
            try context.save()
        }

        func merge() throws { try Deduplicator.run(in: context, profileLog: { _, _, _ in }) }
    }

    func testAProfileEditedOnTwoDevicesOfflineConvergesInEitherImportOrder() throws {
        let picture = try ProfileAvatar.prepare(Self.png(width: 64, height: 64))
        for phoneFirst in [true, false] {
            // Offline: the Mac makes the profile first and names it; the phone, later, picks a picture and then
            // a newer name. Neither has seen the other's record.
            let mac = Device(), phone = Device()
            try mac.store(at: now).setName("George")
            try phone.store(at: now.addingTimeInterval(10)).setAvatar(imageData: try Self.png(width: 64, height: 64))
            try phone.store(at: now.addingTimeInterval(20)).setName("George T.")
            try mac.store(at: now.addingTimeInterval(30)).setName("George")   // unchanged: no write
            let macRecord = try XCTUnwrap(mac.profiles().first), phoneRecord = try XCTUnwrap(phone.profiles().first)

            // Back online: each imports the other's record, in either order, and merges.
            if phoneFirst {
                try mac.importRecord(phoneRecord); try mac.merge()
                try phone.importRecord(macRecord); try phone.merge()
            } else {
                try phone.importRecord(macRecord); try phone.merge()
                try mac.importRecord(phoneRecord); try mac.merge()
            }
            // Each device's merge result reaches the other (survivor updated, loser deleted on both).
            for (from, to) in [(mac, phone), (phone, mac)] {
                for record in try from.profiles() { try to.importRecord(record) }
                try to.merge()
            }

            for device in [mac, phone] {
                let records = try device.profiles()
                XCTAssertEqual(records.count, 1, "one profile on each device (phone first: \(phoneFirst))")
                XCTAssertEqual(records.first?.id, macRecord.id, "the earliest record survives everywhere")
                XCTAssertEqual(records.first?.displayName, "George T.", "the newest name, from the phone")
                XCTAssertEqual(records.first?.avatarData, picture, "the phone's picture")
                XCTAssertEqual(records.first?.updatedAt, now.addingTimeInterval(20))
            }
            XCTAssertEqual(try saves { try mac.merge() }, 0, "a converged store has nothing left to merge")
        }
    }

    func testAProfileFromAnotherAccountIsIgnoredAndLogged() throws {
        let suite = "HITListTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ownership = ProfileOwnership(defaults: defaults, storeName: ModelContainerFactory.mainStoreName)
        let alice = AccountIdentity.key(recordName: "_alice"), bob = AccountIdentity.key(recordName: "_bob")
        var account: String? = alice
        var store = self.store
        store.account = { account }
        store.ownership = ownership

        try store.setName("Alice")
        let alices = try XCTUnwrap(try store.current())
        XCTAssertEqual(ownership.owner(of: alices.id), alice, "claimed by the account it was seen with")

        // Bob signs in. Core Data should purge Alice's record; suppose it didn't, and Bob's arrives.
        account = bob
        let bobs = otherDevicesProfile(name: "Bob", nameAt: -1, createdAt: 50)
        XCTAssertEqual(try store.current()?.id, bobs.id, "Alice's record isn't shown to Bob, though it's older")
        XCTAssertEqual(try store.current()?.displayName, "Bob")
        XCTAssertEqual(ProfileStore.shown(try profiles(), account: bob, ownership: ownership)?.id, bobs.id, "nor in the badge")
        XCTAssertEqual(logged.filter { $0.message == "Ignored a profile record from another iCloud account" }.count, 1)
        XCTAssertEqual(logged.last { $0.message.hasPrefix("Ignored") }?.level, .error)

        let merged = try store.mergeDuplicates()
        XCTAssertEqual(merged, 0, "never merged into Bob's: Alice's name can't win a merge here")
        XCTAssertEqual(try profiles().count, 2, "and never deleted: it's Alice's iCloud data")
        _ = try store.current()
        XCTAssertEqual(logged.filter { $0.message.hasPrefix("Ignored") }.count, 1, "logged once per record")
        XCTAssertFalse(logged.contains { line in line.fields.values.contains { $0.contains("acct1:") || $0.contains("Alice") } })

        // Before the account is known (the first second of a launch), nothing is hidden or claimed.
        account = nil
        XCTAssertEqual(try store.all().count, 2)
    }

    func testThePictureIsDecodedOncePerPicture() throws {
        let cache = ProfileAvatarCache.shared
        cache.removeAll()
        let picture = try ProfileAvatar.prepare(Self.png(width: 200, height: 200))
        let before = cache.decodeCount
        for _ in 0..<20 { XCTAssertNotNil(cache.image(for: picture)) }
        XCTAssertEqual(cache.decodeCount - before, 1, "twenty bodies, one decode")
        XCTAssertNotNil(ProfileAvatarView.image(from: picture))
        XCTAssertEqual(cache.decodeCount - before, 1, "the view goes through the cache")
        let garbage = Data(repeating: 7, count: 100)
        XCTAssertNil(cache.image(for: garbage))
        XCTAssertNil(cache.image(for: garbage))
        XCTAssertEqual(cache.decodeCount - before, 2, "an unreadable picture isn't tried again either")
        cache.removeAll()
        _ = cache.image(for: picture)
        XCTAssertEqual(cache.decodeCount - before, 3, "an account switch empties it")
    }

    // MARK: Picture

    func testPreparedPictureIsAJPEGWithinTheLimitsAndNeverUpscaled() throws {
        let small = try ProfileAvatar.prepare(Self.png(width: 120, height: 80))
        XCTAssertEqual(Self.pixelSize(of: small)?.width, 120, "a small picture keeps its size")
        // A noisy picture is hard to compress: the quality steps down until it fits.
        let noisy = try ProfileAvatar.prepare(Self.png(width: 1600, height: 1600, noise: true))
        XCTAssertLessThanOrEqual(noisy.count, ProfileAvatar.maxBytes)
        XCTAssertLessThanOrEqual(Self.pixelSize(of: noisy).map { max($0.width, $0.height) } ?? 999, 512)
        XCTAssertThrowsError(try ProfileAvatar.prepare(Data()))
    }

    func testInitials() {
        XCTAssertEqual(ProfileAvatar.initials(for: "George Trammell"), "GT")
        XCTAssertEqual(ProfileAvatar.initials(for: "  george  "), "G")
        XCTAssertEqual(ProfileAvatar.initials(for: "Mary Jane van Dyke"), "MD")
        XCTAssertEqual(ProfileAvatar.initials(for: "Émile Zola"), "ÉZ")
        XCTAssertNil(ProfileAvatar.initials(for: ""))
        XCTAssertNil(ProfileAvatar.initials(for: "   "))
    }

    // MARK: Account state

    private func state(_ status: CKAccountStatus?, notice: AccountWatch.Notice? = nil, ever: Bool = true,
                       cloudKit: Bool = true) -> AccountState {
        AccountState.derive(cloudKitEnabled: cloudKit, localOnlyReason: "store opened without CloudKit",
                            status: status, notice: notice, everSignedIn: ever)
    }

    func testAccountStateCoversEveryStatusHonestly() {
        XCTAssertEqual(state(.available), .signedIn)
        XCTAssertEqual(state(.available).title, "iCloud: Signed in")
        XCTAssertEqual(state(.available).detail,
                       "Your tasks are stored in your iCloud account and sync to every device signed in to it.")
        XCTAssertEqual(state(.available, notice: .switched), .switched)
        XCTAssertEqual(state(.available, notice: .signedOut), .signedIn, "a stale signed-out banner doesn't outrank a sign-in")
        XCTAssertEqual(state(.noAccount, ever: true), .signedOut)
        XCTAssertEqual(state(.noAccount, ever: false), .neverSignedIn)
        XCTAssertEqual(state(.restricted), .restricted)
        XCTAssertEqual(state(.temporarilyUnavailable), .needsSignInAgain)
        XCTAssertEqual(state(.couldNotDetermine), .couldNotDetermine)
        XCTAssertEqual(state(nil), .checking)
        XCTAssertEqual(state(.available, cloudKit: false), .localOnly("store opened without CloudKit"))
        XCTAssertEqual(state(.couldNotDetermine).title, "iCloud: Couldn't check")
    }

    func testANewTesterWithoutICloudIsNotWarned() {
        XCTAssertFalse(state(.noAccount, ever: false).isWarning, "someone who never used iCloud isn't shouted at")
        XCTAssertTrue(state(.noAccount, ever: true).isWarning)
        XCTAssertFalse(state(.available).isWarning)
        XCTAssertTrue(state(.restricted).isWarning)
    }

    func testEveryAccountStateSaysWhatItMeansAndNeverMentionsDeleting() {
        let all: [AccountState] = [.checking, .signedIn, .switched, .signedOut, .neverSignedIn, .restricted,
                                   .needsSignInAgain, .couldNotDetermine, .localOnly("x")]
        XCTAssertEqual(Set(all.map(\.label)).count, all.count, "each state reads differently")
        for s in all {
            XCTAssertFalse(s.detail.isEmpty)
            XCTAssertTrue(s.title.hasPrefix("iCloud: "))
            XCTAssertFalse(s.detail.localizedCaseInsensitiveContains("delete"), "\(s): an account change never deletes")
        }
    }

    func testAccountCopyGivesTheSystemsPaths() {
        XCTAssertTrue(AccountCopy.signOut.contains("Sign Out"))
        XCTAssertTrue(AccountCopy.signOut.contains("never deletes"))
        #if os(macOS)
        XCTAssertTrue(AccountCopy.deleteAll.contains("System Settings → [your name] → iCloud → Manage → HITList → Delete from iCloud"))
        #else
        XCTAssertTrue(AccountCopy.deleteAll.contains("iCloud → Storage (on iOS 18: Manage Account Storage) → HITList → Delete Data from iCloud"))
        #endif
        XCTAssertTrue(AccountCopy.deleteProfile.contains("tasks"))
    }

    // MARK: Diagnostics, About, iCloud screen

    func testDiagnosticsProfileLineNeverHoldsTheNameOrPicture() throws {
        XCTAssertEqual(Diagnostics.profileLine(for: [], lastExport: now), "none on this device")
        try store.setName("George Trammell")
        try store.setAvatar(imageData: try Self.png(width: 64, height: 64))
        let line = Diagnostics.profileLine(for: try profiles(), lastExport: now.addingTimeInterval(5))
        XCTAssertTrue(line.hasPrefix("1 record, changed "), line)
        XCTAssertTrue(line.hasSuffix(", exported since"), line)
        XCTAssertFalse(line.contains("George"))
        XCTAssertTrue(Diagnostics.profileLine(records: 1, updatedAt: now, lastExport: now.addingTimeInterval(-1)).hasSuffix("not exported since"))
        XCTAssertTrue(Diagnostics.profileLine(records: 1, updatedAt: now, lastExport: nil).hasSuffix("never exported"))
        XCTAssertTrue(Diagnostics.profileLine(records: 2, updatedAt: now, lastExport: nil).hasPrefix("2 records (merged after the next import)"))
    }

    func testThePrivacyLinkIsTheDocsPermalink() throws {
        XCTAssertEqual(AboutInfo.privacyPolicyURL.absoluteString, "https://aeronyx.github.io/HITList/privacy/")
        render(VStack { AboutSettingsGroup() }, "about")
        render(VStack { MacAboutSection() }, "mac about")
    }

    func testTheICloudScreenNamesTheAccountStateLikeTheAccountScreen() {
        XCTAssertTrue(SyncEnvironmentRow.subtitle(account: .signedIn).hasPrefix("iCloud: Signed in. "))
        XCTAssertTrue(SyncEnvironmentRow.subtitle(account: .neverSignedIn).hasPrefix(AccountState.neverSignedIn.title))
        render(SyncEnvironmentRow(account: .switched), "environment row")
    }

    // MARK: Views

    private func render<V: View>(_ view: V, _ name: String, width: CGFloat = 390, file: StaticString = #filePath, line: UInt = #line) {
        let content = view.modelContainer(container).frame(width: width).background(Theme.background).preferredColorScheme(.dark)
        XCTAssertNotNil(ImageRenderer(content: content).cgImage, "\(name) didn't render", file: file, line: line)
    }

    func testAccountViewsRenderWithAndWithoutAProfile() throws {
        render(VStack { AccountSettingsSection() }, "account, no profile")
        try store.setName("George Trammell")
        render(VStack { AccountSettingsSection() }, "account, name only")
        try store.setAvatar(imageData: try Self.png(width: 300, height: 300))
        render(VStack { AccountSettingsSection() }, "account, name and picture")
        render(ProfileBadge(), "badge")
        render(ProfileAvatarView(imageData: nil, name: "", size: 40), "avatar, empty", width: 40)
        for s in [AccountState.signedIn, .neverSignedIn, .restricted] { render(AccountStatusRow(state: s), "status \(s)") }
    }

    // MARK: Helpers

    static func png(width: Int, height: Int, noise: Bool = false) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if noise, let pixels = context.data?.assumingMemoryBound(to: UInt8.self) {
            var seed: UInt32 = 12345
            for i in 0..<(context.bytesPerRow * height) {
                seed = seed &* 1_103_515_245 &+ 12345
                pixels[i] = i % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: seed >> 16)
            }
        } else {
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let image = try XCTUnwrap(context.makeImage())
        let out = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return out as Data
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    static func type(of data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }
}
