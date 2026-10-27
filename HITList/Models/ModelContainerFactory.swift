import Foundation
import SwiftData

enum ModelContainerFactory {
    /// Whether the running container is syncing through CloudKit.
    nonisolated(unsafe) static var isCloudKitEnabled = false
    nonisolated(unsafe) static var startupError: String? = nil

    /// Builds the CloudKit-backed container, falling back to local-only storage if CloudKit
    /// can't be set up (not signed in to iCloud, missing entitlement during development, ...).
    static func make() -> ModelContainer {
        let schema = Schema(HITListSchema.models)
        let disableCloud = UserDefaults.standard.bool(forKey: "disableCloudKit")
        if !disableCloud {
            let cloud = ModelConfiguration("HITList", schema: schema,
                                           cloudKitDatabase: .private(HITListSchema.cloudKitContainerID))
            do {
                let container = try ModelContainer(for: schema, configurations: [cloud])
                isCloudKitEnabled = true
                return container
            } catch {
                startupError = "iCloud sync unavailable: \(error.localizedDescription)"
            }
        }
        let local = ModelConfiguration("HITList", schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Could not create local store: \(error)")
        }
    }

    static func preview() -> ModelContainer {
        let schema = Schema(HITListSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
