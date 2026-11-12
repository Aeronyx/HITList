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
            "rain": "f05eda108e9bb9f1aa210e7c03b41992f6fddc3a0fa6a2f443922da30ad06f77",
            "snow": "023acce6f3b4b4032fd606ad8f357d3287ad34e7c4a264ba64261e607cd6047a",
            "snow2": "aba47211be20ae991a66131bfb4eb6ffb1cea505e02f84c45bc35b8fd4e27e6b",
            "snow3": "f6c1adf7f42a2eca0dd2ef0cc0737f06319722d3ea41e9407e09f3fc066e0a42",
            "hot": "acdfa9b15cf307da37102ddf07e0de452434d8ee227b05a0f66e47d976da158d",
            "sleep": "0298cf25a8cd494c7324afa43fa80fdd5092b4d4bebc4970edb9c48e53632ca9",
            "sleepSnow": "a9762812a59ef167034bcb37407d07444feea808981d7e9fc257f07f344bec2c",
        ]
        for (name, expected) in stills {
            XCTAssertEqual(hush.rows(name).map(digest), expected, "Hush's \(name) is 0.9.6's")
        }
        // Every frame of it, in name order: its moves are kept as well as its stills.
        let all = hush.frames.sorted { $0.name < $1.name }.map { $0.name + "\n" + $0.rows.joined(separator: "\n") }
        XCTAssertEqual(hush.frames.count, 93)
        XCTAssertEqual(digest(all), "a9daaf772f77453d8db6c61b781b45eb5d7b968dfe8dccda019bae6c5f365524", "every frame of Hush is 0.9.6's")
    }
}
