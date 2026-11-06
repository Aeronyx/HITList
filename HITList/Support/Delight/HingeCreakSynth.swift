import Foundation

/// The creaky hinge's sound, made from nothing (briefs 50, 55: no recordings, no third-party audio). A value type
/// that only the audio thread touches (`HingeCreakEngine`): no allocation (its few arrays are made once and
/// written in place), no locks, no Objective-C while rendering, so it can run inside the render callback.
///
/// An old wooden door, cabinet or chest lid, not a squeaky metal pin (George, 2026-11-05: "more like a
/// door/cabinet/chest creaking open and not like squeaky metal"; "rather quiet so it's funny and not annoying"):
/// - **Stick-slip**: the wood catches and lets go in a train of soft, irregular pulses. Their rate is the creak's
///   fundamental, 80 Hz at a crawl to 350 Hz when flung (`fundamental`; closing a little lower), drifting slowly,
///   each grain a little off the last; each period is up to 15% early or late, some slips are missed and some
///   come twice. Grains (one per few degrees of travel, `HingeCreakMotion`) swell and fade the pulses: a crawl
///   goes "errk… errk", a fast swing runs together into one long groan.
/// - **The wood**: the pulses ring a few broad, low body resonances (120–900 Hz, Q 3–5), plus one at twice the
///   fundamental that carries the groan's pitch, and between grains a few dry knocks of the same wood.
/// - **Nothing bright**: the excitation is smoothed and the mix goes through a fourth-order low-pass at 1.2 kHz,
///   so nothing above ~1.5 kHz rings as a pure tone (that is what reads as squeaky metal).
///
/// Then a DC blocker and a soft-knee limiter (`ceiling`): however hard the phone is flung open, the peak never
/// passes -18 dBFS, and a crawl peaks around 10 dB under that. A kick starts a grain on the first sample of the
/// next buffer, and its first slip sounds at once.
struct HingeCreakSynth {
    /// The limiter's ceiling: -18 dBFS.
    static let ceiling: Float = 0.125

    /// The stick-slip rate (Hz) for an intensity 0...1: 80 Hz at a crawl, 350 Hz flung; closing 12% lower.
    static func fundamental(intensity: Double, opening: Bool) -> Double {
        (80 + 270 * min(max(intensity, 0), 1)) * (opening ? 1 : 0.88)
    }

    /// The low-pass every sample goes through last (Hz).
    static let brightnessCutoff = 1_200.0

    let sampleRate: Double
    private var random: UInt64

    // The drive.
    private var intensity = 0.0
    private var grainRate = 0.0
    private var opening = true
    private var sustainFrames = 0
    private var grainPhase = 0.0

    // Stick-slip: one voice, its loudness the sum of the grains' envelopes.
    private var pitch = 0.0
    private var wander = 0.0
    private var grainDetune = 1.0
    private var pulsePhase = 0.0
    private var pulseIncrement = 0.0
    private var doubleSlipIn = -1
    private var slipLeft = 0
    private var slipAmplitude: Float = 0
    private var smooth0: Float = 0
    private var smooth1: Float = 0
    private var groan = Resonator()
    private var retuneCountdown = 0
    private var grains = GrainEnvelopes()

    // The wood: fixed body modes, and knocks waiting to fire.
    private var body0 = Resonator()
    private var body1 = Resonator()
    private var body2 = Resonator()
    private var body3 = Resonator()
    private var body4 = Resonator()
    private var knocks = PendingClicks()
    private var knockLeft = 0
    private var knockAmplitude: Float = 0

    // Output.
    private var lowpass0 = Biquad()
    private var lowpass1 = Biquad()
    private var dcIn: Float = 0
    private var dcOut: Float = 0
    private let smoothing: Float
    /// Samples since the output last moved; past `quietAfter` the synth is silent.
    private var quietFrames = HingeCreakSynth.quietAfter + 1

