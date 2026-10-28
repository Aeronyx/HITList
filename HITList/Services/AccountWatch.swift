import Foundation
import CloudKit

/// Remembers the iCloud account across launches, so a sign-out or a switch to another account can be
/// told apart from a device that never used iCloud.
///
/// On either change NSPersistentCloudKitContainer purges the local mirror and the lists go empty. The
/// records are untouched in iCloud and come back with the account. The app only explains this: it never
/// deletes anything on an account change, since a deletion would mirror to CloudKit and every device.
struct AccountWatch {
    enum Notice: Equatable { case signedOut, switched }

    let defaults: UserDefaults

    static let everSignedInKey = "sync.everSignedIn"
    static let recordNameKey = "sync.accountRecordName"
    static let lastStatusKey = "sync.lastAccountStatus"

    /// The last definite status seen, from this launch or an earlier one.
    var lastStatus: CKAccountStatus? {
        (defaults.object(forKey: Self.lastStatusKey) as? Int).flatMap(CKAccountStatus.init(rawValue:))
    }

    /// Records `status` and returns the notice to show next. `shown` is the notice on screen now;
    /// `signedOutDismissed` is whether the user closed the signed-out banner since the last sign-in.
    func update(status: CKAccountStatus, shown: Notice?, signedOutDismissed: Bool) -> Notice? {
        switch status {
        case .available:
            defaults.set(true, forKey: Self.everSignedInKey)
            defaults.set(status.rawValue, forKey: Self.lastStatusKey)
            return shown == .signedOut ? nil : shown
        case .noAccount:
            defaults.set(status.rawValue, forKey: Self.lastStatusKey)
            guard defaults.bool(forKey: Self.everSignedInKey), !signedOutDismissed else { return shown }
            return .signedOut
        case .restricted:
            defaults.set(status.rawValue, forKey: Self.lastStatusKey)
            return shown
        default:
            return shown  // couldNotDetermine / temporarilyUnavailable say nothing about which account
        }
    }

    /// Records the signed-in account's user record name and returns the notice to show next.
    func update(userRecordName name: String, shown: Notice?) -> Notice? {
        let previous = defaults.string(forKey: Self.recordNameKey)
        defaults.set(name, forKey: Self.recordNameKey)
        if let previous, previous != name { return .switched }
        return shown
    }
}
