import XCTest
import CloudKit
import CoreLocation
@testable import HITList
import HITListCore

/// `CloudRecordCodec` (brief 142): `SyncRecord` ↔ `CKRecord` without a server. Every field of every type there and
/// back, a newer build's keys left alone by a save (T4), the strict names, the bool and the date edges.
final class CloudRecordCodecTests: XCTestCase {
    private let zone = CloudRecordCodec.zoneID("HITList")
    private var assets: AssetFiles!

    override func setUp() {
        super.setUp()
        assets = AssetFiles()
    }

    override func tearDown() {
        assets.removeAll()
        super.tearDown()
    }

    // MARK: - Samples

    /// A value of `field`'s kind that is not its `required` default, so a field that was dropped shows.
    private func sample(_ field: SyncField, seed: Int) -> SyncValue {
        switch field.kind {
        case .string: return .string("\(field.key) é ✓ \(seed)")
        case .int: return .int(Int64(1_000_000_007 * (seed + 1)))
        case .bool: return .bool(true)
        case .date: return .millis(1_763_190_000_123 + Int64(seed))
        case .data: return .data(Data((0..<(64 + seed)).map { UInt8(($0 * 7 + seed) & 0xff) }))
        case .reference(let type): return .reference(type == "TaskItem" ? UUID().uuidString : "\(type)-\(seed)")
        case .references: return .references(["B-\(seed)", "A-\(seed)", "C-\(seed)"])
        }
    }

    private func full(_ type: String, fields: [SyncField], name: String = UUID().uuidString) -> SyncRecord {
        var record = SyncRecord(type: type, name: name)
        for (index, field) in fields.enumerated() { record[field.key] = sample(field, seed: index) }
        return record
    }

    private var everyType: [(name: String, fields: [SyncField], singleton: String?)] {
        SyncSchema.types.map { ($0.name, $0.fields, $0.singleton) }
            + [(SyncSchema.metaType, CloudRecordCodec.metaFields, SyncSchema.metaName)]
    }

    // MARK: - There and back

    func testEveryFieldOfEveryTypeGoesThereAndBack() throws {
        for type in everyType {
            let record = full(type.name, fields: type.fields, name: type.singleton ?? UUID().uuidString)
            let ck = try CloudRecordCodec.record(for: OutgoingRecord(record: record, system: nil), in: zone, assets: assets)
            XCTAssertEqual(ck.recordType, type.name)
            XCTAssertEqual(ck.recordID.recordName, "\(type.name).\(record.key.name)")
            XCTAssertEqual(ck.recordID.zoneID, zone)
            for field in type.fields {
                XCTAssertNotNil(ck[field.key], "\(type.name).\(field.key) not written")
            }
            let back = try CloudRecordCodec.cloudRecord(from: ck)
            XCTAssertEqual(back.record, record, type.name)
            XCTAssertEqual(SyncSchema.known(back.record) ?? back.record, record, type.name)
        }
    }

    func testAMarkerGoesThereAndBackWithEveryOtherFieldEmptied() throws {
        let key = SyncKey(type: "TaskItem", name: UUID().uuidString)
        let marker = SyncRecord.marker(key, deletedAt: Date(timeIntervalSince1970: 1_763_190_000.5))
        let ck = try CloudRecordCodec.record(for: OutgoingRecord(record: marker, system: nil), in: zone, assets: assets)
        XCTAssertEqual(ck["deletedAt"] as? Date, Date(timeIntervalSince1970: 1_763_190_000.5))
        XCTAssertNil(ck["title"])
        XCTAssertEqual(try CloudRecordCodec.cloudRecord(from: ck).record, marker)
    }

