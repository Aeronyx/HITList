import XCTest
@testable import HITListCore

// The rules by which one record is settled between this device and iCloud (`RecordMerge`, `dev/SYNC-ENGINE.md`
// section 5), rule by rule: M1 to M13 from the table, each with the cases either side of its edge, then each field's
// own rule (`lastWriter`, `clock`, `union`). `MergeOutcome.rule` says which rule decided, and every test asserts it.

/// Records and moments the merge tests share. Times are whole milliseconds after a fixed moment, so a test reads as
/// "edited at 20, deleted at 30".
enum MergeFixture {
    static let epoch: Int64 = 1_800_000_000_000

    static func ms(_ t: Int64) -> SyncValue { .millis(epoch + t) }
    static func at(_ t: Int64) -> Date { Date(timeIntervalSince1970: Double(epoch + t) / 1000) }

    static let taskKey = SyncKey(type: "TaskItem", name: "6B1F3E2A-0000-4000-8000-000000000001")
    static let profileKey = SyncKey(type: "Profile", name: "profile")

    /// A task as a device holds it (every required field present), last changed at `updated`.
    static func task(_ fields: [String: SyncValue] = [:], updated: Int64 = 0, key: SyncKey = taskKey) -> SyncRecord {
        var record = SyncRecord(key: key, fields: ["title": .string("Buy milk"), "createdAt": ms(-1000)])
        record[SyncSchema.updatedAt] = ms(updated)
        for (field, value) in fields { record[field] = value }
        return SyncSchema.filled(record)
    }

    static func profile(_ fields: [String: SyncValue] = [:], updated: Int64 = 0) -> SyncRecord {
        var record = SyncRecord(key: profileKey, fields: ["createdAt": ms(-1000)])
        record[SyncSchema.updatedAt] = ms(updated)
        for (field, value) in fields { record[field] = value }
        return SyncSchema.filled(record)
    }

    static func marker(at t: Int64, key: SyncKey = taskKey) -> SyncRecord { .marker(key, deletedAt: at(t)) }

    static func merge(base: SyncRecord?, local: SyncRecord?, deletedHereAt: Int64? = nil, server: SyncRecord?,
                      now: Int64 = 10_000) -> MergeOutcome {
        RecordMerge.merge(MergeInput(base: base?.comparable, local: local, deletedHereAt: deletedHereAt.map(at),
                                     server: server, now: at(now)))
    }
}

final class RecordMergeTests: XCTestCase {
    private typealias F = MergeFixture

    private func assertSame(_ a: SyncRecord?, _ b: SyncRecord?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(RecordMerge.same(a, b), "\(String(describing: a)) is not the same as \(String(describing: b))",
                      file: file, line: line)
    }

    // MARK: M1 to M4: one side or none

    func testM1NothingAnywhere() {
        let outcome = RecordMerge.merge(MergeInput(base: nil, local: nil, server: nil, now: F.at(0)))
        XCTAssertNil(outcome.merged)
        XCTAssertNil(outcome.device)
        XCTAssertEqual(outcome.rule, .nothing)
    }

    func testM2NewHereGoesToICloud() {
        let local = F.task(["title": .string("New")], updated: 5)
        let outcome = F.merge(base: nil, local: local, server: nil)
        XCTAssertEqual(outcome.rule, .newHere)
        XCTAssertEqual(outcome.merged, local)
        XCTAssertEqual(outcome.device, local)
    }

    func testM3NewThereArrives() {
        let server = F.task(["title": .string("From the Mac")], updated: 5)
        let outcome = F.merge(base: nil, local: nil, server: server)
        XCTAssertEqual(outcome.rule, .newThere)
        XCTAssertEqual(outcome.merged, server)
        XCTAssertEqual(outcome.device, server)
    }

    func testM4MarkerThereNothingHereStaysAMarker() {
        let outcome = F.merge(base: nil, local: nil, server: F.marker(at: 7))
        XCTAssertEqual(outcome.rule, .deletedThereUnknownHere)
        XCTAssertEqual(outcome.merged, F.marker(at: 7))
        XCTAssertNil(outcome.device, "a marker is never written to the device")
    }

    // MARK: M5: both hold it and have never agreed

    func testM5SameIsICloudsEvenWhenUnknownKeysDiffer() {
        var local = F.task(updated: 5)
        local["fieldFromANewerBuild"] = .string("here")
        let server = F.task(updated: 5)
        let outcome = F.merge(base: nil, local: local, server: server)
        XCTAssertEqual(outcome.rule, .firstMeeting)
        XCTAssertEqual(outcome.merged, server)
    }

    func testM5RecordChangedLastWinsWhole() {
        let local = F.task(["title": .string("Here"), "priority": .int(1)], updated: 21)
        let server = F.task(["title": .string("There"), "notes": .string("n")], updated: 20)
        let outcome = F.merge(base: nil, local: local, server: server)
        XCTAssertEqual(outcome.rule, .firstMeeting)
        XCTAssertEqual(outcome.merged, local, "whole: none of the other side's fields")

        let later = F.task(["title": .string("There"), "notes": .string("n")], updated: 22)
        XCTAssertEqual(F.merge(base: nil, local: local, server: later).merged, later)
    }

