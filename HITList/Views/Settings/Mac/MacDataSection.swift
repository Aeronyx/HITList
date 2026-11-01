import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// What the Data section counts: tasks (open, completed, overdue), Groups, labels, filters. Pure over a
/// `ModelContext`, so tests count an in-memory container.
struct DataStats: Equatable {
    var openTasks = 0
    var completedTasks = 0
    var overdueTasks = 0
    var groups = 0
    var labels = 0
    var filters = 0

    /// Counts with `fetchCount` where SwiftData can; overdue needs `DueFormatter.isOverdue` (all-day tasks
    /// are overdue from the next day, timed ones from their time), so it reads only the open dated tasks.
    static func count(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) throws -> DataStats {
        var stats = DataStats()
        stats.openTasks = try context.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted }))
        stats.completedTasks = try context.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isCompleted }))
        let dated = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted && $0.dueDate != nil })
        stats.overdueTasks = try context.fetch(dated).filter { task in
            guard let due = task.dueDate else { return false }
            return DueFormatter.isOverdue(due, hasTime: task.hasDueTime, isCompleted: false, now: now, calendar: calendar)
        }.count
        stats.groups = try context.fetchCount(FetchDescriptor<Project>())
        stats.labels = try context.fetchCount(FetchDescriptor<TaskLabel>())
        stats.filters = try context.fetchCount(FetchDescriptor<SavedFilter>())
        return stats
    }

    /// The store's size on disk: the SQLite file and its -wal and -shm companions. Nil when there is no
    /// regular file there (an in-memory store's URL is /dev/null) or it can't be read.
    static func storeSize(at url: URL?, fileManager: FileManager = .default) -> Int64? {
        guard let url, let type = (try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType,
              type == .typeRegular else { return nil }
        let paths = [url.path, url.path + "-wal", url.path + "-shm"]
        return paths.reduce(Int64(0)) { total, path in
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    /// "1.2 MB", "84 KB".
    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

}

/// Settings → Data on the Mac: the counts and the store, then Export & Import and Backups (moved here
/// from their own sections).
struct MacDataSection: View {
    var body: some View {
        DataLibraryGroup()
        ExportImportGroup()
        BackupsGroup()
    }
}

/// "Library": the counts as tiles, the store's size, and Show store in Finder. Recounted on appear,
/// after every save in this app (`ModelContext.didSave`) and after each CloudKit import.
struct DataLibraryGroup: View {
    @Environment(\.modelContext) private var context
    @State private var stats: DataStats?
    @State private var storeBytes: Int64?

    private var storeURL: URL? { context.container.configurations.first?.url }

    var body: some View {
        HITGroup("Library", footer: Self.footer) {
            DataCountTiles(stats: stats ?? DataStats())
                .padding(.horizontal, HITSpacing.l)
                .padding(.vertical, HITSpacing.m)
                .redacted(reason: stats == nil ? .placeholder : [])
            HITMenuRow("Store size", systemImage: "internaldrive",
                       value: storeBytes.map(DataStats.sizeText) ?? "In memory")
                .accessibilityIdentifier("settings-store-size")
            #if os(macOS)
            HITMenuRow("Show store in Finder", systemImage: "folder", accessory: .none) {
                if let storeURL { NSWorkspace.shared.activateFileViewerSelecting([storeURL]) }
            }
            .disabled(storeBytes == nil)
            .accessibilityIdentifier("settings-show-store")
            #endif
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitImportSucceeded)) { _ in refresh() }
    }

    static let footer = "Everything counted here syncs through iCloud; the store is this Mac's copy of it."

    private func refresh() {
        stats = try? DataStats.count(in: context)
        storeBytes = DataStats.storeSize(at: storeURL)
    }
}

/// The six counts as small tiles in a grid that wraps at narrow widths: big number, caption under it.
struct DataCountTiles: View {
    let stats: DataStats

    private var tiles: [(label: String, value: Int, tint: Color?)] {
        [("Open tasks", stats.openTasks, nil),
         ("Overdue", stats.overdueTasks, stats.overdueTasks > 0 ? HITColor.dueOverdue : nil),
         ("Completed", stats.completedTasks, nil),
         ("Groups", stats.groups, nil),
         ("Labels", stats.labels, nil),
         ("Filters", stats.filters, nil)]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: HITSpacing.s)], alignment: .leading,
                  spacing: HITSpacing.s) {
            ForEach(tiles, id: \.label) { tile in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tile.value)")
                        .font(HITType.title2Bold.monospacedDigit())
                        .foregroundStyle(tile.tint ?? HITColor.text)
                        .contentTransition(.numericText())
                    Text(tile.label)
                        .font(HITType.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HITSpacing.m)
                .padding(.vertical, HITSpacing.s + 2)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings-count-\(tile.label)")
            }
        }
    }
}
