import XCTest
import SwiftData
import SwiftUI
import HITListCore
@testable import HITList

/// The Claude connector (brief 43): settings, the endpoint's gate (token, switch), the message port in the
/// app's sandbox.
@MainActor
final class ClaudeConnectorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ClaudeConnectorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: Settings

    func testSettingsDefaultToOffAndOnlyTasksWithClaude() {
        let settings = ClaudeSettings(defaults: defaults, storeSuffix: nil)
        XCTAssertFalse(settings.isAllowed, "off until George turns it on")
        XCTAssertEqual(settings.rule, ClaudeAccessRule(mode: .onlyShared, hiddenLabel: "private", sharedLabel: "claude"))
    }

    func testSettingsAreKeptPerStore() {
        let main = ClaudeSettings(defaults: defaults, storeSuffix: nil)
        let debug = ClaudeSettings(defaults: defaults, storeSuffix: "Development")
        XCTAssertEqual(main.allowedKey, "claude.allowed", "the helper reads this name")
        XCTAssertEqual(debug.allowedKey, "claude.allowed.Development")
        debug.isAllowed = true
        debug.rule = ClaudeAccessRule(mode: .allExceptHidden, hiddenLabel: "@home")
        XCTAssertFalse(main.isAllowed, "a Debug build's switch never opens the TestFlight app's tasks")
        XCTAssertEqual(main.rule.mode, .onlyShared)
        XCTAssertEqual(debug.rule, ClaudeAccessRule(mode: .allExceptHidden, hiddenLabel: "home"))
    }

    // MARK: The endpoint's gate

    private func request(token: String?, tool: String = "list_tasks") throws -> Data {
        try JSONEncoder().encode(ClaudeWire.Request(token: token, tool: tool, arguments: ["filter": "today"]))
    }

    private func endpoint(allowed: Bool = true, ran: @escaping (String) -> Void = { _ in }) -> ClaudeEndpoint {
        ClaudeEndpoint(token: "right-token", isAllowed: { allowed }) { tool, arguments in
            ran(tool)
            return MCPToolResult(text: "ran \(tool) \(arguments["filter"]?.stringValue ?? "")")
        }
    }

    func testNoTokenIsRefused() throws {
        var ran = false
        let result = endpoint(ran: { _ in ran = true }).result(for: try request(token: nil))
        XCTAssertEqual(result.code, ClaudeWire.Refusal.unauthorized.rawValue)
        XCTAssertTrue(result.isError)
        XCTAssertFalse(ran)
    }

    func testWrongTokenIsRefused() throws {
        var ran = false
        let gate = endpoint(ran: { _ in ran = true })
        for token in ["wrong-token", "right-toke", "right-token!", "", "RIGHT-TOKEN"] {
            XCTAssertEqual(gate.result(for: try request(token: token)).code, ClaudeWire.Refusal.unauthorized.rawValue, token)
        }
        XCTAssertFalse(ran)
    }

    func testAccessOffIsRefusedEvenWithTheToken() throws {
        var ran = false
        let result = endpoint(allowed: false, ran: { _ in ran = true }).result(for: try request(token: "right-token"))
        XCTAssertEqual(result.code, ClaudeWire.Refusal.accessOff.rawValue)
        XCTAssertEqual(result.text, ClaudeWire.accessOffMessage)
        XCTAssertFalse(ran)
    }

    func testTheRightTokenRunsTheTool() throws {
        var ran: String?
        let result = endpoint(ran: { ran = $0 }).result(for: try request(token: "right-token"))
        XCTAssertEqual(ran, "list_tasks")
        XCTAssertEqual(result, MCPToolResult(text: "ran list_tasks today"))
    }

    func testJunkIsABadRequest() {
        XCTAssertEqual(endpoint().result(for: Data("{".utf8)).code, ClaudeWire.Refusal.badRequest.rawValue)
    }

    func testTokenComparison() {
        XCTAssertTrue(ClaudeEndpoint.matches("abc", "abc"))
        XCTAssertFalse(ClaudeEndpoint.matches("abd", "abc"))
        XCTAssertFalse(ClaudeEndpoint.matches("", ""), "an empty token never matches")
    }

    func testTokenFileIsOwnerOnly() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "claude-\(UUID().uuidString)/token")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try ClaudeConnector.writeToken("abc", to: url)
        try ClaudeConnector.writeToken("def", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "def")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    // MARK: The port, in the app's own sandbox

    #if os(macOS)
    /// Sends through the real port from a background thread while the main run loop serves it.
    private func sendThroughPort(_ data: Data, to name: String) -> Result<Data, ClaudePortClient.Failure>? {
        let done = expectation(description: "reply")
        var result: Result<Data, ClaudePortClient.Failure>?
        DispatchQueue.global().async {
            result = ClaudePortClient.send(data, to: name, replyTimeout: 10)
            done.fulfill()
        }
        wait(for: [done], timeout: 15)
        return result
    }

    func testThePortInTheAppGroupCarriesCallsThroughTheGate() throws {
        let name = ClaudeWire.portName(groupID: AppGroup.id, storeSuffix: "tests\(UInt32.random(in: 0 ... .max))")
        let gate = endpoint()
        let server = try XCTUnwrap(ClaudePortServer(name: name) { data in MainActor.assumeIsolated { gate.respond(to: data) } },
                                   "the sandbox lets the app register names inside its app group")
        defer { server.invalidate() }

        let refused = try JSONDecoder().decode(MCPToolResult.self, from: XCTUnwrap(sendThroughPort(try request(token: "nope"), to: name)?.get()))
        XCTAssertEqual(refused.code, ClaudeWire.Refusal.unauthorized.rawValue)
        let answered = try JSONDecoder().decode(MCPToolResult.self, from: XCTUnwrap(sendThroughPort(try request(token: "right-token"), to: name)?.get()))
        XCTAssertEqual(answered.text, "ran list_tasks today")

        server.invalidate()
        XCTAssertEqual(sendThroughPort(Data(), to: name), .failure(.notFound), "closed means gone, not refusing")
    }

    func testThePortCannotBeOpenedOutsideTheAppGroup() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["HITLIST_UNSIGNED"] != nil, "unsigned builds run without the sandbox")
        XCTAssertNil(ClaudePortServer(name: "com.example.claude.\(UUID().uuidString.prefix(8))") { $0 },
                     "the sandbox refuses names outside the app group, so nothing but HITList's group can listen or call")
    }
    #endif
}