    func testM5TieGoesToICloud() {
        let local = F.task(["title": .string("Here")], updated: 20)
        let server = F.task(["title": .string("There")], updated: 20)
        let outcome = F.merge(base: nil, local: local, server: server)
        XCTAssertEqual(outcome.rule, .firstMeeting)
        XCTAssertEqual(outcome.merged, server)
    }

    func testM5MissingUpdatedAtCountsAsTheEarliest() {
        var server = F.task(["title": .string("There")])
        server[SyncSchema.updatedAt] = nil
        let local = F.task(["title": .string("Here")], updated: 1)
        XCTAssertEqual(F.merge(base: nil, local: local, server: server).merged, local)

        var bare = F.task(["title": .string("Here")])
        bare[SyncSchema.updatedAt] = nil
        let outcome = F.merge(base: nil, local: bare, server: server)
        XCTAssertEqual(outcome.merged?["title"], .string("There"), "neither has a time: a tie, iCloud's")
    }

    // MARK: M6: here without a memory, a marker there

    func testM6EditOneMillisecondAfterTheDeletionComesBack() {
        let local = F.task(["title": .string("Kept")], updated: 31)
        let outcome = F.merge(base: nil, local: local, server: F.marker(at: 30))
        XCTAssertEqual(outcome.rule, .firstMeetingDeletedThere)
        XCTAssertEqual(outcome.merged, local)
    }

    func testM6EditAtOrBeforeTheDeletionGoes() {
        for t: Int64 in [30, 29] {
            let outcome = F.merge(base: nil, local: F.task(updated: t), server: F.marker(at: 30))
            XCTAssertEqual(outcome.rule, .firstMeetingDeletedThere)
            XCTAssertEqual(outcome.merged, F.marker(at: 30), "edited at \(t), deleted at 30")
            XCTAssertNil(outcome.device)
        }
    }

    func testM6LocalWithoutUpdatedAtGoes() {
        var local = F.task()
        local[SyncSchema.updatedAt] = nil
        let outcome = F.merge(base: nil, local: local, server: F.marker(at: 30))
        XCTAssertEqual(outcome.merged, F.marker(at: 30))
    }

    // MARK: M7: both hold it, field by field

    func testM7FieldChangedOnOneSideIsThatSides() {
        let base = F.task(["title": .string("Milk"), "notes": .string("")], updated: 10)
        let local = F.task(["title": .string("Oat milk"), "notes": .string("")], updated: 11)
        let server = F.task(["title": .string("Milk"), "notes": .string("2 l")], updated: 30)
        let outcome = F.merge(base: base, local: local, server: server)
        XCTAssertEqual(outcome.rule, .threeWay)
        XCTAssertEqual(outcome.merged?["title"], .string("Oat milk"), "only here: kept though iCloud's is later")
        XCTAssertEqual(outcome.merged?["notes"], .string("2 l"))
        XCTAssertEqual(outcome.merged?.updatedAt, F.at(30))
    }

    func testM7FieldEmptiedOnOneSideStaysEmpty() {
        let base = F.task(["dueDate": F.ms(500)], updated: 10)
        var local = F.task(updated: 11)
        local["dueDate"] = nil
        let server = F.task(["dueDate": F.ms(500), "notes": .string("x")], updated: 12)
        let outcome = F.merge(base: base, local: local, server: server)
        XCTAssertNil(outcome.merged?["dueDate"])
        XCTAssertEqual(outcome.merged?["notes"], .string("x"))
    }

    func testM7BothChangedToTheSameValue() {
        let base = F.task(["priority": .int(4)], updated: 10)
        let local = F.task(["priority": .int(1)], updated: 40)
        let server = F.task(["priority": .int(1)], updated: 20)
        let outcome = F.merge(base: base, local: local, server: server)
        XCTAssertEqual(outcome.merged?["priority"], .int(1))
        XCTAssertEqual(outcome.merged?.updatedAt, F.at(40), "updatedAt is the later of the two")
    }

    func testM7NothingChangedIsICloudsRecord() {
        let base = F.task(updated: 10)
        let outcome = F.merge(base: base, local: base, server: base)
        XCTAssertEqual(outcome.rule, .threeWay)
        XCTAssertEqual(outcome.merged, base)
    }

    // MARK: M8: deleted here, alive there

    func testM8UntouchedThereTheDeletionStands() {
        let base = F.task(updated: 10)
        let outcome = F.merge(base: base, local: nil, deletedHereAt: 50, server: base)
        XCTAssertEqual(outcome.rule, .deletedHere)
        XCTAssertEqual(outcome.merged, F.marker(at: 50))
    }

    func testM8ChangedThereOneMillisecondAfterTheDeletionComesBack() {
        let base = F.task(updated: 10)
        let server = F.task(["title": .string("Edited on the Mac")], updated: 51)
        let outcome = F.merge(base: base, local: nil, deletedHereAt: 50, server: server)
        XCTAssertEqual(outcome.rule, .deletedHere)
        XCTAssertEqual(outcome.merged, server)
        XCTAssertEqual(outcome.device, server)
    }