    func testKindsAreStoredAsTheBriefSays() throws {
        var record = full("TaskItem", fields: SyncSchema.taskItem.fields)
        record["isCompleted"] = .bool(false)
        let ck = try CloudRecordCodec.record(for: OutgoingRecord(record: record, system: nil), in: zone, assets: assets)
        XCTAssertTrue(ck["title"] is String)
        XCTAssertEqual((ck["priority"] as? NSNumber).map { CFNumberIsFloatType($0) }, false)
        XCTAssertEqual(ck["hasDueTime"] as? Int64, 1)
        XCTAssertEqual(ck["isCompleted"] as? Int64, 0)
        XCTAssertTrue(ck["dueDate"] is Date)
        // References are the other record's key name, never a CKRecord.Reference.
        XCTAssertTrue(ck["project"] is String)
        XCTAssertFalse(ck["project"] is CKRecord.Reference)
        XCTAssertEqual(ck["labels"] as? [String], ["A-10", "B-10", "C-10"])

        let profile = full("Profile", fields: SyncSchema.profile.fields, name: "profile")
        let ckProfile = try CloudRecordCodec.record(for: OutgoingRecord(record: profile, system: nil), in: zone, assets: assets)
        let asset = try XCTUnwrap(ckProfile["avatarData"] as? CKAsset)
        let url = try XCTUnwrap(asset.fileURL)
        XCTAssertEqual(try Data(contentsOf: url), profile["avatarData"].flatMap { if case .data(let d) = $0 { return d } else { return nil } })
        XCTAssertTrue(url.path.hasPrefix(assets.folder.path), "the picture's file lives in the transport's own folder")
    }

    // MARK: - T4: every field of the type written, nothing else touched

    func testARebuiltRecordWritesEveryKnownFieldAndLeavesANewerBuildsKeysAlone() throws {
        // iCloud's record, as a newer build left it: every known field, and two keys this build doesn't know.
        let key = SyncKey(type: "TaskItem", name: UUID().uuidString)
        let server = CKRecord(recordType: "TaskItem", recordID: CloudRecordCodec.recordID(for: key, in: zone))
        server["title"] = "Old" as NSString
        server["notes"] = "Kept?" as NSString
        server["futureField"] = "from a newer build" as NSString
        server["futureCount"] = NSNumber(value: Int64(3))
        let system = CloudRecordCodec.systemFields(of: server)

        // This build's change: a title, no notes (emptied), most fields absent.
        var mine = SyncRecord(key: key)
        mine["title"] = .string("New")
        mine["updatedAt"] = .millis(1_763_190_000_000)
        let ck = try CloudRecordCodec.record(for: OutgoingRecord(record: mine, system: system), in: zone, assets: assets)

        let changed = Set(ck.changedKeys())
        let every = Set(SyncSchema.taskItem.fields.map(\.key) + ["deletedAt"])
        XCTAssertEqual(changed, every, "every known field is written, set or emptied, and nothing else")
        XCTAssertFalse(changed.contains("futureField"))
        XCTAssertFalse(changed.contains("futureCount"))
        XCTAssertNil(ck["futureField"], "a rebuilt record holds no values of its own")
        XCTAssertNil(ck["notes"], "emptied")
        XCTAssertEqual(ck["title"] as? String, "New")
        XCTAssertEqual(ck.recordID, server.recordID)
    }

    func testSystemFieldsAreKeptThroughTheRebuild() throws {
        let key = SyncKey(type: "Project", name: UUID().uuidString)
        let server = CKRecord(recordType: "Project", recordID: CloudRecordCodec.recordID(for: key, in: zone))
        let system = CloudRecordCodec.systemFields(of: server)
        let rebuilt = try XCTUnwrap(CloudRecordCodec.rebuilt(from: system, id: server.recordID, type: "Project"))
        XCTAssertEqual(rebuilt.recordID, server.recordID)
        XCTAssertEqual(rebuilt.recordChangeTag, server.recordChangeTag)
        XCTAssertEqual(CloudRecordCodec.systemFields(of: rebuilt), system)
    }

    func testSystemFieldsOfAnotherRecordAreNotUsed() throws {
        let a = CKRecord(recordType: "Project", recordID: CKRecord.ID(recordName: "Project.A", zoneID: zone))
        let system = CloudRecordCodec.systemFields(of: a)
        let otherName = CKRecord.ID(recordName: "Project.B", zoneID: zone)
        let otherZone = CKRecord.ID(recordName: "Project.A", zoneID: CloudRecordCodec.zoneID("HITListProbe-x"))
        XCTAssertNil(CloudRecordCodec.rebuilt(from: system, id: otherName, type: "Project"))
        XCTAssertNil(CloudRecordCodec.rebuilt(from: system, id: otherZone, type: "Project"))
        XCTAssertNil(CloudRecordCodec.rebuilt(from: system, id: a.recordID, type: "TaskLabel"))
        XCTAssertNil(CloudRecordCodec.rebuilt(from: Data("not an archive".utf8), id: a.recordID, type: "Project"))
        // Then the record is made new, and still carries every field.
        let record = SyncRecord(type: "Project", name: "B", fields: ["name": .string("Inbox")])
        let ck = try CloudRecordCodec.record(for: OutgoingRecord(record: record, system: system), in: zone, assets: assets)
        XCTAssertEqual(ck.recordID, otherName)
        XCTAssertEqual(ck["name"] as? String, "Inbox")
    }

