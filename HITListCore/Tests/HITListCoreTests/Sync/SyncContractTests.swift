import XCTest
@testable import HITListCore

// The sync engine's contract (`HITListCore/Sources/HITListCore/Sync/`), pinned where core can pin it: the schema
// table's own consistency, what `known` and `filled` do, dates in whole milliseconds, reference lists, `Codable`, and
// the in-memory stores the engine's tests run on (`SyncMemory.swift`) behaving as `SyncStorage.swift` says.
// (That the table matches the app's models is the app's test: `SwiftDataSyncStore`'s, session 141.)

final class SyncContractTests: XCTestCase {
    // MARK: The schema table

    func testEveryTypeHasCreatedAtAndUpdatedAtAsRequiredDates() {
        for type in SyncSchema.types {
            for key in ["createdAt", SyncSchema.updatedAt] {
                guard let field = type.field(key) else { return XCTFail("\(type.name) has no \(key)") }
                XCTAssertEqual(field.kind, .date, "\(type.name).\(key)")
                XCTAssertNotNil(field.required, "\(type.name).\(key) is on every record")
            }
            XCTAssertNil(type.field(SyncSchema.deletedAt), "\(type.name): deletedAt belongs to every type, unlisted")
        }
    }

    func testNamesAreUniqueAndOnlyTheProfileIsASingleton() {
        XCTAssertEqual(Set(SyncSchema.types.map(\.name)).count, SyncSchema.types.count)
        for type in SyncSchema.types {
            XCTAssertEqual(Set(type.fields.map(\.key)).count, type.fields.count, "\(type.name) repeats a field")
            XCTAssertEqual(SyncSchema.type(type.name)?.name, type.name)
        }
        XCTAssertEqual(SyncSchema.types.filter { $0.singleton != nil }.map(\.name), ["Profile"])
        XCTAssertEqual(SyncSchema.profile.singleton, "profile")
        XCTAssertNil(SyncSchema.type(SyncSchema.metaType), "Meta is the zone's own record, not a synced type")
        XCTAssertEqual(Set(SyncSchema.types.map(\.name)),
                       ["Project", "TaskLabel", "Switchboard", "SavedFilter", "Profile", "TaskItem"])
    }

    func testEveryReferenceNamesATypeInTheTable() {
        for type in SyncSchema.types {
            for name in type.referenced {
                XCTAssertNotNil(SyncSchema.type(name), "\(type.name) points at \(name), which is not synced")
            }
        }
        XCTAssertEqual(SyncSchema.taskItem.referenced, ["Project", "TaskLabel", "TaskItem", "Switchboard"])
    }

    func testTheOrderPutsATypeAfterThoseItPointsAt() {
        let index = Dictionary(uniqueKeysWithValues: SyncSchema.types.enumerated().map { ($1.name, $0) })
        for (i, type) in SyncSchema.types.enumerated() {
            for name in type.referenced where name != type.name {
                XCTAssertLessThan(index[name] ?? .max, i, "\(type.name) comes before \(name), which it points at")
            }
        }
    }

    func testEachFieldsMergeRuleFitsItsKind() {
        for type in SyncSchema.types {
            for field in type.fields {
                if let required = field.required {
                    XCTAssertTrue(field.accepts(required), "\(type.name).\(field.key)'s default is not of its kind")
                }
                switch field.merge {
                case .lastWriter: break
                case .union:
                    guard case .references = field.kind else {
                        return XCTFail("\(type.name).\(field.key) is a union but not a set of references")
                    }
                case .clock(let clock):
                    XCTAssertEqual(type.field(clock)?.kind, .date, "\(type.name).\(field.key)'s clock \(clock)")
                    XCTAssertNotEqual(clock, SyncSchema.updatedAt)
                }
            }
        }
        XCTAssertEqual(RecordMerge.clockKeys(SyncSchema.profile), ["nameUpdatedAt", "avatarUpdatedAt"])
        XCTAssertEqual(SyncSchema.profile.field("avatarData")?.kind, .data(asset: true))
    }

    func testFixedFacts() {
        XCTAssertEqual(SyncSchema.formatVersion, 1)
        XCTAssertEqual(SyncSchema.zoneName, "HITList")
        XCTAssertEqual(SyncSchema.markerLifetime, 400 * 24 * 3600)
        let id = UUID(uuidString: "6B1F3E2A-9C4D-4E5F-8A7B-1D2C3E4F5A6B")!
        XCTAssertEqual(SyncSchema.key(SyncSchema.taskItem, id: id), SyncKey(type: "TaskItem", name: id.uuidString))
        XCTAssertEqual(SyncSchema.key(SyncSchema.profile, id: id), SyncKey(type: "Profile", name: "profile"))
        XCTAssertEqual(SyncKey(type: "TaskItem", name: "x").description, "TaskItem/x")
        XCTAssertLessThan(SyncKey(type: "Project", name: "z"), SyncKey(type: "TaskItem", name: "a"))
    }

