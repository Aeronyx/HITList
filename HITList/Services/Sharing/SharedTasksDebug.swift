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
    static var forcesOn: Bool { seedsSample || pushesSchema }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sharing")
    private static var didRunLaunchHooks = false

    /// Called once Shared Tasks has started (`SharedTasksCenter.startIfOn`).
    @MainActor
    static func runLaunchHooks(_ center: SharedTasksCenter) {
        guard !didRunLaunchHooks else { return }
        didRunLaunchHooks = true
        if pushesSchema { Task { await pushSchema(center) } }
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
