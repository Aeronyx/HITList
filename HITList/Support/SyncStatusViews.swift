import SwiftUI

/// "Synced 2 min ago" with its icon. Re-renders every 30 s so the relative time stays current while visible.
struct SyncStatusLine: View {
    private var monitor: CloudSyncMonitor { .shared }

    var body: some View {
        let state = monitor.state
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Label(state.summary(now: context.date), systemImage: state.symbol)
                .foregroundStyle(color(for: state))
        }
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

/// The smallest possible sync confirmation: a 6 pt dot for the corner of a toolbar button. Green once
/// everything has synced, grey while syncing or offline, orange when sync needs attention. It is a view
/// of `CloudSyncMonitor.state` only; place it with `.overlay(alignment: .topTrailing)`.
struct SyncIndicatorDot: View {
    static let size: CGFloat = 6
    private var monitor: CloudSyncMonitor { .shared }

    var body: some View {
        let state = monitor.state
        Circle()
            .fill(Self.color(for: state))
            .frame(width: Self.size, height: Self.size)
            .accessibilityLabel(state.summary())
    }

    static func color(for state: SyncState) -> Color {
        switch state {
        case .synced: return HITColor.dueToday
        case .syncing, .offline: return Theme.secondaryText
        case .notSignedIn, .restricted, .error, .localOnly: return HITColor.dueTomorrow
        }
    }
}
