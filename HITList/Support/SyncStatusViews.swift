import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif

/// "iCloud: Signed in · Synced 2 min ago" with its icon: the sync health line (`SyncHealth`), word for word
/// what Settings → Account's status row says. Re-renders every 30 s so the relative time stays current while visible.
/// It reads the steadied state (`CloudSyncMonitor.state`), so it never strobes between "Syncing…" and "Synced"; it
/// still says "Syncing…" when the bolt shows work. When work it showed ends in a good sync, the icon turns into a
/// checkmark for a few seconds and the text reads "Synced just now", then it settles back (brief 78: once per visible
/// stretch of work, not on every export). Every change crossfades; plain fades under Reduce Motion.
struct SyncStatusLine: View {
    private var monitor: CloudSyncMonitor { .shared }
    @State private var confirming = false
    @State private var confirmTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = monitor.state
        let account = AccountState.current
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Label {
                Text(Self.text(account: account, sync: state, now: context.date))
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: confirming && state.isSynced ? "checkmark.circle.fill" : state.symbol)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .foregroundStyle(color(for: state))
        }
        .animation(BoltSteadyMotion.crossfadeAnimation, value: SyncSteadiness.kind(state))
        .animation(BoltSteadyMotion.crossfadeAnimation, value: confirming)
        .onChange(of: SyncSteadiness.kind(state)) { old, new in
            guard Self.confirms(from: old, to: new) else { return }
            SyncConfirmation.log.info("Sync confirmed in Settings (\(monitor.lastChangePhase?.rawValue ?? "?", privacy: .public))")
            confirmTask?.cancel()
            confirming = true
            confirmTask = Task {
                try? await Task.sleep(for: SyncConfirmation.checkmarkDuration)
                guard !Task.isCancelled else { return }
                confirming = false
            }
        }
        .onDisappear { confirmTask?.cancel() }
    }

    /// The checkmark plays when the marks turn green after showing work or trouble, never on an ordinary sync.
    static func confirms(from old: SyncSteadiness.Kind, to new: SyncSteadiness.Kind) -> Bool {
        new == .synced && old != .synced && old != .localOnly
    }

    /// The line's text: `SyncHealth.line`, shared with `AccountStatusRow.title`.
    static func text(account: AccountState, sync: SyncState, now: Date = .now) -> String {
        SyncHealth(account: account, sync: sync).line(now: now)
    }

    private func color(for state: SyncState) -> Color {
        switch state {
        case .synced: return .green
        case .syncing, .offline, .retrying: return Theme.secondaryText
        case .notSignedIn where !SyncBolt.everSignedIn(): return Theme.secondaryText
        case .notSignedIn, .restricted, .error, .localOnly: return .orange
        }
    }
}

/// Explains an empty list after an iCloud sign-out or account switch. Placed above ContentView by
/// HITListApp so no list view has to know about it.
struct AccountChangeBanner: View {
    private var monitor: CloudSyncMonitor { .shared }

