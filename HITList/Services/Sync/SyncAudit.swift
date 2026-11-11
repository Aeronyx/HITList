import Foundation
import SwiftData
import OSLog

/// Brief 95, Part 3: "Check iCloud…" as an audit, so the next disagreement names itself. It reads the private
/// database's Core Data zone with CloudKit directly, independently of the mirror (`ICloudZoneReader`, keeping only each
/// record's kind, `CD_id` and change stamps), reads this device's store (`StoreInventory`), and compares them record by
/// record for every kind the store syncs (`SyncComparison`). It answers in words, on the device only ("This device and
/// iCloud agree: 412 tasks, 9 Groups, …", or "2 tasks on this device are not in iCloud: Shave, Call the bank"); the
/// sync log gets counts, short hashes and times, never a title.
///
/// **It repairs nothing by itself.** A task here and not in iCloud was either never sent, or deleted elsewhere and the
/// deletion never arrived; only the person knows which. `SyncRepair` offers both after a backup: "Send to iCloud" and
/// "Remove from this device". For what is in iCloud and not here, it says so, and points at "Reset local cache…" only
/// once nothing here is missing from iCloud (the reset would lose it).
///
/// Nothing is written to iCloud, no record type is added, the schema is untouched.
enum SyncAudit {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    struct Report: Equatable {
        var comparison: SyncComparison.Result
        /// The names of the records that differ, from this device or from iCloud: shown, never logged.
        var names: [UUID: String] = [:]
        /// Records in iCloud the comparison leaves out: many-to-many links, kinds this build doesn't know.
        var otherRecords = 0
        var recordsRead = 0
        var duration: TimeInterval = 0
        /// The zone doesn't exist in iCloud (nothing ever synced for this account, or iCloud data deleted in Settings).
        var zoneMissing = false
        var finishedAt = Date()

        var agree: Bool { comparison.agree }

        func items(_ kind: SyncComparison.Difference.Kind) -> [SyncComparison.Difference] { comparison.differences(kind) }

        /// Whether "Reset local cache…" is safe to point at: nothing here would be lost.
        var resetIsSafe: Bool { items(.onlyHere).isEmpty && items(.newerHere).isEmpty }
    }

    enum Outcome: Equatable {
        case report(Report)
        /// iCloud didn't answer: the check's own words.
        case failed(String)
    }

    /// Reads iCloud and this device and compares them. `progress` hears how many of iCloud's records have been read.
    /// `adopt` hands the read to the beats (`CloudSyncMonitor.auditRead`) so their index starts from it.
    @MainActor
    static func run(container: ModelContainer, reader: ICloudZoneReading = ICloudZoneReader(),
                    timeout: TimeInterval = SyncBeat.Rules().fullReadTimeout,
                    progress: @escaping @MainActor (Int) -> Void = { _ in },
                    adopt: @MainActor (ICloudZoneIndex.ZoneChanges, Data?) -> Void = { _, _ in }) async -> Outcome {
        let started = Date()
        // The database token first, so a change made during the read shows at the next beat.
        let database = await reader.zoneChanged(since: nil, timeout: SyncBeat.Rules().timeout)
        if case .failure(let failure) = database { return .failed(failure.reason) }
        let report: @Sendable (Int) -> Void = { count in Task { @MainActor in progress(count) } }
        let read = await reader.zoneChanges(since: nil, timeout: timeout, progress: report)
        let changes: ICloudZoneIndex.ZoneChanges
        switch read {
        case .failure(let failure): return .failed(failure.reason)
        case .success(let value): changes = value
        }
        var index = ICloudZoneIndex()
        index.apply(changes, at: Date())
        adopt(changes, try? database.get().token)
        let snapshot: StoreInventory.Snapshot
        do {
            snapshot = try await StoreInventory.read(container)
        } catch {
            return .failed("couldn't read this device's tasks: \(error.localizedDescription)")
        }
        let entities = StoreInventory.entities
        let comparison = SyncComparison.compare(remote: index.remoteRecords(entities: entities), local: snapshot.records,
                                                entities: entities)
        var result = Report(comparison: comparison, otherRecords: index.otherRecords(entities: entities),
                            recordsRead: changes.changed.count, zoneMissing: changes.zoneMissing)
        result.names = await names(for: comparison, container: container, reader: reader)
        result.duration = Date().timeIntervalSince(started)
        result.finishedAt = Date()
        return .report(result)
    }

