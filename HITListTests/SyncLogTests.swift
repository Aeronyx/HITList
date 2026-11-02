import XCTest
import CloudKit
@testable import HITList

/// The sync log (brief 25, item 1): a bounded JSON-lines file, newest kept, read back in order, exported
/// as text; and the wording of durations, errors and saves.
final class SyncLogTests: XCTestCase {
    private var directory: URL!
    /// 2026-11-02 17:17:49.677 UTC, a whole number of milliseconds so it survives the round trip exactly.
    private let start = Date(timeIntervalSince1970: 1_793_639_869.677)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "SyncLogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var url: URL { directory.appending(path: "SyncLog/sync-log.jsonl") }

    /// A log whose clock advances one second per entry from `start`.
    private func makeLog(maxEntries: Int = SyncLog.defaultMaxEntries, maxBytes: Int = SyncLog.defaultMaxBytes) -> SyncLog {
        let ticks = Counter()
        let start = self.start
        return SyncLog(url: url, maxEntries: maxEntries, maxBytes: maxBytes, mirrorToOSLog: false) {
            start.addingTimeInterval(TimeInterval(ticks.next()))
        }
    }

    // MARK: Round trip and order

    func testRoundTripKeepsEveryField() {
        let log = makeLog()
        let written = log.record(.event, "export failed after 1.2 s: network unavailable", level: .error,
                                 fields: ["error": "CKErrorDomain 3", "retryAfter": "5.0 s"])
        let read = log.entries()
        XCTAssertEqual(read, [written])
        XCTAssertEqual(read.first?.date, start)
        XCTAssertEqual(read.first?.kind, .event)
        XCTAssertEqual(read.first?.level, .error)
        XCTAssertEqual(read.first?.fields["retryAfter"], "5.0 s")
        XCTAssertEqual(read.first?.pid, ProcessInfo.processInfo.processIdentifier)
    }

    func testEntriesComeBackInTheOrderTheyWereRecorded() {
        let log = makeLog()
        for i in 1...5 { log.record(.note, "line \(i)") }
        let read = log.entries()
        XCTAssertEqual(read.map(\.message), (1...5).map { "line \($0)" })
        XCTAssertEqual(read.map(\.seq), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(read.map(\.id)).count, 5, "ids are unique")
    }

    func testAnExplicitDateIsKept() {
        let log = makeLog()
        let earlier = start.addingTimeInterval(-30)
        log.record(.save, "3 local saves: 3 updated", date: earlier)
        XCTAssertEqual(log.entries().first?.date, earlier)
    }

    func testEmptyFieldsAreLeftOutOfTheFile() throws {
        let log = makeLog()
        log.record(.scene, "App active")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("\"f\""), text)
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    // MARK: Bounds

    func testTheOldestLinesAreDroppedPastTheEntryCap() {
        let log = makeLog(maxEntries: 40)
        for i in 1...100 { log.record(.note, "line \(i)") }
        let read = log.entries()
        XCTAssertLessThanOrEqual(read.count, 40)
        XCTAssertGreaterThanOrEqual(read.count, 30, "a trim keeps three quarters of the cap")
        XCTAssertEqual(read.last?.message, "line 100", "the newest line is always kept")
        let numbers = read.compactMap { Int($0.message.dropFirst(5)) }
        XCTAssertEqual(numbers, Array((101 - numbers.count)...100), "what is kept is the newest run, without gaps")
    }

    func testTheFileStaysUnderTheByteCap() {
        let log = makeLog(maxBytes: 4096)
        let padding = String(repeating: "x", count: 80)
        for i in 1...200 {
            log.record(.note, "line \(i) \(padding)")
            XCTAssertLessThanOrEqual(log.byteCount(), 4096, "a line that crosses the cap is trimmed in the same call")
        }
        XCTAssertEqual(log.entries().last?.message, "line 200 \(padding)")
    }