/// The connector's tools against an in-memory store through the app-side handler (brief 43). Fixed clock:
/// Wednesday 2026-11-04 10:00 in New York.
@MainActor
final class ClaudeToolTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var logged: [(String, [String: String])] = []
    private var completed: [CompletedTask] = []
    private var writes = 0
    private var ids: [String: UUID] = [:]

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!
    private static var today: Date { calendar.startOfDay(for: now) }

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        let errand = TaskLabel(name: "errand"), secret = TaskLabel(name: "private"), shared = TaskLabel(name: "claude")
        let travel = Project(name: "Travel"), hidden = Project(name: "Therapy"), empty = Project(name: "Someday")
        [errand, secret, shared].forEach(context.insert)
        [travel, hidden, empty].forEach(context.insert)
        func add(_ title: String, project: Project? = nil, labels: [TaskLabel] = [], due: Date? = nil, priority: Int = 4) -> TaskItem {
            let task = TaskItem(title: title, priority: priority, dueDate: due, project: project, labels: labels)
            context.insert(task)
            ids[title] = task.id
            return task
        }
        _ = add("Buy milk", labels: [errand], due: Self.today)
        _ = add("Session notes", project: hidden, labels: [secret], due: Self.today, priority: 1)
        let trip = add("Plan trip", project: travel, priority: 2)
        _ = add("Shared idea", labels: [shared])
        let done = add("Old thing")
        done.isCompleted = true
        done.completedAt = Self.now
        let water = add("Water plants", due: Self.today)
        water.recurrenceRule = .daily
        let secretParent = add("Gift for G", labels: [secret])
        try context.save()
        let flights = try TaskActions.addSubtask("Book flights", to: trip, in: context)
        ids["Book flights"] = flights.id
        let wrap = try TaskActions.addSubtask("Wrap it", to: secretParent, in: context)
        ids["Wrap it"] = wrap.id
        logged = []; completed = []; writes = 0
    }

    override func tearDown() async throws { container = nil }

    private let hiddenTitles = ["Session notes", "Gift for G", "Wrap it", "Therapy", "private"]

    /// The tool tests are about hiding @private tasks: they use "All tasks but @private" unless they say otherwise.
    private static let allBut = ClaudeAccessRule(mode: .allExceptHidden)

    private func handler(_ rule: ClaudeAccessRule = allBut) -> ClaudeToolHandler {
        ClaudeToolHandler(context: context, rule: rule, now: Self.now, calendar: Self.calendar, weekStart: 2,
                          log: { [unowned self] in logged.append(($0, $1)) },
                          didWrite: { [unowned self] in writes += 1 },
                          didComplete: { [unowned self] in completed.append($0) })
    }

    private func call(_ tool: String, _ arguments: [String: JSONValue] = [:], rule: ClaudeAccessRule = allBut) throws -> (MCPToolResult, JSONValue) {
        let result = handler(rule).call(tool, arguments)
        return (result, (try? JSONValue.decode(Data(result.text.utf8))) ?? .null)
    }

    private func titles(_ json: JSONValue) -> [String] {
        json["tasks"]?.arrayValue?.compactMap { $0["title"]?.stringValue } ?? []
    }

    private func assertNoHiddenText(_ result: MCPToolResult, file: StaticString = #filePath, line: UInt = #line) {
        for hidden in hiddenTitles {
            XCTAssertFalse(result.text.localizedCaseInsensitiveContains(hidden), "\"\(hidden)\" leaked", file: file, line: line)
        }
    }

    private func fetch(_ title: String) throws -> TaskItem {
        let id = try XCTUnwrap(ids[title])
        return try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
    }

    // MARK: list_tasks

    func testListShowsOpenVisibleTasksOnly() throws {
        let (result, json) = try call(ClaudeTools.listTasks)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(titles(json), ["Buy milk", "Water plants", "Plan trip", "Shared idea"])
        XCTAssertEqual(json["total"], 4, "hidden tasks aren't counted")
        XCTAssertEqual(json["today"], "2026-11-04")
        assertNoHiddenText(result)
        let trip = try XCTUnwrap(json["tasks"]?.arrayValue?.first { $0["title"] == "Plan trip" })
        XCTAssertEqual(trip["group"], "Travel")
        XCTAssertEqual(trip["priority"], 2)
        XCTAssertEqual(trip["subtasks_done"], "0 of 1")
        let milk = try XCTUnwrap(json["tasks"]?.arrayValue?.first)
        XCTAssertEqual(milk["due"], "2026-11-04")
        XCTAssertEqual(milk["labels"], ["errand"])
        XCTAssertEqual(milk["group"], "Inbox")
        XCTAssertEqual(try XCTUnwrap(json["tasks"]?.arrayValue?[1])["repeats"], .string(RecurrenceRule.daily.displayText))
    }

    func testHiddenTasksCannotBeSearchedOrFiltered() throws {
        for filter in ["@private", "#Therapy", "search: session", "\"gift\"", "p1", "today & p1", "completed"] {
            let (result, json) = try call(ClaudeTools.listTasks, ["filter": .string(filter), "include_completed": true])
            XCTAssertFalse(result.isError, filter)
            XCTAssertFalse(titles(json).contains { hiddenTitles.contains($0) }, filter)
            // The reply echoes the filter Claude sent; everything else must hold nothing hidden.
            assertNoHiddenText(MCPToolResult(text: (json["tasks"] ?? .null).prettyString()))
        }
        XCTAssertEqual(titles(try call(ClaudeTools.listTasks, ["filter": "today"]).1), ["Buy milk", "Water plants"])
    }

    func testCompletedTasksOnlyWhenAsked() throws {
        XCTAssertEqual(titles(try call(ClaudeTools.listTasks, ["filter": "completed"]).1), ["Old thing"])
        XCTAssertEqual(try call(ClaudeTools.listTasks, ["include_completed": true]).1["total"], 5)
    }

    func testLimitAndBadFilters() throws {
        let (_, json) = try call(ClaudeTools.listTasks, ["limit": 1])
        XCTAssertEqual(json["returned"], 1)
        XCTAssertEqual(json["total"], 4)
        XCTAssertEqual(try call(ClaudeTools.listTasks, ["limit": 0]).1["returned"], 1, "clamped to at least one")
        let (bad, _) = try call(ClaudeTools.listTasks, ["filter": "today &"])
        XCTAssertTrue(bad.isError)
        XCTAssertTrue(bad.text.contains("didn't parse"))
    }

    // MARK: get_task

    func testHiddenIdsLookExactlyLikeMissingOnes() throws {
        let missing = try call(ClaudeTools.getTask, ["id": .string(UUID().uuidString)]).0
        XCTAssertTrue(missing.isError)
        for title in ["Session notes", "Gift for G", "Wrap it"] {
            for tool in [ClaudeTools.getTask, ClaudeTools.completeTask, ClaudeTools.updateTask] {
                var arguments: [String: JSONValue] = ["id": .string(try XCTUnwrap(ids[title]).uuidString)]
                if tool == ClaudeTools.updateTask { arguments["title"] = "Changed" }
                let result = try call(tool, arguments).0
                XCTAssertEqual(result, missing, "\(tool) on \(title)")
            }
        }
        XCTAssertFalse(try fetch("Gift for G").isCompleted)
        XCTAssertEqual(try fetch("Session notes").title, "Session notes")
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(logged.isEmpty)
    }

    func testGetTaskHasSubtasksAndTheParent() throws {
        let (_, trip) = try call(ClaudeTools.getTask, ["id": .string(try XCTUnwrap(ids["Plan trip"]).uuidString)])
        XCTAssertEqual(trip["subtasks"]?.arrayValue?.first?["title"], "Book flights")
        let (_, flights) = try call(ClaudeTools.getTask, ["id": .string(try XCTUnwrap(ids["Book flights"]).uuidString)])
        XCTAssertEqual(flights["parent"]?["title"], "Plan trip")
        XCTAssertEqual(try call(ClaudeTools.getTask, ["id": "not-a-uuid"]).0.isError, true)
    }

    // MARK: add_task

    func testAddParsesQuickAddTextLikeTheApp() throws {
        let (result, json) = try call(ClaudeTools.addTask, ["text": "Call mum tomorrow 5pm p1 #Family @phone",
                                                           "description": "  Ask about the weekend  "])
        XCTAssertFalse(result.isError, result.text)
        let added = try XCTUnwrap(json["added"])
        XCTAssertEqual(added["title"], "Call mum")
        XCTAssertEqual(added["priority"], 1)
        XCTAssertEqual(added["group"], "Family")
        XCTAssertEqual(added["labels"], ["phone"])
        XCTAssertEqual(added["due"], "2026-11-05T17:00:00-05:00")
        XCTAssertEqual(added["description"], "Ask about the weekend")
        let id = try XCTUnwrap(added["id"]?.stringValue.flatMap(UUID.init(uuidString:)))
        let task = try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(task.project?.name, "Family")
        XCTAssertTrue(task.hasDueTime)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(logged.map(\.0), ["Claude added a task"])
        XCTAssertEqual(logged.first?.1["task"], id.uuidString)
        XCTAssertFalse(logged.description.contains("Call mum"), "never task text in the log")
    }

    func testAddInOnlySharedModeKeepsTheTaskVisible() throws {
        let rule = ClaudeAccessRule(mode: .onlyShared)
        let (_, json) = try call(ClaudeTools.addTask, ["text": "Draft the plan @work"], rule: rule)
        XCTAssertEqual(json["added"]?["labels"], ["claude", "work"])
        XCTAssertNil(json["note"])
        XCTAssertEqual(titles(try call(ClaudeTools.listTasks, rule: rule).1), ["Shared idea", "Draft the plan"])
    }

    func testAddingAPrivateTaskSaysItIsNowHidden() throws {
        let (result, json) = try call(ClaudeTools.addTask, ["text": "Diary @private"])
        XCTAssertFalse(result.isError)
        XCTAssertNotNil(json["note"])
        XCTAssertFalse(titles(try call(ClaudeTools.listTasks).1).contains("Diary"))
    }

    func testAddNeedsATitle() throws {
        XCTAssertTrue(try call(ClaudeTools.addTask, ["text": "  "]).0.isError)
        XCTAssertTrue(try call(ClaudeTools.addTask, ["text": "tomorrow p1"]).0.isError)
        XCTAssertEqual(writes, 0)
    }

    // MARK: complete_task

    func testCompleteMarksDoneOffersUndoAndLogs() throws {
        let (result, json) = try call(ClaudeTools.completeTask, ["id": .string(try XCTUnwrap(ids["Plan trip"]).uuidString)])
        XCTAssertFalse(result.isError)
        XCTAssertEqual(json["completed"], true)
        XCTAssertTrue(try fetch("Plan trip").isCompleted)
        XCTAssertTrue(try fetch("Book flights").isCompleted, "its open subtasks complete with it, as in the app")
        XCTAssertEqual(completed.map(\.title), ["Plan trip"])
        XCTAssertEqual(completed.first?.revert, .uncomplete)
        XCTAssertEqual(logged.first?.1["tool"], "complete_task")
        XCTAssertTrue(try call(ClaudeTools.completeTask, ["id": .string(try XCTUnwrap(ids["Plan trip"]).uuidString)]).0.isError,
                      "already completed")
    }

    func testCompletingARepeatingTaskMovesItOn() throws {
        let (_, json) = try call(ClaudeTools.completeTask, ["id": .string(try XCTUnwrap(ids["Water plants"]).uuidString)])
        XCTAssertEqual(json["repeats"], true)
        XCTAssertEqual(json["next_due"], "2026-11-05")
        XCTAssertFalse(try fetch("Water plants").isCompleted)
        XCTAssertEqual(completed.first?.revert, .restoreDueDate(Self.today))
    }

    // MARK: update_task

    func testUpdateChangesEachField() throws {
        let id = JSONValue.string(try XCTUnwrap(ids["Buy milk"]).uuidString)
        let (result, json) = try call(ClaudeTools.updateTask, ["id": id, "title": "Buy oat milk", "description": "2 cartons",
                                                              "due": "fri 6pm", "priority": 3, "labels": ["@Shop", "errand"],
                                                              "group": "#Groceries"])
        XCTAssertFalse(result.isError, result.text)
        let task = try fetch("Buy milk")
        XCTAssertEqual(task.title, "Buy oat milk")
        XCTAssertEqual(task.notes, "2 cartons")
        XCTAssertEqual(json["updated"]?["due"], "2026-11-06T18:00:00-05:00")
        XCTAssertTrue(task.hasDueTime)
        XCTAssertEqual(task.priority, 3)
        XCTAssertEqual(task.labelList.map(\.name), ["Shop", "errand"])
        XCTAssertEqual(task.project?.name, "Groceries")
        XCTAssertEqual(logged.first?.1["fields"], "description,due,group,labels,priority,title")

        _ = try call(ClaudeTools.updateTask, ["id": id, "due": "none", "group": "Inbox"])
        XCTAssertNil(task.dueDate)
        XCTAssertFalse(task.hasDueTime)
        XCTAssertNil(task.project)
        _ = try call(ClaudeTools.updateTask, ["id": id, "due": "every monday 9am"])
        XCTAssertNotNil(task.recurrenceRule)
        XCTAssertTrue(task.hasDueTime)
    }

    /// Brief 127's scan: a reminder before the due time leans on the time. A due with no time takes it away, so the
    /// "minutes before" goes with it (stored, it would come back the day a time is set again); a reminder typed in the
    /// due phrase ("fri 6pm !30mb") is read, not dropped.
    func testUpdateKeepsRemindersHonestAboutTheTime() throws {
        let id = JSONValue.string(try XCTUnwrap(ids["Buy milk"]).uuidString)
        let task = try fetch("Buy milk")
        _ = try call(ClaudeTools.updateTask, ["id": id, "due": "fri 6pm !30mb"])
        XCTAssertTrue(task.hasDueTime)
        XCTAssertEqual(task.reminderOffsetMinutes, 30, "read with the time beside it")

        _ = try call(ClaudeTools.updateTask, ["id": id, "due": "sat 9am"])
        XCTAssertEqual(task.reminderOffsetMinutes, 30, "a new time keeps the reminder before it")

        _ = try call(ClaudeTools.updateTask, ["id": id, "due": "tomorrow"])
        XCTAssertFalse(task.hasDueTime)
        XCTAssertNil(task.reminderOffsetMinutes, "no time: nothing to count from")

        let (refused, _) = try call(ClaudeTools.updateTask, ["id": id, "due": "fri !30mb"])
        XCTAssertTrue(refused.isError, "no time beside it: not a date phrase")
    }

    func testABadFieldChangesNothing() throws {
        let id = JSONValue.string(try XCTUnwrap(ids["Buy milk"]).uuidString)
        for bad: [String: JSONValue] in [["title": "Renamed", "due": "someday maybe"], ["title": "Renamed", "priority": 7],
                                         ["title": ""], ["labels": "errand"], [:]] {
            var arguments = bad
            arguments["id"] = id
            XCTAssertTrue(try call(ClaudeTools.updateTask, arguments).0.isError, "\(bad)")
        }
        XCTAssertEqual(try fetch("Buy milk").title, "Buy milk")
        XCTAssertEqual(writes, 0)
    }

    func testSubtasksTakeOnlyTitleAndDescription() throws {
        let id = JSONValue.string(try XCTUnwrap(ids["Book flights"]).uuidString)
        XCTAssertTrue(try call(ClaudeTools.updateTask, ["id": id, "due": "tomorrow"]).0.isError)
        XCTAssertFalse(try call(ClaudeTools.updateTask, ["id": id, "title": "Book flights to Lisbon"]).0.isError)
        XCTAssertEqual(try fetch("Book flights").title, "Book flights to Lisbon")
    }

    func testOnlySharedModeKeepsTheSharedLabelOnUpdate() throws {
        let rule = ClaudeAccessRule(mode: .onlyShared)
        let id = JSONValue.string(try XCTUnwrap(ids["Shared idea"]).uuidString)
        _ = try call(ClaudeTools.updateTask, ["id": id, "labels": []], rule: rule)
        XCTAssertEqual(try fetch("Shared idea").labelList.map(\.name), ["claude"])
    }

    // MARK: Groups and labels

    func testGroupsAndLabelsNeverNameHiddenOnes() throws {
        let (groups, groupsJSON) = try call(ClaudeTools.listGroups)
        XCTAssertEqual(groupsJSON["groups"], [["name": "Inbox", "open_tasks": 3], ["name": "Someday", "open_tasks": 0],
                                              ["name": "Travel", "open_tasks": 1]], "Group order, then name")
        assertNoHiddenText(groups)
        let (labels, labelsJSON) = try call(ClaudeTools.listLabels)
        XCTAssertEqual(labelsJSON["labels"], [["name": "claude", "open_tasks": 1], ["name": "errand", "open_tasks": 1]])
        assertNoHiddenText(labels)
        let shared = try call(ClaudeTools.listLabels, rule: ClaudeAccessRule(mode: .onlyShared)).1
        XCTAssertEqual(shared["labels"], [["name": "claude", "open_tasks": 1]])
    }

    func testOnlySharedModeSeesOnlyClaudeTasks() throws {
        XCTAssertEqual(titles(try call(ClaudeTools.listTasks, rule: ClaudeAccessRule(mode: .onlyShared)).1), ["Shared idea"])
    }

    func testUnknownTool() {
        XCTAssertTrue(handler().call("delete_task", [:]).isError)
    }
}