    var body: some View {
        if let notice = monitor.accountNotice {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(Theme.accent)
                Text(Self.message(for: notice))
                    .font(HITType.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { monitor.dismissAccountNotice() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.secondaryText)
                    .help("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.elevated)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        }
    }

    static func message(for notice: AccountWatch.Notice) -> String {
        switch notice {
        case .signedOut:
            return "Signed out of iCloud. Your tasks are safe in iCloud and come back when you sign in."
        case .switched:
            return "Switched iCloud account. Tasks from the other account are safe in iCloud and come back when you sign back in to it."
        }
    }
}

/// Sync status as one small bolt in the toolbar's empty space, on every screen and platform. It says "status is
/// green" and then keeps still (brief 78): it draws `CloudSyncMonitor.state`, the raw state steadied over time
/// (`SyncSteadiness`), not every export and import. Its shape is the message: a filled bolt while all is well, a
/// hollow bolt breathing slowly when work is the news (a sync that keeps trying, the first after a long time,
/// "will keep trying"), a struck-through bolt once trouble has stayed (offline, signed out, restricted, an error,
/// local only) or when it has not synced in a while (`staleAfter`). Its colour is the theme's `bolt`, a pastel that
/// sits apart from the accent; struck-through states go grey, errors and sign-out red. Every change crossfades
/// (`BoltSteadyMotion`), plain fades under Reduce Motion. Tapping it opens Settings.
///
/// It plays once as a "you're good to go": on the first good sync after the app opens, after it comes back from
/// a minute or more away, or after sync was in trouble for a minute or more (`BoltStrikeGate`). Never for
/// ordinary syncs, never in the background; a short blink under Reduce Motion. What plays is the style chosen in
/// Settings → Extras → Sync bolt (`BoltStyle`): the slam (brief 68, `BoltSlamMotion`: a hop while it spins once like a
/// coin, edge-on for an instant (brief 73), then a slam with a buzz of sparks at its foot, 0.8 s; the default) or the strike (brief 54, `BoltStrikeMotion`: a quick
/// double flash with a twirl of a few degrees, 280 ms).
struct SyncBolt: View {
    var action: () -> Void
    /// The glyph's point size: 15% larger than the original 11 pt (George, brief 54), on every platform.
    static let size: CGFloat = 11 * 1.15
    /// Its tap frame, grown by the same 15% (was 14 × 20) so the glyph keeps the same margins.
    static let frame = CGSize(width: 16, height: 23)
    /// How far right of its toolbar slot the bolt is drawn.
    static let nudge: CGFloat = 12
    /// A sync older than this reads as "hasn't synced in a while".
    static let staleAfter: TimeInterval = 24 * 60 * 60
    private var monitor: CloudSyncMonitor { .shared }
    /// Counts the strikes and slams; the keyframe animators play on each change.
    @State private var player = BoltPlayer()
    @AppStorage(BoltStyle.key, store: AppGroup.defaults) private var style: BoltStyle = .fallback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The one gate every bolt on screen asks, so two windows strike together and "the app opened" is the
    /// session's, not each screen's.
    @MainActor static var strikeGate = BoltStrikeGate()

    /// The monitor's state; in the Debug strike demo, the filled bolt a real sync leaves behind.
    private var displayState: SyncState {
        #if DEBUG
        if BoltStrikeDemo.isRequested { return .synced(.now) }
        #endif
        return monitor.state
    }

    var body: some View {
        let state = displayState
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let look = Self.look(for: state, now: tick.date)
            Button(action: action) {
                BoltGlyph(look: look, breathes: Self.breathes(state), reduceMotion: reduceMotion)
                    .modifier(BoltMotions(player: player, color: look.color))
                    .frame(width: Self.frame.width, height: Self.frame.height)
                    .contentShape(Rectangle())
                    // Drawn a little to the right of its toolbar slot, so it sits nearer the two controls
                    // than the toolbar's own item spacing would put it (George, build 9).
                    .offset(x: Self.nudge)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.summary(now: tick.date))
            .accessibilityIdentifier("syncBolt")
            .help(state.summary(now: tick.date))
        }
        // Every list screen draws the bolt, so its first appearance is the launch's first list frame.
        .onAppear { LaunchTiming.firstFrame() }
        .onChange(of: monitor.lastChangeAt) { old, new in strikeIfDue(from: old, to: new) }
        // What arms the next strike: coming back to the front after a while, and sync trouble that lasted.
        .onChange(of: scenePhase) { _, _ in Self.strikeGate.appActive(isActive, now: Date()) }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            Self.strikeGate.appActive(false, now: Date())
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Self.strikeGate.appActive(isActive, now: Date())
        }
        #endif
        // The gate counts trouble from the raw state, exactly as before the marks were steadied.
        .onChange(of: monitor.rawState.isHealthyForStrike, initial: true) { _, healthy in
            Self.strikeGate.syncState(healthy: healthy, now: Date())
        }
        #if DEBUG
        .onAppear { BoltStrikeDemo.shared.startIfRequested() }
        .onAppear { SyncReplayPlayer.shared.startIfRequested() }
        .onChange(of: BoltStrikeDemo.shared.change) { old, new in strikeIfDue(from: old, to: new) }
        #endif
    }

    /// The working look breathes: work that is the news, and "will keep trying".
    static func breathes(_ state: SyncState) -> Bool {
        switch state {
        case .syncing, .retrying: true
        default: false
        }
    }

    /// In front and visible: on the Mac also the active app, so a sync that lands while George works in
    /// another app doesn't flash at the edge of his eye.
    private var isActive: Bool {
        #if os(macOS)
        scenePhase == .active && NSApplication.shared.isActive
        #else
        scenePhase == .active
        #endif
    }

    private func strikeIfDue(from old: Date?, to new: Date?) {
        let kind = Self.strikeGate.advance(from: old, to: new, now: Date(), isActive: isActive, reduceMotion: reduceMotion)
        guard let motion = style.motion(for: kind) else { return }
        // The strike or slam plays as the bolt turns green, whatever the marks were holding.
        monitor.goodToGo()
        player.play(motion)
        SyncConfirmation.log.info("Bolt strike: \(motion.rawValue, privacy: .public) (\(monitor.lastChangePhase?.rawValue ?? "demo", privacy: .public))")
    }

    /// What the bolt shows for a state. Pure, so tests can check it.
    struct Look: Hashable {
        var symbol: String
        var color: Color
        var opacity: Double
    }

    /// Whether this device has ever seen an iCloud account (`AccountWatch`). A tester who never signed in
    /// to iCloud is not in trouble: their tasks stay on the device, so the bolt and the dot stay grey
    /// instead of the red and orange that mean "sync needs attention".
    static func everSignedIn(_ defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.bool(forKey: AccountWatch.everSignedInKey)
    }

    static func look(for state: SyncState, now: Date = Date(), everSignedIn: Bool = SyncBolt.everSignedIn()) -> Look {
        switch state {
        case .notSignedIn where !everSignedIn:
            return Look(symbol: "bolt.slash.fill", color: Theme.secondaryText, opacity: 0.9)
        case .synced(let at) where now.timeIntervalSince(at) > staleAfter:
            return Look(symbol: "bolt.slash.fill", color: Theme.secondaryText, opacity: 0.9)
        case .synced:
            return Look(symbol: "bolt.fill", color: Theme.bolt, opacity: 0.85)
        case .syncing, .retrying:
            return Look(symbol: "bolt", color: Theme.bolt, opacity: 0.85)
        case .offline, .localOnly:
            return Look(symbol: "bolt.slash.fill", color: Theme.secondaryText, opacity: 0.9)
        case .notSignedIn, .restricted, .error:
            return Look(symbol: "bolt.slash.fill", color: HITColor.dueOverdue, opacity: 0.85)
        }
    }
}

/// The bolt's inertia in the drawing (brief 78, rule 4): every change of look crossfades, never a swap on one frame,
/// and the working look breathes slowly rather than pulsing. Reduce Motion: the same timing with plain fades.
enum BoltSteadyMotion {
    /// Seconds a change of look takes.
    static let crossfade: TimeInterval = 0.35
    /// One slow breath in and out of the working look, and how far its opacity falls at the bottom of it.
    static let breathPeriod: TimeInterval = 2.8
    static let breathLow: Double = 0.45
    /// How much smaller the incoming glyph starts (none under Reduce Motion).
    static let settleScale: CGFloat = 0.88

