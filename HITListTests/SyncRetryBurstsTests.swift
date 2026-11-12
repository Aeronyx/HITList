import XCTest
@testable import HITList

/// Brief 95, George's logs of 2026-11-10: the mirror's own immediate retries, one log line per run instead of two per
/// retry (`SyncRetryBursts`).
final class SyncRetryBurstsTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func start(_ type: SyncEventType, at seconds: TimeInterval) -> SyncRetryBursts.Line {
        SyncRetryBursts.Line(date: at(seconds), message: "\(type.title) started", level: .info, fields: ["id": "x"])
    }

    private func failure(_ type: SyncEventType, _ ckError: String, at seconds: TimeInterval) -> SyncRetryBursts.Line {
        SyncRetryBursts.Line(date: at(seconds), message: "\(type.title) failed after 0.01 s: iCloud is busy, will retry",
                             level: .error, fields: ["ckError": ckError, "error": "CKErrorDomain 7", "id": "x",
                                                     "duration": "0.01 s"])
    }

    private func success(_ type: SyncEventType, at seconds: TimeInterval) -> SyncRetryBursts.Line {
        SyncRetryBursts.Line(date: at(seconds), message: "\(type.title) finished in 2.6 s", level: .info, fields: [:])
    }

    /// The iPhone at 18:12:02 (I1865–1982): the launch import fails "serviceUnavailable" after 0.29 s, then 56 imports
    /// start and fail "requestRateLimited" about every 20 ms until 18:12:03.479, with one export between them at
    /// 18:12:03.044; the next import, 83 s later, succeeds. Here 0 s is 18:12:02.065.
    func testGeorgesStormIsTenLinesNotAHundredAndFourteen() {
        var bursts = SyncRetryBursts()
        var written: [SyncRetryBursts.Line] = []
        let first = UUID()
        written += bursts.started(first, type: .importing, at: at(0), line: start(.importing, at: 0))
        written += bursts.failed(first, type: .importing, key: "serviceUnavailable", reason: "iCloud is busy, will retry",
                                 at: at(0.284), line: failure(.importing, "serviceUnavailable", at: 0.284))
        var clock = 0.301
        for n in 0..<56 {
            if n == 34 {  // the export between them: its own lines, the run goes on
                let export = UUID()
                written += bursts.started(export, type: .exporting, at: at(0.979), line: start(.exporting, at: 0.979))
                written += bursts.finished(export, type: .exporting, at: at(0.992), line: success(.exporting, at: 0.992))
            }
            let id = UUID()
            written += bursts.started(id, type: .importing, at: at(clock), line: start(.importing, at: clock))
            written += bursts.failed(id, type: .importing, key: "requestRateLimited", reason: "iCloud is busy, will retry",
                                     at: at(clock + 0.004), line: failure(.importing, "requestRateLimited", at: clock + 0.004))
            clock += 0.0198
        }
        // Quiet: the run's line is due `gap` after its last failure.
        XCTAssertEqual(bursts.deadline?.timeIntervalSince(t0) ?? 0, clock - 0.0198 + 0.004 + SyncRetryBursts.gap, accuracy: 0.0001)
        written += bursts.expire(now: at(5))
        XCTAssertNil(bursts.deadline)
        let last = UUID()
        written += bursts.started(last, type: .importing, at: at(84.3), line: start(.importing, at: 84.3))
        written += bursts.finished(last, type: .importing, at: at(86.96), line: success(.importing, at: 86.96))

        XCTAssertEqual(written.map(\.message), [
            "Import started", "Import failed after 0.01 s: iCloud is busy, will retry",  // CK 6, whole
            "Import started", "Import failed after 0.01 s: iCloud is busy, will retry",  // the first CK 7, whole
            "Export started", "Export finished in 2.6 s",
            "Import failed 55 more times in 1.1 s, each retried at once: iCloud is busy, will retry",
            "Import started", "Import finished in 2.6 s",
        ])
        let run = written[6]
        XCTAssertEqual(run.level, .error)
        XCTAssertEqual(run.fields["ckError"], "requestRateLimited")
        XCTAssertEqual(run.fields["retries"], "55")
        XCTAssertEqual(run.fields["over"], "1.1 s")
        XCTAssertNil(run.fields["id"], "no one event's id")
        XCTAssertEqual(run.date.timeIntervalSince(t0), 0.301 + 55 * 0.0198 + 0.004, accuracy: 0.001, "dated at the run's last failure")
        XCTAssertEqual(written.map(\.date), written.map(\.date).sorted(), "the log keeps the order things happened in")
    }

    func testASuccessEndsTheRunAndItsHeldStartIsWrittenAfterAll() {
        var bursts = SyncRetryBursts()
        var written: [SyncRetryBursts.Line] = []
        for n in 0..<3 {
            let id = UUID()
            let t = Double(n) * 0.1
            written += bursts.started(id, type: .importing, at: at(t), line: start(.importing, at: t))
            written += bursts.failed(id, type: .importing, key: "requestRateLimited", reason: "iCloud is busy, will retry",
                                     at: at(t + 0.01), line: failure(.importing, "requestRateLimited", at: t + 0.01))
        }
        let good = UUID()
        written += bursts.started(good, type: .importing, at: at(0.5), line: start(.importing, at: 0.5))
        XCTAssertEqual(written.count, 2, "held while it may be one more retry")
        written += bursts.finished(good, type: .importing, at: at(1.2), line: success(.importing, at: 1.2))
        XCTAssertEqual(written.map(\.message), [
            "Import started", "Import failed after 0.01 s: iCloud is busy, will retry",
            "Import failed 2 more times in 0.20 s, each retried at once: iCloud is busy, will retry",
            "Import started", "Import finished in 2.6 s",
        ])
        XCTAssertNil(bursts.deadline)
    }

    func testAnotherFailureOrALaterRetryIsWrittenWhole() {
        var bursts = SyncRetryBursts()
        var written: [SyncRetryBursts.Line] = []
        let a = UUID(), b = UUID(), c = UUID()
        written += bursts.started(a, type: .importing, at: at(0), line: start(.importing, at: 0))
        written += bursts.failed(a, type: .importing, key: "requestRateLimited", reason: "busy", at: at(0.01),
                                 line: failure(.importing, "requestRateLimited", at: 0.01))
        // A different error: whole, and it starts a run of its own.
        written += bursts.started(b, type: .importing, at: at(0.1), line: start(.importing, at: 0.1))
        written += bursts.failed(b, type: .importing, key: "networkUnavailable", reason: "network unavailable", at: at(0.2),
                                 line: failure(.importing, "networkUnavailable", at: 0.2))
        // The same error long after: not a retry at once.
        written += bursts.started(c, type: .importing, at: at(10), line: start(.importing, at: 10))
        written += bursts.failed(c, type: .importing, key: "networkUnavailable", reason: "network unavailable", at: at(10.1),
                                 line: failure(.importing, "networkUnavailable", at: 10.1))
        XCTAssertEqual(written.count, 6, "nothing collapsed: no line says the same thing twice in a row at once")
        XCTAssertEqual(bursts.expire(now: at(20)), [], "a run of one has nothing to add")
    }

    func testAHeldStartWhoseEventNeverEndsIsWrittenWhenTheRunGoesQuiet() {
        var bursts = SyncRetryBursts()
        let a = UUID(), b = UUID()
        _ = bursts.started(a, type: .exporting, at: at(0), line: start(.exporting, at: 0))
        _ = bursts.failed(a, type: .exporting, key: "zoneBusy", reason: "busy", at: at(0.01), line: failure(.exporting, "zoneBusy", at: 0.01))
        XCTAssertEqual(bursts.started(b, type: .exporting, at: at(0.5), line: start(.exporting, at: 0.5)), [])
        let quiet = bursts.expire(now: at(3))
        XCTAssertEqual(quiet.map(\.message), ["Export started"], "a running event keeps its line")
        let ended = bursts.failed(b, type: .exporting, key: "zoneBusy", reason: "busy", at: at(4),
                                  line: failure(.exporting, "zoneBusy", at: 4))
        XCTAssertEqual(ended.count, 1, "its start is in the log, so its end is too")
    }
}