    // MARK: known and filled

    func testKnownKeepsTheTablesFieldsOfTheirKindAndDeletedAt() {
        let record = SyncRecord(type: "TaskItem", name: "T", fields: [
            "title": .string("Milk"),
            "priority": .string("high"),            // the wrong kind: left out
            "estimateMinutes": .int(30),            // not in this build's table: left out
            "labels": .referenceList(["L1"]),
            "updatedAt": .millis(5),
            "deletedAt": .millis(9),
        ])
        let known = SyncSchema.known(record)
        XCTAssertEqual(known?.fields, ["title": .string("Milk"), "labels": .referenceList(["L1"]),
                                       "updatedAt": .millis(5), "deletedAt": .millis(9)])
        var odd = record
        odd["deletedAt"] = .string("yesterday")
        XCTAssertNil(SyncSchema.known(odd)?["deletedAt"], "a deletedAt that is not a moment is not known")
        XCTAssertNil(SyncSchema.known(SyncRecord(type: "Attachment", name: "A")))

        let profile = SyncRecord(type: "Profile", name: "profile",
                                 fields: ["avatarData": .digest("ab"), "displayName": .data(Data([1]))])
        XCTAssertEqual(SyncSchema.known(profile)?.fields, ["avatarData": .digest("ab")], "a digest stands for data")
    }

