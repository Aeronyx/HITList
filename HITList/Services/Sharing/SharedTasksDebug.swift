#if DEBUG
import Foundation
import CloudKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import OSLog

/// Debug-only launch arguments for Shared Tasks (brief 51). None of this is in a Release build, and none of it writes
/// the switch: each turns Shared Tasks on for that run only.
///
/// - `-sharedTasksOn YES`: on for this run, with CloudKit, its own file (use it with a `HITLIST_STORE_SUFFIX`).
/// - `-sharedTasksSelfTest YES`: the owner's actions against the shared container's Development database, through the
///   same calls the screens make: a list with tasks, a real two-device conflict (another "device" changes the notes on
///   the server while this one renames), share, stop sharing, delete; each step logs PASS or FAIL ("Shared Tasks
///   self-test:"). It shows the list and its People in a sheet for 8 s while shared, for a screenshot.
/// - `-seedSharedTasksSample YES`: an in-memory store with sample lists and people, no CloudKit (screenshots).
/// - `-openSharedTasks YES` (with `-openSharedList N`, `-openSharedPeople YES`): opens the Shared screen in a sheet a
///   moment after launch, at the Nth list and its People.
/// - `-sharedTasksSchemaPush YES`: the record types into the shared container's Development schema. Run it with its own
///   store and the task store's sync off: `HITLIST_STORE_SUFFIX=sNN …/HITList -disableCloudKit YES -sharedTasksSchemaPush
///   YES`. It makes a list with every field of every record type set, shares it (a `cloudkit.share` with a title),
///   reads each record back from the server, deletes the list again and logs every step ("Shared Tasks schema push:")
///   to the `sharing` category.
enum SharedTasksDebug {
    static var seedsSample: Bool { UserDefaults.standard.bool(forKey: "seedSharedTasksSample") }
    static var pushesSchema: Bool { UserDefaults.standard.bool(forKey: "sharedTasksSchemaPush") }
    static var opensScreen: Bool { UserDefaults.standard.bool(forKey: "openSharedTasks") }
    static var openListIndex: Int? { UserDefaults.standard.object(forKey: "openSharedList").map { _ in UserDefaults.standard.integer(forKey: "openSharedList") } }
    static var opensPeople: Bool { UserDefaults.standard.bool(forKey: "openSharedPeople") }
    static var switchedOnForRun: Bool { UserDefaults.standard.bool(forKey: "sharedTasksOn") }
    static var selfTests: Bool { UserDefaults.standard.bool(forKey: "sharedTasksSelfTest") }
    static var forcesOn: Bool { seedsSample || pushesSchema || switchedOnForRun || selfTests }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sharing")
    private static var didRunLaunchHooks = false

