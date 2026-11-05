import Foundation
import CloudKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Shared Tasks values ↔ CloudKit records (brief 51; field names in `SharedTasksSchema`).
///
/// Every field is written on every save: a record is rebuilt from its last system fields (so the save carries the
/// server's change tag and a conflict comes back as `serverRecordChanged`) with all its values set. Empty values are
/// written as placeholders beside an explicit flag (`hasDueDate`, `isCompleted`, `hasAvatar`), so clearing one never
/// depends on a field's removal reaching the server. Reading is lenient: a missing field reads as unset.
enum SharedTasksRecords {
    /// Member pictures are copied at this size (long side, pixels): they show at 40 pt at most.
    static let avatarPixels = 256

    // MARK: - Ids

    static func zoneID(listID: UUID, ownerName: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: SharedTasksSchema.zoneName(for: listID), ownerName: ownerName)
    }

    static func zoneID(of list: SharedList) -> CKRecordZone.ID { zoneID(listID: list.id, ownerName: list.ownerName) }

    static func recordID(_ ref: SharedTasksStore.RecordRef) -> CKRecord.ID {
        CKRecord.ID(recordName: ref.recordName, zoneID: zoneID(listID: ref.listID, ownerName: ref.ownerName))
    }

    static func shareRecordID(listID: UUID, ownerName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(listID: listID, ownerName: ownerName))
    }

    // MARK: - Values to records

    static func record(for value: SharedTasksStore.RecordValue) -> CKRecord {
        switch value {
        case .list(let list): listRecord(list)
        case .task(let task, let list): taskRecord(task, in: list)
        case .member(let member, let list): memberRecord(member, in: list)
        }
    }

    static func listRecord(_ list: SharedList) -> CKRecord {
        typealias F = SharedTasksSchema.ListField
        let record = restored(list.systemFields, type: SharedTasksSchema.RecordType.list,
                              id: CKRecord.ID(recordName: SharedTasksSchema.listRecordName, zoneID: zoneID(of: list)))
        record[F.title] = list.fields.title.value
        record[F.titleChangedAt] = list.fields.title.changedAt
        record[F.colorHex] = list.fields.colorHex.value
        record[F.colorChangedAt] = list.fields.colorHex.changedAt
        record[F.createdAt] = list.fields.createdAt
        return record
    }

    static func taskRecord(_ task: SharedTask, in list: SharedList) -> CKRecord {
        typealias F = SharedTasksSchema.TaskField
        let record = restored(task.systemFields, type: SharedTasksSchema.RecordType.task,
                              id: CKRecord.ID(recordName: SharedTasksSchema.taskRecordName(for: task.id), zoneID: zoneID(of: list)))
        record[F.title] = task.title.value
        record[F.titleChangedAt] = task.title.changedAt
        record[F.notes] = task.notes.value
        record[F.notesChangedAt] = task.notes.changedAt
        record[F.priority] = Int64(task.priority.value)
        record[F.priorityChangedAt] = task.priority.changedAt
        record[F.hasDueDate] = Int64(task.due.value == nil ? 0 : 1)
        record[F.dueDate] = task.due.value?.date ?? SharedClock.unset
        record[F.hasDueTime] = Int64(task.due.value?.hasTime == true ? 1 : 0)
        record[F.dueChangedAt] = task.due.changedAt
        let completion = task.completion.value
        record[F.isCompleted] = Int64(completion == nil ? 0 : 1)
        record[F.completedAt] = completion?.at ?? SharedClock.unset
        record[F.completedBy] = completion?.by ?? ""
        record[F.completedByName] = completion?.byName ?? ""
        record[F.completionChangedAt] = task.completion.changedAt
        record[F.createdAt] = task.createdAt
        record[F.createdBy] = task.createdBy ?? ""
        record[F.createdByName] = task.createdByName ?? ""
        return record
    }

    static func memberRecord(_ member: SharedMember, in list: SharedList) -> CKRecord {
        typealias F = SharedTasksSchema.MemberField
        let record = restored(member.systemFields, type: SharedTasksSchema.RecordType.member,
                              id: CKRecord.ID(recordName: SharedTasksSchema.memberRecordName(for: member.id), zoneID: zoneID(of: list)))
        record[F.userID] = member.id
        record[F.name] = member.name.value
        record[F.nameChangedAt] = member.name.changedAt
        record[F.hasAvatar] = Int64(member.avatar.value == nil ? 0 : 1)
        record[F.avatar] = member.avatar.value.flatMap { assetFile(for: $0, member: member.id) }.map(CKAsset.init(fileURL:))
        record[F.avatarChangedAt] = member.avatar.changedAt
        record[F.joinedAt] = member.joinedAt
        return record
    }

    // MARK: - Records to values

    enum Fetched {
        case list(SharedListFields, systemFields: Data)
        case task(SharedTask)
        case member(SharedMember)
        case share(CKShare)
        /// Not a Shared Tasks record (a zone or record type this build doesn't know): left alone.
        case other
    }

    static func decode(_ record: CKRecord) -> Fetched {
        if let share = record as? CKShare { return .share(share) }
        switch record.recordType {
        case SharedTasksSchema.RecordType.list:
            return .list(listFields(from: record), systemFields: systemFields(of: record))
        case SharedTasksSchema.RecordType.task:
            return task(from: record).map(Fetched.task) ?? .other
        case SharedTasksSchema.RecordType.member:
            return member(from: record).map(Fetched.member) ?? .other
        default:
            return .other
        }
    }

    static func listFields(from record: CKRecord) -> SharedListFields {
        typealias F = SharedTasksSchema.ListField
        return SharedListFields(title: stamped(record, F.title, F.titleChangedAt, default: ""),
                                colorHex: stamped(record, F.colorHex, F.colorChangedAt, default: SharedTasksStore.defaultColor),
                                createdAt: date(record, F.createdAt) ?? record.creationDate ?? SharedClock.unset)
    }

    static func task(from record: CKRecord) -> SharedTask? {
        typealias F = SharedTasksSchema.TaskField
        guard let id = SharedTasksSchema.taskID(fromRecordName: record.recordID.recordName) else { return nil }
        let due: SharedDue? = int(record, F.hasDueDate) == 1
            ? date(record, F.dueDate).map { SharedDue(date: $0, hasTime: int(record, F.hasDueTime) == 1) } : nil
        let completion: SharedCompletion? = int(record, F.isCompleted) == 1
            ? SharedCompletion(at: date(record, F.completedAt) ?? SharedClock.unset, by: string(record, F.completedBy) ?? "",
                               byName: string(record, F.completedByName) ?? "")
            : nil
        return SharedTask(id: id,
                          title: stamped(record, F.title, F.titleChangedAt, default: ""),
                          notes: stamped(record, F.notes, F.notesChangedAt, default: ""),
                          priority: Stamped(SharedTasksStore.clampPriority(int(record, F.priority) ?? 4), at: date(record, F.priorityChangedAt) ?? SharedClock.unset),
                          due: Stamped(due, at: date(record, F.dueChangedAt) ?? SharedClock.unset),
                          completion: Stamped(completion, at: date(record, F.completionChangedAt) ?? SharedClock.unset),
                          createdAt: date(record, F.createdAt) ?? record.creationDate ?? SharedClock.unset,
                          createdBy: string(record, F.createdBy).flatMap { $0.isEmpty ? nil : $0 },
                          createdByName: string(record, F.createdByName).flatMap { $0.isEmpty ? nil : $0 },
                          systemFields: systemFields(of: record))
    }

    static func member(from record: CKRecord) -> SharedMember? {
        typealias F = SharedTasksSchema.MemberField
        guard let id = SharedTasksSchema.memberID(fromRecordName: record.recordID.recordName) else { return nil }
        let avatar: Data? = int(record, F.hasAvatar) == 1
            ? (record[F.avatar] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) } : nil
        return SharedMember(id: id, name: stamped(record, F.name, F.nameChangedAt, default: ""),
                            avatar: Stamped(avatar, at: date(record, F.avatarChangedAt) ?? SharedClock.unset),
                            joinedAt: date(record, F.joinedAt) ?? record.creationDate ?? SharedClock.unset,
                            systemFields: systemFields(of: record))
    }

    /// The share's people as the Shared screens need them. `me` replaces the placeholder CloudKit uses for the
    /// current user (`CKCurrentUserDefaultName`).
    static func shareInfo(from share: CKShare, me: SharedMemberID?) -> SharedShareInfo {
        let current = share.currentUserParticipant
        let participants = share.participants.map { p -> SharedParticipant in
            let isMe = current.map { p == $0 } ?? false
            var userID = p.userIdentity.userRecordID?.recordName
            if isMe || userID == CKCurrentUserDefaultName { userID = me ?? userID }
            let name = p.userIdentity.nameComponents
                .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            let status: SharedParticipant.Status = switch p.acceptanceStatus {
            case .pending: .pending
            case .accepted: .accepted
            case .removed: .removed
            default: .unknown
            }
            return SharedParticipant(userID: userID, name: name,
                                     contact: p.userIdentity.lookupInfo?.emailAddress ?? p.userIdentity.lookupInfo?.phoneNumber,
                                     role: p.role == .owner ? .owner : .participant, status: status,
                                     canWrite: p.permission == .readWrite, isCurrentUser: isMe)
        }
        return SharedShareInfo(participants: participants, url: share.url, archive: archive(share))
    }

    static func archive(_ share: CKShare) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: share, requiringSecureCoding: true)
    }

    static func unarchiveShare(_ data: Data?) -> CKShare? {
        data.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: $0) }
    }

    // MARK: - System fields

    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// The record as last saved or fetched (its change tag, no values), or a new one.
    static func restored(_ systemFields: Data?, type: String, id: CKRecord.ID) -> CKRecord {
        if let systemFields, let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) {
            coder.requiresSecureCoding = true
            defer { coder.finishDecoding() }
            if let record = CKRecord(coder: coder), record.recordID == id, record.recordType == type { return record }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    // MARK: - Pictures

    /// A JPEG of at most `avatarPixels` on its long side, or the picture itself when it is already that small or
    /// can't be read.
    static func smallAvatar(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              max(w, h) > avatarPixels else { return data }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: avatarPixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return data }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return data }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : data
    }

    /// CKAsset needs a file: the picture is written once per member and content into the caches folder.
    static func assetFile(for data: Data, member: SharedMemberID) -> URL? {
        let folder = URL.cachesDirectory.appending(path: "SharedTasksAssets")
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let safe = member.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let url = folder.appending(path: "\(safe)-\(digest).jpg")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Reading fields

    private static func stamped(_ record: CKRecord, _ key: String, _ timeKey: String, default value: String) -> Stamped<String> {
        Stamped(string(record, key) ?? value, at: date(record, timeKey) ?? SharedClock.unset)
    }

    private static func string(_ record: CKRecord, _ key: String) -> String? { record[key] as? String }

    private static func date(_ record: CKRecord, _ key: String) -> Date? { (record[key] as? Date).map(SharedClock.stamp) }

    private static func int(_ record: CKRecord, _ key: String) -> Int? { (record[key] as? NSNumber)?.intValue }
}
