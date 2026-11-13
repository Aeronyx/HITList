import XCTest
import SwiftData
@testable import HITList

/// Brief 95, Part 3: "Check iCloud…" as an audit. Its words for each outcome, what the sync log may keep (never a
/// title), and the two repairs, each only on the person's word and after a backup.
@MainActor
final class SyncAuditTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func difference(_ kind: SyncComparison.Difference.Kind, _ entity: String = "TaskItem",
                            id: UUID = UUID()) -> SyncComparison.Difference {
        let local = SyncComparison.Local(entity: entity, id: id, updatedAt: at(0), createdAt: at(-60))
        let remote = SyncComparison.Remote(entity: entity, id: id, updatedAt: at(0), recordName: "R-\(id.uuidString)",
                                           modifiedAt: at(1))
        switch kind {
        case .onlyHere: return .init(kind: kind, entity: entity, id: id, local: local, remote: nil)
        case .onlyThere: return .init(kind: kind, entity: entity, id: id, local: nil, remote: remote)
        case .newerHere, .newerThere: return .init(kind: kind, entity: entity, id: id, local: local, remote: remote)
        }
    }

    private func report(_ differences: [SyncComparison.Difference], counts: [String: SyncComparison.Count] = [:],
                        names: [UUID: String] = [:]) -> SyncAudit.Report {
        SyncAudit.Report(comparison: SyncComparison.Result(differences: differences, counts: counts), names: names)
    }

    // MARK: Words

    func testAgreementNamesEveryKind() {
        let counts: [String: SyncComparison.Count] = [
            "TaskItem": .init(here: 412, there: 412), "Project": .init(here: 9, there: 9), "TaskLabel": .init(here: 5, there: 5),
            "SavedFilter": .init(here: 4, there: 4), "Switchboard": .init(here: 2, there: 2), "Profile": .init(here: 1, there: 1),
        ]
        XCTAssertEqual(SyncAuditWords.headline(report([], counts: counts)),
                       "This device and iCloud agree: 412 tasks, 9 Groups, 5 labels, 4 filters, 2 Switchboards, 1 profile.")
    }

    func testEachDifferenceIsALineWithItsNames() {
        let shave = difference(.onlyHere), bank = difference(.onlyHere), gone = difference(.onlyThere)
        let audit = report([shave, bank, gone], names: [shave.id: "Shave", bank.id: "Call the bank", gone.id: "Water plants"])
        XCTAssertEqual(SyncAuditWords.headline(audit), "This device and iCloud differ.")
        let sections = SyncAuditWords.sections(audit)
        XCTAssertEqual(sections.map(\.title), ["2 tasks on this device are not in iCloud", "1 task in iCloud is not on this device"])
        XCTAssertEqual(sections[0].names, ["Shave", "Call the bank"])
        XCTAssertEqual(sections[1].names, ["Water plants"])
        XCTAssertFalse(audit.resetIsSafe, "Reset local cache… would lose Shave and Call the bank")
        XCTAssertTrue(report([gone]).resetIsSafe)
    }

    func testMixedKindsAreCountedTogether() {
        let items = [difference(.onlyThere), difference(.onlyThere, "TaskLabel"), difference(.onlyThere, "Project")]
        XCTAssertEqual(SyncAuditWords.title(.onlyThere, items: items), "1 task, 1 Group and 1 label in iCloud are not on this device")
        XCTAssertEqual(SyncAuditWords.title(.newerThere, items: [difference(.newerThere)]),
                       "1 task changed in iCloud hasn't arrived here yet")
    }

    func testTheSyncLogGetsCountsHashesAndTimesNeverATitle() {
        let shave = difference(.onlyHere)
        let audit = report([shave], counts: ["TaskItem": .init(here: 2, there: 1)], names: [shave.id: "Shave"])
        let line = SyncAuditWords.logLine(audit)
        XCTAssertEqual(line.message, "Check iCloud: this device and iCloud differ (1 only here)")
        let all = ([line.message] + line.fields.values).joined(separator: " ")
        XCTAssertFalse(all.contains("Shave"))
        XCTAssertFalse(all.contains(shave.id.uuidString))
        XCTAssertTrue(line.fields["onlyHere"]?.contains(SyncComparison.shortHash(shave.id)) ?? false)
        XCTAssertTrue(line.fields["onlyHere"]?.contains("created") ?? false, "when it was made helps tell never-sent from deleted")
        XCTAssertEqual(line.fields["here"], "2 tasks")
        XCTAssertEqual(line.fields["iCloud"], "1 task")
    }

    func testTheAuditReadsBothSidesAndHandsItsReadToTheBeats() async throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let here = TaskItem(title: "Shave")
        context.insert(here)
        let both = TaskItem(title: "Call mom")
        context.insert(both)
        try context.save()
        let reader = FakeReader()
        let onlyThere = UUID()
        reader.zone = .success(.init(changed: [
            "R-both": .init(type: "CD_TaskItem", entity: "TaskItem", id: both.id, updatedAt: both.updatedAt, modifiedAt: at(0)),
            "R-there": .init(type: "CD_TaskItem", entity: "TaskItem", id: onlyThere, updatedAt: at(0), modifiedAt: at(0)),
            "R-link": .init(type: "CDMR", entity: "CDMR", id: nil),
        ], token: Data([1]), isFullRead: true))
        reader.names = ["R-there": "Water plants"]
        let outcome = await SyncAudit.run(container: container, reader: reader)
        guard case .report(let found) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(found.items(.onlyHere).map(\.id), [here.id])
        XCTAssertEqual(found.items(.onlyThere).map(\.id), [onlyThere])
        XCTAssertEqual(found.names[here.id], "Shave")
        XCTAssertEqual(found.names[onlyThere], "Water plants", "named from iCloud, for the list")
        XCTAssertEqual(found.otherRecords, 1)
        XCTAssertEqual(found.recordsRead, 3)
        XCTAssertEqual(reader.zoneTokens, [nil], "a fresh read of the whole zone, every time it is asked")
    }

    func testAnUnansweredAuditSaysSo() async {
        let reader = FakeReader()
        reader.database = .failure(ICloudReadFailure(.network, "network unavailable"))
        let outcome = await SyncAudit.run(container: ModelContainerFactory.preview(), reader: reader)
        XCTAssertEqual(outcome, .failed("network unavailable"))
    }

    // MARK: Repairs

    func testSendToICloudIsAnOrdinarySave() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let task = TaskItem(title: "Shave")
        task.updatedAt = at(-3600)
        context.insert(task)
        try context.save()
        let sent = try SyncRepair.sendToICloud([task.id], in: context, now: at(0))
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(task.updatedAt, at(0))
        XCTAssertFalse(context.hasChanges, "saved, so the mirror exports it")
    }

    func testRemoveFromThisDeviceDeletesOnlyWhatWasAsked() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let gone = TaskItem(title: "Shave"), kept = TaskItem(title: "Call mom")
        context.insert(gone)
        context.insert(kept)
        try context.save()
        XCTAssertEqual(try SyncRepair.removeFromDevice([gone.id], in: context), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Call mom"])
    }

    func testABackupComesFirstForASideStore() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        context.insert(TaskItem(title: "Shave"))
        try context.save()
        let folder = FileManager.default.temporaryDirectory.appending(path: "SyncAuditTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try SyncRepair.backUp(context: context, now: at(0), isMainStore: false, sideFolder: folder)
        XCTAssertNotNil(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url?.path ?? ""))
    }

    func testTheResultOfSendingSaysWhetherItArrived() {
        let one = [difference(.onlyHere)]
        XCTAssertEqual(SyncAuditModel.sendResult(sent: one, missing: [], exported: true), "Sent: it is in iCloud now.")
        XCTAssertEqual(SyncAuditModel.sendResult(sent: one + one, missing: one, exported: true),
                       "1 still isn't in iCloud. iCloud didn't take it; the Sync log has the export's answer.")
        XCTAssertEqual(SyncAuditModel.sendResult(sent: one, missing: one, exported: false),
                       "1 still isn't in iCloud. No export finished within a minute; try again in a moment.")
    }
}

