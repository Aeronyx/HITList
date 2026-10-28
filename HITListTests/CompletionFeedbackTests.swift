import XCTest
@testable import HITList

@MainActor
final class CompletionFeedbackTests: XCTestCase {
    private final class Recorder: FeedbackOutput {
        var prepared = 0
        var played = 0
        func prepare() { prepared += 1 }
        func play() { played += 1 }
    }

    private var suites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = "HITListTests.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []
    }

    func testDoesNothingWhenBothTogglesAreOff() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: CompletionFeedback.soundKey)
        defaults.set(false, forKey: CompletionFeedback.hapticsKey)
        let sound = Recorder(), haptics = Recorder()
        let feedback = CompletionFeedback(defaults: defaults, sound: sound, haptics: haptics)

        feedback.prepare()
        feedback.taskCompleted()
        feedback.taskCompleted()

        XCTAssertEqual(sound.prepared + sound.played, 0)
        XCTAssertEqual(haptics.prepared + haptics.played, 0)
    }

    func testBothTogglesDefaultOn() {
        let sound = Recorder(), haptics = Recorder()
        let feedback = CompletionFeedback(defaults: makeDefaults(), sound: sound, haptics: haptics)

        feedback.prepare()
        feedback.taskCompleted()

        XCTAssertEqual(sound.prepared, 1)
        XCTAssertEqual(sound.played, 1)
        XCTAssertEqual(haptics.prepared, 1)
        XCTAssertEqual(haptics.played, 1)
    }

    func testEachToggleGatesOnlyItsOwnOutput() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: CompletionFeedback.soundKey)
        let sound = Recorder(), haptics = Recorder()
        let feedback = CompletionFeedback(defaults: defaults, sound: sound, haptics: haptics)

        feedback.taskCompleted()
        XCTAssertEqual(sound.played, 0)
        XCTAssertEqual(haptics.played, 1)

        // Flipping the toggle takes effect on the next completion, no relaunch.
        defaults.set(true, forKey: CompletionFeedback.soundKey)
        defaults.set(false, forKey: CompletionFeedback.hapticsKey)
        feedback.taskCompleted()
        XCTAssertEqual(sound.played, 1)
        XCTAssertEqual(haptics.played, 1)
    }
}