    func testM8ChangedThereAtOrBeforeTheDeletionIsAMarkerAtTheDeletion() {
        let base = F.task(updated: 10)
        for t: Int64 in [50, 49] {
            let server = F.task(["title": .string("Edited on the Mac")], updated: t)
            let outcome = F.merge(base: base, local: nil, deletedHereAt: 50, server: server)
            XCTAssertEqual(outcome.rule, .deletedHere)
            XCTAssertEqual(outcome.merged, F.marker(at: 50), "edited there at \(t), deleted here at 50")
        }
    }

    func testM8NobodyNoticedYetTheDeletionIsNow() {
        let base = F.task(updated: 10)
        let outcome = F.merge(base: base, local: nil, deletedHereAt: nil, server: base, now: 77)
        XCTAssertEqual(outcome.merged, F.marker(at: 77))

        let server = F.task(["title": .string("Edited")], updated: 76)
        XCTAssertEqual(F.merge(base: base, local: nil, server: server, now: 77).merged, F.marker(at: 77))
        let after = F.task(["title": .string("Edited")], updated: 78)
        XCTAssertEqual(F.merge(base: base, local: nil, server: after, now: 77).merged, after)
    }

    func testM8ChangeThereOnlyInKeysThisBuildDoesNotKnowIsNoChange() {
        let base = F.task(updated: 10)
        var server = F.task(updated: 10)
        server["fieldFromANewerBuild"] = .int(3)
        let outcome = F.merge(base: base, local: nil, deletedHereAt: 50, server: server)
        XCTAssertEqual(outcome.merged, F.marker(at: 50))
    }

    // MARK: M9: alive here, a marker there

    func testM9UnchangedHereGoes() {
        let base = F.task(updated: 10)
        let outcome = F.merge(base: base, local: base, server: F.marker(at: 40))
        XCTAssertEqual(outcome.rule, .deletedThere)
        XCTAssertEqual(outcome.merged, F.marker(at: 40))
        XCTAssertNil(outcome.device)
    }

    func testM9ChangedHereOneMillisecondAfterTheDeletionComesBack() {
        let base = F.task(updated: 10)
        let local = F.task(["title": .string("Edited here")], updated: 41)
        let outcome = F.merge(base: base, local: local, server: F.marker(at: 40))
        XCTAssertEqual(outcome.rule, .deletedThere)
        XCTAssertEqual(outcome.merged, local)
    }

    func testM9ChangedHereAtOrBeforeTheDeletionGoes() {
        let base = F.task(updated: 10)
        for t: Int64 in [40, 39] {
            let local = F.task(["title": .string("Edited here")], updated: t)
            let outcome = F.merge(base: base, local: local, server: F.marker(at: 40))
            XCTAssertEqual(outcome.merged, F.marker(at: 40), "edited here at \(t), deleted there at 40")
        }
    }

    func testM9ChangeWithoutAStampAfterTheDeletionGoes() {
        // A change that did not move `updatedAt` (the day anchoring, a board's clock) has its old time: it loses.
        let base = F.task(["dueDate": F.ms(0)], updated: 10)
        let local = F.task(["dueDate": F.ms(36_000_000)], updated: 10)
        let outcome = F.merge(base: base, local: local, server: F.marker(at: 40))
        XCTAssertEqual(outcome.merged, F.marker(at: 40))
    }

    // MARK: M10, M11

    func testM10DeletedOnBothSidesCarriesTheLaterDeletion() {
        let base = F.task(updated: 10)
        let earlierThere = F.merge(base: base, local: nil, deletedHereAt: 60, server: F.marker(at: 40))
        XCTAssertEqual(earlierThere.rule, .deletedBoth)
        XCTAssertEqual(earlierThere.merged, F.marker(at: 60), "deleted here after: this device's time goes to iCloud")
        let laterThere = F.merge(base: base, local: nil, deletedHereAt: 30, server: F.marker(at: 40))
        XCTAssertEqual(laterThere.rule, .deletedBoth)
        XCTAssertEqual(laterThere.merged, F.marker(at: 40))
        let tie = F.merge(base: base, local: nil, deletedHereAt: 40, server: F.marker(at: 40))
        XCTAssertEqual(tie.merged, F.marker(at: 40))
        let unnoticed = F.merge(base: base, local: nil, server: F.marker(at: 40), now: 90)
        XCTAssertEqual(unnoticed.merged, F.marker(at: 90), "nobody noticed: now, as M8")
    }

