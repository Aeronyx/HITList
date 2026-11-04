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

    static func register(_ container: ModelContainer) {
        self.container = container
    }

    /// The app's main context, or `IntentFailure.appNotReady` if the app has not built its container.
    static func context() throws -> ModelContext {
        guard let container else { throw IntentFailure.appNotReady }
        return container.mainContext
    }

    /// Tests only: forget the registered container.
    static func reset() { container = nil }
}

/// Why an intent could not do what was asked, in words Siri can say.
enum IntentFailure: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case emptyTitle
    case groupNotFound
    case taskNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: "HITList isn’t ready yet. Open it once and try again."
        case .emptyTitle: "That task has no name."
        case .groupNotFound: "That Group isn’t in HITList any more."
        case .taskNotFound: "That task isn’t in HITList any more."
        }
    }
}
