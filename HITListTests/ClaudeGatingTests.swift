import XCTest
import SwiftData
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 49: the Claude integration is off and quiet by default; its privacy choice, setup, Test connection and
/// Copy for Claude appear only once it is switched on, after a question that says what Claude will see and do.
@MainActor
final class ClaudeGatingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ClaudeGatingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: What Settings → Claude shows

    func testOffShowsOnlyTheSwitch() {
        XCTAssertEqual(ClaudeIntegration.parts(enabled: false, mac: true), [.master])
        XCTAssertEqual(ClaudeIntegration.parts(enabled: false, mac: false), [.master])
    }

    func testOnShowsThePrivacyChoiceAndTheTools() {
        XCTAssertEqual(ClaudeIntegration.parts(enabled: true, mac: true), [.master, .privacy, .export, .setup, .test])
        XCTAssertEqual(ClaudeIntegration.parts(enabled: true, mac: false), [.master, .privacy, .export],
                       "no helper to set up on the iPhone and iPad")
    }

    func testCopyForClaudeIsOfferedOnlyWhileOn() {
        let settings = ClaudeSettings(defaults: defaults, storeSuffix: nil)
        XCTAssertFalse(settings.isAllowed, "off by default")
        XCTAssertFalse(ClaudeIntegration.offersExport(settings))
        settings.isAllowed = true
        XCTAssertTrue(ClaudeIntegration.offersExport(settings))
    }

    func testWhoeverTurnedOnAllowClaudeKeepsItOn() {
        // 0.6.0's "Allow Claude" wrote this key; the new switch reads the same one, and so does the helper.
        defaults.set(true, forKey: "claude.allowed")
        XCTAssertTrue(ClaudeSettings(defaults: defaults, storeSuffix: nil).isAllowed)
        XCTAssertEqual(ClaudeSettings(defaults: defaults, storeSuffix: nil).allowedKey, ClaudeWire.allowedKey(storeSuffix: nil))
    }

    // MARK: The switch asks first

    func testTurningOnAsksAndGoesOnOnlyOnConfirm() {
        var toggle = ClaudeIntegration.Switch(isOn: false)
        toggle.request(true)
        XCTAssertTrue(toggle.isAsking)
        XCTAssertFalse(toggle.isOn, "nothing is on while the question is up")
        toggle.cancel()
        XCTAssertFalse(toggle.isAsking)
        XCTAssertFalse(toggle.isOn)
        toggle.request(true)
        toggle.confirm()
        XCTAssertTrue(toggle.isOn)
        XCTAssertFalse(toggle.isAsking)
    }

    func testTurningOffNeedsNoQuestion() {
        var toggle = ClaudeIntegration.Switch(isOn: true)
        toggle.request(false)
        XCTAssertFalse(toggle.isOn)
        XCTAssertFalse(toggle.isAsking)
        toggle.confirm()
        XCTAssertFalse(toggle.isOn, "a stray confirm with no question up changes nothing")
        var on = ClaudeIntegration.Switch(isOn: true)
        on.request(true)
        XCTAssertFalse(on.isAsking, "already on: no question")
    }

    func testTheQuestionSaysWhatClaudeSeesAndDoes() {
        let mac = ClaudeIntegration.confirmation(rule: ClaudeAccessRule(), mac: true)
        XCTAssertEqual(mac.confirm, "Turn On")
        for words in ["read", "add", "complete", "change", "never deletes", "@private", "Anthropic", "off at any time"] {
            XCTAssertTrue(mac.message.contains(words), "Mac question says \(words)")
        }
        let shared = ClaudeIntegration.confirmation(rule: ClaudeAccessRule(mode: .onlyShared, sharedLabel: "ai"), mac: true)
        XCTAssertTrue(shared.message.contains("only tasks labelled @ai"))
        let phone = ClaudeIntegration.confirmation(rule: ClaudeAccessRule(), mac: false)
        XCTAssertTrue(phone.message.contains("Copy for Claude"))
        XCTAssertTrue(phone.message.contains("@private"))
        XCTAssertTrue(phone.message.contains("sends nothing"))
    }

    // MARK: Off means off

    func testTheHelperSaysTheIntegrationIsOff() {
        XCTAssertTrue(ClaudeWire.accessOffMessage.hasPrefix("Claude integration is off in HITList"),
                      ClaudeWire.accessOffMessage)
        XCTAssertFalse(ClaudeWire.accessOffMessage.contains("Allow Claude"), "0.6.0's name for the switch is gone")
    }

    #if os(macOS)
    func testNoPortWhileOffAndNoneAfterTurningOff() throws {
        let suffix = "gate\(UInt32.random(in: 0 ... .max))"
        let settings = ClaudeSettings(defaults: defaults, storeSuffix: suffix)
        let connector = ClaudeConnector(settings: settings)
        connector.attach(container: ModelContainerFactory.preview())
        defer { settings.isAllowed = false; connector.refresh() }

        connector.refresh()
        XCTAssertEqual(connector.status, .off, "off by default: no port")
        XCTAssertEqual(ClaudePortClient.send(Data(), to: connector.portName, replyTimeout: 1), .failure(.notFound))

        settings.isAllowed = true
        connector.refresh()
        XCTAssertEqual(connector.status, .listening(port: connector.portName))

        settings.isAllowed = false
        connector.refresh()
        XCTAssertEqual(connector.status, .off)
        XCTAssertEqual(ClaudePortClient.send(Data(), to: connector.portName, replyTimeout: 1), .failure(.notFound))
        let token = try XCTUnwrap(connector.tokenURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: token.path), "the key goes with the port")
    }
    #endif

    // MARK: Claude's completions get the Undo toast (item 2)

    func testAClaudeCompletionShowsTheUndoToast() {
        let center = NotificationCenter()
        let popouts = PopoutController(draftDefaults: defaults, center: center)
        let record = CompletedTask(id: UUID(), title: "Call the dentist", revert: .uncomplete)
        center.post(name: .claudeDidCompleteTask, object: nil, userInfo: [ClaudeConnector.completedTaskKey: record])
        XCTAssertEqual(popouts.toast.completed, [record])
        XCTAssertEqual(popouts.toast.message, "Completed ‘Call the dentist’")
    }

    func testAClaudeCompletionIsOneTapFromUndone() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "From Claude")
        context.insert(task)
        TaskActions.toggleCompletion(task, in: context)
        XCTAssertTrue(task.isCompleted)

        let center = NotificationCenter()
        let popouts = PopoutController(draftDefaults: defaults, center: center)
        center.post(name: .claudeDidCompleteTask, object: nil,
                    userInfo: [ClaudeConnector.completedTaskKey: CompletedTask(id: task.id, title: task.title, revert: .uncomplete)])
        popouts.undoCompletions(in: context)
        XCTAssertFalse(task.isCompleted)
        XCTAssertFalse(popouts.toast.isVisible)
    }

    func testANotificationWithoutARecordIsIgnored() {
        let center = NotificationCenter()
        let popouts = PopoutController(draftDefaults: defaults, center: center)
        center.post(name: .claudeDidCompleteTask, object: nil, userInfo: ["completedTask": "junk"])
        XCTAssertFalse(popouts.toast.isVisible)
    }

    // MARK: Renders

    func testSectionRendersOffAndOn() {
        let container = ModelContainerFactory.preview()
        let settings = ClaudeSettings(defaults: defaults, storeSuffix: nil)
        for on in [false, true] {
            settings.isAllowed = on
            let view = ClaudeSettingsSection(settings: settings)
                .modelContainer(container).frame(width: 600).preferredColorScheme(.dark)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage, "renders \(on ? "on" : "off")")
        }
    }
}