    func testAnEmptySetOfLabelsIsSentEmptiedAndComesBackAbsent() throws {
        var record = SyncRecord(type: "TaskItem", name: UUID().uuidString)
        record["labels"] = .referenceList([])
        let ck = try CloudRecordCodec.record(for: OutgoingRecord(record: record, system: nil), in: zone, assets: assets)
        XCTAssertNil(ck["labels"])
        XCTAssertTrue(ck.changedKeys().contains("labels"))
        XCTAssertNil(try CloudRecordCodec.cloudRecord(from: ck).record["labels"])
    }

    func testWhatCannotBeSentIsRefused() {
        let unknown = SyncRecord(type: "Gizmo", name: "x", fields: ["a": .string("b")])
        XCTAssertThrowsError(try CloudRecordCodec.record(for: OutgoingRecord(record: unknown, system: nil), in: zone, assets: assets)) {
            XCTAssertEqual($0 as? CloudRecordCodec.EncodeError, .unknownType("Gizmo"))
        }
        let digest = SyncRecord(type: "Profile", name: "profile", fields: ["avatarData": .digest("abc")])
        XCTAssertThrowsError(try CloudRecordCodec.record(for: OutgoingRecord(record: digest, system: nil), in: zone, assets: assets)) {
            XCTAssertEqual($0 as? CloudRecordCodec.EncodeError, .wrongKind(field: "avatarData"))
        }
        let wrongKind = SyncRecord(type: "TaskItem", name: "x", fields: ["priority": .string("high")])
        XCTAssertThrowsError(try CloudRecordCodec.record(for: OutgoingRecord(record: wrongKind, system: nil), in: zone, assets: assets))
        let badName = SyncRecord(type: "TaskItem", name: "has a space", fields: [:])
        XCTAssertThrowsError(try CloudRecordCodec.record(for: OutgoingRecord(record: badName, system: nil), in: zone, assets: assets)) {
            XCTAssertEqual($0 as? CloudRecordCodec.EncodeError, .invalidKey(badName.key))
        }
    }

    // MARK: - In: every key that maps, known or not

    func testKeysANewerBuildWroteReachTheBrainAndAreCutByTheSchema() throws {
        let id = CloudRecordCodec.recordID(for: SyncKey(type: "TaskLabel", name: "L1"), in: zone)
        let ck = CKRecord(recordType: "TaskLabel", recordID: id)
        ck["name"] = "Errands" as NSString
        ck["futureText"] = "x" as NSString
        ck["futureInt"] = NSNumber(value: Int64(42))
        ck["futureDate"] = Date(timeIntervalSince1970: 10.0004) as NSDate
        ck["futureBytes"] = Data([1, 2, 3]) as NSData
        ck["futureList"] = ["b", "a", "b"] as NSArray
        ck["futureFraction"] = NSNumber(value: 1.5)
        ck["futureWhole"] = NSNumber(value: 2.0)
        ck["futurePlace"] = CLLocation(latitude: 1, longitude: 2)
        ck["futureNumbers"] = [NSNumber(value: 1)] as NSArray

        let record = try CloudRecordCodec.cloudRecord(from: ck).record
        XCTAssertEqual(record["name"], .string("Errands"))
        XCTAssertEqual(record["futureText"], .string("x"))
        XCTAssertEqual(record["futureInt"], .int(42))
        XCTAssertEqual(record["futureDate"], .millis(10_000))
        XCTAssertEqual(record["futureBytes"], .data(Data([1, 2, 3])))
        XCTAssertEqual(record["futureList"], .referenceList(["a", "b"]))
        XCTAssertEqual(record["futureWhole"], .int(2))
        XCTAssertNil(record["futureFraction"], "no SyncValue holds a fraction")
        XCTAssertNil(record["futurePlace"])
        XCTAssertNil(record["futureNumbers"])
        XCTAssertEqual(SyncSchema.known(record), SyncRecord(type: "TaskLabel", name: "L1", fields: ["name": .string("Errands")]))
    }

