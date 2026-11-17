import Foundation
import SwiftData

/// The model container App Intents write through (brief 46).
///
/// HITList's intents run inside the app's own process (there is no extension): Siri or Shortcuts launch the
/// app in the background when it isn't running, `HITListApp.init` builds its one container exactly as on a
/// normal launch (`ModelContainerFactory.make()`: the App Group store, CloudKit mirroring, the stuck-sync and
/// Development-store guards) and registers it here. Intents use that container's main context, the same one
/// the lists draw from, so a task added by Siri shows at once and mirrors to iCloud like one added on the
/// card. They never open a second container on the store.
@MainActor
enum IntentStore {
    private(set) static var container: ModelContainer?

    /// Also starts Spotlight indexing on the same container (`SpotlightSync`, brief 52), which does nothing
    /// under tests or on a side store.
    static func register(_ container: ModelContainer) {
        self.container = container
        SpotlightSync.shared.start(container: container)
    }

    /// The app's main context, or `IntentFailure.appNotReady` if the app has not built its container. On the
    /// in-memory fallback (the store couldn't be opened) `IntentFailure.notSaving`: a task Siri "added" there would be
    /// gone when the app quits, and the person would never know (round 32, brief 157; the data review's B10).
    static func context(inMemory: Bool = ModelContainerFactory.isRunningInMemory) throws -> ModelContext {
        guard let container else { throw IntentFailure.appNotReady }
        guard !inMemory else { throw IntentFailure.notSaving }
        return container.mainContext
    }

    /// Tests only: forget the registered container.
    static func reset() { container = nil }
}

/// Why an intent could not do what was asked, in words Siri can say.
enum IntentFailure: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case appNotReady
    /// The app is running without its store (`ModelContainerFactory.isRunningInMemory`): nothing would be kept.
    case notSaving
    case emptyTitle
    case groupNotFound
    case taskNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: "HITList isn’t ready yet. Open it once and try again."
        case .notSaving: "HITList couldn’t open your tasks, so nothing would be saved. Open HITList to see why."
        case .emptyTitle: "That task has no name."
        case .groupNotFound: "That Group isn’t in HITList any more."
        case .taskNotFound: "That task isn’t in HITList any more."
        }
    }
}
