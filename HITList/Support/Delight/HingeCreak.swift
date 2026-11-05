import SwiftUI
import OSLog
#if os(iOS)
import AVFoundation
import Synchronization
#endif

/// Extras → Squeaky hinge (brief 50, George: "every time my friend opens or closes his Duo with HITList open, the
/// hinges squeak/creak, which of course will only be funny if it can happen instantaneously").
///
/// The hinge reports itself through a `UIHingeInteraction` on a zero-size view in the window (`hingeCreak()`,
/// applied once by `ContentView`); its handler hands each update straight to `hingeChanged`, with no SwiftUI
/// update in between. `HingeCreakMotion` turns the angles into drives, which go to the audio thread in one atomic
/// word (`HingeCreakEngine`); the synth (`HingeCreakSynth`) starts a grain with the very next buffer. The engine is
/// pre-warmed: it starts as soon as a hinge has reported (at launch, on an iPhone Duo) and idles on silent
/// buffers, so the first movement costs one buffer (5 ms) plus the output's own latency, not an engine start.
///
/// The audio session is Ambient, as for every HITList sound: the silent switch mutes it and it never pauses
/// music. Nothing plays in the background (the engine stops there), with the switch off, or on a device
/// without a hinge (the engine never starts). The synth's soft limiter keeps it at -12 dBFS or below.
@MainActor
@Observable
final class HingeCreak {
    nonisolated static let key = "delight.squeakyHinge"

    static let shared = HingeCreak()

    nonisolated static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    nonisolated static func shouldRun(enabled: Bool, hasHinge: Bool, inForeground: Bool) -> Bool {
        enabled && hasHinge && inForeground
    }

    /// A hinge has reported during this run: the device folds. Extras shows the switch only then.
    private(set) var hasHinge = false

    /// The latest creaks' timings, newest last (at most 20).
    @ObservationIgnored private(set) var latencies: [HingeCreakLatency] = []

    @ObservationIgnored private var motion = HingeCreakMotion()
    @ObservationIgnored private var enabled = HingeCreak.isEnabled(in: AppGroup.defaults)
    @ObservationIgnored private var inForeground = true
    @ObservationIgnored private var lastUpdate = 0.0
    #if os(iOS)
    private let engine = HingeCreakEngine()
    #endif

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "delight")

    func setEnabled(_ on: Bool) {
        enabled = on
        refresh()
    }

    func setInForeground(_ on: Bool) {
        inForeground = on
        refresh()
    }

    /// A hinge update as it arrives (main thread): its angle in radians, nil when the hinge left this hierarchy.
    /// `hostTime` (mach ticks) is when it arrived.
    func hingeChanged(angle: Double?, at hostTime: UInt64) {
        let seconds = HostClock.seconds(hostTime)
        defer { lastUpdate = seconds }
        guard let angle else {
            Self.log.info("Hinge left this window")
            motion.reset()
            return
        }
        let degrees = angle * 180 / .pi
        if !hasHinge {
            hasHinge = true
            Self.log.info("Hinge reported at \(degrees, format: .fixed(precision: 1))°: squeaky hinge \(self.enabled ? "on" : "off", privacy: .public)")
            refresh()
        }
        // Every update, for reading a real fold's rate back (`log stream --level debug`; not kept otherwise).
        Self.log.debug("Hinge \(degrees, format: .fixed(precision: 1))°, \((seconds - self.lastUpdate) * 1000, format: .fixed(precision: 1)) ms after the last")
        guard running, let drive = motion.update(degrees: degrees, at: seconds) else { return }
        #if os(iOS)
        engine.play(drive, eventHostTime: hostTime)
        if drive.kick { reportLatency(of: hostTime) }
        #endif
    }

    private var running: Bool { Self.shouldRun(enabled: enabled, hasHinge: hasHinge, inForeground: inForeground) }

    /// Starts or stops the engine to match the switch, the hinge and the app's place.
    private func refresh() {
        if !running { motion.reset() }
        #if os(iOS)
        if running { engine.start() } else { engine.stop() }
        #endif
    }

    #if os(iOS)
    /// Reads what the audio thread measured for the creak that `eventHost` started, once it has played.
    private func reportLatency(of eventHost: UInt64) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard let latency = engine.measuredLatency(forEvent: eventHost) else { return }
            latencies = Array((latencies + [latency]).suffix(20))
            Self.log.info("""
                Hinge creak: event → render callback \(latency.toCallback * 1000, format: .fixed(precision: 1)) ms, \
                → audible ≈ \(latency.toAudible * 1000, format: .fixed(precision: 1)) ms \
                (\(latency.frames(at: 120), format: .fixed(precision: 2)) frames at 120 Hz; output latency \
                \(latency.outputLatency * 1000, format: .fixed(precision: 1)) ms, IO buffer \
                \(latency.ioBuffer * 1000, format: .fixed(precision: 1)) ms)
                """)
        }
    }
    #endif
}

