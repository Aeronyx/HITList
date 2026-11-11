import Foundation
import HITListCore

/// What a companion draws at one moment: an index into `CompanionCharacter.drawn`, mirrored or not.
struct CompanionPose: Equatable {
    let frame: Int
    let mirrored: Bool
}

/// One thing a companion does: a small gesture (by its index in the mode's `gestures`), a routine (by its index in
/// the mode's `routines`), the reply to a tap, or the rare flourish, from `start`.
struct CompanionAct: Equatable {
    enum Kind: Equatable {
        case gesture(Int)
        case routine(Int)
        case answer
        case flourish
    }

    let kind: Kind
    let start: Date
}

/// Where a companion's life stands, as the director keeps it: since when it has been on screen, in which place,
/// how it is dressed (`look`, and the `sky` it was dressed for, both decided while nobody is looking), which way it
/// faced before its last act, and that act. The clock turns this and a time into a pose.
struct CompanionStage: Equatable {
    /// When it came on screen.
    var since: Date
    var place: CompanionPlace
    var look: CompanionLook
    /// Facing the other way before `act` (after an odd number of Quill's turns).
    var turned = false
    /// What it is doing; nil at rest (the director puts an act away when it ends).
    var act: CompanionAct?
    /// The sky the look was decided for: which weather routines it may play (storm and rain share a look).
    var sky: CompanionSky = .unknown
    /// Brief 91: how deep the snow has piled, in frames past `snow` (0: the bare `snow`).
    var snowDepth = 0
}

/// The pure clock (briefs 76, 79 and 84): from the time and the stage, which frame to draw and when the drawing next
/// changes. At rest it is the still frame for the look, and nothing changes until the director starts an act; an
/// act's ticks play at their rate and end on the rest frame again. Tests pin it.
struct CompanionClock {
    let character: CompanionCharacter

    /// The ticks an act plays, and their rate. A routine's ticks are flattened from its steps.
    func ticks(_ kind: CompanionAct.Kind, stage: CompanionStage) -> (ticks: [CompanionCharacter.Tick], fps: Double) {
        let posture = character.posture(stage.place)
        let mode = posture.mode(stage.look)
        switch kind {
        case .flourish:
            return (posture.flourish, character.flourishFPS)
        case .answer:
            return (mode.answer.ticks, character.gestureFPS)
        case .gesture(let i):
            let gestures = mode.gestures
            guard gestures.indices.contains(i) else { return ([], character.gestureFPS) }
            return (gestures[i].ticks, character.gestureFPS)
        case .routine(let i):
            guard mode.routines.indices.contains(i) else { return ([], character.gestureFPS) }
            return (mode.ticks(of: mode.routines[i]).map(\.tick), character.gestureFPS)
        }
    }

    /// What each tick of an act draws (its frame in `drawn`, and whether that tick is mirrored on its own), and the
    /// rate; nil when it cannot be drawn in the stage's look (a gesture that would cut through a pile of snow). The
    /// flourish and the weather's own frames are drawn whole; everything else over the still frame for the weather
    /// (only the pixels it changes), and the still frame itself is the weather's, as deep as the snow has piled. A
    /// shake-off shows the bare snow from its first frame of its own on.
    func drawing(_ kind: CompanionAct.Kind, stage: CompanionStage) -> (frames: [CompanionPose], fps: Double)? {
        let mode = character.posture(stage.place).mode(stage.look)
        let weather = stage.look.weather
        if case .flourish = kind {
            let (ticks, fps) = ticks(kind, stage: stage)
            return (ticks.map { CompanionPose(frame: character.drawnIndex($0.frame), mirrored: $0.mirrored) }, fps)
        }
        var entries: [(tick: CompanionCharacter.Tick, whole: Bool)]
        var sky: CompanionSky?
        var shakes = false
        switch kind {
        case .routine(let i) where mode.routines.indices.contains(i):
            let routine = mode.routines[i]
            entries = mode.ticks(of: routine)
            sky = routine.sky
            shakes = routine.shakesOff && weather == .snow
        case .gesture(let i) where mode.gestures.indices.contains(i):
            let gesture = mode.gestures[i]
            entries = gesture.ticks.map { ($0, gesture.sky != nil) }
            sky = gesture.sky
        default:
            entries = ticks(kind, stage: stage).ticks.map { ($0, false) }
        }
        var out: [CompanionPose] = []
        out.reserveCapacity(entries.count)
        var gone = false
        for entry in entries {
            if shakes, entry.whole { gone = true }
            let depth = gone ? 0 : stage.snowDepth
            let frame: Int?
            if shakes, entry.whole {
                frame = character.index[entry.tick.frame]
            } else {
                frame = character.draw(entry.tick, whole: entry.whole, sky: sky, mode: mode, weather: weather, depth: depth)
            }
            guard let frame else { return nil }
            out.append(CompanionPose(frame: frame, mirrored: entry.tick.mirrored))
        }
        return (out, character.gestureFPS)
    }

    /// The same, falling back to the still frame for a tick that cannot be drawn.
    func frames(_ kind: CompanionAct.Kind, stage: CompanionStage) -> (frames: [CompanionPose], fps: Double) {
        if let drawn = drawing(kind, stage: stage) { return drawn }
        let still = restPose(at: .distantPast, stage: CompanionStage(since: stage.since, place: stage.place,
                                                                     look: stage.look, turned: false, sky: stage.sky,
                                                                     snowDepth: stage.snowDepth))
        let count = ticks(kind, stage: stage).ticks.count
        return (Array(repeating: CompanionPose(frame: still.frame, mirrored: false), count: count), character.gestureFPS)
    }

