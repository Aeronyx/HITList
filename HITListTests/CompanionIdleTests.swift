import XCTest
import HITListCore
@testable import HITList

/// Brief 100, item 1: enough idles to stay fresh at an idle every 6 to 36 seconds. For each of Nod, Quill, Tuck, Hush
/// and Glim, in both places: awake at least five flickers and three little loops of its own, the blink the heaviest
/// flicker; asleep at least two; every little loop two to four moves in at most 2.5 s and drawn in plain weather; and
/// over a simulated ten minutes awake, at least eight different idles come up.
@MainActor
final class CompanionIdleTests: XCTestCase {
    static let five = ["nod", "quill", "tuck", "hush", "glim"]

    func testEnoughIdlesForEach() {
        for character in CompanionCharacter.all where Self.five.contains(character.id) {
            XCTAssertEqual(character.problems, [], character.id)
            for place in CompanionPlace.allCases {
                let posture = character.posture(place)
                let awake = posture.awake
                let at = "\(character.id) \(place)"
                let everyday = awake.flickers.filter { awake.gestures[$0].sky == nil }
                XCTAssertGreaterThanOrEqual(everyday.count, 5, "\(at): five flickers of every sky")
                let loops = awake.routines.filter(\.little)
                XCTAssertGreaterThanOrEqual(loops.filter { $0.sky == nil }.count, 3, "\(at): three little loops")
                let heaviest = everyday.max { awake.gestures[$0].weight < awake.gestures[$1].weight }
                XCTAssertEqual(heaviest.map { awake.gestures[$0].name }, "blink", "\(at): the blink the most common")
                for loop in loops {
                    XCTAssertTrue(CompanionCharacter.littleMoves.contains(loop.moves), "\(at) \(loop.name)")
                    XCTAssertLessThanOrEqual(character.duration(of: loop, mode: awake), CompanionCharacter.littleLongest)
                    XCTAssertTrue(character.plays(loop, in: .plain, mode: awake), "\(at) \(loop.name) in plain weather")
                }
                XCTAssertGreaterThanOrEqual(posture.asleep.flickers.count, 3, "\(at): three idles asleep, so they don't just take turns")
            }
        }
    }

    /// The first 100 seconds after it comes on screen, as the app starts (its own launch arguments, a fresh store, a
    /// random seed), over many launches: still about one idle in three a little loop, from the first idle on.
    func testTheFirstIdlesOfALaunch() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
        let launch = CompanionLaunchOptions(arguments: ["-seedDemoData", "YES", "-companionHour", "12"])
        for character in CompanionCharacter.all where Self.five.contains(character.id) {
            var idles = 0
            var loops = 0
            for seed in 0..<300 as Range<UInt64> {
                let name = "CompanionIdleTests.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: name)!
                let d = CompanionDirector(seed: CompanionRandom.mix(seed), launch: launch, observeSystem: false,
                                          cast: CompanionCharacter.all, defaults: defaults,
                                          zone: { TimeZone(identifier: "UTC")! }, sky: { .unknown })
                d.appear(character.id, place: .plus, still: false, calm: false, now: start)
                let mode = character.plus.awake
                var steps = 0
                while let next = d.nextMoment, next < start.addingTimeInterval(100), steps < 1_000 {
                    steps += 1
                    d.fire(now: next)
                    guard let act = d.stages[character.id]?.act, act.start == next else { continue }
                    switch act.kind {
                    case .gesture: idles += 1
                    case .routine(let r) where mode.routines[r].little:
                        idles += 1
                        loops += 1
                    default: break
                    }
                }
                defaults.removePersistentDomain(forName: name)
            }
            let share: Double = Double(loops) / Double(idles)
            print("Companion \(character.id): \(loops) loops in \(idles) idles in the first 100 s of 300 launches")
            XCTAssertEqual(share, 1.0 / 3, accuracy: 0.05, "\(character.id): \(loops) of \(idles)")
        }
    }

    /// Ten minutes on the "+" by day and ten asleep, as George watched: how many different idles came up.
    func testTenMinutesOfIdles() {
        var report: [String] = []
        for character in CompanionCharacter.all where Self.five.contains(character.id) {
            for (hour, label) in [(10, "awake"), (23, "asleep")] {
                let d = CompanionDirector(seed: 7, launch: .none, observeSystem: false, cast: [character], defaults: nil,
                                          zone: { TimeZone(identifier: "UTC")! }, sky: { .clouds })
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC")!
                let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour))!
                d.appear(character.id, place: .plus, still: false, calm: false, now: start)
                let mode = character.plus.mode(d.stages[character.id]!.look)
                var names: [String] = []
                var steps = 0
                while let next = d.nextMoment, next < start.addingTimeInterval(600), steps < 10_000 {
                    steps += 1
                    d.fire(now: next)
                    guard let act = d.stages[character.id]?.act, act.start == next else { continue }
                    switch act.kind {
                    case .gesture(let g): names.append(mode.gestures[g].name)
                    case .routine(let r): names.append((mode.routines[r].little ? "~" : "") + mode.routines[r].name)
                    default: break
                    }
                }
                let distinct = Set(names).count
                XCTAssertGreaterThanOrEqual(distinct, label == "awake" ? 8 : 3, "\(character.id) \(label): \(names)")
                report.append("\(character.id) \(label): \(names.count) idles, \(distinct) different: \(names.joined(separator: " "))")
            }
        }
        let text = report.joined(separator: "\n")
        print("Companion idles:\n\(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "companion-idles.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
