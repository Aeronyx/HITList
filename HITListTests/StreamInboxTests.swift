import XCTest
import SwiftData
import Security
import HITListCore
@testable import HITList

/// The Stream ring's inbox on a device (brief 176), against a relay in this process (`StreamInboxFakeRelay`, reached
/// through `URLProtocol`): captures become tasks by Siri's road, the ack carries exactly what was handled, nothing is
/// added twice, the "starts with Task" rule, a failed save and a relay that is down leave everything for next time.
@MainActor
final class StreamInboxTests: XCTestCase {
    private var container: ModelContainer!
    private var suite: String!
    private var defaults: UserDefaults!
    private var relay: StreamInboxFakeRelay!
    private var logged: [String] = []

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        suite = "StreamInboxTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        relay = StreamInboxFakeRelay()
        logged = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        container = nil
        relay = nil
    }

    private struct SaveFailed: Error {}

    /// A save that fails as `TaskActions.create`'s does: the task is inserted, then the save throws.
    private static func failingSave(_ text: String, in context: ModelContext) throws -> UUID {
        context.insert(TaskItem(title: text))
        throw SaveFailed()
    }

    private func inbox(failing: Set<String> = [], storeIsReal: Bool = true, active: Bool = true,
                       pushEnvironment: InboxPushRegistration.Environment = .development) -> StreamInbox {
        StreamInbox(container: container, defaults: defaults, keyStore: MemoryInboxKey(), client: relay.client,
                    storeIsReal: { storeIsReal }, isActive: { active }, pushEnvironment: { pushEnvironment },
                    addTask: { text, now, context in
                        if failing.contains(text) { return try Self.failingSave(text, in: context) }
                        return try StreamInbox.addThroughQuickAdd(text, now, context)
                    },
                    log: { [weak self] line, _ in self?.logged.append(line) })
    }

    private func connected(failing: Set<String> = [], storeIsReal: Bool = true, active: Bool = true,
                           pushEnvironment: InboxPushRegistration.Environment = .development) async throws -> StreamInbox {
        let inbox = inbox(failing: failing, storeIsReal: storeIsReal, active: active, pushEnvironment: pushEnvironment)
        let problem = await inbox.connect(linkText: relay.link, checkAfter: false)
        XCTAssertNil(problem)
        XCTAssertTrue(inbox.isConnected)
        return inbox
    }

    private func tasks() throws -> [TaskItem] {
        try container.mainContext.fetch(FetchDescriptor<TaskItem>()).sorted { $0.title < $1.title }
    }

    private func task(_ title: String) throws -> TaskItem {
        try XCTUnwrap(try tasks().first { $0.title == title }, "“\(title)” was made")
    }

    // MARK: Captures become tasks

    func testCapturesBecomeTasksWithTheirDatesPriorityAndGroup() async throws {
        relay.add("int-1", "Call the dentist tomorrow at 9am p2.")
        relay.add("int-2", "Task: buy milk #Errands")
        relay.add("int-3", "To do, water the plants friday")
        let inbox = try await connected()
        let result = await inbox.check(.checkNow)
        XCTAssertEqual(result.added, 3)
        XCTAssertNil(result.problem)

        let calendar = Calendar.current
        let dentist = try task("Call the dentist")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        XCTAssertEqual(dentist.dueDate, calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow))
        XCTAssertTrue(dentist.hasDueTime)
        XCTAssertEqual(dentist.priorityValue, .p2)
        XCTAssertNil(dentist.project, "no #Group: the Inbox")

        let milk = try task("Buy milk")
        XCTAssertEqual(milk.project?.name, "Errands", "a #Group that didn't exist is made, as quick add makes it")
        XCTAssertNil(milk.dueDate)

        let plants = try task("Water the plants")
        let due = try XCTUnwrap(plants.dueDate)
        XCTAssertEqual(calendar.component(.weekday, from: due), 6, "Friday")
        XCTAssertFalse(plants.hasDueTime)

        XCTAssertEqual(relay.acks, [["int-1", "int-2", "int-3"]])
        XCTAssertEqual(relay.waitingIDs, [], "handed over")
        XCTAssertEqual(inbox.addedToday, 3)
        XCTAssertNotNil(inbox.lastCaptureAt)
        XCTAssertTrue(logged.contains { $0.contains("3 added") })
        for line in logged {
            XCTAssertFalse(line.contains("dentist") || line.contains("milk") || line.contains("plants"),
                           "the log carries counts, never a capture's words: \(line)")
        }
    }

    func testTheAckCarriesExactlyTheHandledIDs() async throws {
        relay.add("a", "Task: call mom")
        relay.add("b", "Remember where I parked")
        relay.add("c", "Task: fail this one")
        relay.add("test-1", InboxAPI.testText)
        let inbox = try await connected(failing: ["Fail this one"])
        _ = await inbox.setOnlyStartingWithTask(true)
        let result = await inbox.check(.checkNow)
        XCTAssertEqual(result.added, 2, "a, and the relay's test capture whatever the rule says")
        XCTAssertEqual(result.skipped, 1, "b is left in Stream by the rule")
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(relay.acks, [["a", "b", "test-1"]], "added or left by the rule; the failed save is not acked")
        XCTAssertEqual(relay.waitingIDs, ["c"])
        XCTAssertEqual(result.problem, .notSaved(1))
        XCTAssertEqual(try tasks().map(\.title), ["Call mom", InboxAPI.testText])
        XCTAssertEqual(inbox.problem?.words, "A capture couldn't be added. It stays in your relay for next time.")
    }

    func testTheStartsWithTaskRule() async throws {
        relay.add("a", "Task. Book the car service")
        relay.add("b", "Remember where I parked")
        relay.add("c", "Tasks are piling up")
        let inbox = try await connected()
        _ = await inbox.setOnlyStartingWithTask(true)
        XCTAssertTrue(defaults.bool(forKey: StreamInboxSettings.onlyStartingWithTaskKey), "kept")
        let result = await inbox.check(.checkNow)
        XCTAssertEqual(try tasks().map(\.title), ["Book the car service"])
        XCTAssertEqual(result.skipped, 2)
        XCTAssertEqual(relay.acks, [["a", "b", "c"]], "the others are handed over too: they stay only in Stream")

        _ = await inbox.setOnlyStartingWithTask(false)
        relay.add("d", "Remember where I parked.")
        await inbox.check(.checkNow)
        XCTAssertEqual(try tasks().map(\.title), ["Book the car service", "Remember where I parked"], "rule off: every capture")
    }

    // MARK: Never twice, never lost

    func testAnIDAddedBeforeIsNeverAddedTwice() async throws {
        relay.add("a", "Buy milk")
        let inbox = try await connected()
        relay.acksFail = true
        var result = await inbox.check(.checkNow)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.problem, .relayTrouble(500))
        XCTAssertEqual(relay.waitingIDs, ["a"], "not handed over: the ack didn't arrive")
        // The ack's own memory lost too (a kill at the worst moment): the relay offers "a" again to this device.
        defaults.removeObject(forKey: StreamInboxSettings.unackedKey)
        relay.acksFail = false
        result = await inbox.check(.checkNow)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.skipped, 1, "added here before")
        XCTAssertEqual(try tasks().map(\.title), ["Buy milk"], "one task, not two")
        XCTAssertEqual(relay.waitingIDs, [])
    }

    func testAnAckThatFailedGoesFirstNextTime() async throws {
        relay.add("a", "Buy milk")
        let inbox = try await connected()
        relay.acksFail = true
        await inbox.check(.checkNow)
        XCTAssertEqual(defaults.stringArray(forKey: StreamInboxSettings.unackedKey), ["a"], "kept for next time")
        relay.acksFail = false
        let before = relay.requests.count
        await inbox.check(.checkNow)
        let next = relay.requests.dropFirst(before).map(\.path)
        XCTAssertEqual(next.first, InboxAPI.Endpoint.ack.rawValue, "the waiting ack goes before the claim")
        XCTAssertEqual(relay.acks.last, ["a"])
        XCTAssertEqual(relay.waitingIDs, [])
        XCTAssertEqual(try tasks().count, 1)
        XCTAssertNil(defaults.stringArray(forKey: StreamInboxSettings.unackedKey).flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Review finding 5: the stub inserts, as `TaskActions.create` does, before its save throws. What that capture
    /// inserted (the task, and a Group it made) is taken out again; George's own unsaved edits are left alone; the retry
    /// adds it once.
    func testASaveThatFailsIsNotAckedAndLeavesNothingBehind() async throws {
        relay.add("a", "Water the plants #Garden")
        var failing = true
        let inbox = StreamInbox(container: container, defaults: defaults, keyStore: MemoryInboxKey(), client: relay.client,
                                storeIsReal: { true },
                                addTask: { text, now, context in
                                    if failing {
                                        let group = Project(name: "Garden")
                                        context.insert(group)
                                        context.insert(TaskItem(title: "Water the plants", project: group))
                                        throw SaveFailed()
                                    }
                                    return try StreamInbox.addThroughQuickAdd(text, now, context)
                                },
                                log: { _, _ in })
        _ = await inbox.connect(linkText: relay.link, checkAfter: false)
        let context = container.mainContext
        context.insert(TaskItem(title: "George's unsaved draft"))
        var result = await inbox.check(.checkNow)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(relay.acks, [], "nothing handled, nothing acked")
        XCTAssertEqual(relay.waitingIDs, ["a"])
        XCTAssertEqual(context.insertedModelsArray.count, 1, "only George's draft waits to be saved")
        try context.save()
        XCTAssertEqual(try tasks().map(\.title), ["George's unsaved draft"], "a later save writes nothing of the capture")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).filter { $0.name == "Garden" }.count, 0, "nor its Group")
        failing = false
        result = await inbox.check(.checkNow)
        XCTAssertEqual(result.added, 1, "offered again to this device at once (its own claim), and saved this time")
        XCTAssertEqual(relay.acks, [["a"]])
        XCTAssertNil(inbox.problem)
        XCTAssertEqual(try tasks().map(\.title), ["George's unsaved draft", "Water the plants"], "once")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Project>()).filter { $0.name == "Garden" }.count, 1)
    }

    /// Review finding 5, the kill window: a task saved, then the app killed before the capture's id was written down.
    /// The note made before the save finds the task by its title and time, so the capture is acked, not added again.
    func testAKillBetweenTheSaveAndItsNoteAddsNothingTwice() async throws {
        relay.add("k", "Book the car service")
        let inbox = try await connected()
        let started = Date()
        _ = try StreamInbox.addThroughQuickAdd("Book the car service", started, container.mainContext)
        StreamInboxSettings(defaults: defaults).addingNow = .init(id: "k", title: "Book the car service", startedAt: started)
        let result = await inbox.check(.checkNow)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(try tasks().map(\.title), ["Book the car service"], "one task, not two")
        XCTAssertEqual(relay.acks, [["k"]])
        XCTAssertNil(StreamInboxSettings(defaults: defaults).addingNow, "the note is cleared")
    }

    func testARelayThatIsDownLeavesEverythingForNextTimeAndSaysSo() async throws {
        relay.add("a", "Buy milk")
        let inbox = try await connected()
        relay.isDown = true
        let result = await inbox.check(.checkNow)
        XCTAssertEqual(result.problem, .unreachable)
        XCTAssertEqual(inbox.problem?.words, "Couldn't reach your relay. Captures wait there for next time.")
        XCTAssertEqual(try tasks().count, 0)
        XCTAssertEqual(relay.acks, [])
        XCTAssertEqual(relay.waitingIDs, ["a"])
        XCTAssertTrue(logged.contains { $0.contains("Couldn't reach your relay") }, "said once in the log")
        relay.isDown = false
        await inbox.check(.checkNow)
        XCTAssertEqual(try tasks().map(\.title), ["Buy milk"])
        XCTAssertNil(inbox.problem)
    }

    func testNothingIsTakenWhileTheStoreCouldNotBeOpened() async throws {
        relay.add("a", "Buy milk")
        let inbox = try await connected(storeIsReal: false)
        let result = await inbox.check(.checkNow)
        XCTAssertEqual(result.problem, .storeUnavailable)
        XCTAssertFalse(relay.requests.contains { $0.path == InboxAPI.Endpoint.claim.rawValue },
                       "an in-memory store is thrown away at quit: nothing is claimed into it")
        XCTAssertEqual(relay.waitingIDs, ["a"])
    }

    // MARK: Connecting

    func testConnectingAsksTheRelayFirst() async throws {
        let inbox = inbox()
        let notALink = await inbox.connect(linkText: "hello", checkAfter: false)
        XCTAssertEqual(notALink, .notALink)
        XCTAssertEqual(StreamInboxProblem.notALink.words, "That isn't an inbox link")
        let wrongKey = "https://\(relay.host)/#\(String(repeating: "0", count: 64))"
        let refused = await inbox.connect(linkText: wrongKey, checkAfter: false)
        XCTAssertEqual(refused, .keyRefused)
        XCTAssertFalse(inbox.isConnected)
        relay.isDown = true
        let unreachable = await inbox.connect(linkText: relay.link, checkAfter: false)
        XCTAssertEqual(unreachable, .unreachable)
        XCTAssertFalse(inbox.isConnected)
        XCTAssertNil(defaults.string(forKey: StreamInboxSettings.originKey), "nothing kept until the relay said yes")
        relay.isDown = false
        let connected = await inbox.connect(linkText: relay.link, checkAfter: false)
        XCTAssertNil(connected)
        XCTAssertTrue(inbox.isConnected)
        XCTAssertEqual(defaults.string(forKey: StreamInboxSettings.originKey), "https://\(relay.host)")
        XCTAssertEqual(inbox.relayStatus?.stream?.connected, nil, "this fake has no Stream connection")
        XCTAssertEqual(relay.requests.last?.authorization, "Bearer \(relay.key)")
        XCTAssertFalse(relay.requests.contains { $0.path.contains(relay.key) }, "the key never rides in a URL")

        inbox.disconnect()
        XCTAssertFalse(inbox.isConnected)
        XCTAssertNil(inbox.link)
        XCTAssertNil(defaults.string(forKey: StreamInboxSettings.originKey))
        let checked = await inbox.check(.checkNow)
        XCTAssertFalse(checked.ran, "nothing is asked once disconnected")
    }

    func testAConnectionComesBackAtTheNextLaunchAndEachDeviceHasItsOwnID() async throws {
        let keys = MemoryInboxKey()
        let first = StreamInbox(container: container, defaults: defaults, keyStore: keys, client: relay.client, log: { _, _ in })
        _ = await first.connect(linkText: relay.link, checkAfter: false)
        let again = StreamInbox(container: container, defaults: defaults, keyStore: keys, client: relay.client, log: { _, _ in })
        XCTAssertTrue(again.isConnected)
        XCTAssertEqual(again.link, first.link)
        XCTAssertEqual(again.deviceID, first.deviceID, "made once")
        #if os(macOS)
        XCTAssertTrue(first.deviceID.hasPrefix("Mac-"))
        #else
        XCTAssertTrue(first.deviceID.hasPrefix("iPhone-") || first.deviceID.hasPrefix("iPad-"))
        #endif
        let restored = StreamInbox(container: container, defaults: defaults, keyStore: MemoryInboxKey(), client: relay.client,
                                   log: { _, _ in })
        XCTAssertNil(restored.link, "an address whose key isn't on this device is forgotten when the key is first wanted")
        XCTAssertFalse(restored.isConnected)
        XCTAssertNil(defaults.string(forKey: StreamInboxSettings.originKey))
    }

    /// `StreamInbox.start` runs in `App.init`: the Keychain waits for the first check, and is read once.
    func testTheKeychainIsReadWhenTheKeyIsFirstWantedAndOnce() async throws {
        final class CountingKey: StreamInboxKeyStore {
            var reads = 0
            let key: String
            init(_ key: String) { self.key = key }
            func read() -> StreamInboxKeyRead { reads += 1; return .found(key) }
            func save(_ key: String) throws {}
            func remove() {}
        }
        let keys = CountingKey(relay.key)
        defaults.set("https://\(relay.host)", forKey: StreamInboxSettings.originKey)
        let inbox = StreamInbox(container: container, defaults: defaults, keyStore: keys, client: relay.client,
                                storeIsReal: { true }, log: { _, _ in })
        XCTAssertEqual(keys.reads, 0, "nothing read while the app is being made")
        XCTAssertTrue(inbox.isConnected)
        relay.add("a", "Buy milk")
        await inbox.check(.checkNow)
        await inbox.check(.checkNow)
        XCTAssertEqual(keys.reads, 1)
        XCTAssertEqual(try tasks().map(\.title), ["Buy milk"])
    }

    func testATestCaptureArrivesAsATask() async throws {
        let inbox = try await connected()
        _ = await inbox.setOnlyStartingWithTask(true)
        let sent = await inbox.sendTest()
        XCTAssertNil(sent)
        XCTAssertEqual(try tasks().map(\.title), [InboxAPI.testText])
    }

    func testTwoDevicesNeverBothTakeOne() async throws {
        relay.add("a", "Buy milk")
        let otherDefaults = try XCTUnwrap(UserDefaults(suiteName: suite + ".other"))
        defer { otherDefaults.removePersistentDomain(forName: suite + ".other") }
        let mac = try await connected()
        let otherContainer = ModelContainerFactory.preview()
        let phone = StreamInbox(container: otherContainer, defaults: otherDefaults, keyStore: MemoryInboxKey(),
                                client: relay.client, storeIsReal: { true }, log: { _, _ in })
        _ = await phone.connect(linkText: relay.link, checkAfter: false)
        XCTAssertNotEqual(mac.deviceID, phone.deviceID)
        relay.acksFail = true
        await mac.check(.checkNow)
        relay.acksFail = false
        let phoneResult = await phone.check(.checkNow)
        XCTAssertEqual(phoneResult.added, 0, "held for the Mac an hour")
        XCTAssertEqual(try otherContainer.mainContext.fetch(FetchDescriptor<TaskItem>()).count, 0)
    }

    // MARK: Reminders

    func testAReminderFromACaptureIsScheduledLikeAnyOther() async throws {
        relay.add("a", "Call the dentist tomorrow at 9am")
        let inbox = try await connected()
        var reasons: [String] = []
        let observers = NotificationScheduler.observeTriggers { reasons.append($0) }
        defer { observers.forEach(NotificationCenter.default.removeObserver) }
        await inbox.check(.checkNow)
        XCTAssertTrue(reasons.contains("local change"), "the scheduler hears the save, as for a task typed on the card")
        let task = try task("Call the dentist")
        let now = Date()
        let plan = NotificationPlan.make(tasks: [NotificationPlan.Item(task, now: now)], now: now)
        let request = try XCTUnwrap(plan.requests.first { $0.taskID == task.id })
        XCTAssertEqual(request.kind, .due)
        XCTAssertEqual(request.triggerDate, task.dueDate)
    }

    // MARK: The Keychain

    func testTheKeyIsKeptInTheKeychainForThisDeviceOnly() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["HITLIST_UNSIGNED"] != nil, "unsigned builds have no keychain access")
        let store = KeychainInboxKey(account: "xctest-\(UUID().uuidString)")
        defer { store.remove() }
        XCTAssertEqual(store.read(), .notFound)
        try store.save("first-key-0123456789")
        try store.save("second-key-0123456789")
        XCTAssertEqual(store.read(), .found("second-key-0123456789"), "a new key replaces the old")
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: KeychainInboxKey.service,
                                    kSecAttrAccount as String: store.account,
                                    kSecReturnAttributes as String: true]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        var attributes: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &attributes), errSecSuccess)
        let accessible = (attributes as? [String: Any])?[kSecAttrAccessible as String] as? String
        XCTAssertEqual(accessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertNotEqual(KeychainInboxKey().account, store.account, "each store's key is its own")
        store.remove()
        XCTAssertEqual(store.read(), .notFound)
        XCTAssertEqual(StreamInboxKeyRead(status: errSecInteractionNotAllowed, data: nil), .unavailable(errSecInteractionNotAllowed),
                       "a locked Keychain is not a missing key")
    }

    // MARK: Review of 18e36cb8

    /// Finding 1: a capture said at 22:30 and taken at 07:45 means "tomorrow" as of 22:30.
    func testACaptureIsReadAsOfWhenItWasSaid() async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastNight = today.addingTimeInterval(-90 * 60)
        relay.add("late", "Call the dentist tomorrow at 9am", said: lastNight)
        relay.add("ahead", "Buy milk tomorrow", said: Date().addingTimeInterval(3 * 86_400))
        let inbox = try await connected()
        await inbox.check(.checkNow)
        XCTAssertEqual(try task("Call the dentist").dueDate, calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today),
                       "tomorrow, as of the evening it was said: today")
        XCTAssertEqual(try task("Buy milk").dueDate.map(calendar.startOfDay), calendar.date(byAdding: .day, value: 1, to: today),
                       "a time ahead of now is read as now")
    }

    /// Finding 3: the relay's own trouble (an answer it couldn't read, a webhook body it couldn't read, a sign-in it can't
    /// renew) is said on the status line while connected, not only behind the gesture.
    func testTheRelaysTroubleIsSaidOnTheStatusLine() async throws {
        let inbox = try await connected()
        XCTAssertNil(inbox.relayTrouble)
        relay.setStream(connected: true, approvedAt: Date(), lastPollAt: Date(),
                        lastError: "Stream's answer couldn't be read: the relay found no list of interactions in it.")
        await inbox.refreshStatus()
        let trouble = try XCTUnwrap(inbox.relayTrouble)
        XCTAssertTrue(trouble.contains("couldn't be read"), trouble)
        let line = StreamRingWords.status(problem: nil, relayTrouble: trouble, source: .everyMinute, lastCapture: nil,
                                          addedToday: 0, wake: nil, now: Date())
        XCTAssertTrue(line.contains("couldn't be read"), line)
        relay.setStream(connected: true, approvedAt: Date(), lastPollAt: Date(), lastError: nil, refreshable: false)
        await inbox.refreshStatus()
        XCTAssertEqual(inbox.relayTrouble, StreamRingWords.notRenewable)
        relay.setStream(connected: false, approvedAt: Date(), lastPollAt: Date())
        relay.setWebhook(result: "invalid")
        await inbox.refreshStatus()
        XCTAssertEqual(inbox.relayTrouble, StreamRingWords.webhookUnreadable)
    }

    /// Finding 8: the rule is the relay's, one for every device; the switch writes it there, and every claim brings it.
    func testTheRuleLivesOnTheRelayForEveryDevice() async throws {
        let mac = try await connected()
        let otherDefaults = try XCTUnwrap(UserDefaults(suiteName: suite + ".phone"))
        defer { otherDefaults.removePersistentDomain(forName: suite + ".phone") }
        let otherContainer = ModelContainerFactory.preview()
        let phone = StreamInbox(container: otherContainer, defaults: otherDefaults, keyStore: MemoryInboxKey(),
                                client: relay.client, storeIsReal: { true }, log: { _, _ in })
        _ = await phone.connect(linkText: relay.link, checkAfter: false)
        let written = await mac.setOnlyStartingWithTask(true)
        XCTAssertNil(written)
        XCTAssertTrue(mac.onlyStartingWithTask)
        XCTAssertEqual(relay.settings.onlyStartingWithTask, true, "kept by the relay")
        XCTAssertFalse(phone.onlyStartingWithTask, "the iPhone hasn't asked yet")
        relay.add("p", "Remember where I parked")
        relay.add("t", "Task: buy stamps")
        await phone.check(.checkNow)
        XCTAssertTrue(phone.onlyStartingWithTask, "the claim brought the relay's rule")
        XCTAssertEqual(try otherContainer.mainContext.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Buy stamps"],
                       "and the iPhone follows it at once")
    }

    /// Finding 9: a Keychain that can't be read yet (before the first unlock after a restart) is not a missing key.
    func testALockedKeychainIsNotADisconnect() async throws {
        final class LockedOnce: StreamInboxKeyStore {
            var locked = true
            let key: String
            init(_ key: String) { self.key = key }
            func read() -> StreamInboxKeyRead { locked ? .unavailable(errSecInteractionNotAllowed) : .found(key) }
            func save(_ key: String) throws {}
            func remove() {}
        }
        let keys = LockedOnce(relay.key)
        defaults.set("https://\(relay.host)", forKey: StreamInboxSettings.originKey)
        let inbox = StreamInbox(container: container, defaults: defaults, keyStore: keys, client: relay.client,
                                storeIsReal: { true }, log: { _, _ in })
        relay.add("a", "Buy milk")
        let locked = await inbox.check(.checkNow)
        XCTAssertEqual(locked.problem, .keyUnavailable)
        XCTAssertTrue(inbox.isConnected, "the relay isn't forgotten")
        XCTAssertNotNil(defaults.string(forKey: StreamInboxSettings.originKey))
        XCTAssertFalse(StreamInboxProblem.keyUnavailable.words.isEmpty)
        keys.locked = false
        let unlocked = await inbox.check(.checkNow)
        XCTAssertEqual(unlocked.added, 1)
    }

    /// Minor: a check in the background (a cold launch for a push or a refresh) doesn't spend its seconds on the relay's
    /// status.
    func testABackgroundCheckDoesNotAskForTheStatus() async throws {
        let inbox = try await connected(active: false)
        let before = relay.requests.count
        relay.add("a", "Buy milk")
        await inbox.check(.launch)
        let paths = relay.requests.dropFirst(before).map(\.path)
        XCTAssertFalse(paths.contains(InboxAPI.Endpoint.status.rawValue), "\(paths)")
        XCTAssertEqual(try tasks().map(\.title), ["Buy milk"])
    }

    // MARK: Wake-ups

    func testThePushTokenTravelsWithEachClaim() async throws {
        let inbox = try await connected(pushEnvironment: .production)
        StreamInbox.pushTokenArrived(Data([0xAB, 0x12, 0x00, 0xFF]), defaults: defaults)
        await inbox.check(.checkNow)
        let claim = try XCTUnwrap(relay.requests.last { $0.path == InboxAPI.Endpoint.claim.rawValue })
        let push = try XCTUnwrap(claim.json["push"] as? [String: String])
        XCTAssertEqual(push["token"], "ab1200ff")
        XCTAssertEqual(push["environment"], "production", "the push service the build's signed profile names")
        #if os(macOS)
        XCTAssertEqual(push["platform"], "macOS")
        #else
        XCTAssertTrue(["iOS", "iPadOS"].contains(push["platform"] ?? ""))
        #endif
    }

    /// A wake-up push (`{"hitlist":{"inbox":1}}`) runs one check and answers only once it has finished; a push for
    /// anything else (CloudKit's, the engine's) isn't the inbox's.
    func testAWakePushRunsOneCheckAndAnswersAfterIt() async throws {
        XCTAssertTrue(StreamInbox.isWakePush(["aps": ["content-available": 1], "hitlist": ["inbox": 1]]))
        XCTAssertFalse(StreamInbox.isWakePush(["aps": ["content-available": 1], "ck": ["ce": 1]]), "CloudKit's push")
        XCTAssertFalse(StreamInbox.isWakePush(["aps": ["content-available": 1]]))
        relay.add("a", "Buy milk")
        let inbox = try await connected()
        let claims = relay.requests.filter { $0.path == InboxAPI.Endpoint.claim.rawValue }.count
        let first = await inbox.handleWakePush()
        XCTAssertEqual(first, .newData)
        XCTAssertEqual(relay.requests.filter { $0.path == InboxAPI.Endpoint.claim.rawValue }.count, claims + 1, "one check")
        XCTAssertEqual(try tasks().map(\.title), ["Buy milk"], "made before the handler answered")
        let second = await inbox.handleWakePush()
        XCTAssertEqual(second, .noData, "nothing more waited")
        relay.isDown = true
        let third = await inbox.handleWakePush()
        XCTAssertEqual(third, .failed)
    }

    // MARK: Round 3

    /// Finding 3a: the push service a token belongs to is read from the build's signed entitlement, not from whether
    /// it is a Debug build: a Release build signed for development (an Xcode Run in Release, as George's speed probes
    /// are) has a development token, and the relay sent it to the wrong service.
    func testThePushServiceIsReadFromTheSignedProfile() {
        func profile(_ entitlements: String) -> Data {
            var data = Data([0x30, 0x82, 0x0F, 0x1A, 0x06, 0x09, 0x2A, 0x86])  // the signature's wrapper around the plist
            data.append(Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0"><dict><key>Name</key><string>HITList</string>\
                <key>Entitlements</key><dict>\(entitlements)</dict></dict></plist>
                """.utf8))
            data.append(Data([0x00, 0xA0, 0x82, 0x0B, 0xFF]))
            return data
        }
        let phoneDevelopment = profile("<key>aps-environment</key><string>development</string>")
        let macDevelopment = profile("<key>com.apple.developer.aps-environment</key><string>development</string>")
        let production = profile("<key>aps-environment</key><string>production</string>")
        XCTAssertEqual(StreamInbox.pushEnvironment(profile: phoneDevelopment, isSimulator: false), .development)
        XCTAssertEqual(StreamInbox.pushEnvironment(profile: macDevelopment, isSimulator: false), .development)
        XCTAssertEqual(StreamInbox.pushEnvironment(profile: production, isSimulator: false), .production)
        XCTAssertEqual(StreamInbox.pushEnvironment(profile: nil, isSimulator: false), .production,
                       "TestFlight and the App Store carry no profile")
        XCTAssertEqual(StreamInbox.pushEnvironment(profile: Data("not a profile".utf8), isSimulator: false), .production)
        XCTAssertEqual(StreamInbox.pushEnvironment(profile: profile(""), isSimulator: false), .production, "no push entitlement")
        XCTAssertEqual(StreamInbox.pushEnvironment(profile: nil, isSimulator: true), .development, "the simulator's tokens")
    }

    /// Finding 3b: "wakes this iPhone when you speak" only once Apple has taken a push for this device; a registered
    /// token alone is "wake-ups not confirmed yet"; a refused one says why.
    func testTheStatusLineSaysWakeUpsOnlyOnceAppleTookOne() async throws {
        relay.pushConfigured = true
        let inbox = try await connected()
        StreamInbox.pushTokenArrived(Data(repeating: 0xAB, count: 32), defaults: defaults)
        await inbox.check(.checkNow)
        XCTAssertEqual(inbox.wakeWords(for: "iPhone"), StreamRingWords.wakeUnconfirmed, "registered, never woken")
        relay.setWake(device: inbox.deviceID, okAt: Date().addingTimeInterval(-120))
        await inbox.check(.checkNow)
        XCTAssertEqual(inbox.wakeWords(for: "iPhone"), StreamRingWords.wakeOn("iPhone"), "Apple took one two minutes ago")
        let refused = "Apple refused its push token at both of its push services (BadDeviceToken); it isn't woken until HITList on it gives a new one."
        relay.setWake(device: inbox.deviceID, error: refused, refused: true)
        await inbox.check(.checkNow)
        XCTAssertEqual(inbox.wakeWords(for: "iPhone"), StreamRingWords.wakeTrouble("iPhone", refused))
    }
}