/// How long one creak took to start, from the hinge update that started it (brief 50 asks for the numbers).
struct HingeCreakLatency: Equatable {
    /// When the hinge update reached the app (the handler's first line).
    var eventSeconds: Double
    /// When the audio thread picked the drive up (the render callback that started the grain).
    var callbackSeconds: Double
    /// When that buffer's first sample is due at the output, as Core Audio stamps it (0 if not stamped).
    var bufferStartSeconds: Double
    /// The route's own latency after that (`AVAudioSession.outputLatency`).
    var outputLatency: Double
    /// The engine's buffer (`AVAudioSession.ioBufferDuration`).
    var ioBuffer: Double

    var toCallback: Double { callbackSeconds - eventSeconds }
    /// From the hinge update to the creak leaving the speaker.
    var toAudible: Double { max(bufferStartSeconds, callbackSeconds) - eventSeconds + outputLatency }

    /// `toAudible` in display frames at `refreshRate` Hz.
    func frames(at refreshRate: Double) -> Double { toAudible * refreshRate }
}

/// `mach_absolute_time`, which Core Audio's host times use too.
enum HostClock {
    static let ticksPerSecond: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return 1e9 * Double(info.denom) / Double(info.numer)
    }()

    static var now: UInt64 { mach_absolute_time() }

    static func seconds(_ ticks: UInt64) -> Double { Double(ticks) / ticksPerSecond }
}

extension View {
    /// Listens to the hinge (iPhone Duo, iOS 27.1) and keeps the squeaky hinge in step with Extras → Squeaky
    /// hinge and the scene's phase. Applied once, by `ContentView`.
    func hingeCreak() -> some View {
        modifier(HingeCreakHost())
    }
}

private struct HingeCreakHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HingeCreak.key, store: AppGroup.defaults) private var enabled = true

    func body(content: Content) -> some View {
        content
            .background { HingeCreakProbe() }
            // Inactive (a fold moving the window between displays, Control Center) still counts: only the
            // background is silent.
            .onChange(of: scenePhase, initial: true) { _, phase in HingeCreak.shared.setInForeground(phase != .background) }
            .onChange(of: enabled, initial: true) { _, on in HingeCreak.shared.setEnabled(on) }
            #if DEBUG
            .task { await HingeCreakDebug.sweepIfAsked() }
            #endif
    }
}

/// The zero-size view that carries the hinge interaction (iOS 27.1 and the SDK that has it); nothing elsewhere.
private struct HingeCreakProbe: View {
    var body: some View {
        #if compiler(>=6.4) && os(iOS)
        if #available(iOS 27.1, *) {
            HingeInteractionView()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        #endif
    }
}

#if compiler(>=6.4) && os(iOS)
@available(iOS 27.1, *)
private struct HingeInteractionView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        // Called with the initial state, then on every change, on the main thread: straight to the creak.
        view.addInteraction(UIHingeInteraction { _, update in
            let now = HostClock.now
            HingeCreak.shared.hingeChanged(angle: update.hinge.map { Double($0.angle) }, at: now)
        })
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
#endif

