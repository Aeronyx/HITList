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
// How to add V2: copy the V1 model classes into `enum HITListSchemaV2: VersionedSchema` with the
// change applied, point the top-level typealiases in Models.swift at V2, append V2 to
// `HITListMigrationPlan.schemas` and add `.lightweight(fromVersion: HITListSchemaV1.self,
// toVersion: HITListSchemaV2.self)` to `stages`. V1 stays frozen as the shape of build 1's stores.
//
// `SchemaTests.testV1EntityHashesMatchShippedStore` pins V1's entity version hashes to the ones
// recorded in build 1's store metadata, so an accidental shape change fails the tests.

/// Build 1 (0.1.0) schema. The model classes are declared in Models.swift as extensions of this enum
/// and exposed under their plain names through typealiases; SwiftData names the entities (and so the
/// CloudKit record types CD_TaskItem, CD_Project, CD_TaskLabel, CD_SavedFilter) after the bare class
/// name, so nesting them here does not change the store or the CloudKit schema.
enum HITListSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskItem.self, Project.self, TaskLabel.self, SavedFilter.self]
    }
}

enum HITListMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HITListSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
