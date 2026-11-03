import Foundation
import SwiftData

// MARK: - Schema rules (read before touching any @Model)
//
// The models sync to the Production CloudKit container `iCloud.com.trammells.hitlist`, whose schema
// is additive only, forever:
// - Never rename or delete a model or attribute. Never change an attribute's type.
// - New attributes must be optional or have a default value. New relationships must be optional.
// - No `@Attribute(.unique)`. No non-optional relationships.
// - Every model change: bump `HITListSchemaV<n>`, add a lightweight migration stage, push the new fields
//   to CloudKit Development, deploy the schema in the CloudKit dashboard, then release. The push, without
//   touching the real store (never open it under the Development environment):
//     xcodebuild build -project HITList.xcodeproj -scheme HITList -configuration Debug \
//       -destination 'platform=macOS' -derivedDataPath build/DerivedData-mac -allowProvisioningUpdates
//     HITLIST_STORE_SUFFIX=schema build/DerivedData-mac/Build/Products/Debug/HITList.app/Contents/MacOS/HITList -seedSampleData
//   then wait for "exporting succeeded" in `/usr/bin/log show --info --last 2m --predicate 'subsystem ==
//   "com.trammells.hitlist"'`, quit it, and deploy in the dashboard (done this way for V2 on 2026-10-31).
// - `scripts/release.sh` refuses to upload while the Development schema differs from Production
//   (needs a cktool management token; see the script header).
//
// How to add V4: move the live model classes in Models.swift from `extension HITListSchemaV3` to a new
// `extension HITListSchemaV4`, leaving a frozen copy of V3's stored properties behind (as
// SchemaV1Models.swift and SchemaV2Models.swift do), point the typealiases and `HITListSchema.current` at
// V4, append V4 to `HITListMigrationPlan.schemas` and add `.lightweight(fromVersion: HITListSchemaV3.self,
// toVersion: HITListSchemaV4.self)` to `stages`. (V3 was added this way on 2026-11-03.)
//
// `SchemaTests.testV1EntityHashesMatchShippedStore` pins V1's entity version hashes to the ones
// recorded in build 1's store metadata, so an accidental shape change fails the tests;
// `testV2OnlyAddsTaskItemAttributes` checks V2 against V1 the same way;
// `testV2EntityHashesMatchShippedBuilds` pins V2 and `testV3OnlyAddsTheSubtaskRelationship` checks V3.

/// Builds 1–4 (0.1.0) schema, frozen in SchemaV1Models.swift. SwiftData names the entities (and so the
/// CloudKit record types CD_TaskItem, CD_Project, CD_TaskLabel, CD_SavedFilter) after the bare class
/// name, so nesting the classes in these enums does not change the store or the CloudKit schema.
enum HITListSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskItem.self, Project.self, TaskLabel.self, SavedFilter.self]
    }
}

/// Builds 5–13 (0.1.0–0.4.0) schema, frozen in SchemaV2Models.swift. TaskItem gains `reminderOffsetMinutes`,
/// `deadline`, `locationName` (quick-add "+" options) and `flipTarget`, `flipCount`, `flipPeriodStart`
/// (Flipboard charging switches). All optional or defaulted, so the CloudKit change is additive and the
/// store migrates lightweight. Deploy the schema to Production in the CloudKit dashboard before build 5.
enum HITListSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskItem.self, Project.self, TaskLabel.self, SavedFilter.self]
    }
}

/// 0.4.1 schema: the live models in Models.swift. TaskItem gains subtasks, one level deep: `parent`
/// (to-one, nullify) and its inverse `subtasks` (to-many, cascade), both optional, so the CloudKit change
/// is additive (a `CD_parent` reference field on CD_TaskItem) and the store migrates lightweight. Deploy
/// the schema to Production in the CloudKit dashboard before 0.4.1 ships.
enum HITListSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskItem.self, Project.self, TaskLabel.self, SavedFilter.self]
    }
}

enum HITListMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HITListSchemaV1.self, HITListSchemaV2.self, HITListSchemaV3.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: HITListSchemaV1.self, toVersion: HITListSchemaV2.self),
         .lightweight(fromVersion: HITListSchemaV2.self, toVersion: HITListSchemaV3.self)]
    }
}
