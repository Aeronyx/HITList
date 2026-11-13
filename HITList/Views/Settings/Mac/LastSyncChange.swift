import SwiftUI

/// When changes last came from iCloud and last went to it: the mirror's latest import and export
/// (`CloudSyncMonitor`'s remembered times, kept across launches, so they are there before the first sync of a
/// session).
///
/// Until 0.9.9 the row named only the newer of the two ("Import from iCloud · just now"). The mirror imports and then
/// exports every time the app comes to the front, so the row flipped from one to the other on each click into the
/// window (George, 2026-11-13: "constantly flickering back and forth"). Both stand side by side now, and the row
/// changes only as they age.
enum LastSyncChange {
    /// "Received 3 min ago · Sent just now"; one of them alone when the other never happened; "None yet".
    static func text(lastImport: Date?, lastExport: Date?, now: Date) -> String {
        let parts = [
            lastImport.map { "Received \(SyncState.relative($0, now: now))" },
            lastExport.map { "Sent \(SyncState.relative($0, now: now))" },
        ].compactMap { $0 }
        return parts.isEmpty ? "None yet" : parts.joined(separator: " · ")
    }
}

/// iCloud → "Last change": when changes were last received and sent, ticking every 30 seconds.
struct LastSyncChangeRow: View {
    private var monitor: CloudSyncMonitor { .shared }

    var body: some View {
        let lastImport = monitor.lastImportAt, lastExport = monitor.lastExportAt
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            HITMenuRow("Last change", systemImage: "arrow.up.arrow.down",
                       value: LastSyncChange.text(lastImport: lastImport, lastExport: lastExport, now: tick.date))
        }
        .accessibilityIdentifier("settings-last-change")
    }
}