    func testAKnownFieldOfAnotherKindIsLeftForTheSchemaToDrop() throws {
        let id = CloudRecordCodec.recordID(for: SyncKey(type: "TaskItem", name: "T1"), in: zone)
        let ck = CKRecord(recordType: "TaskItem", recordID: id)
        ck["priority"] = "high" as NSString
        ck["project"] = ["P1"] as NSArray
        let record = try CloudRecordCodec.cloudRecord(from: ck).record
        XCTAssertEqual(record["priority"], .string("high"))
        XCTAssertNil(record["project"], "a list where one name goes")
        XCTAssertEqual(SyncSchema.known(record)?.fields, [:])
    }

    func testARecordWhoseNameDoesNotParseIsNotOurs() {
        let mirror = CKRecord(recordType: "CD_TaskItem", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        XCTAssertThrowsError(try CloudRecordCodec.cloudRecord(from: mirror))
        let mismatched = CKRecord(recordType: "Project", recordID: CKRecord.ID(recordName: "TaskItem.T1", zoneID: zone))
        XCTAssertThrowsError(try CloudRecordCodec.cloudRecord(from: mismatched)) {
            XCTAssertEqual($0 as? CloudRecordCodec.DecodeProblem, .notOurs(recordName: "TaskItem.T1", recordType: "Project"))
        }
    }

    // MARK: - Names

    func testNamesParseBackStrictly() {
        let uuid = UUID().uuidString
        XCTAssertEqual(CloudRecordCodec.key(forRecordName: "TaskItem.\(uuid)"), SyncKey(type: "TaskItem", name: uuid))
        XCTAssertEqual(CloudRecordCodec.key(forRecordName: "Profile.profile"), SyncKey(type: "Profile", name: "profile"))
        XCTAssertEqual(CloudRecordCodec.key(forRecordName: "Meta.meta"), SyncKey(type: "Meta", name: "meta"))
        XCTAssertEqual(CloudRecordCodec.key(forRecordName: "Future_Type2.a_b-c"), SyncKey(type: "Future_Type2", name: "a_b-c"))
        for bad in ["", "TaskItem", ".x", "TaskItem.", "1Task.x", "_Task.x", "Task Item.x", "TaskItem.a.b", "TaskItem.a b",
                    "TaskItem.é", "Täsk.x", "TaskItem.\(String(repeating: "a", count: 247))",
                    UUID().uuidString, "CD_TaskItem"] {
            XCTAssertNil(CloudRecordCodec.key(forRecordName: bad), bad)
        }
        XCTAssertNotNil(CloudRecordCodec.key(forRecordName: "TaskItem.\(String(repeating: "a", count: 246))"), "255 in all")
        for type in everyType {
            let key = SyncKey(type: type.name, name: type.singleton ?? uuid)
            XCTAssertEqual(CloudRecordCodec.key(for: CloudRecordCodec.recordID(for: key, in: zone)), key)
        }
    }

    // MARK: - Edges

    func testBoolEdges() throws {
        let field = try XCTUnwrap(SyncSchema.taskItem.field("isCompleted"))
        XCTAssertEqual(try CloudRecordCodec.syncValue(NSNumber(value: Int64(0)), field: field, key: "isCompleted"), .bool(false))
        XCTAssertEqual(try CloudRecordCodec.syncValue(NSNumber(value: Int64(1)), field: field, key: "isCompleted"), .bool(true))
        XCTAssertEqual(try CloudRecordCodec.syncValue(NSNumber(value: Int64(2)), field: field, key: "isCompleted"), .bool(true))
        XCTAssertEqual(try CloudRecordCodec.syncValue(NSNumber(value: Int64(-1)), field: field, key: "isCompleted"), .bool(true))
        XCTAssertEqual(try CloudRecordCodec.syncValue(NSNumber(value: true), field: field, key: "isCompleted"), .bool(true))
        XCTAssertEqual(try CloudRecordCodec.syncValue(NSNumber(value: 0.0), field: field, key: "isCompleted"), .bool(false))
        // Out: Int64 0 or 1, never a Bool NSNumber or a Double.
        for flag in [false, true] {
            let record = SyncRecord(type: "TaskItem", name: "T", fields: ["isCompleted": .bool(flag)])
            let ck = try CloudRecordCodec.record(for: OutgoingRecord(record: record, system: nil), in: zone, assets: assets)
            let number = try XCTUnwrap(ck["isCompleted"] as? NSNumber)
            XCTAssertEqual(number.int64Value, flag ? 1 : 0)
            XCTAssertFalse(CFNumberIsFloatType(number))
            XCTAssertEqual(try CloudRecordCodec.cloudRecord(from: ck).record["isCompleted"], .bool(flag))
        }
    }

    func testDateEdges() throws {
        let field = try XCTUnwrap(SyncSchema.taskItem.field("dueDate"))
        // In: rounded to the nearest whole millisecond (`SyncValue.date`). (An exact half is not a case: a `Date`
        // counts from 2001 in a Double and cannot hold 1970 + 0.0005 s exactly; it lands either side.)
        let cases: [(Double, Int64)] = [
            (0, 0), (0.0004, 0), (0.0006, 1), (0.0014, 1), (0.0016, 2), (1_763_190_000.1234, 1_763_190_000_123),
            (-0.0004, 0), (-0.0006, -1), (-86_400.5, -86_400_500), (253_402_300_799.999, 253_402_300_799_999),
        ]
        for (seconds, ms) in cases {
            let value = try CloudRecordCodec.syncValue(Date(timeIntervalSince1970: seconds) as NSDate, field: field, key: "dueDate")
            XCTAssertEqual(value, .millis(ms), "\(seconds)")
        }
        // Out and back: every whole millisecond stays itself.
        for ms: Int64 in [0, 1, -1, 999, 1_763_190_000_123, -62_135_596_800_000, 253_402_300_799_999] {
            let record = SyncRecord(type: "TaskItem", name: "T", fields: ["dueDate": .millis(ms)])
            let ck = try CloudRecordCodec.record(for: OutgoingRecord(record: record, system: nil), in: zone, assets: assets)
            XCTAssertEqual(try CloudRecordCodec.cloudRecord(from: ck).record["dueDate"], .millis(ms), "\(ms)")
        }
    }

    // MARK: - Asset files

    func testAssetFilesGoWhenTheirRecordIsAnsweredAndAllGoAtTheEnd() throws {
        let id1 = CKRecord.ID(recordName: "Profile.profile", zoneID: zone)
        let id2 = CKRecord.ID(recordName: "Profile.other", zoneID: zone)
        let one = try assets.write(Data([1]), recordID: id1, field: "avatarData")
        let two = try assets.write(Data([2]), recordID: id2, field: "avatarData")
        XCTAssertEqual(assets.count, 2)
        assets.release(id1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: one.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: two.path))
        assets.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: two.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: assets.folder.path))
        XCTAssertEqual(assets.count, 0)
    }

    func testAnAssetOverTheLimitIsNotRead() throws {
        let url = assets.folder.appendingPathComponent("big.asset")
        try FileManager.default.createDirectory(at: assets.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(CloudRecordCodec.assetByteLimit + 1))
        try handle.close()
        let ck = CKRecord(recordType: "Profile", recordID: CKRecord.ID(recordName: "Profile.profile", zoneID: zone))
        ck["avatarData"] = CKAsset(fileURL: url)
        XCTAssertThrowsError(try CloudRecordCodec.cloudRecord(from: ck)) {
            guard case .assetUnreadable(let field, _)? = $0 as? CloudRecordCodec.DecodeProblem else { return XCTFail("\($0)") }
            XCTAssertEqual(field, "avatarData")
        }
    }

    func testStaleAssetFoldersAreSweptAndFreshOnesKept() throws {
        let stale = AssetFiles.root.appendingPathComponent("stale-\(UUID().uuidString)", isDirectory: true)
        let fresh = AssetFiles.root.appendingPathComponent("fresh-\(UUID().uuidString)", isDirectory: true)
        for folder in [stale, fresh] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -2 * 24 * 3600)], ofItemAtPath: stale.path)
        AssetFiles.sweepStale()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        try? FileManager.default.removeItem(at: fresh)
    }
}