    func testFilledAddsRequiredFieldsOnly() {
        let filled = SyncSchema.filled(SyncRecord(type: "Switchboard", name: "S", fields: ["name": .string("Bed")]))
        XCTAssertEqual(filled.fields, [
            "name": .string("Bed"), "sortOrder": .int(0), "cadence": .string("daily"), "resetMinutes": .int(240),
            "resetWeekday": .int(0), "overdueBecomesTask": .bool(false), "createdAt": .millis(0),
            "updatedAt": .millis(0),
        ])
        let task = SyncSchema.filled(SyncRecord(type: "TaskItem", name: "T"))
        for optional in ["dueDate", "completedAt", "recurrence", "project", "labels", "reminderOffsetMinutes",
                         "deadline", "locationName", "flipPeriodStart", "parent", "reminderDate", "switchboard"] {
            XCTAssertNil(task[optional], "\(optional) may be empty and stays absent")
        }
        XCTAssertEqual(task["flipTarget"], .int(1))
        XCTAssertEqual(task["priority"], .int(4))

        let marker = SyncRecord.marker(SyncKey(type: "TaskItem", name: "T"), deletedAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(SyncSchema.filled(marker), marker, "a marker is returned as it is")
        let foreign = SyncRecord(type: "Attachment", name: "A")
        XCTAssertEqual(SyncSchema.filled(foreign), foreign)
    }

    func testAMarkerIsItsTimeAndNothingElse() {
        let when = Date(timeIntervalSince1970: 1_800_000_000.123)
        let marker = SyncRecord.marker(SyncKey(type: "Project", name: "P"), deletedAt: when)
        XCTAssertTrue(marker.isDeleted)
        XCTAssertEqual(marker.fields.count, 2)
        XCTAssertEqual(marker.deletedAt, when)
        XCTAssertEqual(marker.updatedAt, when)
    }

    // MARK: Values

    func testADateSurvivesAtAnySubMillisecondValue() {
        var rng = SyncRandom(seed: 0x5EED)
        for _ in 0..<5_000 {
            let seconds = Double(rng.int(0...4_000_000_000)) + Double(rng.int(0...999_999)) / 1_000_000
            let date = Date(timeIntervalSince1970: seconds)
            let value = SyncValue.date(date)
            guard case .millis(let ms) = value else { return XCTFail("not millis") }
            XCTAssertEqual(ms, Int64((seconds * 1000).rounded()), "seed 0x5EED: \(seconds)")
            // Through iCloud and back (whole milliseconds), it is the same value.
            XCTAssertEqual(SyncValue.date(value.dateValue!), value, "seed 0x5EED: \(seconds)")
            XCTAssertLessThanOrEqual(abs(value.dateValue!.timeIntervalSince(date)), 0.0005 + 1e-6)
        }
        let edge = Date(timeIntervalSince1970: 1_800_000_000.0004)
        XCTAssertEqual(SyncValue.date(edge), .millis(1_800_000_000_000))
        XCTAssertEqual(SyncValue.date(Date(timeIntervalSince1970: 1_800_000_000.0006)), .millis(1_800_000_000_001))
        XCTAssertEqual(SyncValue.date(Date(timeIntervalSince1970: -1.5)), .millis(-1500), "before 1970 too")
        XCTAssertNil(SyncValue.int(3).dateValue)
    }

    func testReferencesSortsAndDropsRepeats() {
        XCTAssertEqual(SyncValue.references(["b", "a", "b", "c"]), .referenceList(["a", "b", "c"]))
        XCTAssertEqual(SyncValue.references(Set(["z", "y"])), .referenceList(["y", "z"]))
        // An empty list is a value here; a device leaves the field absent instead (`RecordMerge.normal` reads
        // the two as the same).
        XCTAssertEqual(SyncValue.references([String]()), .referenceList([]))
    }

    func testComparableIsTheDigestOfDataOnly() {
        let bytes = Data("HITList".utf8)
        XCTAssertEqual(SyncValue.digest(of: Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256, lower-case hex")
        XCTAssertEqual(SyncValue.digest(of: bytes).count, 64)
        XCTAssertEqual(SyncValue.data(bytes).comparable, .digest(SyncValue.digest(of: bytes)))
        XCTAssertEqual(SyncValue.digest(of: Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        for value: SyncValue in [.string("a"), .int(1), .bool(true), .millis(2), .reference("R"),
                                 .referenceList(["L"]), .digest("ab")] {
            XCTAssertEqual(value.comparable, value)
        }
        let record = SyncRecord(type: "Profile", name: "profile", fields: ["avatarData": .data(bytes)])
        XCTAssertEqual(record.comparable["avatarData"], .digest(SyncValue.digest(of: bytes)))
    }

    func testEveryValueAndRecordRoundTripsThroughCodable() throws {
        let values: [SyncValue] = [
            .string(""), .string("Oat milk ✓"), .int(.min), .int(.max), .bool(false), .bool(true),
            .millis(-1500), .millis(1_800_000_000_123), .data(Data()), .data(Data([0, 255, 7])),
            .digest(SyncValue.digest(of: Data([1]))), .reference("6B1F3E2A-0000-4000-8000-000000000001"),
            .referenceList([]), .referenceList(["a", "b"]),
        ]
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        for value in values {
            XCTAssertEqual(try decoder.decode(SyncValue.self, from: encoder.encode(value)), value)
        }
        let record = SyncRecord(type: "TaskItem", name: "T", fields: Dictionary(uniqueKeysWithValues:
            values.enumerated().map { ("f\($0)", $1) }))
        XCTAssertEqual(try decoder.decode(SyncRecord.self, from: encoder.encode(record)), record)
        let cloud = CloudRecord(record: record, system: Data([9, 9]))
        XCTAssertEqual(try decoder.decode(CloudRecord.self, from: encoder.encode(cloud)), cloud)
        let entry = LedgerEntry(key: record.key, base: record.comparable, system: Data([1]),
                                deletedHereAt: Date(timeIntervalSince1970: 1_800_000_000.5))
        XCTAssertEqual(try decoder.decode(LedgerEntry.self, from: encoder.encode(entry)), entry)
        for change in [PendingChange.save(record.key), .delete(record.key)] {
            XCTAssertEqual(try decoder.decode(PendingChange.self, from: encoder.encode(change)), change)
        }
        for loss in [ZoneLoss.deleted, .purged, .encryptedDataReset] {
            XCTAssertEqual(try decoder.decode(ZoneLoss.self, from: encoder.encode(loss)), loss)
        }
    }

    // MARK: MemoryLocalStore

    private func task(_ name: String, _ fields: [String: SyncValue] = [:]) -> SyncRecord {
        SyncRecord(type: "TaskItem", name: name, fields: fields.merging(["title": .string(name)]) { a, _ in a })
    }

    private func key(_ type: String, _ name: String) -> SyncKey { SyncKey(type: type, name: name) }

    func testAStaleExpectedWritesNothingAndComesBack() async throws {
        let store = MemoryLocalStore([task("T1")])
        let held = try await store.records()[0]
        await store.edit(key("TaskItem", "T1"), ["notes": .string("typed meanwhile")])
        let stale = try await store.apply([
            LocalWrite(key: key("TaskItem", "T1"), expected: held, record: task("T1", ["title": .string("From iCloud")])),
            LocalWrite(key: key("TaskItem", "T2"), expected: nil, record: task("T2")),
        ])
        XCTAssertEqual(stale, [key("TaskItem", "T1")])
        let t1 = await store.record(key("TaskItem", "T1"))
        XCTAssertEqual(t1?["title"], .string("T1"))
        XCTAssertEqual(t1?["notes"], .string("typed meanwhile"))
        let t2 = await store.record(key("TaskItem", "T2"))
        XCTAssertNotNil(t2, "the other write went ahead")

        let exists = try await store.apply([LocalWrite(key: key("TaskItem", "T2"), expected: nil, record: nil)])
        XCTAssertEqual(exists, [key("TaskItem", "T2")], "expected absent, but it is here")
        let gone = try await store.apply([LocalWrite(key: key("TaskItem", "T9"), expected: task("T9"), record: nil)])
        XCTAssertEqual(gone, [key("TaskItem", "T9")], "expected here, but it is not")
    }

    func testExpectedComparesByDigestAndFilledFields() async throws {
        let store = MemoryLocalStore([SyncRecord(type: "Profile", name: "profile",
                                                 fields: ["avatarData": .data(Data([1, 2]))])])
        let held = try await store.records()[0]
        XCTAssertEqual(held["displayName"], .string(""), "required fields filled in")
        let stale = try await store.apply([LocalWrite(key: held.key, expected: held.comparable,
                                                      record: SyncRecord(type: "Profile", name: "profile"))])
        XCTAssertTrue(stale.isEmpty)
    }

    func testExpectedIsComparedAsTheMergeReadsIt() async throws {
        // `expected` is compared with `RecordMerge.same`: what the merge reads as the same record lets the write go
        // ahead (before, an exact comparison made a list in another order "changed meanwhile", for ever).
        let store = MemoryLocalStore([
            SyncRecord(type: "TaskLabel", name: "L1"), SyncRecord(type: "TaskLabel", name: "L2"),
            task("T", ["labels": .references(["L1", "L2"])]), task("U"), task("V", ["notes": .string("")]),
        ])
        var reordered = await store.record(key("TaskItem", "T"))!
        reordered["labels"] = .referenceList(["L2", "L1", "L2"])
        var emptyList = await store.record(key("TaskItem", "U"))!
        emptyList["labels"] = .referenceList([])
        var unfilled = await store.record(key("TaskItem", "V"))!
        unfilled["notes"] = nil
        unfilled["fieldFromANewerBuild"] = .int(1)
        let stale = try await store.apply([
            LocalWrite(key: key("TaskItem", "T"), expected: reordered, record: task("T", ["title": .string("T2")])),
            LocalWrite(key: key("TaskItem", "U"), expected: emptyList, record: task("U", ["title": .string("U2")])),
            LocalWrite(key: key("TaskItem", "V"), expected: unfilled, record: task("V", ["title": .string("V2")])),
        ])
        XCTAssertEqual(stale, [])
        for name in ["T", "U", "V"] {
            let record = await store.record(key("TaskItem", name))
            XCTAssertEqual(record?["title"], .string("\(name)2"))
        }

        var changed = await store.record(key("TaskItem", "T"))!
        changed["labels"] = .references(["L1"])
        let still = try await store.apply([LocalWrite(key: key("TaskItem", "T"), expected: changed, record: nil)])
        XCTAssertEqual(still, [key("TaskItem", "T")], "a label truly different is still a change meanwhile")
    }

    func testAReferenceToNothingIsWrittenAsNone() async throws {
        let store = MemoryLocalStore([SyncRecord(type: "TaskLabel", name: "L1")])
        _ = try await store.apply([LocalWrite(key: key("TaskItem", "T"), expected: nil, record: task("T", [
            "project": .reference("P-missing"), "labels": .references(["L1", "L-missing"]),
            "parent": .reference("T-missing"),
        ]))])
        let t = await store.record(key("TaskItem", "T"))
        XCTAssertNil(t?["project"])
        XCTAssertNil(t?["parent"])
        XCTAssertEqual(t?["labels"], .referenceList(["L1"]))
    }

    func testRecordsPointedAtInTheSameWriteAreKept() async throws {
        let store = MemoryLocalStore()
        _ = try await store.apply([
            LocalWrite(key: key("TaskItem", "C"), expected: nil, record: task("C", ["parent": .reference("P")])),
            LocalWrite(key: key("TaskItem", "P"), expected: nil, record: task("P", ["project": .reference("G")])),
            LocalWrite(key: key("Project", "G"), expected: nil, record: SyncRecord(type: "Project", name: "G")),
        ])
        let child = await store.record(key("TaskItem", "C"))
        let parent = await store.record(key("TaskItem", "P"))
        XCTAssertEqual(child?["parent"], .reference("P"))
        XCTAssertEqual(parent?["project"], .reference("G"))
    }

    func testDeletingATaskDeletesItsSubTasksAndAGroupClearsItsTasks() async throws {
        let store = MemoryLocalStore([
            SyncRecord(type: "Project", name: "G"),
            task("P", ["project": .reference("G")]),
            task("C1", ["parent": .reference("P")]), task("C2", ["parent": .reference("P")]),
            task("Other", ["project": .reference("G")]),
        ])
        _ = try await store.apply([LocalWrite(key: key("TaskItem", "P"), expected: await store.record(key("TaskItem", "P")),
                                              record: nil)])
        let count = await store.count
        XCTAssertEqual(count, 2, "the task and its sub-tasks are gone")
        await store.delete(key("Project", "G"))
        let other = await store.record(key("TaskItem", "Other"))
        XCTAssertNotNil(other)
        XCTAssertNil(other?["project"], "deleting a Group leaves its tasks in the Inbox")
    }

    func testDeletingATaskDeletesEveryLevelBelowIt() async throws {
        // The app keeps sub-tasks one level deep, but records from elsewhere may nest deeper, and SwiftData's
        // cascade deletes every level. Twenty grandchildren make any order of the store's walk show a straggler.
        var records = [task("A"), task("B", ["parent": .reference("A")])]
        for n in 0..<20 { records.append(task("C\(n)", ["parent": .reference("B")])) }
        let store = MemoryLocalStore(records)
        await store.delete(key("TaskItem", "A"))
        let left = try await store.records().map(\.key.name)
        XCTAssertEqual(left, [], "left behind: \(left)")
    }

    func testRecordsForSomeKeysLeavesOutWhatIsNotHere() async throws {
        let store = MemoryLocalStore([task("T1"), task("T2")])
        let some = try await store.records([key("TaskItem", "T2"), key("TaskItem", "T9")])
        XCTAssertEqual(some.map(\.key.name), ["T2"])
    }

    // MARK: MemoryLedger

    func testALedgerWriteIsAllOrNothing() async throws {
        let ledger = MemoryLedger()
        let k = key("TaskItem", "T")
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: k, base: task("T"), system: Data([1]))]
        write.deferUpsert = [CloudRecord(record: task("U"), system: Data([2]))]
        write.facts = [LedgerFact.firstFetchDone: Data([1])]
        await ledger.failNext()
        do {
            try await ledger.write(write)
            XCTFail("the write should have failed")
        } catch {}
        let entries = try await ledger.entries()
        let deferred = try await ledger.deferred()
        let fact = try await ledger.fact(LedgerFact.firstFetchDone)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(deferred.isEmpty)
        XCTAssertNil(fact)

        try await ledger.write(write)
        let after = try await ledger.entries()
        XCTAssertEqual(after.map(\.key), [k])
        var forget = LedgerWrite()
        forget.remove = [k]
        forget.deferRemove = [key("TaskItem", "U")]
        forget.facts = [LedgerFact.firstFetchDone: nil]
        XCTAssertFalse(forget.isEmpty)
        XCTAssertTrue(LedgerWrite().isEmpty)
        try await ledger.write(forget)
        let empty = try await ledger.entries()
        let noDeferred = try await ledger.deferred()
        let noFact = try await ledger.fact(LedgerFact.firstFetchDone)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(noDeferred.isEmpty)
        XCTAssertNil(noFact)
    }

    func testResetForgetsEverythingTheTransportsStateToo() async throws {
        let ledger = MemoryLedger()
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: key("TaskItem", "T"))]
        write.deferUpsert = [CloudRecord(record: task("U"), system: Data([2]))]
        write.facts = [LedgerFact.account: Data("acct".utf8)]
        try await ledger.write(write)
        await ledger.saveTransportState(Data([7]))
        let state = await ledger.loadTransportState()
        XCTAssertEqual(state, Data([7]))
        let viaFact = try await ledger.fact(LedgerFact.transport)
        XCTAssertEqual(viaFact, Data([7]), "the transport's state is one of the ledger's facts")

        try await ledger.reset()
        let entries = try await ledger.entries()
        let deferred = try await ledger.deferred()
        let account = try await ledger.fact(LedgerFact.account)
        let transport = await ledger.loadTransportState()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(deferred.isEmpty)
        XCTAssertNil(account)
        XCTAssertNil(transport)
    }
}
