#if (DEBUG || RESPONSE_PROBE) && os(iOS)
import UIKit
import QuartzCore
import Observation

/// Brief 164 (round 33): how long the iPhone takes to answer a tap, and why. Debug only, and only with
/// `-responseProbe YES` (or `-responseAutopilot YES`, brief 168). Nothing in a released build, nothing without the
/// argument; a Release build for measuring compiles it in with `OTHER_SWIFT_FLAGS='$(inherited) -D RESPONSE_PROBE'`
/// on the xcodebuild command line, so no project file changes.
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

    static var isAsked: Bool {
        UserDefaults.standard.bool(forKey: "responseProbe") || ResponseAutopilot.isAsked
    }
    /// Every main-thread run of 0.5 ms or more, for the autopilot's steps (`runs` keeps only those of 4 ms).
    fileprivate static var allRuns: [(CFTimeInterval, CFTimeInterval)] = []
    /// How many times the main run loop woke: at rest a screen that draws nothing wakes it seldom.
    fileprivate static var wakes = 0

    static func startIfAsked() {
        guard isAsked, !started else { return }
        started = true
        try? "# n view start busy longest settled (ms after the finger's lift)\n".write(to: file, atomically: true, encoding: .utf8)
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue
                                                          | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            MainActor.assumeIsolated {
                if activity == .afterWaiting { wokeAt = now; wakes += 1; return }
                if wokeAt > 0, now - wokeAt >= 0.004 { runs.append((wokeAt, now)) }
                if wokeAt > 0, now - wokeAt >= 0.0005 { allRuns.append((wokeAt, now)) }
                wokeAt = 0
                report(now: now)
            }
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        attach()
        ResponseAutopilot.startIfAsked()
    }

    /// The main thread's runs between two moments (the autopilot's steps).
    fileprivate static func work(from: CFTimeInterval, to: CFTimeInterval) -> (busy: Double, longest: Double, count: Int) {
        let span = allRuns.filter { $0.1 > from && $0.0 < to }
        let lengths = span.map { min($0.1, to) - max($0.0, from) }
        return (lengths.reduce(0, +), lengths.max() ?? 0, span.count)
    }

    /// When the longest main-thread run between two moments ended.
    fileprivate static func longestRunEnd(from: CFTimeInterval, to: CFTimeInterval) -> CFTimeInterval? {
        allRuns.filter { $0.1 > from && $0.0 < to }.max { ($0.1 - $0.0) < ($1.1 - $1.0) }?.1
    }

    fileprivate static func writeLine(_ line: String) { write(line) }

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
        if allRuns.count > 20_000 { allRuns.removeFirst(10_000) }
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

/// Brief 168 (round 34): the app drives itself, so the phone can be measured with nobody's finger and no XCUITest
/// (whose accessibility queries keep the app's main thread busy). With `-responseAutopilot YES` it switches each tab
/// in turn three times through the shell's own state, rests a minute on each tab, then opens Settings, pushes each of
/// its pages, scrolls it top to bottom and goes back, twice. For each step it writes to `tmp/response-probe.txt`:
/// `step <name> frame <ms> work <ms> busy <ms> longest <ms> worst <ms> slow <n>`:
/// - `frame`: from the change to the first frame that can show it (the display link's next target after the step's
///   longest main-thread run, which is the new screen being built);
/// - `work`: the main thread's work in that time; `busy` and `longest`: its work, and its longest run, in the step's
///   window (the motion included);
/// - `worst` and `slow`: the longest gap between two frames in the window, and how many gaps were over 32 ms.
/// `rest <name> <s> busy <ms> longest <ms> wakes <n>` is a screen left alone; `memory <name> <MB>` the footprint.
@MainActor
enum ResponseAutopilot {
    static var isAsked: Bool { UserDefaults.standard.bool(forKey: "responseAutopilot") }
    private static var started = false

