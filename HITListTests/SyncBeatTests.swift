import XCTest
@testable import HITList

/// Brief 95, rule 2: "So the app asks." The beat's schedule and requests (`SyncBeat`), against a fake iCloud.
@MainActor
final class SyncBeatTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
    private let rules = SyncBeat.Rules()

    // MARK: The schedule

    private func due(_ last: SyncBeat.LastResult?, failures: Int = 0, misses: Int = 0, retryAfter: Date? = nil,
                     now: TimeInterval = 0.5) -> TimeInterval {
        SyncBeat.nextDue(rules: rules, now: at(now), lastStart: last == nil ? nil : at(0), lastEnd: last == nil ? nil : at(0.4),
                         last: last, failures: failures, misses: misses, retryAfterUntil: retryAfter).timeIntervalSince(start)
    }

    func testEveryFifteenSecondsWhileItConfirms() {
        XCTAssertEqual(due(.confirmed), 15, accuracy: 0.001)
        XCTAssertEqual(due(nil), 0.5, accuracy: 0.001, "the first beat goes out at once")
    }

    func testAFirstMissGetsASecondChanceInsideTheWindow() {
        XCTAssertEqual(due(.missed, misses: 1), 7.4, accuracy: 0.001)
        XCTAssertEqual(due(.missed, misses: 2), 15.4, accuracy: 0.001, "then the normal pace: iCloud does answer")
        XCTAssertLessThan(15 + rules.retry + rules.timeout + 1, BoltTruth.Rules().window,
                          "a lost beat at 15 s and its second chance both end before the window does")
    }

    func testFailuresBackOffToAMinuteAndHonourRetryAfter() {
        XCTAssertEqual(due(.failed, failures: 1), 7.4, accuracy: 0.001)
        XCTAssertEqual(due(.failed, failures: 2), 15.4, accuracy: 0.001)
        XCTAssertEqual(due(.failed, failures: 3), 30.4, accuracy: 0.001)
        XCTAssertEqual(due(.failed, failures: 4), 60.4, accuracy: 0.001)
        XCTAssertEqual(due(.failed, failures: 40), 60.4, accuracy: 0.001, "never faster, never a spin")
        XCTAssertEqual(due(.failed, failures: 1, retryAfter: at(90)), 90, accuracy: 0.001, "iCloud's own retry-after wins")
    }

    func testTwoBeatsNeverStartCloserThanTheMinimumGap() {
        XCTAssertEqual(SyncBeat.nextDue(rules: rules, now: at(0.5), lastStart: at(0), lastEnd: at(0.3), last: nil,
                                        failures: 0, misses: 0, retryAfterUntil: nil).timeIntervalSince(start), 2, accuracy: 0.001)
    }

    // MARK: The requests

    func testTheFirstBeatReadsTheWholeZoneAndTheNextAsksOnlyWhatChanged() async {
        let reader = FakeReader()
        reader.zone = .success(.init(changed: ["r1": entry(), "r2": entry()], token: Data([1]), isFullRead: true))
        let beat = SyncBeat(reader: reader, indexURL: nil, clock: { self.at(0) })
        var reading: [Int?] = []
        beat.onReading = { reading.append($0) }
        _ = await beat.runOnce()
        XCTAssertEqual(reader.zoneTokens, [nil], "a whole read")
        XCTAssertTrue(beat.index.complete)
        XCTAssertEqual(beat.index.entries.count, 2)
        XCTAssertEqual(reading.first, 0)
        XCTAssertEqual(reading.last, Optional<Int>.none)
        // Nothing changed: one request, no zone fetch.
        reader.database = .success(ICloudDatabaseAnswer(zoneChanged: false, token: Data([2])))
        _ = await beat.runOnce()
        XCTAssertEqual(reader.zoneTokens.count, 1)
        XCTAssertEqual(beat.index.databaseToken, Data([2]))
        // A change: the zone fetch asks from the zone's own token.
        reader.database = .success(ICloudDatabaseAnswer(zoneChanged: true, token: Data([3])))
        reader.zone = .success(.init(changed: ["r3": entry()], deleted: ["r1"], token: Data([4])))
        _ = await beat.runOnce()
        XCTAssertEqual(reader.zoneTokens.last, Data([1]))
        XCTAssertEqual(Set(beat.index.entries.keys), ["r2", "r3"])
        XCTAssertEqual(beat.index.zoneToken, Data([4]))
    }

    func testAFailedZoneFetchKeepsTheDatabaseTokenSoTheChangeIsAskedForAgain() async {
        let reader = FakeReader()
        let beat = SyncBeat(reader: reader, indexURL: nil, clock: { self.at(0) })
        _ = await beat.runOnce()
        let kept = beat.index.databaseToken
        reader.database = .success(ICloudDatabaseAnswer(zoneChanged: true, token: Data([7])))
        reader.zone = .failure(SyncBeatFailure(.network, "network unavailable"))
        let outcome = await beat.runOnce()
        XCTAssertEqual(outcome, .failed(SyncBeatFailure(.network, "network unavailable")))
        XCTAssertEqual(beat.index.databaseToken, kept)
        XCTAssertEqual(beat.last, .failed)
        XCTAssertEqual(beat.failures, 1)
    }

    func testTheJudgeDecidesWhatTheBeatCameTo() async {
        let reader = FakeReader()
        let beat = SyncBeat(reader: reader, indexURL: nil, clock: { self.at(0) })
        beat.judge = { _, answer in
            XCTAssertEqual(answer, .answered(indexChanged: true))
            return .answered(BoltTruth.Findings(receiving: 1))
        }
        var heard: [BoltTruth.Outcome] = []
        beat.onOutcome = { heard.append($1) }
        _ = await beat.runOnce()
        XCTAssertEqual(heard, [.answered(BoltTruth.Findings(receiving: 1))])
        XCTAssertEqual(beat.last, .missed)
        XCTAssertEqual(beat.misses, 1)
    }

    func testNoBeatsWhileNoBoltCanBeSeen() async throws {
        let reader = FakeReader()
        let beat = SyncBeat(reader: reader, indexURL: nil)
        beat.setEligible(false)
        beat.beatSoon()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(reader.databaseCalls, 0, "a hidden Mac window, an app in the background: nothing asks")
        beat.setEligible(true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(reader.databaseCalls, 1, "visible again: one beat at once")
        beat.setEligible(false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(reader.databaseCalls, 1, "and nothing queued behind it")
    }

    func testAnotherAccountsIndexIsForgotten() async {
        let reader = FakeReader()
        let beat = SyncBeat(reader: reader, indexURL: nil, clock: { self.at(0) })
        beat.account("acct1:a")
        _ = await beat.runOnce()
        XCTAssertTrue(beat.index.complete)
        beat.account("acct1:a")
        XCTAssertTrue(beat.index.complete)
        beat.account("acct1:b")
        XCTAssertFalse(beat.index.complete)
        XCTAssertEqual(beat.index.accountKey, "acct1:b")
    }

    func testASignInReadsTheZoneWholeAgain() async {
        let reader = FakeReader()
        let beat = SyncBeat(reader: reader, indexURL: nil, clock: { self.at(0) })
        _ = await beat.runOnce()
        reader.database = .success(ICloudDatabaseAnswer(zoneChanged: false, token: Data([5])))
        beat.requireFullRead()
        _ = await beat.runOnce()
        XCTAssertEqual(reader.zoneTokens, [nil, nil])
    }

    func testAFirstReadCutShortGoesOnFromWhereItStopped() async {
        // A large zone on a slow network: the first read is cut short after its first records and a token.
        let reader = FakeReader()
        reader.zoneQueue = [.success(.init(changed: ["r1": entry()], token: Data([1]), reachedEnd: false)),
                            .success(.init(changed: ["r2": entry()], token: Data([2])))]
        let beat = SyncBeat(reader: reader, indexURL: nil, clock: { self.at(0) })
        _ = await beat.runOnce()
        XCTAssertFalse(beat.index.complete, "still reading: nothing can be compared yet")
        XCTAssertEqual(beat.index.zoneToken, Data([1]))
        _ = await beat.runOnce()
        XCTAssertEqual(reader.zoneTokens, [nil, Data([1])], "the second beat went on from the first one's token")
        XCTAssertTrue(beat.index.complete)
        XCTAssertEqual(Set(beat.index.entries.keys), ["r1", "r2"])
    }

    func testAWholeReadAgainCutShortKeepsTheCompleteIndex() async {
        let reader = FakeReader()
        reader.zone = .success(.init(changed: ["r1": entry(), "r2": entry()], token: Data([1]), isFullRead: true))
        let beat = SyncBeat(reader: reader, indexURL: nil, clock: { self.at(0) })
        _ = await beat.runOnce()
        reader.database = .success(ICloudDatabaseAnswer(zoneChanged: false, token: Data([5])))
        reader.zoneQueue = [.success(.init(changed: ["r3": entry()], token: Data([9]), reachedEnd: false))]
        beat.requireFullRead()
        _ = await beat.runOnce()
        XCTAssertTrue(beat.index.complete)
        XCTAssertEqual(Set(beat.index.entries.keys), ["r1", "r2"], "half a read never replaces a whole one")
        _ = await beat.runOnce()
        XCTAssertEqual(reader.zoneTokens, [nil, nil, nil], "and the next beat reads it whole again")
    }

    private func entry() -> ICloudZoneIndex.Entry {
        ICloudZoneIndex.Entry(type: "CD_TaskItem", entity: "TaskItem", id: UUID(), updatedAt: at(0), modifiedAt: at(0))
    }
}

/// iCloud, answered by the test.
final class FakeReader: ICloudZoneReading, @unchecked Sendable {
    var database: Result<ICloudDatabaseAnswer, SyncBeatFailure> = .success(ICloudDatabaseAnswer(zoneChanged: true, token: Data([0])))
    var zone: Result<ICloudZoneIndex.ZoneChanges, SyncBeatFailure> = .success(.init(changed: [:], token: Data([0]), isFullRead: true))
    /// Answers for the next zone fetches, in order, before `zone`.
    var zoneQueue: [Result<ICloudZoneIndex.ZoneChanges, SyncBeatFailure>] = []
    var names: [String: String] = [:]
    private(set) var databaseCalls = 0
    private(set) var zoneTokens: [Data?] = []

    func zoneChanged(since token: Data?, timeout: TimeInterval) async -> Result<ICloudDatabaseAnswer, SyncBeatFailure> {
        databaseCalls += 1
        return database
    }

    func zoneChanges(since token: Data?, timeout: TimeInterval,
                     progress: @escaping @Sendable (Int) -> Void) async -> Result<ICloudZoneIndex.ZoneChanges, SyncBeatFailure> {
        zoneTokens.append(token)
        let next = zoneQueue.isEmpty ? zone : zoneQueue.removeFirst()
        if case .success(var changes) = next {
            changes.isFullRead = token == nil
            return .success(changes)
        }
        return next
    }

    func names(of recordNames: [String], timeout: TimeInterval) async -> Result<[String: String], SyncBeatFailure> {
        .success(names.filter { recordNames.contains($0.key) })
    }
}