/// "Copy for Claude" (brief 43): only what the privacy rule allows, in the backup's snapshot shape.
@MainActor
final class ClaudeExportTests: XCTestCase {
    func testExportHoldsOnlyVisibleTasksAndTheirGroupsAndLabels() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let secret = TaskLabel(name: "private"), home = TaskLabel(name: "home")
        let hiddenGroup = Project(name: "Therapy"), work = Project(name: "Work")
        [secret, home].forEach(context.insert)
        [hiddenGroup, work].forEach(context.insert)
        let open = TaskItem(title: "Ship it", project: work, labels: [home])
        let hidden = TaskItem(title: "Session notes", project: hiddenGroup, labels: [secret])
        [open, hidden].forEach(context.insert)
        context.insert(SavedFilter(name: "Secret", query: "@private"))
        try context.save()
        let visibleSub = try TaskActions.addSubtask("Tag release", to: open, in: context)
        _ = try TaskActions.addSubtask("Hidden step", to: hidden, in: context)

        let snapshot = try ClaudeExport.snapshot(from: context, rule: ClaudeAccessRule(mode: .allExceptHidden))
        XCTAssertEqual(Set(snapshot.tasks.map(\.title)), ["Ship it", "Tag release"])
        XCTAssertEqual(snapshot.tasks.first { $0.id == visibleSub.id }?.parentID, open.id)
        XCTAssertEqual(snapshot.projects.map(\.name), ["Work"])
        XCTAssertEqual(snapshot.labels.map(\.name), ["home"])
        XCTAssertTrue(snapshot.filters.isEmpty, "saved filters can name a hidden label")
        XCTAssertEqual(snapshot.deviceName, "HITList")