    static var crossfadeAnimation: Animation { .easeInOut(duration: crossfade) }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: settleScale))
    }
}

/// The bolt's glyph for one look. A new look crossfades over the old one (`BoltSteadyMotion`); the working look
/// breathes. The toolbar bolt wears its strike and slam on the outside, so a change of look never restarts them.
struct BoltGlyph: View {
    var look: SyncBolt.Look
    var breathes: Bool
    var reduceMotion: Bool

    private struct Identity: Hashable {
        var look: SyncBolt.Look
        var breathes: Bool
    }

    var body: some View {
        let identity = Identity(look: look, breathes: breathes)
        ZStack {
            Image(systemName: look.symbol)
                .font(.system(size: SyncBolt.size, weight: .bold))
                .foregroundStyle(look.color.opacity(look.opacity))
                .modifier(BoltBreath(active: breathes))
                .id(identity)
                .transition(BoltSteadyMotion.transition(reduceMotion: reduceMotion))
        }
        .animation(BoltSteadyMotion.crossfadeAnimation, value: identity)
    }
}

/// The working look's slow breath of opacity, from full to `BoltSteadyMotion.breathLow` and back.
struct BoltBreath: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([1.0, BoltSteadyMotion.breathLow]) { glyph, opacity in
                glyph.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: BoltSteadyMotion.breathPeriod / 2)
            }
        } else {
            content
        }
    }
}

