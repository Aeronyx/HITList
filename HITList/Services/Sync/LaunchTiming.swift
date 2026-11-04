import Foundation
import OSLog

/// How long a launch takes to show its first list (brief 42, item 5): milliseconds since the process
/// started, at a few points of `HITListApp.init` that the sync code already passes through, and at the
/// first frame of a screen (the toolbar's `SyncBolt` appearing, which every list screen draws).
///
/// The first frame writes one sync-log line, "First screen 412 ms after launch", with the marks as fields,
/// and emits `os_signpost` events (subsystem `com.trammells.hitlist`, category `launch`) for Instruments.
/// Nothing runs after that: no timer, no observer.
@MainActor
enum LaunchTiming {
    static let signposter = OSSignposter(subsystem: "com.trammells.hitlist", category: "launch")

    /// When the kernel started this process; nil if it couldn't be read.
    nonisolated static let processStart: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }()

    /// Milliseconds from the process start to `date`; nil without a start time.
    nonisolated static func milliseconds(at date: Date = Date(), since start: Date? = processStart) -> Int? {
        start.map { Int((date.timeIntervalSince($0) * 1000).rounded()) }
    }

    private(set) static var marks: [(name: String, ms: Int)] = []
    private(set) static var firstFrameMs: Int?

    /// Records that launch reached `name` ("store", "dedupe"). Only before the first frame.
    static func mark(_ name: String, at date: Date = Date()) {
        guard firstFrameMs == nil, let ms = milliseconds(at: date) else { return }
        marks.append((name, ms))
        signposter.emitEvent("Launch mark", "\(name, privacy: .public) \(ms) ms")
    }

    /// The first list frame. Logged once per process; later calls do nothing.
    static func firstFrame(at date: Date = Date(), log: @MainActor (String, [String: String]) -> Void = writeToSyncLog) {
        guard firstFrameMs == nil, let ms = milliseconds(at: date) else { return }
        firstFrameMs = ms
        signposter.emitEvent("First frame", "\(ms) ms")
        log("First screen \(ms) ms after launch", fields(firstFrame: ms))
    }

    static func writeToSyncLog(_ message: String, _ fields: [String: String]) {
        CloudSyncMonitor.shared.write(.launch, message, level: .notice, fields: fields)
    }

    /// "store=180 ms" for each mark, plus "firstFrame".
    static func fields(firstFrame: Int) -> [String: String] {
        var fields = ["firstFrame": "\(firstFrame) ms"]
        for mark in marks { fields[mark.name] = "\(mark.ms) ms" }
        return fields
    }

    /// Tests only: forget this process's marks.
    static func reset() {
        marks = []
        firstFrameMs = nil
    }
}
