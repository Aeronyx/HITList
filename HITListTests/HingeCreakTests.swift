import XCTest
@testable import HITList

/// The squeaky hinge (brief 50): how hinge updates become grains of sound (`HingeCreakMotion`), the sound
/// itself (`HingeCreakSynth`), and when it may play at all (`HingeCreak`).
@MainActor
final class HingeCreakTests: XCTestCase {
    private let frame = 1.0 / 60

    // MARK: Motion

    func testTheFirstUpdateOnlyRecordsWhereTheHingeIs() {
        var motion = HingeCreakMotion()
        XCTAssertNil(motion.update(degrees: 0, at: 10), "the interaction's initial state is not a movement")
    }

    func testTheFirstMovementAfterRestStartsAGrainAtOnce() throws {
        var motion = HingeCreakMotion()
        _ = motion.update(degrees: 0, at: 0)
        let drive = try XCTUnwrap(motion.update(degrees: 6, at: 5), "a phone that sat closed for 5 s starts opening")
        XCTAssertTrue(drive.kick, "no waiting for the grain clock: the first grain starts with the next audio buffer")
        XCTAssertTrue(drive.opening)
        XCTAssertGreaterThan(drive.intensity, 0.5, "6° in about a frame is a brisk opening, not a crawl")
    }

    func testFasterIsMoreIntenseWithMoreGrains() throws {
        func steady(_ degreesPerFrame: Double) throws -> HingeCreakMotion.Drive {
            var motion = HingeCreakMotion()
            var last: HingeCreakMotion.Drive?
            for step in 0...10 { last = motion.update(degrees: Double(step) * degreesPerFrame, at: Double(step) * frame) ?? last }
            return try XCTUnwrap(last)
        }
        let slow = try steady(1.5)   // 90°/s
        let fast = try steady(8)     // 480°/s
        XCTAssertGreaterThan(fast.intensity, slow.intensity)
        XCTAssertGreaterThan(fast.grainRate, slow.grainRate)
        XCTAssertLessThanOrEqual(fast.grainRate, HingeCreakMotion.grainRates.upperBound)
        XCTAssertLessThanOrEqual(fast.intensity, 1)
    }

    func testSteadyMotionKicksOnlyOnce() {
        var motion = HingeCreakMotion()
        var kicks = 0, drives = 0
        for step in 0...30 {
            if let drive = motion.update(degrees: Double(step) * 3, at: Double(step) * frame) {
                drives += 1
                if drive.kick { kicks += 1 }
            }
        }
        XCTAssertEqual(drives, 30)
        XCTAssertEqual(kicks, 1, "after the first, grains follow the grain clock while the hinge keeps moving")
    }

    func testAPauseLongerThanTheSustainKicksAgain() throws {
        var motion = HingeCreakMotion()
        _ = motion.update(degrees: 0, at: 0)
        XCTAssertEqual(motion.update(degrees: 4, at: frame)?.kick, true)
        _ = motion.update(degrees: 8, at: 2 * frame)
        let resumed = try XCTUnwrap(motion.update(degrees: 12, at: 2 * frame + 1))
        XCTAssertTrue(resumed.kick, "the sound had stopped; it starts again at once")
        XCTAssertFalse(motion.update(degrees: 8, at: 3 * frame + 1)?.opening ?? true, "closing again")
    }

    func testSlowMotionCreaksByAngleSteps() {
        var motion = HingeCreakMotion()
        var drives: [HingeCreakMotion.Drive] = []
        for step in 0...40 {
            if let drive = motion.update(degrees: Double(step) * 0.3, at: Double(step) * frame) { drives.append(drive) }
        }
        // 12° in steps of a degree: a grain every 3–4 updates, not one per update.
        XCTAssertEqual(drives.count, 12, accuracy: 1)
        XCTAssertTrue(drives.allSatisfy { $0.intensity < 0.4 }, "18°/s is a slow, quiet creak")
    }