/// The smallest possible sync confirmation: a 6 pt dot for the corner of a toolbar button. Green while all is well,
/// grey while work is the news or offline, orange once sync needs attention. It is a view of `CloudSyncMonitor.state`,
/// steadied like the bolt (`SyncSteadiness`); place it with `.overlay(alignment: .topTrailing)`. Its colour crossfades.
/// It pulses once, scale 1 → 1.6 → 1 with `HITMotion.spring`, only when the bolt plays its "you're good to go"
/// (`BoltStrikeGate`: after launch, after a minute away, after a minute of trouble), never on an ordinary import or
/// export, and never under Reduce Motion (brief 78). The scale is a render effect, so the dot's layout stays 6 pt.
struct SyncIndicatorDot: View {
    static let size: CGFloat = 6
    static let pulseScale: CGFloat = 1.6
    private var monitor: CloudSyncMonitor { .shared }
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let state = monitor.state
        Circle()
            .fill(Self.color(for: state))
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(scale)
            .animation(BoltSteadyMotion.crossfadeAnimation, value: Self.color(for: state))
            .accessibilityLabel(state.summary())
            .onChange(of: monitor.lastChangeAt) { old, new in
                guard Self.pulses(for: SyncBolt.strikeGate.advance(from: old, to: new, now: Date(), isActive: isActive,
                                                                     reduceMotion: reduceMotion)) else { return }
                SyncConfirmation.log.info("Sync dot pulse (\(monitor.lastChangePhase?.rawValue ?? "?", privacy: .public))")
                pulse()
            }
    }

    /// Pulses with the gate's strike only: no pulse for an ordinary sync, none for the Reduce Motion blink.
    static func pulses(for strike: BoltStrikeGate.Strike) -> Bool { strike == .strike }

    private var isActive: Bool {
        #if os(macOS)
        scenePhase == .active && NSApplication.shared.isActive
        #else
        scenePhase == .active
        #endif
    }

    private func pulse() {
        withAnimation(HITMotion.spring) { scale = Self.pulseScale }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(HITMotion.spring) { scale = 1 }
        }
    }

    static func color(for state: SyncState, everSignedIn: Bool = SyncBolt.everSignedIn()) -> Color {
        switch state {
        case .synced: return HITColor.dueToday
        case .syncing, .offline, .retrying: return Theme.secondaryText
        case .notSignedIn where !everSignedIn: return Theme.secondaryText
        case .notSignedIn, .restricted, .error, .localOnly: return HITColor.dueTomorrow
        }
    }
}

/// The bolt's lightning strike (brief 54): a quick double flash, a twirl of a few degrees and a hair of
/// scale, back at rest in 280 ms; under Reduce Motion a 140 ms opacity blink instead. Keyframes, so it
/// plays on the render timeline at the display's own rate with nothing allocated per frame.
enum BoltStrikeMotion {
    /// One frame of the strike; `Frame()` is the bolt at rest.
    struct Frame: Equatable {
        var scale: CGFloat = 1
        /// Degrees.
        var twirl: Double = 0
        /// 0 at rest, 1 at the brightest of the flash.
        var glow: Double = 0
        var opacity: Double = 1
    }