    /// Called once Shared Tasks has started (`SharedTasksCenter.startIfOn`).
    @MainActor
    static func runLaunchHooks(_ center: SharedTasksCenter) {
        guard !didRunLaunchHooks else { return }
        didRunLaunchHooks = true
        if pushesSchema { Task { await pushSchema(center) } }
        if selfTests { Task { await selfTest(center) } }
        if opensScreen {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                let lists = center.store?.sortedLists ?? []
                let list = openListIndex.flatMap { lists.indices.contains($0) ? lists[$0].id : nil }
                SharedTasksPresenter.presentScreen(list: list, people: opensPeople)
            }
        }
    }

    // MARK: - Sample

    static let me = "_sample0me000000000000000000000000"
    static let sam = "_sample0sam00000000000000000000000"
    static let alex = "_sample0alex0000000000000000000000"

    /// Two lists: one Sam shares with me (Sam, Alex and me; a task Sam completed), one of mine waiting for people.
    @MainActor
    static func sampleStore(now: Date = Date()) -> SharedTasksStore {
        let store = SharedTasksStore(persistence: .memory)
        store.setMe(me)
        store.setProfile(SharedProfile(name: "George", nameChangedAt: now, avatar: nil, avatarChangedAt: now))
        let t = SharedClock.stamp(now)
        let groceries = UUID()
        store.applyServerList(SharedListFields(title: Stamped("Groceries", at: t), colorHex: Stamped("#4FD1E8", at: t), createdAt: t),
                              systemFields: nil, listID: groceries, scope: .joined, ownerName: sam)
        store.applyShare(SharedShareInfo(participants: [
            SharedParticipant(userID: sam, name: "Sam Rivera", contact: nil, role: .owner, status: .accepted, canWrite: true, isCurrentUser: false),
            SharedParticipant(userID: me, name: "George Trammell", contact: nil, role: .participant, status: .accepted, canWrite: true, isCurrentUser: true),
            SharedParticipant(userID: alex, name: "Alex Kim", contact: nil, role: .participant, status: .accepted, canWrite: true, isCurrentUser: false),
        ], url: nil, archive: nil), listID: groceries, scope: .joined, ownerName: sam)
        for (id, name, hex) in [(sam, "Sam", "#8FD694"), (alex, "Alex", "#B07CF5")] {
            store.applyServerMember(SharedMember(id: id, name: Stamped(name, at: t), avatar: Stamped(swatch(hex), at: t), joinedAt: t),
                                    listID: groceries, scope: .joined, ownerName: sam)
        }
        store.setProfile(SharedProfile(name: "George", nameChangedAt: now, avatar: nil, avatarChangedAt: now))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        func task(_ title: String, priority: Int = 4, due: SharedDue? = nil, by: SharedMemberID, done: (SharedMemberID, String, TimeInterval)? = nil) {
            let completion = done.map { SharedCompletion(at: SharedClock.stamp(now.addingTimeInterval($0.2)), by: $0.0, byName: $0.1) }
            store.applyServerTask(SharedTask(id: UUID(), title: Stamped(title, at: t), notes: Stamped("", at: t), priority: Stamped(priority, at: t),
                                             due: Stamped(due, at: t), completion: Stamped(completion, at: t), createdAt: t,
                                             createdBy: by, createdByName: nil), listID: groceries, scope: .joined, ownerName: sam)
        }
        task("Oat milk", priority: 2, due: SharedDue(date: Calendar.current.startOfDay(for: now), hasTime: false), by: sam)
        task("Coffee beans", by: me)
        task("Lemons", due: SharedDue(date: tomorrow, hasTime: false), by: alex)
        task("Bread", by: sam, done: (sam, "Sam", -3600))
        task("Eggs", by: me, done: (me, "George", -7200))

        let trip = try? store.createList(title: "Weekend trip", colorHex: "#F2A65A")
        if let trip {
            _ = try? store.addTask(to: trip.id, title: "Book the cabin", priority: 1)
            _ = try? store.addTask(to: trip.id, title: "Pack the tent")
        }
        return store
    }

    /// A small round-coloured JPEG standing in for a profile picture.
    static func swatch(_ hex: String) -> Data? {
        let size = 64
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x808080
        context.setFillColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                             blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    // MARK: - Self-test

    /// Waits for Shared Tasks to know who this account is (`connect`), up to 60 s.
    @MainActor
    private static func connected(_ center: SharedTasksCenter, say: (String) -> Void) async -> (SharedTasksStore, SharedTasksSync)? {
        for _ in 0..<60 where center.store?.me == nil || center.phase != .ready {
            if center.phase == .noAccount { say("no iCloud account; stopping"); return nil }
            try? await Task.sleep(for: .seconds(1))
        }
        guard let store = center.store, store.me != nil, let sync = center.syncForDebug else { say("not connected after 60 s; stopping"); return nil }
        return (store, sync)
    }

    /// Sends until nothing is pending (up to 30 s).
    private static func sendAll(_ sync: SharedTasksSync) async {
        for _ in 0..<30 {
            await sync.sendNow()
            let state = sync.engine(.owned).state
            if state.pendingRecordZoneChanges.isEmpty && state.pendingDatabaseChanges.isEmpty { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    @MainActor
    static func selfTest(_ center: SharedTasksCenter) async {
        func say(_ message: String) { log.notice("Shared Tasks self-test: \(message, privacy: .public)") }
        func verdict(_ ok: Bool) -> String { ok ? "PASS" : "FAIL" }
        say("starting (\(ModelContainerFactory.storeName))")
        guard let (store, sync) = await connected(center, say: say) else { return }
        let database = sync.container.privateCloudDatabase
        do {
            let list = try center.createList(title: "Self-test \(Date().formatted(date: .omitted, time: .standard))")
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            let milk = try store.addTask(to: list.id, title: "Milk", priority: 2, due: SharedDue(date: tomorrow, hasTime: false))
            _ = try store.addTask(to: list.id, title: "Bread")
            try store.setCompleted(true, task: milk.id, in: list.id)
            await sendAll(sync)
            let zoneID = SharedTasksRecords.zoneID(listID: list.id, ownerName: CKCurrentUserDefaultName)
            let milkID = CKRecord.ID(recordName: SharedTasksSchema.taskRecordName(for: milk.id), zoneID: zoneID)
            let saved = try await database.record(for: milkID)
            say("1 list, two tasks, Milk completed and due tomorrow, saved: \(verdict(saved["isCompleted"] as? Int64 == 1 && saved["hasDueDate"] as? Int64 == 1))")

            // Another device changes the notes on the server; this one renames on its older change tag.
            saved["notes"] = "From another device"
            saved["notesChangedAt"] = SharedClock.stamp(Date().addingTimeInterval(1))
            _ = try await database.modifyRecords(saving: [saved], deleting: [])
            try store.setTitle("Oat milk", task: milk.id, in: list.id)
            await sendAll(sync)
            let merged = try await database.record(for: milkID)
            let mergedOK = merged["title"] as? String == "Oat milk" && merged["notes"] as? String == "From another device"
                && merged["isCompleted"] as? Int64 == 1
            say("2 conflict merged per field on the server (title \(merged["title"] as? String ?? "?"), notes \(merged["notes"] as? String ?? "?")): \(verdict(mergedOK))")
            let local = store.list(list.id)?.task(milk.id)
            say("2 this device has both too: \(verdict(local?.title.value == "Oat milk" && local?.notes.value == "From another device"))")

            let share = try await center.prepareShare(for: list.id)
            let shareID = SharedTasksRecords.shareRecordID(listID: list.id, ownerName: CKCurrentUserDefaultName)
            let onServer = (try? await database.record(for: shareID)) is CKShare
            say("3 shared (url \(share.url != nil ? "yes" : "no"), on the server \(onServer)): \(verdict(onServer && share.url != nil))")
            let again = try await center.prepareShare(for: list.id)
            say("3 Invite again reuses the share: \(verdict(again.recordID == share.recordID))")

            SharedTasksPresenter.presentScreen(list: list.id, people: true)
            say("showing the list and People")
            try? await Task.sleep(for: .seconds(8))
            SharedTasksPresenter.dismiss()

            try await center.stopSharing(list.id)
            let shareGone = (try? await database.record(for: shareID)) == nil
            say("4 stopped sharing, the owner keeps the list: \(verdict(shareGone && store.list(list.id) != nil && store.list(list.id)?.share == nil))")

            try center.deleteList(list.id)
            await sendAll(sync)
            let zoneGone = (try? await database.recordZone(for: zoneID)) == nil
            say("5 deleted for everyone (zone gone): \(verdict(zoneGone && store.list(list.id) == nil))")
            say("done")
        } catch {
            say("failed: \(error)")
        }
    }

    // MARK: - Schema push

    @MainActor
    static func pushSchema(_ center: SharedTasksCenter) async {
        func say(_ message: String) { log.notice("Shared Tasks schema push: \(message, privacy: .public)") }
        say("starting (\(ModelContainerFactory.storeName); container \(SharedTasksSchema.containerID))")
        for _ in 0..<60 where center.store?.me == nil || center.phase != .ready {
            if center.phase == .noAccount { say("no iCloud account; stopping"); return }
            try? await Task.sleep(for: .seconds(1))
        }
        guard let store = center.store, let me = store.me, let sync = center.syncForDebug else { say("not connected after 60 s; stopping"); return }
        say("connected as \(me.prefix(8))…")
        do {
            let now = Date()
            store.setProfile(SharedProfile(name: "Schema push", nameChangedAt: now, avatar: swatch("#5E81F4"), avatarChangedAt: now))
            let list = try store.createList(title: "Schema push \(now.formatted(date: .numeric, time: .standard))", colorHex: "#5E81F4")
            let task = try store.addTask(to: list.id, title: "Every field", notes: "Notes", priority: 2,
                                         due: SharedDue(date: now.addingTimeInterval(86_400), hasTime: true))
            try store.setCompleted(true, task: task.id, in: list.id)
            await sync.sendNow()
            for _ in 0..<30 where !sync.engine(.owned).state.pendingRecordZoneChanges.isEmpty || !sync.engine(.owned).state.pendingDatabaseChanges.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                await sync.sendNow()
            }
            say("sent: zone, SharedList, SharedTask, SharedMember (pending now: \(sync.engine(.owned).state.pendingRecordZoneChanges.count))")
            let share = try await center.prepareShare(for: list.id)
            say("shared: \(share.recordID.recordName), participants \(share.participants.count), url \(share.url != nil ? "yes" : "no")")
            let database = sync.container.privateCloudDatabase
            let zoneID = SharedTasksRecords.zoneID(listID: list.id, ownerName: CKCurrentUserDefaultName)
            for name in [SharedTasksSchema.listRecordName, SharedTasksSchema.taskRecordName(for: task.id), SharedTasksSchema.memberRecordName(for: me)] {
                let record = try await database.record(for: CKRecord.ID(recordName: name, zoneID: zoneID))
                say("read back \(record.recordType): \(record.allKeys().sorted().joined(separator: ", "))")
            }
            try store.deleteList(list.id)
            await sync.sendNow()
            say("deleted the sample list again; done")
        } catch {
            say("failed: \(error)")
        }
    }
}
#endif
