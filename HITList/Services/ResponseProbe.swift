#if DEBUG && os(iOS)
import UIKit
import QuartzCore

/// Brief 164 (round 33): how long the iPhone takes to answer a tap, and why. Debug only, and only with
/// `-responseProbe YES`. Nothing in a released build, nothing without the argument.
///
/// For every finger lifted it writes one line to `tmp/response-probe.txt` in the app's container
/// (`xcrun devicectl device copy from … --domain-type appDataContainer --source tmp/response-probe.txt`):
/// - `start`: milliseconds from the finger's lift to the first main-thread run of 4 ms or more. A long `start` with
///   the main thread idle is a tap recognised late (a gesture waiting on another, a control under something that
///   takes the touch first); a short one means the app went to work at once.
/// - `busy`: milliseconds the main thread worked in the 1.5 s after the lift, `longest` its longest single run,
///   `settled` the end of the last run of 4 ms or more: a slow answer is a large `busy` and `longest`.
/// - `view`: the class of the view the finger touched.
/// The main thread's runs are measured between the run loop's waking and its going back to sleep
/// (`CFRunLoopObserver`), as the system's own hang detection does.
@MainActor
enum ResponseProbe {
    private static var started = false
    private static var observer: CFRunLoopObserver?
    private static var wokeAt: CFTimeInterval = 0
    /// Main-thread runs of 4 ms or more: (start, end) in `CACurrentMediaTime`.
    private static var runs: [(CFTimeInterval, CFTimeInterval)] = []
    private static var pending: [(lift: CFTimeInterval, view: String)] = []
    private static var count = 0
    private static var restFrom: CFTimeInterval = 0
    private static let file = FileManager.default.temporaryDirectory.appendingPathComponent("response-probe.txt")

    static var isAsked: Bool { UserDefaults.standard.bool(forKey: "responseProbe") }

    static func startIfAsked() {
        guard isAsked, !started else { return }
        started = true
        try? "# n view start busy longest settled (ms after the finger's lift)\n".write(to: file, atomically: true, encoding: .utf8)
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue
                                                          | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            MainActor.assumeIsolated {
                if activity == .afterWaiting { wokeAt = now; return }
                if wokeAt > 0, now - wokeAt >= 0.004 { runs.append((wokeAt, now)) }
                wokeAt = 0
                report(now: now)
            }
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        attach()
    }

    /// Watches every touch of every window without taking one (`cancelsTouchesInView` off, never recognised).
    private static func attach() {
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows where !(window.gestureRecognizers ?? []).contains(where: { $0 is Watcher }) {
                window.addGestureRecognizer(Watcher())
            }
        }
        if !started { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { attach() } // windows the app opens later (sheets)
    }

    fileprivate static func lifted(at time: CFTimeInterval, view: UIView?) {
        let name = view.map { String(describing: type(of: $0)) } ?? "?"
        pending.append((time, name))
    }

    private static func report(now: CFTimeInterval) {
        while let first = pending.first, now - first.lift > 1.5 {
            pending.removeFirst()
            let window = runs.filter { $0.1 > first.lift && $0.0 < first.lift + 1.5 }
            let busy = window.reduce(0) { $0 + ($1.1 - max($1.0, first.lift)) }
            let longest = window.map { $0.1 - max($0.0, first.lift) }.max() ?? 0
            let start = window.first.map { max(0, $0.0 - first.lift) } ?? -0.001
            let settled = window.last.map { $0.1 - first.lift } ?? 0
            count += 1
            let line = String(format: "%d %@ %.0f %.0f %.0f %.0f\n", count, first.view, start * 1000, busy * 1000,
                              longest * 1000, settled * 1000)
            write(line)
        }
        // Every 5 s: how much the main thread worked, touched or not (a busy thread at rest answers every tap late).
        if restFrom == 0 { restFrom = now }
        if now - restFrom >= 5 {
            let span = runs.filter { $0.1 > restFrom }
            let busy = span.reduce(0) { $0 + ($1.1 - max($1.0, restFrom)) }
            write(String(format: "rest %.1fs busy %.0f longest %.0f runs %d\n", now - restFrom, busy * 1000,
                         (span.map { $0.1 - $0.0 }.max() ?? 0) * 1000, span.count))
            restFrom = now
        }
        runs.removeAll { $0.1 < now - 7 }
    }

    private static func write(_ line: String) {
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
        print("responseProbe", line, terminator: "")
    }

    private final class Watcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            for touch in touches { ResponseProbe.lifted(at: touch.timestamp, view: touch.view) }
            state = .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }

        override func reset() { super.reset() }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    }
}
#endif