    static let duration: TimeInterval = 0.28
    static let peakScale: CGFloat = 1.1
    static let twirl: Double = 7
    static let blinkDuration: TimeInterval = 0.14
    /// How far the flash lifts the bolt's colour toward white (`brightness`).
    static let flashBrightness: Double = 0.45

    /// Every track is always there (a keyframes builder can't choose between tracks); a track the
    /// chosen motion doesn't use holds its resting value.
    @KeyframesBuilder<Frame>
    static func keyframes(for strike: BoltStrikeGate.Strike) -> some Keyframes<Frame> {
        let blink = strike == .blink
        // Lightning flickers: bright, a dip, a second smaller flash, then it fades.
        KeyframeTrack(\.glow) {
            if blink {
                LinearKeyframe(0, duration: blinkDuration)
            } else {
                LinearKeyframe(1, duration: 0.035, timingCurve: .easeOut)
                LinearKeyframe(0.3, duration: 0.05, timingCurve: .easeIn)
                LinearKeyframe(0.85, duration: 0.03, timingCurve: .easeOut)
                LinearKeyframe(0, duration: duration - 0.115, timingCurve: .easeOut)
            }
        }
        KeyframeTrack(\.twirl) {
            if blink {
                LinearKeyframe(0, duration: blinkDuration)
            } else {
                LinearKeyframe(-twirl, duration: 0.06, timingCurve: .easeOut)
                LinearKeyframe(twirl * 0.35, duration: 0.1, timingCurve: .easeInOut)
                LinearKeyframe(0, duration: duration - 0.16, timingCurve: .easeOut)
            }
        }
        KeyframeTrack(\.scale) {
            if blink {
                LinearKeyframe(1, duration: blinkDuration)
            } else {
                LinearKeyframe(peakScale, duration: 0.06, timingCurve: .easeOut)
                LinearKeyframe(1, duration: duration - 0.06, timingCurve: .easeOut)
            }
        }
        KeyframeTrack(\.opacity) {
            if blink {
                LinearKeyframe(0.45, duration: 0.05, timingCurve: .easeIn)
                LinearKeyframe(1, duration: blinkDuration - 0.05, timingCurve: .easeOut)
            } else {
                LinearKeyframe(1, duration: duration)
            }
        }
    }

    /// The whole strike as a timeline, for tests.
    static func timeline(for strike: BoltStrikeGate.Strike) -> KeyframeTimeline<Frame> {
        KeyframeTimeline(initialValue: Frame()) { keyframes(for: strike) }
    }

    /// Plays one frame on the glyph: the flash, a hair of scale, the twirl, the blink's fade. At `Frame()` it draws
    /// the glyph exactly as it rests.
    struct Effect: ViewModifier {
        var frame: Frame
        var color: Color

        func body(content: Content) -> some View {
            content
                .brightness(frame.glow * flashBrightness)
                .shadow(color: color.opacity(frame.glow * 0.7), radius: frame.glow > 0.001 ? 3 : 0)
                .scaleEffect(frame.scale)
                .rotationEffect(.degrees(frame.twirl))
                .opacity(frame.opacity)
        }
    }
}

/// How the bolt says "you're good to go" (Settings → Extras → Sync bolt, brief 68): the slam (`BoltSlamMotion`, the
/// default; George asked for it on 0.8.1) or brief 54's strike (`BoltStrikeMotion`). Kept in `AppGroup.defaults`.
/// It changes what plays, never when: `BoltStrikeGate` decides that, and Reduce Motion gets the blink for both.
enum BoltStyle: String, CaseIterable, Identifiable {
    case strike, slam

    static let key = "delight.boltStyle"
    static let fallback: BoltStyle = .slam

    var id: Self { self }

    var title: String {
        switch self {
        case .strike: "Strike"
        case .slam: "Slam"
        }
    }

    static func selected(in defaults: UserDefaults = AppGroup.defaults) -> BoltStyle {
        defaults.string(forKey: key).flatMap(BoltStyle.init(rawValue:)) ?? fallback
    }

