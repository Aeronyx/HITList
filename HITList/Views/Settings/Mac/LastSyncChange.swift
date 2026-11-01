import SwiftUI

/// The newest change that went through iCloud, and which way: an import brought changes in, an export
/// sent this device's changes out. Read from `CloudSyncMonitor`'s remembered import and export times
/// (kept across launches), so it is there before the first sync of the session.
struct LastSyncChange: Equatable {
    enum Phase: Equatable {
        case imported, exported

        /// "Import from iCloud", "Export to iCloud".
        var title: String {
            switch self {
            case .imported: "Import from iCloud"
            case .exported: "Export to iCloud"
            }
        }

        var systemImage: String {
            switch self {
            case .imported: "icloud.and.arrow.down"
            case .exported: "icloud.and.arrow.up"
            }
        }
    }

    let date: Date
    let phase: Phase

    /// The later of the last import and the last export; nil if neither has happened. When both carry
    /// the same instant, this session's own record of which came last (`sessionPhase`) decides, else export.
    static func latest(lastImport: Date?, lastExport: Date?, sessionPhase: CloudSyncMonitor.Phase? = nil) -> LastSyncChange? {
        switch (lastImport, lastExport) {
        case (nil, nil): return nil
        case let (i?, nil): return LastSyncChange(date: i, phase: .imported)
        case let (nil, e?): return LastSyncChange(date: e, phase: .exported)
        case let (i?, e?):
            if i > e { return LastSyncChange(date: i, phase: .imported) }
            if e > i { return LastSyncChange(date: e, phase: .exported) }
            return LastSyncChange(date: i, phase: sessionPhase == .importing ? .imported : .exported)
        }
    }

    /// "Import from iCloud · 3 min ago".
    func text(now: Date) -> String { "\(phase.title) · \(SyncState.relative(date, now: now))" }
}

/// iCloud → "Last change": the newest import or export and how long ago, ticking every 30 seconds.
struct LastSyncChangeRow: View {
    private var monitor: CloudSyncMonitor { .shared }

    var body: some View {
        let change = LastSyncChange.latest(lastImport: monitor.lastImportAt, lastExport: monitor.lastExportAt,
                                           sessionPhase: monitor.lastChangePhase)
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            HITMenuRow("Last change", systemImage: change?.phase.systemImage ?? "clock.arrow.circlepath",
                       value: change?.text(now: tick.date) ?? "None yet")
        }
        .accessibilityIdentifier("settings-last-change")
    }
}
