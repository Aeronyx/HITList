import CryptoKit
import XCTest
@testable import HITList

/// Drawings George has said to keep (round 23, 2026-11-12, on 0.9.6: "Hush is actually the perfect example of a
/// good rework … Keep the new Hush"). A change to one of them fails here, so it is a decision and never a side
/// effect; the digests are of each frame's rows joined by newlines, computed once from the `v0.9.6` tag.
final class CompanionKeptTests: XCTestCase {
    private func digest(_ rows: [String]) -> String {
        SHA256.hash(data: Data(rows.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func testHushIsZeroNineSixsPixelForPixel() {
        let hush = CompanionCharacter.hush
        let stills: [String: String] = [
            "rest": "8af9d32c4e3282d1dab2f4125e8174905f8ecd589e1102f43a3a0c13938878dd",
            // Round 24 (brief 125): the rain's water on it, beads, a drop off the hood's tip and a puddle.
            "rain": "e6fad7c0288d33cc3cacea3a34685e5cb89a5cc670da5676a4ccb3879ccab4c4",
            "snow": "023acce6f3b4b4032fd606ad8f357d3287ad34e7c4a264ba64261e607cd6047a",
            "snow2": "aba47211be20ae991a66131bfb4eb6ffb1cea505e02f84c45bc35b8fd4e27e6b",
            "snow3": "f6c1adf7f42a2eca0dd2ef0cc0737f06319722d3ea41e9407e09f3fc066e0a42",
            "hot": "acdfa9b15cf307da37102ddf07e0de452434d8ee227b05a0f66e47d976da158d",
            "sleep": "0298cf25a8cd494c7324afa43fa80fdd5092b4d4bebc4970edb9c48e53632ca9",
            "sleepSnow": "a9762812a59ef167034bcb37407d07444feea808981d7e9fc257f07f344bec2c",
            "sleepRain": "edd32ce935826f46a22bab699de1929da16f82a53ed943e85c1bf6d427662338",
        ]
        for (name, expected) in stills {
            XCTAssertEqual(hush.rows(name).map(digest), expected, "Hush's \(name) is 0.9.6's")
        }
        // Every frame of it, in name order: its moves are kept as well as its stills. Round 24 (brief 125, George: "Hush:
        // done for now") gives only the frames it draws whole for the rain their water (18 of 0.9.6's 93, and 5 new:
        // the drop's landing, and asleep in the rain a still and its drop); the other 75 are 0.9.6's pixel for pixel.
        func everyFrame(_ frames: [CompanionCharacter.Frame]) -> String {
            digest(frames.sorted { $0.name < $1.name }.map { $0.name + "\n" + $0.rows.joined(separator: "\n") })
        }
        let wet = Self.hushWet
        XCTAssertEqual(hush.frames.count, 98)
        XCTAssertEqual(wet.count, 23)
        XCTAssertEqual(Set(wet).subtracting(hush.frames.map(\.name)), [], "every rain frame named is one of Hush's")
        XCTAssertEqual(everyFrame(hush.frames.filter { !wet.contains($0.name) }),
                       "087c92f38618d1e3d8de8d1419856f3257678c09de8e6044c7ddec9164669293", "75 frames of Hush are 0.9.6's")
        XCTAssertEqual(everyFrame(hush.frames.filter { wet.contains($0.name) }),
                       "436fc0b9134b3665e4b88c7dd0ac80447c998a0fd11178bfe2eecd25f601580b", "Hush's rain frames are round 24's")
    }

    /// The frames Hush draws whole for the rain (its stills, the drop off its hood, its drip routine, thunder's
    /// frames and the ear flicks drawn for the hood), which round 24 gives water.
    static let hushWet: Set<String> = [
        "rain", "hRimA", "hRimB", "hRimC", "hdA", "hdB", "hdC", "hdD", "hdE", "hdF", "hdG", "hShakeL", "hShakeR",
        "hoodTug", "hoodTugBlink", "startle", "wideRain", "earFlick@rain", "earFlickR@rain",
        "sleepRain", "sleepDripA", "sleepDripB", "sleepDripC",
    ]

    /// Round 24 (brief 125, George: "During rain, they should have little droplets bead off of them every once in a
    /// while, and have some droplets stick around or tiny puddles pool around their feet"): in the rain, awake and
    /// asleep, in both places, Hush's hood (or, asleep, its shawl of ears) carries a few beads in the water's blue, one
    /// hanging from its lowest tip; a small puddle lies on the surface it sits on, beside its feet; now and then the
    /// bead lets go and lands in the puddle. Every frame drawn whole for the rain carries the same puddle, and every
    /// drop in them is water, none in its own pale inks.
    func testHushsRainIsWet() throws {
        let hush = CompanionCharacter.hush
        let water: Set<Character> = ["p", "h", "u"]
        let ground = hush.seatRow - 1
        for place in CompanionPlace.allCases {
            let posture = hush.posture(place)
            XCTAssertEqual(posture.awake.rain, "rain", "\(place)")
            XCTAssertEqual(posture.asleep.rain, "sleepRain", "\(place): asleep in the rain, a still of its own")
            XCTAssertEqual(posture.asleep.gestures.filter { $0.sky == .rain }.map(\.name), ["drip"], "\(place)")
            XCTAssertEqual(posture.awake.gestures.filter { $0.sky == .rain && $0.flicker }.map(\.name), ["rimDrip"])
        }
        for still in ["rain", "sleepRain"] {
            let rows = try XCTUnwrap(hush.rows(still)).map(Array.init)
            // The puddle: four to eight pixels on the surface, one glint, a deep pixel, narrower than Hush.
            let puddle = rows[ground].filter { water.contains($0) }
            XCTAssertTrue((4...8).contains(puddle.count), "\(still): a puddle of \(puddle.count)")
            XCTAssertEqual(puddle.filter { $0 == "h" }.count, 1, "\(still): one glint")
            XCTAssertTrue(puddle.contains("u"), "\(still)")
            for y in hush.seatRow..<hush.height {
                XCTAssertFalse(rows[y].contains { water.contains($0) }, "\(still) row \(y): nothing under the seat")
            }
            // Beads above it: two to four, none touching another, and one hanging (two tall) from a tip.
            var beads = 0
            var hangs = false
            for y in 0..<ground {
                for x in 0..<hush.width where water.contains(rows[y][x]) {
                    if y > 0, water.contains(rows[y - 1][x]) { hangs = true; continue }
                    beads += 1
                }
            }
            XCTAssertTrue((2...4).contains(beads), "\(still): \(beads) beads")
            XCTAssertTrue(hangs, "\(still): one hangs from the tip")
            // Asleep in the rain it is as it sleeps (its ears round it like a shawl), its water aside.
            if still == "sleepRain" {
                let sleep = try XCTUnwrap(hush.rows("sleep")).map(Array.init)
                for y in 0..<hush.height {
                    for x in 0..<hush.width where !water.contains(rows[y][x]) {
                        XCTAssertEqual(rows[y][x], sleep[y][x], "sleepRain (\(x), \(y)) is its sleep")
                    }
                }
            }
        }
        // Every frame drawn whole for the rain carries the puddle (or, as the drop lands, the puddle's glint jumping).
        let puddle = String(try XCTUnwrap(hush.rows("rain"))[ground])
        let asleepPuddle = String(try XCTUnwrap(hush.rows("sleepRain"))[ground])
        for name in Self.hushWet {
            let row = String(try XCTUnwrap(hush.rows(name))[ground])
            let want = name.hasPrefix("sleep") ? asleepPuddle : puddle
            let moved = zip(row, want).filter { $0 != $1 }.count
            XCTAssertLessThanOrEqual(moved, 3, "\(name): the puddle is there")
            XCTAssertTrue(row.contains("h"), "\(name): the puddle is there")
            // Every drop is the water's: nothing of its pale inks hangs off the hood or falls.
            let rows = try XCTUnwrap(hush.rows(name)).map(Array.init)
            for y in 0..<hush.seatRow {
                for x in 0..<hush.width where rows[y][x] == "l" {
                    let neighbours = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)].filter {
                        (0..<hush.width).contains($0.0) && (0..<hush.height).contains($0.1)
                    }
                    XCTAssertTrue(neighbours.contains { rows[$0.1][$0.0] != CompanionInk.clear },
                                  "\(name) (\(x), \(y)): a drop in its own pale ink")
                }
            }
        }
        // The drop lets go: one pixel of water clear of the bead, then the puddle's glint jumps.
        let drop = try XCTUnwrap(hush.rows("hRimB")).map(Array.init)
        let rain = try XCTUnwrap(hush.rows("rain")).map(Array.init)
        let falling = (0..<ground).flatMap { y in (0..<hush.width).filter { drop[y][$0] != rain[y][$0] && water.contains(drop[y][$0]) } }
        XCTAssertEqual(falling.count, 1, "one drop in the air")
        XCTAssertNotEqual(try XCTUnwrap(hush.rows("hRimC"))[ground], String(rain[ground]), "it lands in the puddle")
    }
}