    init(sampleRate: Double, seed: UInt64 = 0x4849_4E47_4543_5245) {
        self.sampleRate = sampleRate
        random = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        body0 = Resonator(frequency: 118, q: 4, sampleRate: sampleRate)
        body1 = Resonator(frequency: 205, q: 5, sampleRate: sampleRate)
        body2 = Resonator(frequency: 335, q: 5, sampleRate: sampleRate)
        body3 = Resonator(frequency: 540, q: 4, sampleRate: sampleRate)
        body4 = Resonator(frequency: 880, q: 3, sampleRate: sampleRate)
        // Butterworth sections of a fourth-order low-pass.
        lowpass0 = Biquad(lowpass: Self.brightnessCutoff, q: 0.541, sampleRate: sampleRate)
        lowpass1 = Biquad(lowpass: Self.brightnessCutoff, q: 1.307, sampleRate: sampleRate)
        // The slip's own edge: a one-pole smoother at ~900 Hz, twice.
        smoothing = Float(1 - exp(-2 * Double.pi * 900 / sampleRate))
    }

    /// Nothing sounding and nothing due: the engine marks its buffers silent.
    var isSilent: Bool { quietFrames > Self.quietAfter && sustainFrames <= 0 }

    /// The latest drive from the hinge.
    mutating func apply(_ drive: HingeCreakMotion.Drive) {
        intensity = min(max(drive.intensity, 0), 1)
        grainRate = drive.grainRate
        opening = drive.opening
        sustainFrames = Int(drive.sustain * sampleRate)
        if pitch == 0 || isSilent { pitch = targetPitch }
        if drive.kick {
            grainPhase = 0
            startGrain()
        }
    }

    /// Renders `count` mono samples into `out`. Returns false (and writes zeros) when silent.
    mutating func render(into out: UnsafeMutablePointer<Float>, count: Int) -> Bool {
        if isSilent && grains.isEmpty && knocks.isEmpty {
            out.update(repeating: 0, count: count)
            return false
        }
        let grainStep = grainRate / sampleRate
        let level = Float(0.3 + 0.7 * intensity)
        for index in 0..<count {
            // New grains while the hinge is moving.
            if sustainFrames > 0 {
                sustainFrames -= 1
                grainPhase += grainStep
                if grainPhase >= 1 {
                    grainPhase -= 1
                    startGrain()
                }
            }
            if retuneCountdown <= 0 { retune() } else { retuneCountdown -= 1 }

            // Stick-slip: the wood lets go, a little early or late each time, now and then not at all or twice.
            pulsePhase += pulseIncrement
            if pulsePhase >= 1 {
                pulsePhase -= 1
                let roll = nextUnit()
                if roll >= 0.08 { startSlip(amplitude: 0.55 + 0.45 * nextUnit()) }
                if roll > 0.94 { doubleSlipIn = Int(Double(0.18 + 0.2 * nextUnit()) * sampleRate / max(pitch, 1)) }
                pulseIncrement = pitch * grainDetune * (1 + 0.3 * (Double(nextUnit()) - 0.5)) / sampleRate
            }
            if doubleSlipIn >= 0 {
                if doubleSlipIn == 0 { startSlip(amplitude: 0.35 + 0.3 * nextUnit()) }
                doubleSlipIn -= 1
            }
            var slip: Float = 0
            if slipLeft > 0 {
                slipLeft -= 1
                slipAmplitude *= Self.slipDecay
                slip = slipAmplitude * (0.65 + 0.35 * (2 * nextUnit() - 1))
            }
            // Soften the slip's edge, so it thumps rather than clicks.
            smooth0 += smoothing * (slip - smooth0)
            smooth1 += smoothing * (smooth0 - smooth1)
            let loudness = min(1, grains.advance())
            let excitation = smooth1 * loudness

            // Dry knocks of the same wood, between and after the grains.
            var knock: Float = 0
            if knocks.advance() { startKnock() }
            if knockLeft > 0 {
                knockLeft -= 1
                knockAmplitude *= Self.knockDecay
                knock = knockAmplitude * (2 * nextUnit() - 1)
            }

            let drive = excitation + knock
            let wood = body0.process(drive) + 0.9 * body1.process(drive) + 0.75 * body2.process(drive)
                + 0.5 * body3.process(drive) + 0.25 * body4.process(drive)
            let voiced = 0.8 * groan.process(excitation) + 0.35 * excitation

            // Mix, darken, block DC, limit softly.
            let mixed = level * Self.gain * lowpass1.process(lowpass0.process(wood + voiced))
            let blocked = mixed - dcIn + 0.995 * dcOut
            dcIn = mixed
            dcOut = blocked
            let sample = Self.limit(blocked)
            out[index] = sample
            // Slips are only heard through a grain, so the slip clock ticking on alone is quiet.
            if abs(sample) < 1e-6 && grains.isEmpty && knockLeft == 0 {
                if quietFrames <= Self.quietAfter { quietFrames += 1 }
            } else {
                quietFrames = 0
            }
        }
        if isSilent {
            // Rung out: clear the filters' last traces so the next creak starts clean.
            body0.reset(); body1.reset(); body2.reset(); body3.reset(); body4.reset(); groan.reset()
            lowpass0.reset(); lowpass1.reset()
            smooth0 = 0; smooth1 = 0; dcIn = 0; dcOut = 0
        }
        return true
    }

