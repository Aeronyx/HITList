import Foundation

/// The squeaky hinge's sound, made from nothing (brief 50: no recordings, no third-party audio). A value type
/// that only the audio thread touches (`HingeCreakEngine`): no allocation (its few arrays are made once and
/// written in place), no locks, no Objective-C while rendering, so it can run inside the render callback.
///
/// Two layers, both driven by grains (one per few degrees of travel, `HingeCreakMotion`):
/// - **The squeak**: friction's stick-slip as a pulse train with a little timing jitter, at a pitch that rises
///   with the hinge's speed (380 → 820 Hz; closing a touch lower) and wanders slowly, through a body resonance
///   at the pitch and a pair of narrow resonances near its third harmonic tuned 2% apart, so they beat like a
///   hinge pin that isn't quite round. Each grain swells and fades its loudness: slow travel chirps
///   "ee-ee-ee", fast travel runs together into one squeal.
/// - **The creak**: each grain also drops two to four short noise clicks, 6–14 ms apart, into low wooden
///   resonances (165, 270, 440 Hz and a 1.25 kHz crack): the ratchet of a door's wood. Strongest when slow.
///
/// Then a DC blocker and a soft limiter (`ceiling`): however hard the phone is flung open, the peak never passes
/// -12 dBFS. A kick starts a grain on the first sample of the next buffer, and its first impulse rings at once.
struct HingeCreakSynth {
    /// The soft limiter's ceiling: -12 dBFS.
    static let ceiling: Float = 0.25

    let sampleRate: Double
    private var random: UInt64

    // The drive.
    private var intensity = 0.0
    private var grainRate = 0.0
    private var opening = true
    private var sustainFrames = 0
    private var grainPhase = 0.0

    // The squeak: one voice, its loudness the sum of the grains' envelopes.
    private var pitch = 0.0
    private var wander = 0.0
    private var pulsePhase = 0.0
    private var pulseIncrement = 0.0
    private var body = Resonator()
    private var upper = Resonator()
    private var lower = Resonator()
    private var retuneCountdown = 0
    private var grains = GrainEnvelopes()

    // The creak: clicks waiting to fire, and the click sounding now.
    private var clicks = PendingClicks()
    private var clickLeft = 0
    private var clickAmplitude: Float = 0
    private var wood0 = Resonator()
    private var wood1 = Resonator()
    private var wood2 = Resonator()
    private var crack = Resonator()

    // Output.
    private var dcIn: Float = 0
    private var dcOut: Float = 0
    /// Samples since the output last moved; past `quietAfter` the synth is silent.
    private var quietFrames = HingeCreakSynth.quietAfter + 1

    init(sampleRate: Double, seed: UInt64 = 0x4849_4E47_4543_5245) {
        self.sampleRate = sampleRate
        random = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        wood0 = Resonator(frequency: 165, q: 7, sampleRate: sampleRate)
        wood1 = Resonator(frequency: 270, q: 6, sampleRate: sampleRate)
        wood2 = Resonator(frequency: 440, q: 5, sampleRate: sampleRate)
        crack = Resonator(frequency: 1250, q: 3, sampleRate: sampleRate)
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
        if isSilent && grains.isEmpty && clicks.isEmpty {
            out.update(repeating: 0, count: count)
            return false
        }
        let grainStep = grainRate / sampleRate
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

            // The squeak: stick-slip pulses through the pin's resonances, as loud as the grains say.
            var excitation: Float = 0
            pulsePhase += pulseIncrement
            if pulsePhase >= 1 {
                pulsePhase -= 1
                excitation = 0.8 + 0.2 * nextUnit()
                // The next slip comes a little early or late.
                pulseIncrement = pitch * (1 + 0.03 * (Double(nextUnit()) - 0.5)) / sampleRate
            }
            let loudness = min(1, grains.advance())
            let pin = 0.55 * body.process(excitation) + upper.process(excitation) + lower.process(excitation)
            let squeak = pin * loudness * squeakLevel

            // The creak: clicks of noise into the wood.
            var click: Float = 0
            if clicks.advance() { startClick() }
            if clickLeft > 0 {
                clickLeft -= 1
                clickAmplitude *= Self.clickDecay
                click = clickAmplitude * (2 * nextUnit() - 1)
            }
            let wood = wood0.process(click) + 0.8 * wood1.process(click) + 0.6 * wood2.process(click)
                + 0.25 * crack.process(click)

            // Mix, block DC, limit softly.
            let mixed = Self.squeakGain * squeak + Self.woodGain * wood
            let blocked = mixed - dcIn + 0.995 * dcOut
            dcIn = mixed
            dcOut = blocked
            let sample = Self.ceiling * tanhf(blocked / Self.ceiling)
            out[index] = sample
            if abs(sample) < 1e-6 && grains.isEmpty && clickLeft == 0 {
                if quietFrames <= Self.quietAfter { quietFrames += 1 }
            } else {
                quietFrames = 0
            }
        }
        if isSilent {
            // Rung out: clear the filters' last traces so the next creak starts clean.
            body.reset(); upper.reset(); lower.reset()
            wood0.reset(); wood1.reset(); wood2.reset(); crack.reset()
            dcIn = 0; dcOut = 0
        }
        return true
    }

    // MARK: Grains

    private static let quietAfter = 2_048
    private static let squeakGain: Float = 2.0
    private static let woodGain: Float = 3.2
    private static let clickDecay: Float = 0.965

    private var targetPitch: Double { (380 + 440 * intensity) * (opening ? 1 : 0.88) }
    private var squeakLevel: Float { Float(0.35 + 0.65 * intensity) }
    private var creakLevel: Float { Float(1 - 0.4 * intensity) }

    private mutating func startGrain() {
        // Shorter, brighter grains as the hinge speeds up; each a little different.
        let seconds = (0.09 - 0.035 * intensity) * (0.85 + 0.3 * Double(nextUnit()))
        grains.start(length: Int(seconds * sampleRate), attack: Int(0.0015 * sampleRate),
                     amplitude: 0.75 + 0.25 * nextUnit())
        if pulseIncrement == 0 || quietFrames > 0 {
            // From quiet, the first slip is now: the creak is heard from the first sample.
            pulsePhase = 1
            pulseIncrement = pitch / sampleRate
        }
        let count = 2 + Int(nextUnit() * 2.99)
        var at = 0
        for _ in 0..<count {
            clicks.schedule(in: at, amplitude: creakLevel * (0.6 + 0.4 * nextUnit()))
            at += Int((0.006 + 0.008 * Double(nextUnit())) * sampleRate)
        }
        quietFrames = 0
    }

    private mutating func startClick() {
        clickAmplitude = clicks.firedAmplitude
        clickLeft = Int(0.004 * sampleRate)
    }

    /// Every 32 samples: the pitch glides toward the speed's and wanders a little; the resonances follow.
    private mutating func retune() {
        retuneCountdown = 32
        wander = min(0.03, max(-0.03, wander + 0.004 * (Double(nextUnit()) - 0.5)))
        pitch += (targetPitch * (1 + wander) - pitch) * 0.05
        body.tune(frequency: pitch, q: 5, sampleRate: sampleRate)
        upper.tune(frequency: pitch * 3.03, q: 20, sampleRate: sampleRate)
        lower.tune(frequency: pitch * 2.97, q: 20, sampleRate: sampleRate)
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

/// Clicks waiting to fire, in samples from now (made once, written in place, as above).
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

    /// True when a click fires on this sample (its loudness in `firedAmplitude`).
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
