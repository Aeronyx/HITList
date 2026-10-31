import XCTest
import AVFoundation
@testable import HITList

@MainActor
final class CompletionSoundTests: XCTestCase {
    private var suites: [String] = []
    private var directories: [URL] = []

    private func makeDefaults() -> UserDefaults {
        let name = "HITListTests.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HITListTests.\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }

    /// A silent 16-bit mono wav of `seconds`.
    private func makeWav(seconds: Double, in directory: URL, name: String = "sound.wav") throws -> URL {
        let url = directory.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        for url in directories { try? FileManager.default.removeItem(at: url) }
        suites = []
        directories = []
    }

    func testRawValuesRoundTripAndBuiltInsAreBundled() throws {
        for sound in CompletionSound.allCases {
            XCTAssertEqual(CompletionSound(rawValue: sound.rawValue), sound)
            XCTAssertFalse(sound.displayName.isEmpty)
        }
        XCTAssertEqual(CompletionSound.builtIns.map(\.rawValue), ["bubble", "swish"])
        for sound in CompletionSound.builtIns {
            let url = try XCTUnwrap(sound.bundleURL, "\(sound.rawValue).caf missing from the bundle")
            XCTAssertLessThanOrEqual(try CustomSoundStore.duration(of: url), 0.35)
        }
        XCTAssertNil(CompletionSound.custom.bundleURL)
        XCTAssertNil(CompletionSound.none.bundleURL)
    }

    func testSelectionDefaultsToPopAndPersists() {
        let defaults = makeDefaults()
        XCTAssertEqual(CompletionSound.selected(in: defaults), .bubble)

        CompletionSound.select(.swish, in: defaults)
        XCTAssertEqual(defaults.string(forKey: CompletionSound.key), "swish")
        XCTAssertEqual(CompletionSound.selected(in: defaults), .swish)

        defaults.set("no-such-sound", forKey: CompletionSound.key)
        XCTAssertEqual(CompletionSound.selected(in: defaults), .bubble)
    }

    func testOldToggleOffReadsAsNoneAndPickingASoundTurnsItBackOn() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: CompletionFeedback.soundKey)
        XCTAssertEqual(CompletionSound.selected(in: defaults), .none)
        XCTAssertFalse(CompletionFeedback(defaults: defaults).isSoundEnabled)

        CompletionSound.select(.swish, in: defaults)
        XCTAssertTrue(CompletionFeedback(defaults: defaults).isSoundEnabled)

        CompletionSound.select(.none, in: defaults)
        XCTAssertFalse(CompletionFeedback(defaults: defaults).isSoundEnabled)
    }

    func testRejectsSoundsLongerThanTwoSeconds() throws {
        let defaults = makeDefaults()
        let store = CustomSoundStore(directory: makeDirectory(), defaults: defaults)
        let long = try makeWav(seconds: 2.5, in: makeDirectory())

        XCTAssertThrowsError(try store.importSound(from: long)) { error in
            guard case CustomSoundStore.ImportError.tooLong(let seconds) = error else {
                return XCTFail("Expected tooLong, got \(error)")
            }
            XCTAssertEqual(seconds, 2.5, accuracy: 0.01)
        }
        XCTAssertNil(store.fileURL)
        XCTAssertNil(store.displayName)
    }

    func testImportsShortSoundAndReplacesThePreviousOne() throws {
        let defaults = makeDefaults()
        let store = CustomSoundStore(directory: makeDirectory(), defaults: defaults)
        let source = makeDirectory()

        try store.importSound(from: try makeWav(seconds: 0.5, in: source, name: "Ding.wav"))
        XCTAssertEqual(store.fileURL?.lastPathComponent, "custom.wav")
        XCTAssertEqual(store.displayName, "Ding.wav")

        let aiff = source.appendingPathComponent("Chime.aiff")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsBigEndianKey: true]
        let file = try AVAudioFile(forWriting: aiff, settings: settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_410)!
        buffer.frameLength = 4_410
        try file.write(from: buffer)
        try store.importSound(from: aiff)
        XCTAssertEqual(store.fileURL?.lastPathComponent, "custom.aiff")
        XCTAssertEqual(store.displayName, "Chime.aiff")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory!.appendingPathComponent("custom.wav").path))

        store.remove()
        XCTAssertNil(store.fileURL)
        XCTAssertNil(store.displayName)
    }

    func testCustomFallsBackToPopWhenItsFileIsMissing() throws {
        let defaults = makeDefaults()
        let store = CustomSoundStore(directory: makeDirectory(), defaults: defaults)
        CompletionSound.select(.custom, in: defaults)
        XCTAssertEqual(CompletionSound.resolvedURL(in: defaults, custom: store), CompletionSound.bubble.bundleURL)

        let stored = try store.importSound(from: try makeWav(seconds: 0.3, in: makeDirectory()))
        XCTAssertEqual(CompletionSound.resolvedURL(in: defaults, custom: store), stored)

        // Deleted behind the app's back.
        try FileManager.default.removeItem(at: stored)
        XCTAssertEqual(CompletionSound.resolvedURL(in: defaults, custom: store), CompletionSound.bubble.bundleURL)
        XCTAssertNotNil(CompletionSound.bubble.bundleURL)

        CompletionSound.select(.none, in: defaults)
        XCTAssertNil(CompletionSound.resolvedURL(in: defaults, custom: store))
    }
}