#if os(iOS)
/// What the main thread and the audio thread share, lock-free: the latest drive in one word, the arrival time of
/// the hinge update behind the latest kick, and back from the audio thread, what it measured for that kick.
final class HingeCreakMailbox: Sendable {
    let drive = Atomic<UInt64>(0)
    /// The last drive sequence the audio thread applied.
    let applied = Atomic<UInt8>(0)
    let kickEventHost = Atomic<UInt64>(0)
    let measuredEventHost = Atomic<UInt64>(0)
    let measuredCallbackHost = Atomic<UInt64>(0)
    let measuredBufferHost = Atomic<UInt64>(0)
}

/// The audio thread's side: the synth and the last drive it applied. Touched only inside the render callback.
private final class HingeCreakRenderState: @unchecked Sendable {
    private var synth: HingeCreakSynth
    private var lastSequence: UInt8 = 0
    private let mailbox: HingeCreakMailbox

    init(sampleRate: Double, mailbox: HingeCreakMailbox) {
        synth = HingeCreakSynth(sampleRate: sampleRate)
        self.mailbox = mailbox
    }

    func render(isSilence: UnsafeMutablePointer<ObjCBool>, timestamp: UnsafePointer<AudioTimeStamp>,
                frames: AVAudioFrameCount, buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let word = mailbox.drive.load(ordering: .acquiring)
        let sequence = HingeCreakMotion.Drive.sequence(of: word)
        if sequence != lastSequence {
            lastSequence = sequence
            let drive = HingeCreakMotion.Drive(packed: word)
            synth.apply(drive)
            mailbox.applied.store(sequence, ordering: .releasing)
            if drive.kick {
                let stamp = timestamp.pointee
                mailbox.measuredCallbackHost.store(mach_absolute_time(), ordering: .relaxed)
                mailbox.measuredBufferHost.store(stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : 0, ordering: .relaxed)
                mailbox.measuredEventHost.store(mailbox.kickEventHost.load(ordering: .relaxed), ordering: .releasing)
            }
        }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        guard let first = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let count = Int(frames)
        let sounding = synth.render(into: first, count: count)
        for index in 1..<max(list.count, 1) {
            list[index].mData?.assumingMemoryBound(to: Float.self).update(from: first, count: count)
        }
        if !sounding { isSilence.pointee = true }
        return noErr
    }
}

/// A pre-warmed `AVAudioEngine` with one source node playing `HingeCreakSynth`, on the Ambient session with a
/// 5 ms buffer. Main thread only; the render block runs on the audio thread.
@MainActor
final class HingeCreakEngine {
    static let ioBuffer: TimeInterval = 0.005