    func testM10AMarkerStillToGoSurvivesICloudsEarlierMarkerDeliveredAgain() {
        // The brain keeps a later marker still to go as base = iCloud's earlier marker and `deletedHereAt` = this
        // device's later time (M10's result when the base was alive). iCloud's earlier marker delivered again (T2)
        // before the later one is sent must not drop it: twice is once.
        let first = F.merge(base: F.task(updated: 10), local: nil, deletedHereAt: 60, server: F.marker(at: 40))
        XCTAssertEqual(first.merged, F.marker(at: 60))
        let again = F.merge(base: F.marker(at: 40), local: nil, deletedHereAt: 60, server: F.marker(at: 40))
        XCTAssertEqual(again.rule, .deletedBoth)
        XCTAssertEqual(again.merged, F.marker(at: 60), "the later marker is still to go")

        let older = F.merge(base: F.marker(at: 40), local: nil, deletedHereAt: 30, server: F.marker(at: 40))
        XCTAssertEqual(older.merged, F.marker(at: 40), "an earlier time here is no news")
        let newerThere = F.merge(base: F.marker(at: 40), local: nil, deletedHereAt: 60, server: F.marker(at: 70))
        XCTAssertEqual(newerThere.merged, F.marker(at: 70))
        // With a marker base, `now` never stands in for a deletion here: two devices would send fresher markers
        // to each other at every sync.
        let unnoticed = F.merge(base: F.marker(at: 40), local: nil, server: F.marker(at: 40), now: 90)
        XCTAssertEqual(unnoticed.merged, F.marker(at: 40))
    }

    func testM11GoneForGoodUnchangedHereGoes() {
        let base = F.task(updated: 10)
        let outcome = F.merge(base: base, local: base, server: nil)
        XCTAssertEqual(outcome.rule, .goneForGood)
        XCTAssertNil(outcome.merged)
        XCTAssertNil(outcome.device)
    }

    func testM11GoneForGoodChangedHereIsNewAgain() {
        let base = F.task(updated: 10)
        let local = F.task(["title": .string("Still wanted")], updated: 11)
        let outcome = F.merge(base: base, local: local, server: nil)
        XCTAssertEqual(outcome.rule, .goneForGood)
        XCTAssertEqual(outcome.merged, local)
    }

    func testM11GoneForGoodAndGoneHere() {
        let outcome = F.merge(base: F.task(updated: 10), local: nil, server: nil)
        XCTAssertEqual(outcome.rule, .goneForGood)
        XCTAssertNil(outcome.merged)
        XCTAssertEqual(F.merge(base: F.marker(at: 10), local: nil, server: nil).rule, .goneForGood)
    }

    // MARK: M12, M13: made again

    func testM12MadeAgainHereStandsWhateverItsDatesAgainstTheMarkerItKnew() {
        // An undo brings the item back with its old `updatedAt`, long before the deletion.
        let local = F.task(["title": .string("Undone")], updated: 1)
        let outcome = F.merge(base: F.marker(at: 40), local: local, server: F.marker(at: 40))
        XCTAssertEqual(outcome.rule, .cameBackHere)
        XCTAssertEqual(outcome.merged, local)
        var stray = F.marker(at: 40)
        stray["title"] = .string("left behind")
        XCTAssertEqual(F.merge(base: F.marker(at: 40), local: local, server: stray).merged, local,
                       "the same marker, whatever was left on it")
    }

    func testM12AgainstANewerMarkerIsOrderedAsM6() {
        // Deleted again elsewhere (at 90) since this device agreed on the deletion at 40.
        for (t, comesBack): (Int64, Bool) in [(1, false), (89, false), (90, false), (91, true)] {
            let local = F.task(["title": .string("Undone")], updated: t)
            let outcome = F.merge(base: F.marker(at: 40), local: local, server: F.marker(at: 90))
            XCTAssertEqual(outcome.rule, .cameBackHere)
            XCTAssertEqual(outcome.merged, comesBack ? local : F.marker(at: 90), "made again at \(t)")
        }
        let older = F.merge(base: F.marker(at: 40), local: F.task(updated: 1), server: F.marker(at: 30))
        XCTAssertEqual(older.merged, F.task(updated: 1), "a marker older than the one it knew is no news")
    }

    func testM12MadeAgainOnBothSidesIsAFirstMeeting() {
        let local = F.task(["title": .string("Here")], updated: 50)
        let server = F.task(["title": .string("There")], updated: 60)
        let outcome = F.merge(base: F.marker(at: 40), local: local, server: server)
        XCTAssertEqual(outcome.rule, .cameBackHere)
        XCTAssertEqual(outcome.merged, server)
        XCTAssertEqual(F.merge(base: F.marker(at: 40), local: server, server: local).merged, server,
                       "the later one, whichever side it is on")
        XCTAssertEqual(F.merge(base: F.marker(at: 40), local: local, server: local).merged, local)
    }

    func testM12MadeAgainHereAndGoneForGoodThere() {
        // Two rows of the table apply (M11: B present, not there; M12: here, B a marker); both say L.
        let local = F.task(updated: 1)
        let outcome = F.merge(base: F.marker(at: 40), local: local, server: nil)
        XCTAssertEqual(outcome.merged, local)
        XCTAssertEqual(outcome.rule, .goneForGood)
    }

    func testM13MadeAgainElsewhereArrives() {
        let server = F.task(["title": .string("Back")], updated: 2)
        let outcome = F.merge(base: F.marker(at: 40), local: nil, server: server)
        XCTAssertEqual(outcome.rule, .cameBackThere)
        XCTAssertEqual(outcome.merged, server)
        XCTAssertEqual(outcome.device, server)
    }

