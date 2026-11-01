import SwiftUI
import OSLog

/// "Synced 2 min ago" with its icon. Re-renders every 30 s so the relative time stays current while visible.
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
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Label {
                Text(state.summary(now: context.date))
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

    private func color(for state: SyncState) -> Color {
        switch state {
        case .synced: return .green
        case .syncing, .offline: return Theme.secondaryText
        case .notSignedIn, .restricted, .error, .localOnly: return .orange
        }
    }
}

/// One quiet line at the bottom of the sidebar, shown only when sync is not in its normal state.
struct SyncStatusFooter: View {
    var action: () -> Void
    private var monitor: CloudSyncMonitor { .shared }

    var body: some View {
        let state = monitor.state
        if state.showsInSidebar(hasSyncedBefore: monitor.lastSyncedAt != nil) {
            Button(action: action) {
                Label(state.summary(), systemImage: state.symbol)
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Theme.surface)
            .help("iCloud Sync settings")
        }
    }
}

extension SyncState {
    /// The sidebar stays silent when synced, and while a routine sync runs after an edit. A first
    /// download (nothing synced yet, e.g. after resetting the local cache) is worth a line.
    func showsInSidebar(hasSyncedBefore: Bool) -> Bool {
        switch self {
        case .synced: return false
        case .syncing: return !hasSyncedBefore
        default: return true
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
struct SyncBolt: View {
    var action: () -> Void
    static let size: CGFloat = 11
    /// How far right of its toolbar slot the bolt is drawn.
    static let nudge: CGFloat = 12
    /// A sync older than this reads as "hasn't synced in a while".
    static let staleAfter: TimeInterval = 24 * 60 * 60
    private var monitor: CloudSyncMonitor { .shared }
    @State private var flash = false
    @State private var lastPulse: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = monitor.state
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let look = Self.look(for: state, now: tick.date)
            Button(action: action) {
                Image(systemName: look.symbol)
                    .font(.system(size: Self.size, weight: .bold))
                    .foregroundStyle(look.color.opacity(flash ? 1 : look.opacity))
                    .symbolEffect(.pulse, options: .repeating, isActive: state == .syncing && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 14, height: 20)
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
    }

    /// What the bolt shows for a state. Pure, so tests can check it.
    struct Look: Equatable {
        var symbol: String
        var color: Color
        var opacity: Double
    }

    static func look(for state: SyncState, now: Date = Date()) -> Look {
        switch state {
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

    static func color(for state: SyncState) -> Color {
        switch state {
        case .synced: return HITColor.dueToday
        case .syncing, .offline: return Theme.secondaryText
        case .notSignedIn, .restricted, .error, .localOnly: return HITColor.dueTomorrow
        }
    }
}