/// iCloud as a test answers for it (`ICloudZoneReading`): what Check iCloud… reads, without the network.
final class FakeReader: ICloudZoneReading, @unchecked Sendable {
    var database: Result<ICloudDatabaseAnswer, ICloudReadFailure> = .success(ICloudDatabaseAnswer(zoneChanged: true, token: Data([0])))
    var zone: Result<ICloudZoneIndex.ZoneChanges, ICloudReadFailure> = .success(.init(changed: [:], token: Data([0]), isFullRead: true))
    /// Answers for the next zone fetches, in order, before `zone`.
    var zoneQueue: [Result<ICloudZoneIndex.ZoneChanges, ICloudReadFailure>] = []
    var names: [String: String] = [:]
    private(set) var databaseCalls = 0
    private(set) var zoneTokens: [Data?] = []

    func zoneChanged(since token: Data?, timeout: TimeInterval) async -> Result<ICloudDatabaseAnswer, ICloudReadFailure> {
        databaseCalls += 1
        return database
    }

    func zoneChanges(since token: Data?, timeout: TimeInterval,
                     progress: @escaping @Sendable (Int) -> Void) async -> Result<ICloudZoneIndex.ZoneChanges, ICloudReadFailure> {
        zoneTokens.append(token)
        let next = zoneQueue.isEmpty ? zone : zoneQueue.removeFirst()
        if case .success(var changes) = next {
            changes.isFullRead = token == nil
            return .success(changes)
        }
        return next
    }

    func names(of recordNames: [String], timeout: TimeInterval) async -> Result<[String: String], ICloudReadFailure> {
        .success(names.filter { recordNames.contains($0.key) })
    }
}