    /// The names of the records that differ: this device's for what it holds, iCloud's (`CD_title`, `CD_name`) for
    /// what only iCloud holds. At most `limit` from iCloud: the lists show the first ones and a count.
    @MainActor
    static func names(for comparison: SyncComparison.Result, container: ModelContainer, reader: ICloudZoneReading,
                      limit: Int = 50) async -> [UUID: String] {
        var wanted: [String: Set<UUID>] = [:]
        for difference in comparison.differences where difference.local != nil {
            wanted[difference.entity, default: []].insert(difference.id)
        }
        var names = StoreInventory.names(of: wanted, in: container.mainContext)
        let remoteOnly = comparison.differences(.onlyThere).prefix(limit)
        let recordNames = remoteOnly.compactMap { $0.remote?.recordName }
        if case .success(let found) = await reader.names(of: recordNames, timeout: SyncBeat.Rules().timeout * 2) {
            for difference in remoteOnly {
                if let name = difference.remote.flatMap({ found[$0.recordName] }) { names[difference.id] = name }
            }
        }
        return names
    }
}

/// The audit's words (pure): what the person reads, and the counts, short hashes and times the sync log keeps.
enum SyncAuditWords {
    /// "This device and iCloud agree: 412 tasks, 9 Groups, 5 labels, 4 filters, 1 profile."
    static func headline(_ report: SyncAudit.Report) -> String {
        if report.zoneMissing, report.comparison.counts.values.allSatisfy({ $0.here == 0 }) {
            return "Nothing in iCloud and nothing on this device yet."
        }
        if report.agree {
            return "This device and iCloud agree: \(SyncComparison.countsText(report.comparison.counts, side: \.here))."
        }
        return "This device and iCloud differ."
    }

    /// One line per kind of difference: "2 tasks on this device are not in iCloud", with the names after it.
    struct Section: Equatable, Identifiable {
        var kind: SyncComparison.Difference.Kind
        var title: String
        var names: [String]
        var id: String { kind.rawValue }
    }

    static func sections(_ report: SyncAudit.Report, nameLimit: Int = 50) -> [Section] {
        SyncComparison.Difference.Kind.allCases.compactMap { kind in
            let items = report.items(kind)
            guard !items.isEmpty else { return nil }
            let unnamed = "(no name)"
            let names = items.prefix(nameLimit).map { report.names[$0.id].map { $0.isEmpty ? unnamed : $0 } ?? unnamed }
            var list = Array(names)
            if items.count > nameLimit { list.append("and \(items.count - nameLimit) more") }
            return Section(kind: kind, title: title(kind, items: items), names: list)
        }
    }

    /// "2 tasks on this device are not in iCloud", "1 task and 1 label in iCloud are not on this device".
    static func title(_ kind: SyncComparison.Difference.Kind, items: [SyncComparison.Difference]) -> String {
        let what = counted(items)
        let one = items.count == 1
        switch kind {
        case .onlyHere: return "\(what) on this device \(one ? "is" : "are") not in iCloud"
        case .onlyThere: return "\(what) in iCloud \(one ? "is" : "are") not on this device"
        case .newerHere: return "\(what) changed here \(one ? "hasn't" : "haven't") reached iCloud yet"
        case .newerThere: return "\(what) changed in iCloud \(one ? "hasn't" : "haven't") arrived here yet"
        }
    }