        let text = try ClaudeExport.text(for: snapshot)
        XCTAssertTrue(text.hasPrefix(ClaudeExport.schemaNote))
        for leak in ["Session notes", "Hidden step", "Therapy", "private", "Secret"] {
            XCTAssertFalse(text.contains(leak), leak)
        }
        let json = try XCTUnwrap(text.components(separatedBy: "```json\n").last?.components(separatedBy: "\n```").first)
        let decoded = try Snapshot.from(json: Data(json.utf8))  // the backup format, readable by Import
        XCTAssertEqual(decoded.tasks.map(\.id), snapshot.tasks.map(\.id))
        XCTAssertEqual(decoded.projects.map(\.name), ["Work"])

        let shared = try ClaudeExport.snapshot(from: context, rule: ClaudeAccessRule(mode: .onlyShared))
        XCTAssertTrue(shared.tasks.isEmpty, "nothing is labelled @claude yet")
        XCTAssertTrue(shared.labels.isEmpty)
    }

    // MARK: Setup snippets

    func testClaudeDesktopConfig() throws {
        let config = ClaudeSetup.desktopConfig(helperPath: "/Applications/HITList.app/Contents/MacOS/hitlist-mcp", storeSuffix: nil)
        let json = try JSONValue.decode(Data(config.utf8))
        XCTAssertEqual(json, ["mcpServers": ["hitlist": ["command": "/Applications/HITList.app/Contents/MacOS/hitlist-mcp"]]])
        let debug = try JSONValue.decode(Data(ClaudeSetup.desktopConfig(helperPath: "/x/hitlist-mcp", storeSuffix: "Development").utf8))
        XCTAssertEqual(debug["mcpServers"]?["hitlist"]?["args"], ["--store", "Development"])
    }

    func testClaudeCodeCommand() {
        XCTAssertEqual(ClaudeSetup.claudeCodeCommand(helperPath: "/Applications/HITList.app/Contents/MacOS/hitlist-mcp", storeSuffix: nil),
                       "claude mcp add --scope user hitlist -- /Applications/HITList.app/Contents/MacOS/hitlist-mcp")
        XCTAssertEqual(ClaudeSetup.claudeCodeCommand(helperPath: "/Users/g/My Builds/HITList.app/Contents/MacOS/hitlist-mcp",
                                                     storeSuffix: "Development"),
                       "claude mcp add --scope user hitlist -- '/Users/g/My Builds/HITList.app/Contents/MacOS/hitlist-mcp' --store Development")
        XCTAssertEqual(ClaudeSetup.shellQuoted("it's"), "'it'\\''s'")
    }

    #if os(macOS)
    func testTheHelperShipsInsideTheMacApp() {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: ClaudeSetup.helperURL.path),
                      "hitlist-mcp is embedded at HITList.app/Contents/MacOS")
    }
    #endif

    func testSettingsSectionRenders() {
        let container = ModelContainerFactory.preview()
        let view = ClaudeSettingsSection().modelContainer(container).frame(width: 600).preferredColorScheme(.dark)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }
}