    func testAHingeAtRestNeverCreaks() {
        var motion = HingeCreakMotion()
        for step in 0...600 {
            let wobble = step.isMultiple(of: 2) ? 0.04 : -0.04
            XCTAssertNil(motion.update(degrees: 90 + wobble, at: Double(step) * 0.1), "sensor noise at rest, 60 s of it")
        }
    }

    func testAStatusChangeWithoutMovementIsSilent() {
        var motion = HingeCreakMotion()
        _ = motion.update(degrees: 180, at: 0)
        XCTAssertNil(motion.update(degrees: 180, at: 0.5))
    }

    func testSustainCoversTheGapToTheNextUpdate() throws {
        var motion = HingeCreakMotion()
        _ = motion.update(degrees: 0, at: 0)
        let drive = try XCTUnwrap(motion.update(degrees: 3, at: 0.1), "updates 100 ms apart")
        XCTAssertGreaterThanOrEqual(drive.sustain, 0.1, "keeps sounding until the next update is due")
        XCTAssertTrue(HingeCreakMotion.sustains.contains(drive.sustain))
    }

    func testLeavingTheHingeStartsOver() {
        var motion = HingeCreakMotion()
        _ = motion.update(degrees: 0, at: 0)
        motion.reset()
        XCTAssertNil(motion.update(degrees: 90, at: 1), "after the hinge went away, the next update is a first one again")
    }

    func testADriveFitsInOneWordForTheAudioThread() {
        let drive = HingeCreakMotion.Drive(intensity: 0.73, grainRate: 31.5, sustain: 0.084, kick: true, opening: false)
        let word = drive.packed(sequence: 200)
        XCTAssertEqual(HingeCreakMotion.Drive.sequence(of: word), 200)
        let back = HingeCreakMotion.Drive(packed: word)
        XCTAssertEqual(back.intensity, 0.73, accuracy: 0.0001)
        XCTAssertEqual(back.grainRate, 31.5, accuracy: 0.01)
        XCTAssertEqual(back.sustain, 0.084, accuracy: 0.0001)
        XCTAssertTrue(back.kick)
        XCTAssertFalse(back.opening)
    }

    // MARK: Sound

    private let sampleRate = 48_000.0

