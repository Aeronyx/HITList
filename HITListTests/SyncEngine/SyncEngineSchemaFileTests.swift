import XCTest
import HITListCore
@testable import HITList

/// The engine's CloudKit schema as a file in the repository (`dev/cloudkit/sync-engine.ckdb`, round 32): what
/// `xcrun cktool import-schema` puts into the engine's container's Development side before George deploys it to
/// Production, and what `scripts/release.sh` checks Production against. Schema as code, so that Production gets
/// exactly what the engine sends and nothing a test run left behind (the transport's probe writes a field of its own
/// into Development on purpose), and no index nobody asked for: the engine never queries, it fetches a zone's
/// changes; `recordName` alone is queryable, so the CloudKit Console can list records.
///
/// This test pins the file to `SyncSchema`: a field added to the schema without the file fails here, with the text
/// the file should hold. One type beside the engine's is pinned too: `HLRollout` (`rolloutBlock`, round 34).
final class SyncEngineSchemaFileTests: XCTestCase {
    static var fileURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dev/cloudkit/sync-engine.ckdb")
    }

    /// CloudKit's type for a field's kind. A bool is an INT64 (0 or 1), a reference is the other record's name.
    static func cloudType(_ kind: SyncField.Kind) -> String {
        switch kind {
        case .string, .reference: "STRING"
        case .int, .bool: "INT64"
        case .date: "TIMESTAMP"
        case .data(let asset): asset ? "ASSET" : "BYTES"
        case .references: "LIST<STRING>"
        }
    }

    /// The file's text: the format `cktool export-schema` writes, record types and fields in name order.
    static func expectedText() -> String {
        let system: [(String, String)] = [
            ("\"___createTime\"", "TIMESTAMP"), ("\"___createdBy\"", "REFERENCE"), ("\"___etag\"", "STRING"),
            ("\"___modTime\"", "TIMESTAMP"), ("\"___modifiedBy\"", "REFERENCE"), ("\"___recordID\"", "REFERENCE QUERYABLE"),
        ]
        // The file's one role (round 34, brief 170): the only one that may create or write the rollout's word.
        var out = "DEFINE SCHEMA\n\n    CREATE ROLE \(SyncEngineRollout.adminRole);\n"
        let types = ([SyncSchema.metaType] + SyncSchema.types.map(\.name)).sorted()
        var rolloutWritten = false
        for type in types {
            if !rolloutWritten, CloudRecordCodec.recordType(for: type) > SyncEngineRollout.recordType {
                out += rolloutBlock(system: system)
                rolloutWritten = true
            }
            var fields = (CloudRecordCodec.fields(ofType: type) ?? []).map { ($0.key, cloudType($0.kind)) }
            fields.append((SyncSchema.deletedAt, "TIMESTAMP"))
            fields.sort { $0.0 < $1.0 }
            let rows = system + fields
            let width = rows.map(\.0.count).max() ?? 0
            out += "\n    RECORD TYPE \(CloudRecordCodec.recordType(for: type)) (\n"
            for (name, kind) in rows {
                out += "        \(name.padding(toLength: width, withPad: " ", startingAt: 0)) \(kind),\n"
            }
            out += "        GRANT WRITE TO \"_creator\",\n        GRANT CREATE TO \"_icloud\",\n        GRANT READ TO \"_world\"\n    );\n"
        }
        if !rolloutWritten { out += rolloutBlock(system: system) }
        // CloudKit's own type, as every export carries it.
        out += """

            RECORD TYPE Users (
                "___createTime" TIMESTAMP,
                "___createdBy"  REFERENCE,
                "___etag"       STRING,
                "___modTime"    TIMESTAMP,
                "___modifiedBy" REFERENCE,
                "___recordID"   REFERENCE,
                roles           LIST<INT64>,
                GRANT WRITE TO "_creator",
                GRANT READ TO "_world"
            );

        """
        return out
    }

    /// One type beside the engine's (round 34, brief 170): `HLRollout`, George's word that lets every device move
    /// (`SyncEngineRollout`). It lives in the same container's **public** database and is never synced, so it is not
    /// in `SyncSchema`: it is pinned here from `SyncEngineRollout`'s own names instead, grants included. Readable by
    /// the world; created and written only by the custom role (no `_icloud` CREATE, no `_creator` WRITE: no tester can
    /// make, change or delete it). It sits in name order among the engine's types, as an export lists them.
    static func rolloutBlock(system: [(String, String)]) -> String {
        let rows = system + [(SyncEngineRollout.minBuildField, "INT64"), (SyncEngineRollout.pausedField, "INT64")]
        let width = rows.map(\.0.count).max() ?? 0
        var out = "\n    RECORD TYPE \(SyncEngineRollout.recordType) (\n"
        for (name, kind) in rows {
            out += "        \(name.padding(toLength: width, withPad: " ", startingAt: 0)) \(kind),\n"
        }
        out += "        GRANT READ TO \"_world\",\n        GRANT WRITE, CREATE, READ TO \(SyncEngineRollout.adminRole)\n    );\n"
        return out
    }

    /// The rollout's type is not one the engine syncs, and the engine cannot take it for one of its own.
    func testTheRolloutTypeIsNotAnEngineType() {
        XCTAssertFalse(SyncSchema.types.map { CloudRecordCodec.recordType(for: $0.name) }.contains(SyncEngineRollout.recordType))
        XCTAssertNotEqual(CloudRecordCodec.recordType(for: SyncSchema.metaType), SyncEngineRollout.recordType)
        // The codec reads any well-formed `HL…` name as a type (a newer build's, kept as it is): "Rollout" is not one of
        // the engine's, and it lives in the public database, which the engine never reads.
        let asType = CloudRecordCodec.type(forRecordType: SyncEngineRollout.recordType)
        XCTAssertFalse(SyncSchema.types.map(\.name).contains(asType ?? ""))
        XCTAssertNotEqual(asType, SyncSchema.metaType)
    }

    func testTheSchemaFileIsExactlyWhatTheEngineSends() throws {
        let expected = Self.expectedText()
        guard let found = try? String(contentsOf: Self.fileURL, encoding: .utf8) else {
            // The simulator and CI's checkout both reach the file; a sandbox that cannot is no failure of the schema.
            throw XCTSkip("dev/cloudkit/sync-engine.ckdb is out of this process's reach")
        }
        if found != expected { print("HLSCHEMA-BEGIN\n\(expected)HLSCHEMA-END") }
        XCTAssertEqual(found, expected, """
            dev/cloudkit/sync-engine.ckdb is not what SyncSchema sends. Replace it with the text printed between \
            HLSCHEMA-BEGIN and HLSCHEMA-END, then follow scripts/release.sh's three steps (reset the engine's \
            Development side, import the file, deploy to Production) before the release that sends the new field.
            """)
    }

    /// Additive forever: every field kind the schema uses has a CloudKit type, and no two fields of a type share a
    /// name whatever their case (CloudKit's field names are case-sensitive; a pair that differs only in case would
    /// be a trap for the next reader).
    func testEveryTypeHasDistinctFieldNames() {
        for type in SyncSchema.types {
            let names = type.fields.map { $0.key.lowercased() } + [SyncSchema.deletedAt.lowercased()]
            XCTAssertEqual(Set(names).count, names.count, type.name)
        }
    }
}