    func testLinesThatDontDecodeAreSkipped() throws {
        let log = makeLog()
        log.record(.note, "first")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"torn\": \n".utf8))
        try handle.close()
        log.record(.note, "second")
        XCTAssertEqual(log.entries().map(\.message), ["first", "second"])
    }

    func testAKindFromANewerBuildReadsAsANote() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"k":"telepathy","l":"loud","m":"from the future","n":1,"p":7,"t":1793639869677}"#
        try Data((line + "\n").utf8).write(to: url)
        let read = makeLog().entries()
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first?.kind, .note)
        XCTAssertEqual(read.first?.level, .info)
        XCTAssertEqual(read.first?.pid, 7)
    }

    func testTwoWritersOnOneFileKeepEveryLine() {
        // Two app instances share the file; each appends whole lines, and a trim by one doesn't lose the other's.
        let a = makeLog(maxEntries: 40), b = makeLog(maxEntries: 40)
        for i in 1...30 {
            a.record(.note, "a\(i)")
            b.record(.note, "b\(i)")
        }
        let read = a.entries()
        XCTAssertLessThanOrEqual(read.count, 40)
        XCTAssertEqual(read.last?.message, "b30")
        XCTAssertEqual(read.dropLast().last?.message, "a30")
        XCTAssertEqual(read.map(\.message), b.entries().map(\.message))
    }

    func testANilURLKeepsNothing() {
        let log = SyncLog(url: nil, mirrorToOSLog: false)
        log.record(.note, "nowhere")
        XCTAssertEqual(log.entries(), [])
        XCTAssertEqual(log.byteCount(), 0)
    }

    func testEachRecordIsPostedOnTheMainQueue() {
        let posted = expectation(forNotification: .syncLogDidRecord, object: nil) { note in
            XCTAssertTrue(Thread.isMainThread)
            return SyncLog.entry(from: note)?.message == "posted"
        }
        makeLog().record(.note, "posted")
        wait(for: [posted], timeout: 2)
    }

    func testTheSharedLogLivesInTheAppGroupAndDevelopmentRunsGetTheirOwn() throws {
        let base = try XCTUnwrap(SyncLog.defaultURL(suffix: nil))
        XCTAssertEqual(base.lastPathComponent, "sync-log.jsonl")
        XCTAssertEqual(base.deletingLastPathComponent().lastPathComponent, "SyncLog")
        XCTAssertEqual(SyncLog.defaultURL(suffix: "s25")?.lastPathComponent, "sync-log-s25.jsonl")
        XCTAssertEqual(SyncLog.defaultURL(suffix: "")?.lastPathComponent, "sync-log.jsonl")
        XCTAssertNil(SyncLog.shared.url, "unit tests never write the real log")
    }

    // MARK: Text

    func testTextExportIsOneLinePerEntryOldestFirst() {
        let log = makeLog()
        log.record(.launch, "Launch HITList 0.3.4 (11) · macOS · Production · TestFlight", level: .notice, fields: ["pid": "52543"])
        log.record(.event, "export failed after 1.2 s: network unavailable", level: .error,
                   fields: ["error": "CKErrorDomain 3", "ckError": "networkUnavailable"])
        let text = SyncLog.text(log.entries(), header: ["HITList sync log"], timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(text, """
            HITList sync log
            Times are local (UTC+00:00), oldest first; 2 entries.

            2026-11-02 17:17:49.677  launch    Launch HITList 0.3.4 (11) · macOS · Production · TestFlight · pid=52543
            2026-11-02 17:17:50.677  event     ERROR export failed after 1.2 s: network unavailable · ckError=networkUnavailable · error=CKErrorDomain 3

            """)
    }

    func testTheTextNamesTheOffsetOfTheTimeZone() {
        let text = SyncLog.text([], timeZone: TimeZone(secondsFromGMT: -6 * 3600)!)
        XCTAssertTrue(text.hasPrefix("Times are local (UTC-06:00), oldest first; 0 entries."), text)
    }

    func testOSLogLinesCarryTheKindAndFields() {
        let entry = SyncLogEntry(seq: 1, date: start, pid: 1, kind: .event, level: .info, message: "import finished in 0.49 s",
                                 fields: ["id": "3F2A9C1B", "duration": "0.49 s"])
        XCTAssertEqual(SyncLog.osLogText(entry), "[event] import finished in 0.49 s · duration=0.49 s · id=3F2A9C1B")
    }

    // MARK: Wording

    func testDurations() {
        let d = SyncLogFormat.duration
        XCTAssertEqual(d(0.494), "0.49 s")
        XCTAssertEqual(d(-1), "0.00 s")
        XCTAssertEqual(d(4.26), "4.3 s")
        XCTAssertEqual(d(12.4), "12 s")
        XCTAssertEqual(d(420), "7 min")
        XCTAssertEqual(d(432), "7 min 12 s")
        XCTAssertEqual(d(7200), "2 h")
        XCTAssertEqual(d(7380), "2 h 3 min")
        XCTAssertEqual(d(273_600), "3 d 4 h")
    }

    func testErrorFieldsKeepEverythingTheErrorSays() {
        let underlying = CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 30])
        let error = NSError(domain: NSCocoaErrorDomain, code: 134_410, userInfo: [
            NSLocalizedDescriptionKey: "CloudKit integration failed",
            NSUnderlyingErrorKey: underlying as NSError,
            "NSDebugDescription": "line one\nline two",
        ])
        let fields = SyncLogFormat.errorFields(error)
        XCTAssertEqual(fields["error"], "NSCocoaErrorDomain 134410")
        XCTAssertEqual(fields["description"], "CloudKit integration failed")
        XCTAssertNil(fields["ckError"], "not a CloudKit error itself")
        XCTAssertEqual(fields["retryAfter"], "30 s", "taken from the underlying CKError")
        XCTAssertTrue(fields["underlying"]?.hasPrefix("CKErrorDomain 7 requestRateLimited") == true, fields["underlying"] ?? "")
        XCTAssertEqual(fields["info.NSDebugDescription"], "line one line two")
    }

    func testErrorFieldsNameCloudKitCodesAndPartialFailures() {
        let partial = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: ["CD_TaskItem/1": CKError(.quotaExceeded), "CD_TaskItem/2": CKError(.quotaExceeded)],
            CKErrorRetryAfterKey: 5,
        ])
        let fields = SyncLogFormat.errorFields(partial)
        XCTAssertEqual(fields["error"], "CKErrorDomain 2")
        XCTAssertEqual(fields["ckError"], "partialFailure")
        XCTAssertEqual(fields["retryAfter"], "5.0 s")
        XCTAssertEqual(fields["partialErrors"], "2: CD_TaskItem/1: CKErrorDomain quotaExceeded; CD_TaskItem/2: CKErrorDomain quotaExceeded")
    }

    func testLongValuesAreClipped() {
        XCTAssertEqual(SyncLogFormat.clip("abcdef", 4), "abc…")
        XCTAssertEqual(SyncLogFormat.clip("abc", 4), "abc")
    }

    @MainActor
    func testSaveSummaryWording() {
        var summary = CloudSyncMonitor.SaveSummary(inserted: 1, updated: 2, entities: ["TaskItem": 2, "Project": 1])
        XCTAssertEqual(summary.text, "1 inserted, 2 updated")
        XCTAssertEqual(summary.entityText, "TaskItem 2, Project 1")
        summary.add(CloudSyncMonitor.SaveSummary(deleted: 1, entities: ["Project": 1]))
        XCTAssertEqual(summary.text, "1 inserted, 2 updated, 1 deleted")
        XCTAssertEqual(summary.entityText, "Project 2, TaskItem 2")
        XCTAssertEqual(CloudSyncMonitor.SaveSummary(userInfo: nil).total, 0)
    }
}

/// A thread-safe step counter for the injected clock.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = -1
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
