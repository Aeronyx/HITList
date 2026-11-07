import Foundation
import SwiftData

/// What a `cktool export-schema` file says against what the models need. Pure, so tests pin it; `release.sh`
/// hands the Production export to `CloudKitSchemaTests` through the preflight (`TEST_RUNNER_HITLIST_CLOUDKIT_SCHEMA`).
///
/// Why this exists: the drift check in `release.sh` compares Development with Production and is blind to a field
/// that neither has. Development learns a field only when a Development build exports a record carrying it, and
/// sessions run with sync off, so `TaskItem.deadline`, `locationName` and `flipPeriodStart` (0.4.0) reached neither
/// environment for a week. Production rejects a record with a field it lacks, and the mirroring retries that record
/// first, so the first flip of a switch stopped a friend's Mac exporting for the rest of his session (2026-11-06).
enum CloudKitSchemaCheck {
    /// Record types and their field names, read from the text of a `.ckdb` export: `RECORD TYPE CD_TaskItem (`
    /// opens one, each line inside names a field (system fields start with `___`, grants with `GRANT`), `)` closes it.
    static func recordTypes(in export: String) -> [String: Set<String>] {
        var types: [String: Set<String>] = [:]
        var current: String?
        for rawLine in export.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("RECORD TYPE ") {
                let rest = line.dropFirst("RECORD TYPE ".count)
                var name = rest.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
                if name.hasSuffix("(") { name.removeLast() }
                current = unquoted(name)
                types[unquoted(name)] = []
            } else if line.hasPrefix(")") {
                current = nil
            } else if let type = current, let first = line.split(separator: " ").first {
                let field = unquoted(String(first))
                guard !field.isEmpty, !field.hasPrefix("___"), field != "GRANT" else { continue }
                types[type, default: []].insert(field)
            }
        }
        return types
    }

    private static func unquoted(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// The record types and fields the models mirror to: `CD_<Entity>`, with `CD_<attribute>` for each attribute and
    /// `CD_<relationship>` for each to-one relationship (it holds a record name). To-many relationships go through
    /// `CDMR` records and have no field of their own.
    static func requiredFields(for schema: Schema) -> [String: Set<String>] {
        var required: [String: Set<String>] = [:]
        for entity in schema.entities {
            var fields = Set(entity.attributes.map { "CD_\($0.name)" })
            for relationship in entity.relationships where relationship.isToOneRelationship {
                fields.insert("CD_\(relationship.name)")
            }
            required["CD_\(entity.name)"] = fields
        }
        return required
    }

    /// "CD_TaskItem.CD_deadline" for each required field `exported` lacks, sorted; empty when the export has them all.
    static func missingFields(in exported: [String: Set<String>], for schema: Schema) -> [String] {
        requiredFields(for: schema).flatMap { type, fields in
            fields.subtracting(exported[type] ?? []).map { "\(type).\($0)" }
        }.sorted()
    }
}
