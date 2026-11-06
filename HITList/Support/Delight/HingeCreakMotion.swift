import Foundation

/// Turns the iPhone Duo's hinge updates into what the creak plays (brief 50). Pure, so `HingeCreakTests` pins it.
///
/// The system reports the hinge's angle at a rate it chooses ("system policy", `UIHinge.angle`), so the speed
/// comes from the updates themselves: the travel since the last drive over the time it took. A drive goes to the
/// synth once the hinge has travelled `stepDegrees` one way (sensor wobble at rest changes direction and never
/// adds up); its intensity (pitch and loudness) follows the angular speed, its grain rate is one grain per
/// `grainDegrees` of travel at that speed, and it sustains until the next update is due, so the sound runs on
/// between sparse updates and stops soon after the hinge does; a fast movement sustains for the travel it has left
/// (momentum, up to 0.8 s), which carries the creak across the moment the window moves to the other display. The first movement after the sound has stopped
/// `kick`s: the synth starts a grain with its next buffer instead of waiting for the grain clock.
struct HingeCreakMotion {
    struct Drive: Equatable {
        /// 0...1, from the angular speed: the groan's pitch and the creak's loudness follow it.
        var intensity: Double
        /// Grains per second.
        var grainRate: Double
        /// How long to keep making grains without another drive.
        var sustain: TimeInterval
        /// Start a grain at once.
        var kick: Bool
        /// The angle is growing (the phone opening); closing groans a little lower.
        var opening: Bool
    }

    /// Travel that sends a drive.
    static let stepDegrees = 1.0
    /// Travel per grain at the current speed.
    static let grainDegrees = 3.0
    /// Changes smaller than this are sensor noise.
    static let noiseDegrees = 0.05
    /// A gap this long between updates means the hinge was at rest: what moved, moved in the last frame or so.
    static let restGap: TimeInterval = 0.25
    static let nominalInterval: TimeInterval = 1.0 / 60
    /// Speeds (degrees per second) that map to intensity 0 and 1: a crawl, and a phone flicked open.
    static let slowSpeed = 15.0
    static let fastSpeed = 540.0
    static let grainRates: ClosedRange<Double> = 8...45
    static let sustains: ClosedRange<TimeInterval> = 0.06...0.25
    /// Fully open. Closed is 0.
    static let fullyOpenDegrees = 180.0
    /// Momentum: a movement at least this intense keeps creaking for the time the travel left would take at its
    /// speed, up to `momentumCap`, so the sound carries on while no updates come (on the simulator, 0.6–0.8 s while
    /// the system moves the window between the displays). Slow movements, and the last few degrees, stop promptly.
    static let momentumIntensity = 0.5
    static let momentumCap: TimeInterval = 0.8
    static let momentumMinTravel = 5.0

    private var last: (angle: Double, time: TimeInterval)?
    /// Travel toward the next drive (keeps the remainder past each step).
    private var stepTravel = 0.0
    /// Travel and its start time since the last drive, for the speed.
    private var windowTravel = 0.0
    private var windowStart: TimeInterval = 0
    /// +1 opening, -1 closing, 0 not yet known.
    private var direction = 0.0
    private var soundingUntil: TimeInterval = -.infinity

    /// A hinge update: its angle in degrees and when it arrived. Returns what to play, if anything.
    mutating func update(degrees angle: Double, at time: TimeInterval) -> Drive? {
        guard let previous = last else {
            last = (angle, time)
            return nil
        }
        let delta = angle - previous.angle
        guard abs(delta) >= Self.noiseDegrees else {
            // Too small to count; remember the time so a long pause still reads as rest.
            last = (previous.angle, time)
            return nil
        }
        last = (angle, time)
        let elapsed = time - previous.time
        let resting = elapsed > Self.restGap
        let sign: Double = delta > 0 ? 1 : -1
        if resting || sign != direction {
            // A new movement: after a rest it happened within about a frame; a change of direction starts over.
            direction = sign
            stepTravel = 0
            windowTravel = 0
            windowStart = resting ? time - Self.nominalInterval : previous.time
        }
        stepTravel += abs(delta)
        windowTravel += abs(delta)
        guard stepTravel >= Self.stepDegrees else { return nil }
        stepTravel = stepTravel.truncatingRemainder(dividingBy: Self.stepDegrees)

        let speed = windowTravel / max(time - windowStart, 1.0 / 240)
        windowTravel = 0
        windowStart = time
        let interval = resting ? Self.nominalInterval : elapsed
        var sustain = min(max(2 * interval, Self.sustains.lowerBound), Self.sustains.upperBound)
        let intensity = Self.intensity(forSpeed: speed)
        let travelLeft = sign > 0 ? max(0, Self.fullyOpenDegrees - angle) : max(0, angle)
        if intensity >= Self.momentumIntensity, travelLeft > Self.momentumMinTravel {
            sustain = max(sustain, min(Self.momentumCap, travelLeft / speed))
        }
        let kick = time > soundingUntil
        soundingUntil = time + sustain
        return Drive(intensity: intensity,
                     grainRate: min(max(speed / Self.grainDegrees, Self.grainRates.lowerBound), Self.grainRates.upperBound),
                     sustain: sustain, kick: kick, opening: sign > 0)
    }

    /// The hinge left (or the creak was switched off): the next update is a first one again.
    mutating func reset() {
        self = HingeCreakMotion()
    }

    /// 0 at `slowSpeed` and below, 1 at `fastSpeed` and above, logarithmic between (ears hear speed that way).
    static func intensity(forSpeed degreesPerSecond: Double) -> Double {
        guard degreesPerSecond > slowSpeed else { return 0 }
        return min(1, log(degreesPerSecond / slowSpeed) / log(fastSpeed / slowSpeed))
    }
}

extension HingeCreakMotion.Drive {
    /// One 64-bit word, so the audio thread reads a whole drive in one atomic load (`HingeCreakEngine`):
    /// intensity, grain rate and sustain as 16-bit fixed point, the two flags, and a sequence number that tells
    /// the audio thread a new drive has arrived.
    func packed(sequence: UInt8) -> UInt64 {
        func fixed(_ value: Double, scale: Double) -> UInt64 { UInt64(min(max(value * scale, 0), 65_535).rounded()) }
        return fixed(intensity, scale: 65_535)
            | fixed(grainRate, scale: 100) << 16
            | fixed(sustain, scale: 10_000) << 32
            | (kick ? 1 : 0) << 48
            | (opening ? 1 : 0) << 49
            | UInt64(sequence) << 56
    }

    init(packed word: UInt64) {
        func field(_ shift: UInt64) -> Double { Double((word >> shift) & 0xFFFF) }
        self.init(intensity: field(0) / 65_535, grainRate: field(16) / 100, sustain: field(32) / 10_000,
                  kick: (word >> 48) & 1 == 1, opening: (word >> 49) & 1 == 1)
    }

    static func sequence(of word: UInt64) -> UInt8 {
        UInt8(truncatingIfNeeded: word >> 56)
    }

    /// The drive as the audio thread should play it when it picks it up `age` seconds after the hinge update:
    /// as sent within a couple of buffers; later, only the rest of its sustain and no kick (that movement's
    /// moment has passed); nil once the sustain has run out, so a stalled audio route never creaks late.
    func picked(upAfter age: TimeInterval) -> Self? {
        guard age > Self.freshAge else { return self }
        guard age < sustain else { return nil }
        var late = self
        late.sustain = sustain - age
        late.kick = false
        return late
    }

    /// Picked up sooner than this (a few buffers; the simulator renders in ~20 ms slices), a drive plays as sent.
    static let freshAge: TimeInterval = 0.05
}