    /// Whether an act can be drawn in the stage's look.
    func canDraw(_ kind: CompanionAct.Kind, stage: CompanionStage) -> Bool { drawing(kind, stage: stage) != nil }

    /// How deep the snow is at `now`: after a shake-off has ended, the bare snow.
    func snowDepth(at now: Date, stage: CompanionStage) -> Int {
        guard stage.look.weather == .snow, let act = stage.act, case .routine(let i) = act.kind else { return stage.snowDepth }
        let mode = character.posture(stage.place).mode(stage.look)
        guard mode.routines.indices.contains(i), mode.routines[i].shakesOff, now >= end(of: act, stage: stage) else {
            return stage.snowDepth
        }
        return 0
    }

    func duration(_ kind: CompanionAct.Kind, stage: CompanionStage) -> TimeInterval {
        let (ticks, fps) = ticks(kind, stage: stage)
        return Double(ticks.count) / fps
    }

    func end(of act: CompanionAct, stage: CompanionStage) -> Date {
        act.start.addingTimeInterval(duration(act.kind, stage: stage))
    }

    /// Whether an act is playing at `now`.
    func isActing(at now: Date, stage: CompanionStage) -> Bool {
        guard let act = stage.act else { return false }
        return now >= act.start && now < end(of: act, stage: stage)
    }

    /// Which way it faces at rest at `now`: after a flourish that turns it, the other way. Never turned in a place
    /// where it doesn't turn (Quill on the "+").
    func facing(at now: Date, stage: CompanionStage) -> Bool {
        guard character.turns(stage.place) else { return false }
        guard let act = stage.act, act.kind == .flourish, now >= end(of: act, stage: stage) else { return stage.turned }
        return !stage.turned
    }

    /// The still frame for the stage's look (as deep as the snow has piled), facing the way it faces at `now`.
    func restPose(at now: Date, stage: CompanionStage) -> CompanionPose {
        let mode = character.posture(stage.place).mode(stage.look)
        let still = mode.still(stage.look.weather, depth: snowDepth(at: now, stage: stage))
        return CompanionPose(frame: character.drawnIndex(still), mirrored: facing(at: now, stage: stage))
    }

    /// The pose at `now`; the still frame when `still` (Reduce Motion).
    func pose(at now: Date, stage: CompanionStage, still: Bool = false) -> CompanionPose {
        guard !still, let act = stage.act, isActing(at: now, stage: stage) else {
            return restPose(at: now, stage: stage)
        }
        let (frames, fps) = frames(act.kind, stage: stage)
        guard !frames.isEmpty else { return restPose(at: now, stage: stage) }
        let i = min(frames.count - 1, Self.tick(now.timeIntervalSince(act.start), fps: fps))
        let entry = frames[i]
        let turned = character.turns(stage.place) && stage.turned
        return CompanionPose(frame: entry.frame, mirrored: turned != entry.mirrored)
    }

    /// The first moment after `now` at which `pose` differs; nil when it won't change again until the director
    /// starts another act (a still companion costs no redraws). Held frames are skipped.
    func nextChange(after now: Date, stage: CompanionStage) -> Date? {
        guard let act = stage.act else { return nil }
        let end = end(of: act, stage: stage)
        guard now < end else { return nil }
        let current = pose(at: now, stage: stage)
        let (frames, fps) = frames(act.kind, stage: stage)
        let turned = character.turns(stage.place) && stage.turned
        var k = now < act.start ? 0 : Self.tick(now.timeIntervalSince(act.start), fps: fps) + 1
        while k < frames.count {
            let t = act.start.addingTimeInterval(Double(k) / fps)
            let entry = frames[k]
            let pose = CompanionPose(frame: entry.frame, mirrored: turned != entry.mirrored)
            if t > now, pose != current { return t }
            k += 1
        }
        return pose(at: end, stage: stage) != current ? end : nil
    }

    /// The tick `elapsed` seconds in, at `fps`. A hair of slack, so a moment computed as a tick's start (which a
    /// `Date` far from its reference can round a nanosecond early) counts as that tick and not the one before.
    static func tick(_ elapsed: TimeInterval, fps: Double) -> Int {
        // One step per line: the CI runner's older Swift is slow to type-check mixed arithmetic.
        let ticks: Double = elapsed * fps
        let slack: Double = ticks + 1e-6
        let whole: Int = Int(slack.rounded(.down))
        return max(0, whole)
    }
}

/// A tiny seeded mixer (SplitMix64's finaliser): the same input always gives the same output, so the schedule can
/// be pinned by tests.
enum CompanionRandom {
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in 0..<1 from `seed` and `index`.
    static func unit(_ seed: UInt64, _ index: Int) -> Double {
        let key: UInt64 = mix(UInt64(bitPattern: Int64(index)))
        let mixed: UInt64 = mix(seed ^ key)
        let top: UInt64 = mixed >> 11
        let scale: Double = 9_007_199_254_740_992    // 2^53
        return Double(top) / scale
    }

    /// A stable seed for a name (`String.hashValue` changes from launch to launch).
    static func seed(_ name: String) -> UInt64 {
        let prime: UInt64 = 0x0000_0100_0000_01B3
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in name.utf8 {
            let xored: UInt64 = hash ^ UInt64(byte)
            hash = xored &* prime
        }
        return hash
    }
}
