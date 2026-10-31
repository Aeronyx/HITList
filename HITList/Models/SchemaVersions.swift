import Foundation
import SwiftData

// MARK: - Schema rules (read before touching any @Model)
//
// The models sync to the Production CloudKit container `iCloud.com.trammells.hitlist`, whose schema
// is additive only, forever:
// - Never rename or delete a model or attribute. Never change an attribute's type.
// - New attributes must be optional or have a default value. New relationships must be optional.
// - No `@Attribute(.unique)`. No non-optional relationships.
// - Every model change: bump `HITListSchemaV<n>`, add a lightweight migration stage, run the app once
//   against Development, deploy the schema in the CloudKit dashboard, then release.
// - `scripts/release.sh` refuses to upload while the Development schema differs from Production
//   (needs a cktool management token; see the script header).
//
// How to add V3: move the live model classes in Models.swift from `extension HITListSchemaV2` to a new
// `extension HITListSchemaV3`, leaving a frozen copy of V2's stored properties behind (as
// SchemaV1Models.swift does for V1), point the typealiases and `HITListSchema.current` at V3, append V3
// to `HITListMigrationPlan.schemas` and add `.lightweight(fromVersion: HITListSchemaV2.self,
// toVersion: HITListSchemaV3.self)` to `stages`.
//
// `SchemaTests.testV1EntityHashesMatchShippedStore` pins V1's entity version hashes to the ones
// recorded in build 1's store metadata, so an accidental shape change fails the tests;
// `testV2OnlyAddsTaskItemAttributes` checks V2 against V1 the same way.

/// Builds 1–4 (0.1.0) schema, frozen in SchemaV1Models.swift. SwiftData names the entities (and so the
/// CloudKit record types CD_TaskItem, CD_Project, CD_TaskLabel, CD_SavedFilter) after the bare class
/// name, so nesting the classes in these enums does not change the store or the CloudKit schema.
enum HITListSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskItem.self, Project.self, TaskLabel.self, SavedFilter.self]
    }
}

/// Build 5 (0.1.0) schema: the live models in Models.swift. TaskItem gains `reminderOffsetMinutes`,
/// `deadline`, `locationName` (quick-add "+" options) and `flipTarget`, `flipCount`, `flipPeriodStart`
/// (Flipboard charging switches). All optional or defaulted, so the CloudKit change is additive and the
/// store migrates lightweight. Deploy the schema to Production in the CloudKit dashboard before build 5.
enum HITListSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskItem.self, Project.self, TaskLabel.self, SavedFilter.self]
    }
}

enum HITListMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HITListSchemaV1.self, HITListSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: HITListSchemaV1.self, toVersion: HITListSchemaV2.self)]
    }
}
