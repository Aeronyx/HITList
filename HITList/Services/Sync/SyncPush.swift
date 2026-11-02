import Foundation
import CloudKit

/// What a remote notification says, for the sync log: whether it is CloudKit's, which subscription,
/// zone and database scope, the container and its environment. Built from the push's userInfo: the
/// typed `CKNotification` where CloudKit can parse it, and the raw `ck` dictionary for what it doesn't
/// expose (the container environment, `ce`).
struct SyncPush: Equatable, Sendable {
    var isCloudKit: Bool
    /// "database", "recordZone", "query", "readNotification", or "unknown".
    var type: String
    var subscriptionID: String?
    var zone: String?
    /// "private", "shared" or "public".
    var databaseScope: String?
    var container: String?
    /// CloudKit's container-environment code from the payload (`ck.ce`), as sent.
    var environmentCode: String?
    var notificationID: String?
    var isPruned = false

    init(userInfo: [AnyHashable: Any]) {
        let ck = userInfo["ck"] as? [String: Any]
        isCloudKit = ck != nil
        type = "unknown"
        container = ck?["cid"] as? String
        environmentCode = (ck?["ce"]).map { "\($0)" }
        notificationID = ck?["nid"] as? String
        // A database change ("met"), a zone fetch ("fet") or a query ("qry"); each names the subscription.
        let body = (ck?["met"] ?? ck?["fet"] ?? ck?["qry"]) as? [String: Any]
        subscriptionID = body?["sid"] as? String
        zone = body?["zid"] as? String
        databaseScope = (body?["dbs"] as? Int).flatMap(Self.scopeName(rawValue:))
        if ck?["met"] != nil { type = "database" } else if ck?["fet"] != nil { type = "recordZone" } else if ck?["qry"] != nil { type = "query" }

        guard isCloudKit, let note = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return }
        type = Self.typeName(note.notificationType)
        container = note.containerIdentifier ?? container
        subscriptionID = note.subscriptionID ?? subscriptionID
        isPruned = note.isPruned
        if let database = note as? CKDatabaseNotification {
            databaseScope = Self.scopeName(database.databaseScope)
        } else if let zoneNote = note as? CKRecordZoneNotification {
            databaseScope = Self.scopeName(zoneNote.databaseScope)
            zone = zoneNote.recordZoneID?.zoneName ?? zone
        }
    }

    /// "CloudKit database change · private · iCloud.com.trammells.hitlist", or "not from CloudKit".
    var summary: String {
        guard isCloudKit else { return "not from CloudKit" }
        let what = type == "database" ? "database change" : type == "recordZone" ? "zone change" : type
        return (["CloudKit \(what)", databaseScope, container] as [String?]).compactMap { $0 }.joined(separator: " · ")
    }

    var fields: [String: String] {
        var fields: [String: String] = ["cloudKit": isCloudKit ? "yes" : "no"]
        if let subscriptionID { fields["subscription"] = subscriptionID }
        if let zone { fields["zone"] = zone }
        if let databaseScope { fields["scope"] = databaseScope }
        if let container { fields["container"] = container }
        if let environmentCode { fields["ce"] = environmentCode }
        if let notificationID { fields["nid"] = String(notificationID.prefix(12)) }
        if isPruned { fields["pruned"] = "yes" }
        return fields
    }

    static func typeName(_ type: CKNotification.NotificationType) -> String {
        switch type {
        case .query: "query"
        case .recordZone: "recordZone"
        case .readNotification: "readNotification"
        case .database: "database"
        @unknown default: "unknown"
        }
    }

    static func scopeName(_ scope: CKDatabase.Scope) -> String {
        switch scope {
        case .public: "public"
        case .private: "private"
        case .shared: "shared"
        @unknown default: "scope \(scope.rawValue)"
        }
    }

    /// An imported enum accepts any raw value, so only CloudKit's three scopes (1–3) get a name.
    static func scopeName(rawValue: Int) -> String? {
        guard (1...3).contains(rawValue), let scope = CKDatabase.Scope(rawValue: rawValue) else { return nil }
        return scopeName(scope)
    }
}