    private var engine: AVAudioEngine?
    private let mailbox = HingeCreakMailbox()
    private var sequence: UInt8 = 0
    private var lastWasKick = false
    private var observers: [NSObjectProtocol] = []
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "delight")

    func start() {
        if let engine {
            if !engine.isRunning { try? engine.start() }
            return
        }
        // A fresh start: no drive left over from before the engine last stopped.
        sequence = 0
        lastWasKick = false
        mailbox.drive.store(0, ordering: .releasing)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient)
            try session.setPreferredIOBufferDuration(Self.ioBuffer)
        } catch {
            Self.log.error("Squeaky hinge: audio session: \(error.localizedDescription, privacy: .public)")
        }
        let engine = AVAudioEngine()
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: outputRate > 0 ? outputRate : 48_000, channels: 1)
        else { return }
        let state = HingeCreakRenderState(sampleRate: format.sampleRate, mailbox: mailbox)
        let source = AVAudioSourceNode(format: format) { isSilence, timestamp, frames, buffers in
            state.render(isSilence: isSilence, timestamp: timestamp, frames: frames, buffers: buffers)
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
            self.engine = engine
            observe(engine)
            Self.log.info("""
                Squeaky hinge ready: \(format.sampleRate, format: .fixed(precision: 0)) Hz, IO buffer \
                \(session.ioBufferDuration * 1000, format: .fixed(precision: 1)) ms, output latency \
                \(session.outputLatency * 1000, format: .fixed(precision: 1)) ms
                """)
        } catch {
            Self.log.error("Squeaky hinge: engine didn't start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        engine?.stop()
        engine = nil
    }

    func play(_ drive: HingeCreakMotion.Drive, eventHostTime: UInt64) {
        var drive = drive
        // A kick the audio thread hasn't picked up yet is carried by the next drive rather than lost to it.
        if lastWasKick, mailbox.applied.load(ordering: .acquiring) != sequence { drive.kick = true }
        if drive.kick && !lastWasKick { mailbox.kickEventHost.store(eventHostTime, ordering: .relaxed) }
        lastWasKick = drive.kick
        sequence &+= 1
        mailbox.drive.store(drive.packed(sequence: sequence), ordering: .releasing)
    }

    /// What the audio thread measured for the kick that the hinge update at `eventHost` started.
    func measuredLatency(forEvent eventHost: UInt64) -> HingeCreakLatency? {
        guard mailbox.measuredEventHost.load(ordering: .acquiring) == eventHost else { return nil }
        let session = AVAudioSession.sharedInstance()
        let buffer = mailbox.measuredBufferHost.load(ordering: .relaxed)
        return HingeCreakLatency(eventSeconds: HostClock.seconds(eventHost),
                                 callbackSeconds: HostClock.seconds(mailbox.measuredCallbackHost.load(ordering: .relaxed)),
                                 bufferStartSeconds: buffer == 0 ? 0 : HostClock.seconds(buffer),
                                 outputLatency: session.outputLatency, ioBuffer: session.ioBufferDuration)
    }

    /// A route change or an interruption stops the engine; start it again when it's over.
    private func observe(_ engine: AVAudioEngine) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let engine = self?.engine, !engine.isRunning { try? engine.start() } }
            },
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
                MainActor.assumeIsolated { if ended, let engine = self?.engine, !engine.isRunning { try? engine.start() } }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.engine != nil else { return }
                    self.stop()
                    self.start()
                }
            },
        ]
    }
}
#endif

#if DEBUG
/// Debug-only `-hingeSweep YES`: where no hinge can be moved (the simulator's fold is Device Hub's, which a session
/// can't reach), plays three opening-and-closing sweeps through the real path a second or two after launch, as a
/// hinge reporting at 60 Hz would (the device then counts as hinged, so Extras shows the switch), and prints the
/// latencies measured.
@MainActor
enum HingeCreakDebug {
    static func sweepIfAsked() async {
        guard UserDefaults.standard.bool(forKey: "hingeSweep") else { return }
        let creak = HingeCreak.shared
        creak.hingeChanged(angle: 0, at: HostClock.now)
        try? await Task.sleep(for: .seconds(2))
        for _ in 0..<3 {
            await sweep(from: 0, to: 180, seconds: 0.6)
            try? await Task.sleep(for: .seconds(1.2))
            await sweep(from: 180, to: 0, seconds: 0.45)
            try? await Task.sleep(for: .seconds(1.2))
        }
        try? await Task.sleep(for: .seconds(0.5))
        let audible = creak.latencies.map { $0.toAudible * 1000 }.sorted()
        let callback = creak.latencies.map { $0.toCallback * 1000 }.sorted()
        if let first = audible.first, let last = audible.last, let cbMax = callback.last {
            print(String(format: "HINGE-SWEEP %d kicks: audible %.1f–%.1f ms (median %.1f), to render callback ≤ %.1f ms, output latency %.1f ms, IO buffer %.1f ms",
                         audible.count, first, last, audible[audible.count / 2], cbMax,
                         (creak.latencies.last?.outputLatency ?? 0) * 1000, (creak.latencies.last?.ioBuffer ?? 0) * 1000))
        } else {
            print("HINGE-SWEEP no kicks measured")
        }
    }

    /// An eased sweep at 60 updates a second, each update stamped as it is sent.
    private static func sweep(from start: Double, to end: Double, seconds: Double) async {
        let steps = Int(seconds * 60)
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let degrees = start + (end - start) * (0.5 - 0.5 * cos(.pi * progress))
            HingeCreak.shared.hingeChanged(angle: degrees * .pi / 180, at: HostClock.now)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}
#endif