    func testM13AgainstALaterDeletionStillToGoIsOrderedAsM8() {
        // This device holds a later marker of its own still to send (base = iCloud's marker at 1, `deletedHereAt`
        // 6) when another device's revival arrives. The revival is ordered against that deletion as in M8.
        for (t, comesBack): (Int64, Bool) in [(3, false), (6, false), (7, true)] {
            let server = F.task(["title": .string("Back")], updated: t)
            let outcome = F.merge(base: F.marker(at: 1), local: nil, deletedHereAt: 6, server: server)
            XCTAssertEqual(outcome.rule, .cameBackThere)
            XCTAssertEqual(outcome.merged, comesBack ? server : F.marker(at: 6), "revived at \(t), deleted here at 6")
        }
        // Without a deletion of its own still to go, `now` never stands in: the revival arrives.
        let server = F.task(["title": .string("Back")], updated: 3)
        let outcome = F.merge(base: F.marker(at: 1), local: nil, server: server, now: 90)
        XCTAssertEqual(outcome.merged, server)
    }

    func testAMarkerBothKnewAndNothingHereIsDeletedOnBothSides() {
        // Not in the table (M10 needs B alive, M13 a live record there). Nothing has happened: iCloud's marker.
        let outcome = F.merge(base: F.marker(at: 40), local: nil, server: F.marker(at: 40))
        XCTAssertEqual(outcome.merged, F.marker(at: 40))
        XCTAssertEqual(outcome.rule, .deletedBoth, "M13 is 'alive there'; this is a deletion on both sides")
        let later = F.merge(base: F.marker(at: 40), local: nil, server: F.marker(at: 70))
        XCTAssertEqual(later.merged, F.marker(at: 70))
        XCTAssertEqual(later.rule, .deletedBoth)
    }

    // MARK: Every situation has one rule

    func testEveryOneOfTheEighteenSituationsHasItsRule() {
        // B: none, alive, a marker. Here: none, the item. There: none, alive, a marker. Where the table has two rows
        // that apply (M1 and M11 with a base and nothing anywhere; M11 and M12 with a marker base, the item here and
        // nothing there) the code says M11; both rows give the same result.
        enum Side { case none, alive, marker }
        let expected: [(Side, Bool, Side, MergeOutcome.Rule)] = [
            (.none, false, .none, .nothing), (.none, false, .alive, .newThere),
            (.none, false, .marker, .deletedThereUnknownHere), (.none, true, .none, .newHere),
            (.none, true, .alive, .firstMeeting), (.none, true, .marker, .firstMeetingDeletedThere),
            (.alive, false, .none, .goneForGood), (.alive, false, .alive, .deletedHere),
            (.alive, false, .marker, .deletedBoth), (.alive, true, .none, .goneForGood),
            (.alive, true, .alive, .threeWay), (.alive, true, .marker, .deletedThere),
            (.marker, false, .none, .goneForGood), (.marker, false, .alive, .cameBackThere),
            (.marker, false, .marker, .deletedBoth), (.marker, true, .none, .goneForGood),
            (.marker, true, .alive, .cameBackHere), (.marker, true, .marker, .cameBackHere),
        ]
        func record(_ side: Side, _ t: Int64) -> SyncRecord? {
            switch side {
            case .none: return nil
            case .alive: return F.task(updated: t)
            case .marker: return F.marker(at: t)
            }
        }
        for (b, here, s, rule) in expected {
            let outcome = F.merge(base: record(b, 10), local: here ? F.task(updated: 20) : nil, deletedHereAt: 30,
                                  server: record(s, 25))
            XCTAssertEqual(outcome.rule, rule, "B \(b), here \(here), there \(s)")
        }
        XCTAssertEqual(Set(expected.map(\.3)).count, MergeOutcome.Rule.allCases.count - 1, "every rule but M0 is used")
    }

    // MARK: What the merge reads: required fields, data, markers, unknown types and keys

    func testRequiredFieldMissingOnICloudsSideReadsAsItsDefault() {
        var server = F.task(updated: 10)
        server["priority"] = nil
        server["title"] = nil
        let filled = F.task(["priority": .int(4), "title": .string("")], updated: 10)
        assertSame(server, filled)
        let outcome = F.merge(base: filled, local: filled, server: server)
        XCTAssertEqual(outcome.merged, filled, "the result carries the required fields")
        XCTAssertEqual(F.merge(base: nil, local: nil, server: server).device?["priority"], .int(4))
    }

    func testValueOfTheWrongKindIsNotKnown() {
        var server = F.task(updated: 10)
        server["title"] = .int(3)
        XCTAssertEqual(RecordMerge.normal(server)?["title"], .string(""))
    }

