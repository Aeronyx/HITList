import Foundation
import HITListCore

/// Which store's outbox this build writes: the real store's in Release. A Debug build made with
/// `HITLIST_WIDGET_SUFFIX=<name>` (project.yml) writes that side store's, as its widgets read that store's snapshot; a
/// Debug build without one writes the Development store's, the one a Debug app opens (`SyncStoreGuard`), so a share
/// from a build run in Xcode never reaches the TestFlight app's store.
enum ShareStore {
    static var suffix: String? {
        #if DEBUG
        let baked = Bundle.main.object(forInfoDictionaryKey: "HITListWidgetSuffix") as? String ?? ""
        return baked.isEmpty ? "Development" : baked
        #else
        return nil
        #endif
    }

    /// What the app last wrote for the sheet; nil before it first has.
    static func context() -> ShareContext? {
        ShareRoad.contextURL(suffix: suffix).flatMap(ShareContext.load(from:))
    }
}