    private func render(_ synth: inout HingeCreakSynth, seconds: Double) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
        var offset = 0
        while offset < samples.count {
            let count = min(240, samples.count - offset)   // 5 ms buffers, as the engine asks for
            samples.withUnsafeMutableBufferPointer { _ = synth.render(into: $0.baseAddress! + offset, count: count) }
            offset += count
        }
        return samples
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count)))
    }

    private func zeroCrossings(_ samples: ArraySlice<Float>) -> Int {
        zip(samples, samples.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    private func drive(_ intensity: Double, sustain: Double = 0.5, kick: Bool = true) -> HingeCreakMotion.Drive {
        HingeCreakMotion.Drive(intensity: intensity, grainRate: 8 + 37 * intensity, sustain: sustain, kick: kick, opening: true)
    }

    func testSilentUntilTheHingeMoves() {
        var synth = HingeCreakSynth(sampleRate: sampleRate)
        XCTAssertTrue(render(&synth, seconds: 0.2).allSatisfy { $0 == 0 })
        XCTAssertTrue(synth.isSilent)
    }

    func testAKickSoundsWithinTwoMilliseconds() throws {
        var synth = HingeCreakSynth(sampleRate: sampleRate)
        synth.apply(drive(0.6))
        let samples = render(&synth, seconds: 0.05)
        let onset = try XCTUnwrap(samples.firstIndex { abs($0) > 0.001 }, "it sounds")
        XCTAssertLessThan(Double(onset) / sampleRate, 0.002, "the creak starts at the top of the first buffer")
    }

    func testNeverLouderThanTheGentleLimit() {
        var synth = HingeCreakSynth(sampleRate: sampleRate)
        synth.apply(drive(1, sustain: 1))
        let samples = render(&synth, seconds: 1)
        let peak = samples.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, HingeCreakSynth.ceiling + 1e-6)
        XCTAssertLessThan(HingeCreakSynth.ceiling, 0.36, "below -9 dBFS: a delight, never a fright")
        XCTAssertGreaterThan(rms(samples[...]), 0.02, "but clearly audible")
        XCTAssertFalse(samples.contains { !$0.isFinite })
    }

    func testFasterIsHigherAndLouder() {
        func sound(_ intensity: Double) -> ArraySlice<Float> {
            var synth = HingeCreakSynth(sampleRate: sampleRate)
            synth.apply(drive(intensity, sustain: 0.6))
            return render(&synth, seconds: 0.6)[...]
        }
        let slow = sound(0.15), fast = sound(0.95)
        XCTAssertGreaterThan(rms(fast), rms(slow) * 1.3)
        XCTAssertGreaterThan(zeroCrossings(fast), zeroCrossings(slow), "a higher squeal")
    }

    func testGoesQuietSoonAfterTheHingeStops() {
        var synth = HingeCreakSynth(sampleRate: sampleRate)
        synth.apply(drive(0.8, sustain: 0.1))
        let samples = render(&synth, seconds: 0.8)
        let tail = samples[Int(0.5 * sampleRate)...]
        XCTAssertTrue(tail.allSatisfy { abs($0) < 1e-4 }, "silent within 400 ms of the sustain running out")
        XCTAssertTrue(synth.isSilent, "and says so, so the engine can mark its buffers silent")
    }

    func testTheSameMovementSoundsTheSameEachTime() {
        func sound(seed: UInt64) -> [Float] {
            var synth = HingeCreakSynth(sampleRate: sampleRate, seed: seed)
            synth.apply(drive(0.5))
            return render(&synth, seconds: 0.2)
        }
        XCTAssertEqual(sound(seed: 7), sound(seed: 7))
        XCTAssertNotEqual(sound(seed: 7), sound(seed: 8), "the grains' jitter comes from the seed")
    }

    // MARK: When it plays

    func testOnByDefaultUnderItsOwnKey() {
        let suite = "HingeCreakTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(HingeCreak.key, "delight.squeakyHinge")
        XCTAssertTrue(HingeCreak.isEnabled(in: defaults))
        defaults.set(false, forKey: HingeCreak.key)
        XCTAssertFalse(HingeCreak.isEnabled(in: defaults))
    }

    func testPlaysOnlyWithAHingeSwitchedOnAndInTheForeground() {
        XCTAssertTrue(HingeCreak.shouldRun(enabled: true, hasHinge: true, inForeground: true))
        XCTAssertFalse(HingeCreak.shouldRun(enabled: false, hasHinge: true, inForeground: true), "Extras → Squeaky hinge off")
        XCTAssertFalse(HingeCreak.shouldRun(enabled: true, hasHinge: false, inForeground: true), "every phone without a hinge")
        XCTAssertFalse(HingeCreak.shouldRun(enabled: true, hasHinge: true, inForeground: false), "no sound in the background")
    }

    func testTheSettingsRowShowsOnlyWithAHinge() {
        XCTAssertFalse(HingeCreakSettingsRow.isShown(hasHinge: false))
        XCTAssertTrue(HingeCreakSettingsRow.isShown(hasHinge: true))
    }

    func testLatencyIsMeasuredFromTheHingeEventToTheBufferThatStartsTheCreak() {
        let latency = HingeCreakLatency(eventSeconds: 10, callbackSeconds: 10.004, bufferStartSeconds: 10.009,
                                        outputLatency: 0.006, ioBuffer: 0.005)
        XCTAssertEqual(latency.toCallback, 0.004, accuracy: 1e-9)
        XCTAssertEqual(latency.toAudible, 0.015, accuracy: 1e-9, "to the buffer's first sample, plus the output's own latency")
        XCTAssertEqual(latency.frames(at: 60), 0.9, accuracy: 1e-9)
        XCTAssertEqual(latency.frames(at: 120), 1.8, accuracy: 1e-9)
    }
}