    /// What the bolt plays for the gate's answer: this style for a strike, the blink for a blink, nothing for none.
    func motion(for strike: BoltStrikeGate.Strike) -> BoltMotion? {
        switch strike {
        case .none: nil
        case .blink: .blink
        case .strike: self == .slam ? .slam : .strike
        }
    }
}

/// One play of the bolt: brief 54's strike or its Reduce Motion blink, or brief 68's slam.
enum BoltMotion: String {
    case strike, blink, slam
}

/// Counts the bolt's plays: each new `strikes` starts the strike's keyframes (as `strikeKind`), each new `slams` the
/// slam's (`BoltMotions`).
struct BoltPlayer: Equatable {
    var strikes = 0
    var strikeKind: BoltStrikeGate.Strike = .strike
    var slams = 0

    mutating func play(_ motion: BoltMotion) {
        switch motion {
        case .strike, .blink:
            let kind: BoltStrikeGate.Strike = motion == .blink ? .blink : .strike
            if strikeKind != kind { strikeKind = kind }
            strikes &+= 1
        case .slam:
            slams &+= 1
        }
    }
}

/// The bolt's motions on its glyph, both resting at identity: the strike's keyframes on each new `player.strikes`, the
/// slam's on each new `player.slams`. The toolbar bolt and the Extras preview both wear it, so they play the same frames.
struct BoltMotions: ViewModifier {
    var player: BoltPlayer
    var color: Color

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: BoltStrikeMotion.Frame(), trigger: player.strikes) { glyph, fx in
                glyph.modifier(BoltStrikeMotion.Effect(frame: fx, color: color))
            } keyframes: { _ in
                BoltStrikeMotion.keyframes(for: player.strikeKind)
            }
            .keyframeAnimator(initialValue: BoltSlamMotion.Frame(), trigger: player.slams) { glyph, fx in
                glyph.modifier(BoltSlamMotion.Effect(frame: fx, color: color))
            } keyframes: { _ in
                BoltSlamMotion.keyframes()
            }
    }
}

/// The bolt as the toolbar draws it after a good sync, at the toolbar's size: Settings → Extras → Sync bolt's icon,
/// which plays a style when asked.
struct BoltPreviewGlyph: View {
    var player: BoltPlayer

    var body: some View {
        let look = SyncBolt.look(for: .synced(.now), everSignedIn: true)
        Image(systemName: look.symbol)
            .font(.system(size: SyncBolt.size, weight: .bold))
            .foregroundStyle(look.color.opacity(look.opacity))
            .modifier(BoltMotions(player: player, color: look.color))
    }
}

#if DEBUG
/// A Debug-only stand-in for real syncs, so the strike can be recorded on a simulator with sync off:
/// launch with `-boltStrikeDemo YES` and, from the first bolt's appearance, `change` advances on a schedule
/// and the gate is re-armed before each, so every fake sync strikes (the real rules strike far less often;
/// see `BoltStrikeGate`). Every bolt watches it.
@MainActor
@Observable
final class BoltStrikeDemo {
    static let shared = BoltStrikeDemo()
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "boltStrikeDemo") }

    /// Seconds after the first bolt appears for each fake sync.
    static let schedule: [TimeInterval] = [0, 1.5, 4, 16, 17, 22, 24] + (0..<30).map { 28 + Double($0) * 4 }

    private(set) var change: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Starts the schedule once per process; later calls do nothing.
    func startIfRequested() {
        guard Self.isRequested, task == nil else { return }
        let start = Date()
        task = Task { @MainActor in
            for offset in Self.schedule {
                let wait = start.addingTimeInterval(offset).timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                SyncConfirmation.log.info("Bolt strike demo: fake sync at +\(offset, format: .fixed(precision: 1), privacy: .public) s")
                SyncBolt.strikeGate.armForDemo()  // each fake sync plays, so the motion can be recorded
                change = Date()
            }
        }
    }
}
#endif
