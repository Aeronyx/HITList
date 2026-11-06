import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif

/// "iCloud: Signed in · Synced 2 min ago" with its icon: the sync health line (`SyncHealth`), word for word
/// what Settings → Account's status row says. Re-renders every 30 s so the relative time stays current while visible.
/// When a sync finishes while it is on screen, the icon turns into a checkmark for a few seconds
/// (`contentTransition(.symbolEffect(.replace))`; a plain swap under Reduce Motion), the text reads
/// "Synced just now", and then it settles back to the usual icon.
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
            } icon: {
                Image(systemName: confirming && state.isSynced ? "checkmark.circle.fill" : state.symbol)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .foregroundStyle(color(for: state))
        }
        .onChange(of: monitor.lastChangeAt) { old, new in
            guard SyncConfirmation.didAdvance(from: old, to: new) else { return }
            SyncConfirmation.log.info("Sync confirmed in Settings (\(monitor.lastChangePhase?.rawValue ?? "?", privacy: .public))")
            confirmTask?.cancel()
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirming = true }
            confirmTask = Task {
                try? await Task.sleep(for: SyncConfirmation.checkmarkDuration)
                guard !Task.isCancelled else { return }
                withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirming = false }
            }
        }
        .onDisappear { confirmTask?.cancel() }
    }

    /// The line's text: `SyncHealth.line`, shared with `AccountStatusRow.title`.
    static func text(account: AccountState, sync: SyncState, now: Date = .now) -> String {
        SyncHealth(account: account, sync: sync).line(now: now)
    }

    private func color(for state: SyncState) -> Color {
        switch state {
        case .synced: return .green
        case .syncing, .offline: return Theme.secondaryText
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

/// Sync status as one small bolt in the toolbar's empty space, on every screen and platform. Its shape
/// is the message: a filled bolt when everything has synced recently, a hollow bolt breathing while a
/// sync is in flight, a struck-through bolt when it cannot sync (offline, signed out, restricted, an
/// error, local only) or has not synced in a while (`staleAfter`). Its colour is the theme's `bolt`, a
/// pastel that sits apart from the accent; struck-through states go grey, errors and sign-out red. It
/// flicks brighter once when a change lands, and tapping it opens Settings.
///
/// When a sync lands it also plays one lightning strike (brief 54, `BoltStrikeMotion`): a quick double
/// flash with a twirl of a few degrees, gone in 280 ms. `BoltStrikeGate` keeps it rare: never during the
/// launch's import storm, once per burst, at least 5 s apart, never in the background, and a short blink
/// instead under Reduce Motion.
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
    @State private var flash = false
    @State private var lastPulse: Date?
    /// Bumped once per strike; the keyframe animator plays on each change.
    @State private var strikes = 0
    @State private var strikeKind: BoltStrikeGate.Strike = .strike
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The one gate every bolt on screen asks, so two windows strike together and the launch storm is
    /// the session's, not each screen's.
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
                Image(systemName: look.symbol)
                    .font(.system(size: Self.size, weight: .bold))
                    .foregroundStyle(look.color.opacity(flash ? 1 : look.opacity))
                    .symbolEffect(.pulse, options: .repeating, isActive: state == .syncing && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .keyframeAnimator(initialValue: BoltStrikeMotion.Frame(), trigger: strikes) { glyph, fx in
                        glyph
                            .brightness(fx.glow * BoltStrikeMotion.flashBrightness)
                            .shadow(color: look.color.opacity(fx.glow * 0.7), radius: fx.glow > 0.001 ? 3 : 0)
                            .scaleEffect(fx.scale)
                            .rotationEffect(.degrees(fx.twirl))
                            .opacity(fx.opacity)
                    } keyframes: { _ in
                        BoltStrikeMotion.keyframes(for: strikeKind)
                    }
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
        .onChange(of: monitor.lastChangeAt) { old, new in
            let now = Date()
            guard SyncConfirmation.shouldPulse(from: old, to: new, lastPulse: lastPulse, now: now,
                                               reduceMotion: reduceMotion) else { return }
            lastPulse = now
            withAnimation(HITMotion.quick) { flash = true }
            Task {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(HITMotion.standard) { flash = false }
            }
        }
        .onChange(of: monitor.lastChangeAt) { old, new in strikeIfDue(from: old, to: new) }
        #if DEBUG
        .onAppear { BoltStrikeDemo.shared.startIfRequested() }
        .onChange(of: BoltStrikeDemo.shared.change) { old, new in strikeIfDue(from: old, to: new) }
        #endif
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
        guard kind != .none else { return }
        if strikeKind != kind { strikeKind = kind }
        strikes &+= 1
        SyncConfirmation.log.info("Bolt strike: \(kind == .blink ? "blink" : "strike", privacy: .public) (\(monitor.lastChangePhase?.rawValue ?? "demo", privacy: .public))")
    }

    /// What the bolt shows for a state. Pure, so tests can check it.
    struct Look: Equatable {
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
        case .syncing:
            return Look(symbol: "bolt", color: Theme.bolt, opacity: 0.85)
        case .offline, .localOnly:
            return Look(symbol: "bolt.slash.fill", color: Theme.secondaryText, opacity: 0.9)
        case .notSignedIn, .restricted, .error:
            return Look(symbol: "bolt.slash.fill", color: HITColor.dueOverdue, opacity: 0.85)
        }
    }
}

/// The smallest possible sync confirmation: a 6 pt dot for the corner of a toolbar button. Green once
/// everything has synced, grey while syncing or offline, orange when sync needs attention. It is a view
/// of `CloudSyncMonitor.state` only; place it with `.overlay(alignment: .topTrailing)`.
/// Each time a CloudKit import or export finishes (`CloudSyncMonitor.lastChangeAt` advances) it pulses
/// once, scale 1 → 1.6 → 1 with `HITMotion.spring`; bursts merge, and Reduce Motion turns it off
/// (`SyncConfirmation`). The scale is a render effect, so the dot's layout stays 6 pt.
struct SyncIndicatorDot: View {
    static let size: CGFloat = 6
    static let pulseScale: CGFloat = 1.6
    private var monitor: CloudSyncMonitor { .shared }
    @State private var scale: CGFloat = 1
    @State private var lastPulse: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = monitor.state
        Circle()
            .fill(Self.color(for: state))
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(scale)
            .accessibilityLabel(state.summary())
            .onChange(of: monitor.lastChangeAt) { old, new in
                let now = Date()
                guard SyncConfirmation.shouldPulse(from: old, to: new, lastPulse: lastPulse, now: now,
                                                   reduceMotion: reduceMotion) else { return }
                lastPulse = now
                SyncConfirmation.log.info("Sync dot pulse (\(monitor.lastChangePhase?.rawValue ?? "?", privacy: .public))")
                pulse()
            }
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
        case .syncing, .offline: return Theme.secondaryText
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
}

#if DEBUG
/// A Debug-only stand-in for real syncs, so the strike can be recorded on a simulator with sync off:
/// launch with `-boltStrikeDemo YES` and, from the first bolt's appearance, `change` advances the way
/// `CloudSyncMonitor.lastChangeAt` does: a launch storm (nothing plays), a burst (one strike), a sync
/// inside the cooldown (nothing), then a sync every 4 s (a strike each). Every bolt watches it.
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
                change = Date()
            }
        }
    }
}
#endif
