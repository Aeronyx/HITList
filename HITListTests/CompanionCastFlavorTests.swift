import XCTest
import HITListCore
@testable import HITList

/// Brief 105: each creature moves like itself. George, the evening 0.9.4 went out: "Please don't be lazy and just have
/// every creature with feet swing their feet as a part of their idle animations […] Each animation should match the
/// vibe of its creature." For the six this brief redrew (Nod, Quill, Tuck, Hush, Glim, Phase), in both places: enough
/// idles of their own (awake six flickers and four little loops, asleep three), the blink still the most common, and
/// over half an hour awake on the "+" at most a fifth of what each does is a foot swinging (a move that changes only
/// what hangs below the line it sits on, other than a tail, an ear or a lantern: Nod's legs are the only feet among
/// the six that swing at all now, slowly and one at a time).
@MainActor
final class CompanionCastFlavorTests: XCTestCase {
    static let six = ["nod", "quill", "tuck", "hush", "glim", "phase"]

    func testEachHasEnoughIdlesOfItsOwn() {
        for character in CompanionCharacter.all where Self.six.contains(character.id) {
            XCTAssertEqual(character.problems, [], character.id)
            for place in CompanionPlace.allCases {
                let posture = character.posture(place)
                let awake = posture.awake
                let at = "\(character.id) \(place)"
                let everyday = awake.flickers.filter { awake.gestures[$0].sky == nil }
                XCTAssertGreaterThanOrEqual(everyday.count, 6, "\(at): six flickers")
                XCTAssertGreaterThanOrEqual(awake.routines.filter { $0.little && $0.sky == nil }.count, 4, "\(at): four little loops")
                XCTAssertGreaterThanOrEqual(awake.routines.filter { !$0.little && $0.sky == nil }.count, 3, "\(at): three routines")
                XCTAssertGreaterThanOrEqual(posture.asleep.flickers.count, 3, "\(at): three breaths asleep")
                let heaviest = everyday.map { awake.gestures[$0].weight }.max() ?? 0
                XCTAssertEqual(awake.gesture(named: "blink")?.weight, heaviest, "\(at): the blink the most common")
            }
        }
    }

    /// Brief 105: the glances one pixel wide and the twitches every eared creature had are gone as idles; what is left
    /// is drawn at a size that reads at 1x (more than two pixels change somewhere in it).
    func testNoIdleIsTooSmallToSee() {
        for character in CompanionCharacter.all where Self.six.contains(character.id) {
            for place in CompanionPlace.allCases {
                let awake = character.posture(place).awake
                for index in awake.flickers where awake.gestures[index].sky == nil {
                    let gesture = awake.gestures[index]
                    let most = gesture.ticks.map { character.difference($0.frame, awake.rest) }.max() ?? 0
                    XCTAssertGreaterThanOrEqual(most, 2, "\(character.id) \(place) \(gesture.name)")
                }
            }
        }
    }

    /// Half an hour on the "+" by day, as George watches it: how often a foot swings.
    func testFeetSwingAtMostAFifthOfTheTime() {
        var report: [String] = []
        for character in CompanionCharacter.all where Self.six.contains(character.id) {
            let d = CompanionDirector(seed: 11, launch: .none, observeSystem: false, cast: [character], defaults: nil,
                                      zone: { TimeZone(identifier: "UTC")! }, sky: { .clouds })
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 10))!
            d.appear(character.id, place: .plus, still: false, calm: false, now: start)
            let mode = character.plus.awake
            var idles = 0
            var feet = 0
            var steps = 0
            while let next = d.nextMoment, next < start.addingTimeInterval(1_800), steps < 20_000 {
                steps += 1
                d.fire(now: next)
                guard let act = d.stages[character.id]?.act, act.start == next else { continue }
                var frames: [String] = []
                switch act.kind {
                case .gesture(let g): frames = mode.gestures[g].ticks.map(\.frame)
                case .routine(let r) where mode.routines[r].little: frames = mode.ticks(of: mode.routines[r]).map(\.tick.frame)
                default: continue
                }
                idles += 1
                if Self.onlyFeet(character, frames: frames, rest: mode.rest) { feet += 1 }
            }
            let share: Double = Double(feet) / Double(max(idles, 1))
            report.append("\(character.id): \(feet) of \(idles) idles a foot swinging")
            XCTAssertGreaterThan(idles, 40, character.id)
            XCTAssertLessThanOrEqual(share, 0.2, "\(character.id): \(feet) of \(idles) idles a foot swinging")
        }
        print("Companion feet:\n" + report.joined(separator: "\n"))
    }

    /// Every frame of it that moves anything moves only legs below the seat line: pixels on rows below `seatRow` that
    /// are its own legs (not a tail, an ear, a lantern or a hem, which `legs` leaves out).
    static func onlyFeet(_ character: CompanionCharacter, frames: [String], rest: String) -> Bool {
        guard let legs = Self.legs[character.id] else { return false }
        var moved = false
        guard let r = character.rows(rest)?.map(Array.init) else { return false }
        for frame in frames where frame != rest {
            guard let f = character.rows(frame)?.map(Array.init) else { continue }
            for y in 0..<min(f.count, r.count) {
                for x in 0..<min(f[y].count, r[y].count) where f[y][x] != r[y][x] {
                    if y < character.seatRow || !legs.contains(x) { return false }
                    moved = true
                }
            }
        }
        return moved
    }

    /// The columns of each one's legs below the seat line (only Nod has any that swing).
    static let legs: [String: ClosedRange<Int>] = ["nod": 5...12]
}