    static func startIfAsked() {
        guard isAsked, !started else { return }
        started = true
        // Minutes of nobody's finger: the screen must not lock under the run.
        UIApplication.shared.isIdleTimerDisabled = true
        Task { @MainActor in await run() }
    }

    private static func say(_ line: String) { ResponseProbe.writeLine(line + "\n") }

    private static func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private static func run() async {
        let driver = ProbeDriver.shared
        await pause(8)
        memory("launch")
        await rest("start", 10)
        for pass in 1...3 {
            for tab in [MobileTab.inbox, .upcoming, .flipboard, .today] {
                await step("tab \(tab.rawValue) \(pass)") { driver.send(.tab(tab)) }
                say("context \(tab.rawValue) \(driver.context)")
                await pause(0.8)
            }
        }
        memory("all four visited")
        // A save with every tab visited: what each list on the way does when the store changes (on Today).
        let run = Int(Date().timeIntervalSince1970) % 100_000
        for n in 1...3 {
            let title = "Probe \(run) \(n)"
            await step("add task \(n)") { driver.send(.addTask("\(title) today")) }
            await pause(0.8)
            await step("check off \(n)", window: 1.5) { driver.send(.complete(title)) }
            await pause(0.8)
        }
        for tab in [MobileTab.today, .inbox, .upcoming, .flipboard] {
            driver.send(.tab(tab))
            await pause(3)
            await rest(tab.rawValue, 60)
        }
        driver.send(.tab(.today))
        await pause(2)
        for pass in 1...2 {
            await step("settings open \(pass)", window: 1.5) { driver.send(.openSettings) }
            await pause(1)
            await scroll("settings home \(pass)")
            for page in SettingsPage.allCases {
                await step("push \(page.rawValue) \(pass)") { driver.send(.push(page)) }
                await pause(0.6)
                await scroll("\(page.rawValue) \(pass)")
                await pause(0.3)
                await step("back \(page.rawValue) \(pass)") { driver.send(.back) }
                await pause(0.6)
            }
            await step("settings close \(pass)", window: 1.5) { driver.send(.closeSettings) }
            await pause(1.5)
        }
        memory("after settings")
        await rest("today after settings", 20)
        say("done")
    }

    private static func name(_ text: String) -> String { text.replacingOccurrences(of: " ", with: "_") }

    private static func step(_ label: String, window: Double = 1.2, _ action: () -> Void) async {
        let ticker = Ticker()
        let t0 = CACurrentMediaTime()
        action()
        ticker.start()
        await pause(window)
        ticker.stop()
        // The answering frame: the first after the step's longest main-thread run (SwiftUI may build the new screen a
        // turn after the change, so the very first tick can come before it).
        let all = ResponseProbe.work(from: t0, to: t0 + window)
        let built = ResponseProbe.longestRunEnd(from: t0, to: t0 + window) ?? t0
        let first = ticker.ticks.first(where: { $0.at >= built }) ?? ticker.ticks.first ?? (t0, t0)
        let toFrame = ResponseProbe.work(from: t0, to: first.at)
        say(String(format: "step %@ frame %.0f work %.0f busy %.0f longest %.0f worst %.0f slow %d", name(label),
                   (first.target - t0) * 1000, toFrame.busy * 1000, all.busy * 1000, all.longest * 1000,
                   ticker.worstGap * 1000, ticker.slowGaps))
    }

