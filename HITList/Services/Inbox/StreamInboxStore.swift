import Foundation
import Security

/// Where a device keeps its connection to the Stream ring's relay (brief 176). The inbox key lives in the Keychain, on
/// this device only and readable after the first unlock (never in a backup or iCloud Keychain): each device connects on
/// its own. The relay's address, the "starts with Task" rule, the device's own id and what this device has added live in
/// `AppGroup.defaults` (`StreamInboxSettings`); a side store keeps all of it apart from the real store's.
protocol StreamInboxKeyStore: AnyObject {
    func read() -> StreamInboxKeyRead
    func save(_ key: String) throws
    func remove()
}

/// What reading the key gave. Only `notFound` means the key isn't on this device; `unavailable` (the Keychain locked
/// before the first unlock after a restart, or any other status) means "not now" (review, finding 9).
enum StreamInboxKeyRead: Equatable {
    case found(String)
    case notFound
    case unavailable(OSStatus)

    init(status: OSStatus, data: Data?) {
        switch status {
        case errSecSuccess:
            if let data, let key = String(data: data, encoding: .utf8) { self = .found(key) } else { self = .notFound }
        case errSecItemNotFound:
            self = .notFound
        default:
            self = .unavailable(status)
        }
    }
}

/// The inbox key as a generic password named for this launch's store, so a Debug side store never reads or replaces
/// the real store's key. On the Mac in the data-protection keychain, as on iOS, so `ThisDeviceOnly` holds and no
/// keychain prompt ever asks about a rebuilt app.
final class KeychainInboxKey: StreamInboxKeyStore {
    static let service = "com.trammells.hitlist.stream-inbox"
    let account: String

    init(account: String = ModelContainerFactory.storeName) {
        self.account = account
    }

    struct Failure: Error, Equatable {
        let status: OSStatus
    }

    private var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    func read() -> StreamInboxKeyRead {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return StreamInboxKeyRead(status: status, data: item as? Data)
    }

    func save(_ key: String) throws {
        remove()
        var query = query
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrLabel as String] = "HITList Stream ring inbox"
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func remove() {
        SecItemDelete(query as CFDictionary)
    }
}

/// A key held in memory: the hosted tests, and Debug's pretend relay (`-streamInboxDemo YES`).
final class MemoryInboxKey: StreamInboxKeyStore {
    private var key: String?

    init(_ key: String? = nil) {
        self.key = key
    }

    func read() -> StreamInboxKeyRead { key.map(StreamInboxKeyRead.found) ?? .notFound }
    func save(_ key: String) throws { self.key = key }
    func remove() { key = nil }
}

/// The inbox's settings and its memory of what this device handled.
struct StreamInboxSettings {
    let defaults: UserDefaults

    static let originKey = "streamInbox.origin"
    static let onlyStartingWithTaskKey = "streamInbox.onlyStartingWithTask"
    static let deviceKey = "streamInbox.deviceID"
    /// The last `addedLimit` capture ids this device made tasks of: one is never added twice here.
    static let addedKey = "streamInbox.addedIDs"
    /// Ids handled (added or left by the rule) whose ack hasn't reached the relay yet: sent first next time.
    static let unackedKey = "streamInbox.unackedIDs"
    static let lastCheckedKey = "streamInbox.lastCheckedAt"
    static let lastCaptureKey = "streamInbox.lastCaptureAt"
    static let addedDayKey = "streamInbox.addedDay"
    static let addedCountKey = "streamInbox.addedCount"
    /// The capture being added right now, written before its save (review, finding 5).
    static let addingKey = "streamInbox.addingNow"
    /// This device's push token, in hex, for the relay's wake-ups.
    static let pushTokenKey = "streamInbox.pushToken"
    /// Ids whose ack iOS is delivering as a background upload (round 3, finding 4).
    static let ackSendingKey = "streamInbox.ackSending"

    static let addedLimit = 500

    /// A capture whose task is being saved: if the app is killed between the save and the id being written down, the
    /// next check finds the task by its title and time instead of adding it again.
    struct Adding: Codable, Equatable {
        let id: String
        let title: String
        let startedAt: Date

        /// The task this note stands for: its title, made from a moment before the save to a few minutes after.
        func couldHaveMade(title: String, createdAt: Date) -> Bool {
            title == self.title && createdAt >= startedAt.addingTimeInterval(-5) && createdAt <= startedAt.addingTimeInterval(300)
        }
    }

    var addingNow: Adding? {
        get { defaults.data(forKey: Self.addingKey).flatMap { try? JSONDecoder().decode(Adding.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.addingKey) }
    }

    var pushToken: String? {
        get { defaults.string(forKey: Self.pushTokenKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.pushTokenKey) }
    }

    var origin: String? {
        get { defaults.string(forKey: Self.originKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.originKey) }
    }

    var onlyStartingWithTask: Bool {
        get { defaults.bool(forKey: Self.onlyStartingWithTaskKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.onlyStartingWithTaskKey) }
    }

    /// This device's id for the relay's claims: made once, "Mac-1A2B3C4D".
    func deviceID(platform: String) -> String {
        if let id = defaults.string(forKey: Self.deviceKey), !id.isEmpty { return id }
        let id = "\(platform)-\(UUID().uuidString.prefix(8))"
        defaults.set(id, forKey: Self.deviceKey)
        return id
    }

    var addedIDs: [String] {
        get { defaults.stringArray(forKey: Self.addedKey) ?? [] }
        nonmutating set { defaults.set(Array(newValue.suffix(Self.addedLimit)), forKey: Self.addedKey) }
    }

    var unackedIDs: [String] {
        get { defaults.stringArray(forKey: Self.unackedKey) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Self.unackedKey) }
    }

    var ackSending: [String] {
        get { defaults.stringArray(forKey: Self.ackSendingKey) ?? [] }
        nonmutating set { defaults.set(Array(newValue.suffix(Self.addedLimit)), forKey: Self.ackSendingKey) }
    }

    /// A background ack finished: delivered, its ids leave `unackedIDs` (exactly those: ids handled since stay); either
    /// way they are no longer in flight, so a later failure hands them to iOS again.
    func ackFinished(_ ids: [String], delivered: Bool) {
        let done = Set(ids)
        ackSending = ackSending.filter { !done.contains($0) }
        if delivered { unackedIDs = unackedIDs.filter { !done.contains($0) } }
    }

    var lastCheckedAt: Date? {
        get { defaults.object(forKey: Self.lastCheckedKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastCheckedKey) }
    }

    var lastCaptureAt: Date? {
        get { defaults.object(forKey: Self.lastCaptureKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastCaptureKey) }
    }

    /// How many tasks this device made from captures on `now`'s day.
    func addedToday(now: Date, calendar: Calendar = .current) -> Int {
        defaults.string(forKey: Self.addedDayKey) == Self.day(now, calendar) ? defaults.integer(forKey: Self.addedCountKey) : 0
    }

    func countAdded(_ count: Int, now: Date, calendar: Calendar = .current) {
        guard count > 0 else { return }
        let today = Self.day(now, calendar)
        let before = addedToday(now: now, calendar: calendar)
        defaults.set(today, forKey: Self.addedDayKey)
        defaults.set(before + count, forKey: Self.addedCountKey)
    }

    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
