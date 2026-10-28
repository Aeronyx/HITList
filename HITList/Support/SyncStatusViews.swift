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
                    .font(.caption)
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