    /// Soft knee from 60% of the ceiling; never past it.
    static func limit(_ x: Float) -> Float {
        let knee = 0.6 * ceiling
        let magnitude = abs(x)
        guard magnitude > knee else { return x }
        let over = knee + (ceiling - knee) * tanhf((magnitude - knee) / (ceiling - knee))
        return x < 0 ? -over : over
    }

    // MARK: Grains

    private static let quietAfter = 2_048
    private static let gain: Float = 1.4
    private static let slipDecay: Float = 0.82
    private static let knockDecay: Float = 0.9

    private var targetPitch: Double { Self.fundamental(intensity: intensity, opening: opening) }
    private var knockLevel: Float { Float(0.5 - 0.3 * intensity) }

    private mutating func startGrain() {
        // Long groans at a crawl, shorter ones that run together when fast; each a little different, and a little
        // off the last one's pitch.
        let seconds = (0.16 - 0.08 * intensity) * (0.7 + 0.6 * Double(nextUnit()))
        grains.start(length: Int(seconds * sampleRate), attack: Int(0.004 * sampleRate),
                     amplitude: 0.6 + 0.4 * nextUnit())
        grainDetune = 0.9 + 0.2 * Double(nextUnit())
        if pulseIncrement == 0 || quietFrames > 0 {
            // From quiet, the first slip is now: the creak is heard from the first sample.
            pulsePhase = 1
            pulseIncrement = pitch / sampleRate
        }
        // A dry knock or two of the wood, somewhere in or just after the grain.
        let count = 1 + Int(nextUnit() * 1.99)
        for _ in 0..<count {
            knocks.schedule(in: Int(seconds * Double(0.3 + 0.9 * nextUnit()) * sampleRate),
                            amplitude: knockLevel * (0.5 + 0.5 * nextUnit()))
        }
        quietFrames = 0
    }

    private mutating func startSlip(amplitude: Float) {
        slipAmplitude = amplitude
        slipLeft = Int(0.0015 * sampleRate)
    }

    private mutating func startKnock() {
        knockAmplitude = knocks.firedAmplitude
        knockLeft = Int(0.003 * sampleRate)
    }

    /// Every 32 samples: the pitch glides toward the speed's and wanders; the groan's resonance follows.
    private mutating func retune() {
        retuneCountdown = 32
        wander = min(0.12, max(-0.12, wander + 0.01 * (Double(nextUnit()) - 0.5)))
        pitch += (targetPitch * (1 + wander) - pitch) * 0.03
        groan.tune(frequency: 2 * pitch * grainDetune, q: 3, sampleRate: sampleRate)
    }

    /// 0..<1 from a xorshift64* generator: deterministic per seed.
    private mutating func nextUnit() -> Float {
        random ^= random >> 12
        random ^= random << 25
        random ^= random >> 27
        let value = random &* 0x2545_F491_4F6C_DD1D
        return Float(value >> 40) / Float(1 << 24)
    }
}