    /// Scrolls the screen on top from its top to its bottom at a thumb's flick speed, one step a frame.
    private static func scroll(_ label: String) async {
        guard let view = topScrollView() else { return say("scroll \(name(label)) none") }
        let top = -view.adjustedContentInset.top
        let bottom = max(top, view.contentSize.height + view.adjustedContentInset.bottom - view.bounds.height)
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: top), animated: false)
        await pause(0.3)
        guard bottom - top > 1 else {
            return say(String(format: "scroll %@ fits content %.0f height %.0f", name(label), view.contentSize.height,
                              view.bounds.height))
        }
        let ticker = Ticker()
        let speed: CGFloat = 1600 // points a second
        let t0 = CACurrentMediaTime()
        var last = t0
        ticker.onTick = { now in
            let y = min(bottom, view.contentOffset.y + speed * CGFloat(now - last))
            last = now
            view.contentOffset.y = y
            return y < bottom
        }
        ticker.start()
        while ticker.isRunning { await pause(0.05) }
        let t1 = CACurrentMediaTime()
        let all = ResponseProbe.work(from: t0, to: t1)
        say(String(format: "scroll %@ points %.0f ms %.0f busy %.0f longest %.0f worst %.0f slow %d", name(label),
                   bottom - top, (t1 - t0) * 1000, all.busy * 1000, all.longest * 1000, ticker.worstGap * 1000,
                   ticker.slowGaps))
    }

    /// The front screen's scroll view: in the frontmost presented controller, the last one (drawn on top) that starts
    /// at the window's leading edge and spans it.
    private static func topScrollView() -> UIScrollView? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first,
              var controller = window.rootViewController else { return nil }
        while let next = controller.presentedViewController, !next.isBeingDismissed { controller = next }
        var found: UIScrollView?
        func visit(_ view: UIView) {
            if view.isHidden || view.alpha < 0.01 { return }
            if let scroll = view as? UIScrollView, scroll.bounds.height > 200 {
                let frame = scroll.convert(scroll.bounds, to: window)
                if abs(frame.minX) < 2, frame.width > window.bounds.width * 0.8 { found = scroll }
            }
            view.subviews.forEach(visit)
        }
        visit(controller.view)
        return found
    }

    private static func rest(_ label: String, _ seconds: Double) async {
        let wakes = ResponseProbe.wakes
        let t0 = CACurrentMediaTime()
        await pause(seconds)
        let t1 = CACurrentMediaTime()
        let all = ResponseProbe.work(from: t0, to: t1)
        say(String(format: "rest %@ %.0fs busy %.0f longest %.0f runs %d wakes %d", name(label), t1 - t0,
                   all.busy * 1000, all.longest * 1000, all.count, ResponseProbe.wakes - wakes))
    }

    private static func memory(_ label: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let mb = result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
        say(String(format: "memory %@ %.1f MB", name(label), mb))
    }

    /// A display link for one step: when each frame came, and the longest gap between two.
    private final class Ticker: NSObject {
        private var link: CADisplayLink?
        private(set) var ticks: [(at: CFTimeInterval, target: CFTimeInterval)] = []
        var onTick: ((CFTimeInterval) -> Bool)?
        var isRunning: Bool { link != nil }

        var worstGap: Double { zip(ticks, ticks.dropFirst()).map { $1.at - $0.at }.max() ?? 0 }
        var slowGaps: Int { zip(ticks, ticks.dropFirst()).filter { $1.at - $0.at > 0.032 }.count }

        func start() {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            let now = CACurrentMediaTime()
            ticks.append((now, link.targetTimestamp))
            if let onTick, !onTick(now) { stop() }
        }
    }
}

/// The autopilot's orders to the iPhone shell (`MobileShell`) and Settings (`SettingsHome`), which carry them out
/// through their own state, as a tap would.
@MainActor @Observable
final class ProbeDriver {
    static let shared = ProbeDriver()

    enum Command: Equatable {
        case tab(MobileTab), openSettings, closeSettings, push(SettingsPage), back, addTask(String), complete(String)
    }

    struct Order: Equatable {
        let serial: Int
        let command: Command
    }

    private(set) var order: Order?
    /// The list the "+" would add to, as the shell last saw it (`popouts.listContext`).
    @ObservationIgnored var contextReader: () -> String = { "?" }
    var context: String { contextReader() }

    func send(_ command: Command) {
        order = Order(serial: (order?.serial ?? 0) + 1, command: command)
    }
}
#endif