    func testDataIsComparedByDigestAndTakenAsBytesFromTheSideThatWon() {
        let x = Data([1, 2, 3]), y = Data([9, 9])
        let base = F.profile(["avatarData": .data(x), "avatarUpdatedAt": F.ms(5)], updated: 5)
        XCTAssertEqual(base.comparable["avatarData"], .digest(SyncValue.digest(of: x)))
        assertSame(base.comparable, base)

        let local = F.profile(["avatarData": .data(x), "avatarUpdatedAt": F.ms(5), "displayName": .string("G")],
                              updated: 8)
        let server = F.profile(["avatarData": .data(y), "avatarUpdatedAt": F.ms(9)], updated: 9)
        let outcome = F.merge(base: base, local: local, server: server)
        XCTAssertEqual(outcome.merged?["avatarData"], .data(y), "bytes, not the base's digest")
        XCTAssertEqual(outcome.merged?["displayName"], .string("G"))

        let flipped = F.merge(base: base, local: server, server: local)
        XCTAssertEqual(flipped.merged?["avatarData"], .data(y))
        let same = F.merge(base: base, local: local, server: base)
        XCTAssertEqual(same.merged?["avatarData"], .data(x), "unchanged: iCloud's bytes, never a digest")
    }

    func testAMarkerWithContentLeftOnItIsAMarker() {
        var stray = F.marker(at: 40)
        stray["title"] = .string("left behind")
        stray["priority"] = .int(1)
        assertSame(stray, F.marker(at: 40))
        let outcome = F.merge(base: nil, local: nil, server: stray)
        XCTAssertEqual(outcome.merged, F.marker(at: 40), "a marker carries its time and nothing else")
        XCTAssertNil(outcome.device)
        let m9 = F.merge(base: F.task(updated: 10), local: F.task(updated: 10), server: stray)
        XCTAssertEqual(m9.merged, F.marker(at: 40))
    }

    func testAMarkerIsTheSameAsAnotherWithTheSameTime() {
        assertSame(F.marker(at: 40), F.marker(at: 40))
        XCTAssertFalse(RecordMerge.same(F.marker(at: 40), F.marker(at: 41)))
        var noStamp = F.marker(at: 40)
        noStamp[SyncSchema.updatedAt] = nil
        assertSame(noStamp, F.marker(at: 40))
    }

    func testATypeThisBuildDoesNotKnowIsLeftAlone() {
        let foreign = SyncRecord(type: "Attachment", name: "A1", fields: ["blob": .string("x")])
        XCTAssertEqual(RecordMerge.normal(foreign), foreign)
        let outcome = RecordMerge.merge(MergeInput(base: nil, local: nil, server: foreign, now: F.at(0)))
        XCTAssertEqual(outcome.rule, .unknownType, "M0: the caller does nothing")
        XCTAssertEqual(MergeOutcome.Rule.unknownType.rawValue, "M0")
        XCTAssertNil(outcome.merged, "the device's record, untouched: it holds none")
        let withBase = RecordMerge.merge(MergeInput(base: foreign, local: nil, server: foreign, now: F.at(0)))
        XCTAssertEqual(withBase.rule, .unknownType)
        XCTAssertNil(withBase.device)
        let held = RecordMerge.merge(MergeInput(base: nil, local: foreign, server: nil, now: F.at(0)))
        XCTAssertEqual(held.merged, foreign)
        XCTAssertEqual(held.rule, .unknownType)
    }

    func testKeysThisBuildDoesNotKnowOnEitherSideAreIgnored() {
        var local = F.task(["title": .string("Here")], updated: 20)
        local["colourOfTheSky"] = .string("blue")
        var server = F.task(updated: 10)
        server["estimateMinutes"] = .int(30)
        var base = F.task(updated: 10)
        base["estimateMinutes"] = .int(15)
        assertSame(server, base)
        let outcome = F.merge(base: base, local: local, server: server)
        XCTAssertEqual(outcome.merged?["title"], .string("Here"))
        XCTAssertNil(outcome.merged?["colourOfTheSky"], "never sent")
        XCTAssertNil(outcome.merged?["estimateMinutes"], "never cleared either: the transport leaves the key alone")
    }

    func testReferenceListsCompareAsSetsAndEmptyIsNone() {
        let sorted = F.task(["labels": .references(["L1", "L2"])], updated: 10)
        let raw = F.task(["labels": .referenceList(["L2", "L1", "L2"])], updated: 10)
        assertSame(raw, sorted)
        var none = F.task(updated: 10)
        none["labels"] = nil
        assertSame(F.task(["labels": .referenceList([])], updated: 10), none)
        XCTAssertNil(RecordMerge.normal(F.task(["labels": .referenceList([])]))?["labels"])
        XCTAssertEqual(RecordMerge.normal(raw)?["labels"], .referenceList(["L1", "L2"]))
    }
}

// MARK: - Each field's own rule

/// How a field both sides changed since they last agreed is settled (`SyncField.Merge`): `lastWriter` (the record
/// changed last, a tie to iCloud), `clock` (the profile's name and picture, each by its own time) and `union` (a
/// task's labels).
final class RecordMergeFieldRuleTests: XCTestCase {
    private typealias F = MergeFixture

    // MARK: lastWriter

    func testLastWriterBothChangedTheRecordChangedLastWins() {
        let base = F.task(["title": .string("Milk")], updated: 10)
        let local = F.task(["title": .string("Oat milk")], updated: 31)
        let server = F.task(["title": .string("Soy milk")], updated: 30)
        XCTAssertEqual(F.merge(base: base, local: local, server: server).merged?["title"], .string("Oat milk"))
        let later = F.task(["title": .string("Soy milk")], updated: 32)
        XCTAssertEqual(F.merge(base: base, local: local, server: later).merged?["title"], .string("Soy milk"))
    }