/// A two-pole band-pass (RBJ's constant 0 dB peak), transposed direct form II. Retuning keeps its state, so a
/// gliding pitch doesn't click.
private struct Resonator {
    private var b0: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    private var z1: Float = 0
    private var z2: Float = 0

    init() {}

    init(frequency: Double, q: Double, sampleRate: Double) {
        tune(frequency: frequency, q: q, sampleRate: sampleRate)
    }

    mutating func tune(frequency: Double, q: Double, sampleRate: Double) {
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        b0 = Float(alpha / a0)
        a1 = Float(-2 * cos(w0) / a0)
        a2 = Float((1 - alpha) / a0)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = -a1 * y + z2
        z2 = -b0 * x - a2 * y
        return y
    }

    mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

/// A two-pole low-pass (RBJ), transposed direct form II.
private struct Biquad {
    private var b0: Float = 1
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    private var z1: Float = 0
    private var z2: Float = 0

    init() {}

    init(lowpass frequency: Double, q: Double, sampleRate: Double) {
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        let cosw = cos(w0)
        b0 = Float((1 - cosw) / 2 / a0)
        b1 = Float((1 - cosw) / a0)
        b2 = b0
        a1 = Float(-2 * cosw / a0)
        a2 = Float((1 - alpha) / a0)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

/// Up to six grains' loudness envelopes at once. The array is made once and only ever written in place, so the
/// audio thread never allocates. Each grain rises over its attack and falls as a raised cosine.
private struct GrainEnvelopes {
    private struct Grain {
        var age = 0
        var length = 0
        var attack = 1
        var amplitude: Float = 0
        var isActive: Bool { age < length }
    }

    private var grains = ContiguousArray(repeating: Grain(), count: 6)
    private var next = 0

    var isEmpty: Bool { grains.allSatisfy { !$0.isActive } }

    mutating func start(length: Int, attack: Int, amplitude: Float) {
        let attack = max(attack, 1)
        // A free slot, else the oldest.
        let slot = grains.firstIndex { !$0.isActive } ?? next
        grains[slot] = Grain(age: 0, length: max(length, attack + 1), attack: attack, amplitude: amplitude)
        next = (slot + 1) % grains.count
    }

    /// The summed loudness for this sample; ages every grain by one.
    mutating func advance() -> Float {
        var sum: Float = 0
        for index in grains.indices where grains[index].isActive {
            let grain = grains[index]
            let level: Float
            if grain.age < grain.attack {
                // Starts at a fifth, so the grain's first sample is already heard.
                level = 0.2 + 0.8 * Float(grain.age) / Float(grain.attack)
            } else {
                let fall = Float(grain.age - grain.attack) / Float(grain.length - grain.attack)
                level = 0.5 + 0.5 * cosf(Float.pi * fall)
            }
            sum += level * grain.amplitude
            grains[index].age += 1
        }
        return sum
    }
}

/// Knocks waiting to fire, in samples from now (made once, written in place, as above).
private struct PendingClicks {
    private struct Click {
        var wait = -1
        var amplitude: Float = 0
    }

    private var clicks = ContiguousArray(repeating: Click(), count: 8)
    private(set) var firedAmplitude: Float = 0

    var isEmpty: Bool { clicks.allSatisfy { $0.wait < 0 } }

    mutating func schedule(in samples: Int, amplitude: Float) {
        if let slot = clicks.firstIndex(where: { $0.wait < 0 }) {
            clicks[slot] = Click(wait: samples, amplitude: amplitude)
        }
    }

    /// True when a knock fires on this sample (its loudness in `firedAmplitude`).
    mutating func advance() -> Bool {
        var fired = false
        for index in clicks.indices where clicks[index].wait >= 0 {
            if clicks[index].wait == 0 {
                firedAmplitude = fired ? max(firedAmplitude, clicks[index].amplitude) : clicks[index].amplitude
                fired = true
            }
            clicks[index].wait -= 1
        }
        return fired
    }
}
