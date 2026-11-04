import Foundation
import CloudKit
import CryptoKit

/// Remembers the iCloud account across launches, so a sign-out or a switch to another account can be
/// told apart from a device that never used iCloud.
///
/// On either change NSPersistentCloudKitContainer purges the local mirror and the lists go empty. The
/// records are untouched in iCloud and come back with the account. The app never deletes anything in
/// iCloud on an account change, since a deletion would mirror to CloudKit and every device; what it
/// clears is local only (`AccountSwitch`).
///
/// The account is remembered as `AccountIdentity.key`, a one-way hash of the CloudKit user record name,
/// never the record name itself. Each store remembers its own (the TestFlight build's HITList.store keeps
/// the plain key; a Debug build's HITList-Development.store its own), so whichever build notices a switch
/// first doesn't hide it from the other, whose drafts and reminders still need clearing.
struct AccountWatch {
    enum Notice: Equatable { case signedOut, switched }

    let defaults: UserDefaults
    /// The store this launch opened: its account memory is its own.
    var storeName: String = ModelContainerFactory.storeName

    static let everSignedInKey = "sync.everSignedIn"
    static let recordNameKey = "sync.accountRecordName"
    static let lastStatusKey = "sync.lastAccountStatus"

    /// `recordNameKey` for this store. The real store keeps the plain key, as the sync times do.
    var accountKeyName: String { CloudSyncMonitor.syncTimeKey(Self.recordNameKey, storeName: storeName) }

    /// The last definite status seen, from this launch or an earlier one.
    var lastStatus: CKAccountStatus? {
        (defaults.object(forKey: Self.lastStatusKey) as? Int).flatMap(CKAccountStatus.init(rawValue:))
    }

    /// The hashed account last seen with this store; nil before the first. A raw record name written by
    /// builds up to 0.5.0 is read as its hash.
    var lastAccount: String? {
        defaults.string(forKey: accountKeyName).map(AccountIdentity.key(forStored:))
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

    /// What `identify` found: this account's key, the one remembered before it (nil the first time), and
    /// whether they differ.
    struct Identity: Equatable {
        var account: String
        var previous: String?
        var isSwitch: Bool { previous.map { $0 != account } ?? false }
    }

    /// Remembers the signed-in account (hashed) and says whether it differs from the last one seen.
    func identify(userRecordName name: String) -> Identity {
        let previous = lastAccount
        let account = AccountIdentity.key(recordName: name)
        defaults.set(account, forKey: accountKeyName)
        return Identity(account: account, previous: previous)
    }

    /// Records the signed-in account's user record name and returns the notice to show next.
    func update(userRecordName name: String, shown: Notice?) -> Notice? {
        identify(userRecordName: name).isSwitch ? .switched : shown
    }
}

/// The iCloud account as HITList keeps it: a salted SHA-256 of the CloudKit user record name, so nothing
/// stored or logged can be traced back to the Apple account, while the same account always gives the
/// same key. "acct1:" + 32 hex digits.
enum AccountIdentity {
    static let prefix = "acct1:"

    static func key(recordName: String) -> String {
        let digest = SHA256.hash(data: Data("HITList account \(recordName)".utf8))
        return prefix + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func isKey(_ value: String) -> Bool { value.hasPrefix(prefix) }

    /// A stored value as a key: builds up to 0.5.0 stored the raw record name.
    static func key(forStored value: String) -> String {
        isKey(value) ? value : key(recordName: value)
    }
}
