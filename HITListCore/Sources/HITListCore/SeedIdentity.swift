import Foundation
import CryptoKit

/// Stable identifiers for records the app creates on its own (default filters, ...), so every device
/// seeds the same `id` and duplicates from devices that seeded before their first CloudKit import
/// can be recognised by `id` rather than only by name.
public enum SeedIdentity {
    /// Fixed namespace for HITList seeds. Never change it: the ids derived from it live in CloudKit.
    public static let namespace = UUID(uuidString: "6B1F3E2A-9C4D-4E5F-8A7B-1D2C3E4F5A6B")!

    /// RFC 4122 version 5 (SHA-1, name-based) UUID of `name` in `namespace`.
    public static func uuid(for name: String, in namespace: UUID = SeedIdentity.namespace) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Id of a default saved filter, keyed by its seed key (not its display name, which the user may edit).
    public static func savedFilter(_ key: String) -> UUID { uuid(for: "SavedFilter/\(key)") }
}
