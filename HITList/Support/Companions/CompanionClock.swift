import Foundation

/// What a companion draws at one moment: a frame, mirrored or not.
struct CompanionPose: Equatable {
    let frame: Int
    let mirrored: Bool
}

/// Where a companion's life stands, as the director keeps it: since when it has been on screen, which way it
/// faced then, and the flourishes it has started since (oldest first). The clock turns this and a time into
/// a pose.
struct CompanionStage: Equatable {
    /// When it came on screen; the idle's first loop starts here.
    var since: Date
    /// Facing the other way at `since` (after an odd number of Quill's turns).
    var turned = false
    /// Flourish start times since `since`, oldest first; they never overlap.
    var plays: [Date] = []
}

/// The pure clock (brief 76): from the time, the stage and a seed, which frame to draw, and when the drawing
/// next changes. The idle is a run of loops, one picked per cycle by weight from the seed and the cycle's
/// number, each starting and ending on the rest frame; a flourish plays from its start time to its end, then the
/// idle starts again on the rest frame (turned round if the flourish turns). Tests pin it.
struct CompanionClock {
    let character: CompanionCharacter
    let seed: UInt64

    /// The pose at `now`, or the rest frame when `still` (Reduce Motion).
    func pose(at now: Date, stage: CompanionStage, still: Bool = false) -> CompanionPose {
        let played = stage.plays.filter { $0 <= now }
        let turnsBefore = character.flourishTurns ? played.count : 0
        if still {
            // The finished flourishes still count: a still Quill lies whichever way it last curled up.
            let finished = character.flourishTurns ? played.filter { now >= end(of: $0) }.count : 0
            return CompanionPose(frame: character.restFrame, mirrored: stage.turned != (finished % 2 == 1))
        }
        if let last = played.last, now < end(of: last) {
            let tick = min(character.flourish.count - 1, Self.tick(now.timeIntervalSince(last), fps: character.flourishFPS))
            let entry = character.flourish[tick]
            let facing = stage.turned != ((turnsBefore - 1) % 2 == 1)
            return CompanionPose(frame: character.frameIndex(entry), mirrored: facing != entry.mirrored)
        }
        let facing = stage.turned != (turnsBefore % 2 == 1)
        let anchor = played.last.map(end(of:)) ?? stage.since
        let entry = idleTick(at: now, anchor: anchor)
        return CompanionPose(frame: character.frameIndex(entry), mirrored: facing != entry.mirrored)
    }

    /// The first moment after `now` at which `pose` may differ (a tick boundary where the frame changes, a known
    /// flourish's start or end). Held frames are skipped, so a still stretch of idle costs no redraws.
    func nextChange(after now: Date, stage: CompanionStage) -> Date {
        let current = pose(at: now, stage: stage)
        let upcoming = stage.plays.first { $0 > now }
        var t = nextTickBoundary(after: now, stage: stage)
        // Look ahead at most one idle cycle or one flourish for a tick whose frame differs.
        let limit = now.addingTimeInterval(max(character.idleCycle, character.flourishDuration) + 1)
        var steps = 0
        while t < limit, steps < 512 {
            steps += 1
            if let upcoming, upcoming <= t { return upcoming }
            if pose(at: t, stage: stage) != current { return t }
            t = nextTickBoundary(after: t, stage: stage)
        }
        return upcoming.map { min($0, t) } ?? t
    }

    func end(of play: Date) -> Date { play.addingTimeInterval(character.flourishDuration) }

    /// Whether a flourish is playing at `now`.
    func isFlourishing(at now: Date, stage: CompanionStage) -> Bool {
        guard let last = stage.plays.last(where: { $0 <= now }) else { return false }
        return now < end(of: last)
    }

    // MARK: - Idle

    /// The idle tick at `now` for an idle that began at `anchor`.
    func idleTick(at now: Date, anchor: Date) -> CompanionCharacter.Tick {
        let ticks = Self.tick(now.timeIntervalSince(anchor), fps: character.idleFPS)
        let length = character.idleLength
        let loop = loop(forCycle: ticks / length, anchor: anchor)
        return loop.ticks[ticks % length]
    }

    /// The loop for the `cycle`th cycle of an idle that began at `anchor`: weighted, from the seed. The first
    /// cycle is always the first (plainest) loop, so a companion arriving on screen settles before it blinks.
    func loop(forCycle cycle: Int, anchor: Date) -> CompanionCharacter.Loop {
        let loops = character.idle
        guard cycle > 0, loops.count > 1 else { return loops[0] }
        let total = loops.reduce(0) { $0 + $1.weight }
        let key = UInt64(bitPattern: Int64((anchor.timeIntervalSinceReferenceDate * 1000).rounded()))
        var pick = Int(CompanionRandom.mix(seed ^ CompanionRandom.mix(key) ^ CompanionRandom.mix(UInt64(cycle))) % UInt64(total))
        for loop in loops {
            if pick < loop.weight { return loop }
            pick -= loop.weight
        }
        return loops[0]
    }

    private func nextTickBoundary(after t: Date, stage: CompanionStage) -> Date {
        let played = stage.plays.filter { $0 <= t }
        if let last = played.last, t < end(of: last) {
            let tick = Self.tick(t.timeIntervalSince(last), fps: character.flourishFPS) + 1
            let next = min(end(of: last), last.addingTimeInterval(Double(tick) / character.flourishFPS))
            return next > t ? next : min(end(of: last), t.addingTimeInterval(1 / character.flourishFPS))
        }
        let anchor = played.last.map(end(of:)) ?? stage.since
        let tick = Self.tick(t.timeIntervalSince(anchor), fps: character.idleFPS) + 1
        let next = anchor.addingTimeInterval(Double(tick) / character.idleFPS)
        return next > t ? next : t.addingTimeInterval(1 / character.idleFPS)
    }

    /// The tick `elapsed` seconds in, at `fps`. A hair of slack, so a moment computed as a tick's start (which a
    /// `Date` far from its reference can round a nanosecond early) counts as that tick and not the one before.
    static func tick(_ elapsed: TimeInterval, fps: Double) -> Int {
        max(0, Int((elapsed * fps + 1e-6).rounded(.down)))
    }
}

/// A tiny seeded mixer (SplitMix64's finaliser): the same input always gives the same output, so the idle and
/// the schedule can be pinned by tests.
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