    /// "2 tasks and 1 label", by kind in the audit's order.
    static func counted(_ items: [SyncComparison.Difference]) -> String {
        let byEntity = Dictionary(grouping: items, by: \.entity)
        let order = SyncComparison.kindNames.map(\.entity) + byEntity.keys.sorted()
        var seen: Set<String> = []
        let parts = order.compactMap { entity -> String? in
            guard seen.insert(entity).inserted, let group = byEntity[entity] else { return nil }
            return SyncComparison.name(of: entity).count(group.count)
        }
        switch parts.count {
        case 0: return "Nothing"
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }

    /// What each choice means, in plain words, under the lists.
    static let onlyHereNote = "Each was either never sent to iCloud, or deleted on another device and the deletion never arrived here. Only you know which."
    static let onlyThereNote = "This device should receive these by itself. If they don't arrive, Reset local cache… downloads everything from iCloud again."
    static let onlyThereWaitNote = "This device should receive these by itself. Resolve the tasks above first: Reset local cache… would lose them."

    /// The audit's line in the sync log.
    static func logLine(_ report: SyncAudit.Report) -> (message: String, fields: [String: String]) {
        var fields = SyncComparison.logFields(report.comparison)
        fields["records"] = "\(report.recordsRead)"
        fields["duration"] = SyncLogFormat.duration(report.duration)
        if report.otherRecords > 0 { fields["links"] = "\(report.otherRecords)" }
        if report.zoneMissing { fields["zone"] = "missing" }
        let message = report.agree ? "Check iCloud: this device and iCloud agree"
                                   : "Check iCloud: this device and iCloud differ (\(SyncComparison.differenceSummary(report.comparison)))"
        return (message, fields)
    }
}

/// Brief 95: the audit's two repairs, each only on the person's word and after a backup (`LocalBackup`'s format).
@MainActor
enum SyncRepair {
    /// "Send to iCloud": an ordinary edit and save of each record (its `updatedAt` moves to now), which the mirror
    /// exports like any other change. Returns how many were saved.
    static func sendToICloud(_ ids: Set<UUID>, entity: String = "TaskItem", in context: ModelContext,
                             now: Date = Date()) throws -> Int {
        var touched = 0
        func touch<M: PersistentModel>(_ type: M.Type, id: KeyPath<M, UUID>, _ apply: (M) -> Void) throws {
            for model in try context.fetch(FetchDescriptor<M>()) where ids.contains(model[keyPath: id]) {
                apply(model)
                touched += 1
            }
        }
        switch entity {
        case "Project": try touch(Project.self, id: \.id) { $0.updatedAt = now }
        case "TaskLabel": try touch(TaskLabel.self, id: \.id) { $0.updatedAt = now }
        case "SavedFilter": try touch(SavedFilter.self, id: \.id) { $0.updatedAt = now }
        case "Switchboard": try touch(Switchboard.self, id: \.id) { $0.updatedAt = now }
        case "Profile": try touch(Profile.self, id: \.id) { $0.updatedAt = now }
        default: try touch(TaskItem.self, id: \.id) { $0.updatedAt = now }
        }
        if context.hasChanges { try context.save() }
        return touched
    }

    /// "Remove from this device": deletes each record here. The mirror sends the deletion, which changes nothing in
    /// iCloud for a record iCloud never had. Returns how many were deleted.
    static func removeFromDevice(_ ids: Set<UUID>, entity: String = "TaskItem", in context: ModelContext) throws -> Int {
        var removed = 0
        func remove<M: PersistentModel>(_ type: M.Type, id: KeyPath<M, UUID>) throws {
            for model in try context.fetch(FetchDescriptor<M>()) where ids.contains(model[keyPath: id]) {
                context.delete(model)
                removed += 1
            }
        }
        switch entity {
        case "Project": try remove(Project.self, id: \.id)
        case "TaskLabel": try remove(TaskLabel.self, id: \.id)
        case "SavedFilter": try remove(SavedFilter.self, id: \.id)
        case "Switchboard": try remove(Switchboard.self, id: \.id)
        case "Profile": try remove(Profile.self, id: \.id)
        default: try remove(TaskItem.self, id: \.id)
        }
        if context.hasChanges { try context.save() }
        return removed
    }

    /// A backup before either repair: today's daily backup for HITList.store (written now), or for a side store a file
    /// of its own in `Application Support/Backups before iCloud repairs/<store>/`. Returns where it went.
    static func backUp(context: ModelContext, now: Date = .now, isMainStore: Bool = ModelContainerFactory.isMainStoreOpen,
                       sideFolder: URL = sideBackupFolder) throws -> URL? {
        if isMainStore { return try LocalBackup.run(context: context, now: now) }
        let snapshot = try SnapshotBuilder.build(from: context)
        return try LocalBackup.write(try snapshot.jsonData(), in: sideFolder, now: now)
    }

    nonisolated static var sideBackupFolder: URL {
        URL.applicationSupportDirectory
            .appending(path: "Backups before iCloud repairs", directoryHint: .isDirectory)
            .appending(path: ModelContainerFactory.storeName, directoryHint: .isDirectory)
    }
}
