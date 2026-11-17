import Foundation

/// The few things only the app can do for the engine's brain (`SyncCore`), and what the app hears from it.
///
/// The three notices (`didWrite`, `didAccept`, `statusDidChange`) are called on the brain's own executor while it
/// works, in order: they must return at once (hand the work to the main actor, post a notification) and never wait
/// for the brain, which is busy until they return. `willRemoveLocalData` is awaited, and is the one place the brain
/// waits for the app: it must not call the brain either.
public protocol SyncHost: AnyObject, Sendable {
    /// Called before anything of the person's is removed from the device (a sign-out, another account, a purge
    /// answered "remove here too"): write a backup. Throw, and nothing is removed: the brain stays held and says
    /// why.
    func willRemoveLocalData(reason: SyncRemovalReason) async throws

    /// The same, with the accounts the device leaves and joins (`previous`, `current`: the transport's account ids;
    /// nil when not known): the one call the brain makes. At an account switch the host also sets the previous
    /// account's backups aside, after its own backup and before anything is removed, so the one order is the brain's
    /// (brief 160, review 147 F6). The default writes the backup alone.
    func willRemoveLocalData(reason: SyncRemovalReason, switchingFrom previous: String?, to current: String?) async throws

    /// Items a fetch (or a conflict settled after a send) wrote to the device: what the mirror's import used to
    /// trigger (the name deduplication, reminders, widgets, Spotlight) runs for these. Deleted items among them.
    func didWrite(_ keys: Set<SyncKey>)

    /// Records iCloud accepted from this device (saved or removed for good).
    func didAccept(_ keys: Set<SyncKey>)

    /// Every change of `SyncStatus`, the first one included.
    func statusDidChange(_ status: SyncStatus)
}

public extension SyncHost {
    func willRemoveLocalData(reason: SyncRemovalReason, switchingFrom previous: String?, to current: String?) async throws {
        try await willRemoveLocalData(reason: reason)
    }
}