    func testLastWriterTieGoesToICloud() {
        let base = F.task(["title": .string("Milk")], updated: 10)
        let local = F.task(["title": .string("Oat milk")], updated: 30)
        let server = F.task(["title": .string("Soy milk")], updated: 30)
        XCTAssertEqual(F.merge(base: base, local: local, server: server).merged?["title"], .string("Soy milk"))
    }

    func testLastWriterDecidesEachFieldOnItsOwn() {
        // The later record wins only the fields both changed; a field the earlier side alone changed stays.
        let base = F.task(["title": .string("Milk"), "priority": .int(4), "notes": .string("")], updated: 10)
        let local = F.task(["title": .string("Oat milk"), "priority": .int(2), "notes": .string("")], updated: 20)
        let server = F.task(["title": .string("Soy milk"), "priority": .int(4), "notes": .string("aisle 3")],
                            updated: 30)
        let merged = F.merge(base: base, local: local, server: server).merged
        XCTAssertEqual(merged?["title"], .string("Soy milk"))
        XCTAssertEqual(merged?["priority"], .int(2))
        XCTAssertEqual(merged?["notes"], .string("aisle 3"))
        XCTAssertEqual(merged?.updatedAt, F.at(30))
    }

    func testLastWriterFlipCountCountsOnce() {
        // A known limit (section 5): two devices flipping the same switch apart count once.
        let base = F.task(["flipCount": .int(0)], updated: 10)
        let local = F.task(["flipCount": .int(1)], updated: 20)
        let server = F.task(["flipCount": .int(1)], updated: 21)
        XCTAssertEqual(F.merge(base: base, local: local, server: server).merged?["flipCount"], .int(1))
    }

    // MARK: clock: the profile

    func testClockNameLaterHereAndPictureLaterThereBothSurviveWithABase() {
        let x = Data([1]), y = Data([2, 2])
        let base = F.profile(["displayName": .string("G"), "nameUpdatedAt": F.ms(1),
                              "avatarData": .data(x), "avatarUpdatedAt": F.ms(1)], updated: 1)
        let local = F.profile(["displayName": .string("George"), "nameUpdatedAt": F.ms(10),
                               "avatarData": .data(x), "avatarUpdatedAt": F.ms(1)], updated: 10)
        let server = F.profile(["displayName": .string("G"), "nameUpdatedAt": F.ms(1),
                                "avatarData": .data(y), "avatarUpdatedAt": F.ms(20)], updated: 20)
        for (l, s) in [(local, server), (server, local)] {
            let merged = F.merge(base: base, local: l, server: s).merged
            XCTAssertEqual(merged?["displayName"], .string("George"))
            XCTAssertEqual(merged?["nameUpdatedAt"], F.ms(10))
            XCTAssertEqual(merged?["avatarData"], .data(y))
            XCTAssertEqual(merged?["avatarUpdatedAt"], F.ms(20))
            XCTAssertEqual(merged?.updatedAt, F.at(20))
        }
    }

    func testClockNameLaterHereAndPictureLaterThereBothSurviveWithoutABase() {
        // Two devices that each made a profile before they first met (M5): neither record wins whole.
        let x = Data([1]), y = Data([2, 2])
        let local = F.profile(["displayName": .string("George"), "nameUpdatedAt": F.ms(30),
                               "avatarData": .data(x), "avatarUpdatedAt": F.ms(5)], updated: 30)
        let server = F.profile(["displayName": .string("G"), "nameUpdatedAt": F.ms(10),
                                "avatarData": .data(y), "avatarUpdatedAt": F.ms(40)], updated: 40)
        for (l, s) in [(local, server), (server, local)] {
            let outcome = F.merge(base: nil, local: l, server: s)
            XCTAssertEqual(outcome.rule, .firstMeeting)
            XCTAssertEqual(outcome.merged?["displayName"], .string("George"))
            XCTAssertEqual(outcome.merged?["nameUpdatedAt"], F.ms(30))
            XCTAssertEqual(outcome.merged?["avatarData"], .data(y))
            XCTAssertEqual(outcome.merged?["avatarUpdatedAt"], F.ms(40))
            XCTAssertEqual(outcome.merged?.updatedAt, F.at(40))
        }
    }

    func testClockBothSetTheNameTheLaterClockWinsNotTheLaterRecord() {
        let base = F.profile(["displayName": .string("G"), "nameUpdatedAt": F.ms(1)], updated: 1)
        let local = F.profile(["displayName": .string("George"), "nameUpdatedAt": F.ms(25)], updated: 25)
        // iCloud's record is later (its picture was set at 50), but its name is older.
        let server = F.profile(["displayName": .string("Geo"), "nameUpdatedAt": F.ms(20),
                                "avatarUpdatedAt": F.ms(50)], updated: 50)
        let merged = F.merge(base: base, local: local, server: server).merged
        XCTAssertEqual(merged?["displayName"], .string("George"))
        XCTAssertEqual(merged?["nameUpdatedAt"], F.ms(25))
        XCTAssertEqual(merged?["avatarUpdatedAt"], F.ms(50))
    }

