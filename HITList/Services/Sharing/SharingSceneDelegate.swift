#if os(iOS)
import UIKit
import CloudKit
import OSLog

/// The iOS scene delegate class (brief 51), for one thing: CloudKit share acceptance, which iOS delivers only to a
/// scene delegate since the app-delegate method was deprecated (iOS 26). `SyncAppDelegate` names this class in each
/// window scene's configuration; SwiftUI keeps managing the window and forwards the scene callbacks it doesn't use
/// itself. Nothing else lives here.
final class SharingSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// A cold launch from an invitation link: the metadata comes with the connection.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        let metadata = connectionOptions.cloudKitShareMetadata
        Logger(subsystem: "com.trammells.hitlist", category: "sharing")
            .info("Shared Tasks: scene connected\(metadata != nil ? " with an invitation" : "", privacy: .public)")
        Task { @MainActor in
            SharedTasksCenter.shared.startIfOn()
            if let metadata { SharedTasksCenter.shared.userAccepted(metadata) }
        }
    }

    /// An invitation link opened while the app runs.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        SharedTasksCenter.shared.userAccepted(cloudKitShareMetadata)
    }
}
#endif
