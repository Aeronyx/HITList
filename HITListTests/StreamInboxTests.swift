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

    private func inbox(failing: Set<String> = [], storeIsReal: Bool = true) -> StreamInbox {
        StreamInbox(container: container, defaults: defaults, keyStore: MemoryInboxKey(), client: relay.client,
                    storeIsReal: { storeIsReal },
                    addTask: { text, context in
                        if failing.contains(text) { throw SaveFailed() }
                        return try StreamInbox.addThroughQuickAdd(text, context)
                    },
                    log: { [weak self] line, _ in self?.logged.append(line) })
    }

    private func connected(failing: Set<String> = [], storeIsReal: Bool = true) async throws -> StreamInbox {
        let inbox = inbox(failing: failing, storeIsReal: storeIsReal)
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
        inbox.setOnlyStartingWithTask(true)
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
        inbox.setOnlyStartingWithTask(true)
        XCTAssertTrue(defaults.bool(forKey: StreamInboxSettings.onlyStartingWithTaskKey), "kept")
        let result = await inbox.check(.checkNow)
        XCTAssertEqual(try tasks().map(\.title), ["Book the car service"])
        XCTAssertEqual(result.skipped, 2)
        XCTAssertEqual(relay.acks, [["a", "b", "c"]], "the others are handed over too: they stay only in Stream")

        inbox.setOnlyStartingWithTask(false)
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

    func testASaveThatFailsIsNotAckedAndComesBack() async throws {
        relay.add("a", "Pay the water bill")
        var failing: Set<String> = ["Pay the water bill"]
        let inbox = StreamInbox(container: container, defaults: defaults, keyStore: MemoryInboxKey(), client: relay.client,
                                storeIsReal: { true },
                                addTask: { text, context in
                                    if failing.contains(text) { throw SaveFailed() }
                                    return try StreamInbox.addThroughQuickAdd(text, context)
                                },
                                log: { _, _ in })
        _ = await inbox.connect(linkText: relay.link, checkAfter: false)
        var result = await inbox.check(.checkNow)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(relay.acks, [], "nothing handled, nothing acked")
        XCTAssertEqual(relay.waitingIDs, ["a"])
        failing = []
        result = await inbox.check(.checkNow)
        XCTAssertEqual(result.added, 1, "offered again to this device at once (its own claim), and saved this time")
        XCTAssertEqual(relay.acks, [["a"]])
        XCTAssertNil(inbox.problem)
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
        XCTAssertFalse(restored.isConnected, "an address whose key isn't on this device is forgotten")
    }

    func testATestCaptureArrivesAsATask() async throws {
        let inbox = try await connected()
        inbox.setOnlyStartingWithTask(true)
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
        XCTAssertEqual(phoneResult.added, 0, "held for the Mac ten minutes")
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
        XCTAssertNil(store.read())
        try store.save("first-key-0123456789")
        try store.save("second-key-0123456789")
        XCTAssertEqual(store.read(), "second-key-0123456789", "a new key replaces the old")
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
        XCTAssertNil(store.read())
    }
}