    func testClockTieGoesToICloud() {
        let base = F.profile(["displayName": .string("G"), "nameUpdatedAt": F.ms(1)], updated: 1)
        let local = F.profile(["displayName": .string("George"), "nameUpdatedAt": F.ms(25)], updated: 25)
        let server = F.profile(["displayName": .string("Geo"), "nameUpdatedAt": F.ms(25)], updated: 25)
        XCTAssertEqual(F.merge(base: base, local: local, server: server).merged?["displayName"], .string("Geo"))
        XCTAssertEqual(F.merge(base: nil, local: local, server: server).merged?["displayName"], .string("Geo"))
    }

    func testClockASideWithNoClockLosesToASideWithOne() {
        let base = F.profile(["displayName": .string("G")], updated: 1)
        let local = F.profile(["displayName": .string("George"), "nameUpdatedAt": F.ms(5)], updated: 5)
        let server = F.profile(["displayName": .string("Geo")], updated: 9)
        XCTAssertEqual(F.merge(base: base, local: local, server: server).merged?["displayName"], .string("George"))
        XCTAssertEqual(F.merge(base: nil, local: local, server: server).merged?["displayName"], .string("George"))
    }

    func testClockAPictureRemovedLaterStaysRemoved() {
        let x = Data([1, 2])
        let base = F.profile(["avatarData": .data(x), "avatarUpdatedAt": F.ms(1)], updated: 1)
        let local = F.profile(["avatarUpdatedAt": F.ms(30)], updated: 30)
        let server = F.profile(["avatarData": .data(Data([7])), "avatarUpdatedAt": F.ms(20)], updated: 20)
        XCTAssertNil(F.merge(base: base, local: local, server: server).merged?["avatarData"])
        XCTAssertNil(F.merge(base: nil, local: local, server: server).merged?["avatarData"])
        XCTAssertNil(F.merge(base: nil, local: server, server: local).merged?["avatarData"])
    }

    // MARK: union: a task's labels

    private func labels(_ names: String...) -> SyncValue? { names.isEmpty ? nil : .references(names) }

    private func mergedLabels(base: [String], local: [String], server: [String]) -> SyncValue? {
        func task(_ names: [String], _ t: Int64) -> SyncRecord {
            var record = F.task(updated: t)
            record["labels"] = names.isEmpty ? nil : .references(names)
            return record
        }
        return F.merge(base: task(base, 10), local: task(local, 20), server: task(server, 30)).merged?["labels"]
    }

    func testUnionAddedOnBothSides() {
        XCTAssertEqual(mergedLabels(base: ["a"], local: ["a", "b"], server: ["a", "c"]), labels("a", "b", "c"))
        XCTAssertEqual(mergedLabels(base: [], local: ["b"], server: ["c"]), labels("b", "c"))
        XCTAssertEqual(mergedLabels(base: [], local: ["b"], server: ["b", "c"]), labels("b", "c"))
    }

    func testUnionRemovedOnOneSide() {
        XCTAssertEqual(mergedLabels(base: ["a", "b"], local: ["b"], server: ["a", "b", "c"]), labels("b", "c"))
        XCTAssertEqual(mergedLabels(base: ["a", "b"], local: ["a", "b", "c"], server: ["b"]), labels("b", "c"))
    }

    func testUnionAddedOnOneSideAndRemovedOnTheOther() {
        // Here added b; there removed a. Both stand.
        XCTAssertEqual(mergedLabels(base: ["a"], local: ["a", "b"], server: []), labels("b"))
        XCTAssertEqual(mergedLabels(base: ["a"], local: [], server: ["a", "b"]), labels("b"))
    }

    func testUnionRemovedDifferentLabelsOnEachSide() {
        XCTAssertEqual(mergedLabels(base: ["a", "b", "c"], local: ["b", "c"], server: ["a", "c"]), labels("c"))
    }

    func testUnionBothEmptied() {
        XCTAssertNil(mergedLabels(base: ["a", "b"], local: [], server: []))
        XCTAssertNil(mergedLabels(base: ["a", "b"], local: ["b"], server: ["a"]), "each removed the other's")
    }

    func testUnionOneSideOnlyIsThatSides() {
        XCTAssertEqual(mergedLabels(base: ["a", "b"], local: ["a"], server: ["a", "b"]), labels("a"))
        XCTAssertEqual(mergedLabels(base: ["a", "b"], local: ["a", "b"], server: ["c"]), labels("c"))
    }

    func testUnionWithoutABaseIsTheWholeRecordsLabels() {
        // M5 has no base to tell additions from removals: the record changed last, whole, labels and all.
        var local = F.task(updated: 20)
        local["labels"] = .references(["a"])
        var server = F.task(updated: 30)
        server["labels"] = .references(["b"])
        XCTAssertEqual(F.merge(base: nil, local: local, server: server).merged?["labels"], labels("b"))
    }
}
