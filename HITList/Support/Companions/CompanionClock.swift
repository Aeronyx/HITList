import Foundation

/// What a companion draws at one moment: an index into `CompanionCharacter.drawn`, mirrored or not.
struct CompanionPose: Equatable {
    let frame: Int
    let mirrored: Bool
}

/// One thing a companion does: a small gesture (by its index in the mode's `gestures`), the reply to a tap, or the
/// rare flourish, from `start`.
struct CompanionAct: Equatable {
    enum Kind: Equatable {
        case gesture(Int)
        case answer
        case flourish
    }

    let kind: Kind
    let start: Date
}

/// Where a companion's life stands, as the director keeps it: since when it has been on screen, in which place,
/// how it is dressed (`look`, decided while nobody is looking), which way it faced before its last act, and that
/// act. The clock turns this and a time into a pose.
struct CompanionStage: Equatable {
    /// When it came on screen.
    var since: Date
    var place: CompanionPlace
    var look: CompanionLook
    /// Facing the other way before `act` (after an odd number of Quill's turns).
    var turned = false
    /// What it is doing; nil at rest (the director puts an act away when it ends).
    var act: CompanionAct?
}

/// The pure clock (briefs 76 and 79): from the time and the stage, which frame to draw and when the drawing next
/// changes. At rest it is the still frame for the look, and nothing changes until the director starts an act; an
/// act's ticks play at their rate and end on the rest frame again. Tests pin it.
struct CompanionClock {
    let character: CompanionCharacter

    /// The ticks an act plays, and their rate.
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
        }
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

    /// Which way it faces at rest at `now`: after a flourish that turns it, the other way.
    func facing(at now: Date, stage: CompanionStage) -> Bool {
        guard character.flourishTurns, let act = stage.act, act.kind == .flourish, now >= end(of: act, stage: stage)
        else { return stage.turned }
        return !stage.turned
    }

    /// The still frame for the stage's look, facing the way it faces at `now`.
    func restPose(at now: Date, stage: CompanionStage) -> CompanionPose {
        let mode = character.posture(stage.place).mode(stage.look)
        let base = mode.base(stage.look.weather)
        return CompanionPose(frame: character.drawnIndex(base), mirrored: facing(at: now, stage: stage))
    }

    /// The pose at `now`; the still frame when `still` (Reduce Motion).
    func pose(at now: Date, stage: CompanionStage, still: Bool = false) -> CompanionPose {
        guard !still, let act = stage.act, isActing(at: now, stage: stage) else {
            return restPose(at: now, stage: stage)
        }
        let (ticks, fps) = ticks(act.kind, stage: stage)
        let i = min(ticks.count - 1, Self.tick(now.timeIntervalSince(act.start), fps: fps))
        let entry = ticks[i]
        let mirrored = stage.turned != entry.mirrored
        if act.kind == .flourish {
            return CompanionPose(frame: character.drawnIndex(entry.frame), mirrored: mirrored)
        }
        let mode = character.posture(stage.place).mode(stage.look)
        let base = mode.base(stage.look.weather)
        return CompanionPose(frame: character.drawnIndex(entry.frame, over: base, rest: mode.rest), mirrored: mirrored)
    }

    /// The first moment after `now` at which `pose` differs; nil when it won't change again until the director
    /// starts another act (a still companion costs no redraws). Held frames are skipped.
    func nextChange(after now: Date, stage: CompanionStage) -> Date? {
        guard let act = stage.act else { return nil }
        let end = end(of: act, stage: stage)
        guard now < end else { return nil }
        let current = pose(at: now, stage: stage)
        let (ticks, fps) = ticks(act.kind, stage: stage)
        var k = now < act.start ? 0 : Self.tick(now.timeIntervalSince(act.start), fps: fps) + 1
        while k < ticks.count {
            let t = act.start.addingTimeInterval(Double(k) / fps)
            if t > now, pose(at: t, stage: stage) != current { return t }
            k += 1
        }
        return pose(at: end, stage: stage) != current ? end : nil
    }

    /// The tick `elapsed` seconds in, at `fps`. A hair of slack, so a moment computed as a tick's start (which a
    /// `Date` far from its reference can round a nanosecond early) counts as that tick and not the one before.
    static func tick(_ elapsed: TimeInterval, fps: Double) -> Int {
        max(0, Int((elapsed * fps + 1e-6).rounded(.down)))
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
        Double(mix(seed ^ mix(UInt64(bitPattern: Int64(index)))) >> 11) / Double(1 << 53)
    }

    /// A stable seed for a name (`String.hashValue` changes from launch to launch).
    static func seed(_ name: String) -> UInt64 {
        name.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}
