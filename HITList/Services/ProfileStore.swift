import Foundation
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The account's profile (brief 34): one `Profile` record per iCloud account, in the same SwiftData +
/// CloudKit store as the tasks, so it syncs, recovers and is watched (`SyncWatchdog`) exactly like them;
/// there is no separate CloudKit code path.
///
/// Reading never creates a record: a device that only shows the Account screen adds nothing that could
/// race another device's profile. The first write (a name or a picture) creates it. Two devices that both
/// wrote before they synced hold two records until `Deduplicator` runs `mergeDuplicates` after the import.
///
/// Every write, merge and delete is saved at once and logged to the sync log (kind `profile`) without the
/// name or the picture: only what changed, sizes and counts.
@MainActor
struct ProfileStore {
    typealias Log = @MainActor (_ message: String, _ level: SyncLogEntry.Level, _ fields: [String: String]) -> Void

    /// The app's log: through `CloudSyncMonitor.write`, so the line lands after any saves still being gathered.
    static let syncLog: Log = { CloudSyncMonitor.shared.write(.profile, $0, level: $1, fields: $2) }

    /// Longer names are cut here; the field shows them whole while typing.
    static let maxNameLength = 80

    enum ProfileError: Error, LocalizedError {
        case unreadablePicture

        var errorDescription: String? { "That picture couldn't be read. Try another one." }
    }

    let context: ModelContext
    var log: Log = ProfileStore.syncLog
    var clock: () -> Date = { Date() }

    // MARK: Reading

    /// Every profile record, survivor first (`Deduplicator.precedes`' order: earliest `createdAt`, then id).
    func all() throws -> [Profile] {
        try context.fetch(FetchDescriptor<Profile>()).sorted(by: Self.precedes)
    }

    /// The profile to show: the one a merge would keep. Nil when none exists yet.
    func current() throws -> Profile? { try all().first }

    // MARK: Writing

    /// The profile, created (and saved) when there is none.
    @discardableResult
    func fetchOrCreate() throws -> Profile {
        if let existing = try current() { return existing }
        let profile = Profile()
        let now = clock()
        profile.createdAt = now
        profile.updatedAt = now
        context.insert(profile)
        try save("Profile created", fields: ["id": Self.shortID(profile)])
        return profile
    }

    /// Sets the name, trimmed and capped at `maxNameLength`. An empty name clears it. Unchanged: no write.
    func setName(_ raw: String) throws {
        let name = Self.cleanName(raw)
        if (try current()?.displayName ?? "") == name { return }
        let profile = try fetchOrCreate()
        let now = clock()
        profile.displayName = name
        profile.nameUpdatedAt = now
        profile.updatedAt = now
        try save(name.isEmpty ? "Profile name cleared" : "Profile name set",
                 fields: ["id": Self.shortID(profile), "characters": "\(name.count)"])
    }

    /// Sets the picture from any image file's data (downscaled by `ProfileAvatar.prepare`), or removes it
    /// for nil. Throws `ProfileError.unreadablePicture`, changing nothing, when the data isn't an image.
    func setAvatar(imageData: Data?) throws {
        guard let imageData else {
            guard let profile = try current(), profile.avatarData != nil else { return }
            let now = clock()
            profile.avatarData = nil
            profile.avatarUpdatedAt = now
            profile.updatedAt = now
            try save("Profile picture removed", fields: ["id": Self.shortID(profile)])
            return
        }
        let prepared: Data
        do {
            prepared = try ProfileAvatar.prepare(imageData)
        } catch {
            log("Profile picture refused: not a readable image", .error, ["bytes": "\(imageData.count)"])
            throw error
        }
        let profile = try fetchOrCreate()
        let now = clock()
        profile.avatarData = prepared
        profile.avatarUpdatedAt = now
        profile.updatedAt = now
        let size = ProfileAvatar.pixelSize(of: prepared)
        try save("Profile picture set", fields: ["id": Self.shortID(profile), "bytes": "\(prepared.count)",
                                                  "pixels": size.map { "\($0.width)x\($0.height)" } ?? "?",
                                                  "original": "\(imageData.count)"])
    }

    /// Deletes every profile record (only those: no task, Group or setting is touched) and returns how
    /// many there were. The deletion syncs to every device, as any deletion does.
    @discardableResult
    func delete() throws -> Int {
        let profiles = try all()
        guard !profiles.isEmpty else { return 0 }
        for profile in profiles { context.delete(profile) }
        try save("Profile deleted", fields: ["records": "\(profiles.count)"])
        return profiles.count
    }

    // MARK: Merging

    /// Collapses several profile records into one and returns how many were deleted. Called by
    /// `Deduplicator.run` at launch and after every import; it saves with the rest of that pass.
    ///
    /// The survivor is the earliest record (as for Groups), so every device keeps the same one. Each field
    /// comes from the record that changed it last: the name with the newest `nameUpdatedAt` (a tie goes to the
    /// survivor), the picture with the newest `avatarUpdatedAt` among those that have one, so a merge never
    /// loses a picture. `updatedAt` becomes the newest of the group. Deterministic from the data, so two
    /// devices merging the same records write the same values; a second pass changes nothing.
    func mergeDuplicates() throws -> Int {
        let group = try all()
        guard group.count > 1, let winner = group.first else { return 0 }
        let fields = Self.merged(group)
        if winner.displayName != fields.name { winner.displayName = fields.name }
        if winner.nameUpdatedAt != fields.nameUpdatedAt { winner.nameUpdatedAt = fields.nameUpdatedAt }
        if winner.avatarData != fields.avatar { winner.avatarData = fields.avatar }
        if winner.avatarUpdatedAt != fields.avatarUpdatedAt { winner.avatarUpdatedAt = fields.avatarUpdatedAt }
        if winner.updatedAt != fields.updatedAt { winner.updatedAt = fields.updatedAt }
        for loser in group.dropFirst() { context.delete(loser) }
        log("Merged duplicate profiles", .notice, ["records": "\(group.count)", "kept": Self.shortID(winner),
                                                   "picture": fields.avatar == nil ? "none" : "kept"])
        return group.count - 1
    }

    struct MergedFields: Equatable {
        var name: String
        var nameUpdatedAt: Date?
        var avatar: Data?
        var avatarUpdatedAt: Date?
        var updatedAt: Date
    }

    /// The merged values of `group`, which is in survivor order (`all()`).
    static func merged(_ group: [Profile]) -> MergedFields {
        // `max` keeps the first of equal elements only when compared strictly, so walk in survivor order.
        func newest(_ candidates: [Profile], by stamp: (Profile) -> Date?) -> Profile? {
            candidates.reduce(nil as Profile?) { best, next in
                guard let best else { return next }
                return (stamp(next) ?? .distantPast) > (stamp(best) ?? .distantPast) ? next : best
            }
        }
        let named = newest(group, by: \.nameUpdatedAt)
        // No record ever stamped a name (a record made before 0.5.0's store did): the first non-empty one.
        let nameSource = named?.nameUpdatedAt == nil ? (group.first { !$0.displayName.isEmpty } ?? named) : named
        let pictured = newest(group.filter { $0.avatarData != nil }, by: \.avatarUpdatedAt)
        return MergedFields(name: nameSource?.displayName ?? "", nameUpdatedAt: nameSource?.nameUpdatedAt,
                            avatar: pictured?.avatarData, avatarUpdatedAt: pictured?.avatarUpdatedAt ?? group.first?.avatarUpdatedAt,
                            updatedAt: group.map(\.updatedAt).max() ?? .distantPast)
    }

    // MARK: Sample (schema push)

    /// `-seedSampleData` (a side store only, never the real one; see `TaskActions.seedSampleDataIfRequested`):
    /// two profile records with a name and a picture, a small one and one too large to be kept inline, so
    /// every CD_Profile field, `CD_avatarData_ckAsset` included, reaches the CloudKit Development schema.
    /// The two are merged by the next dedupe pass, as two devices' profiles would be.
    func seedSampleProfiles() throws {
        let now = clock()
        for (name, bytes) in [("Sample profile", 2_000), ("Sample profile, large picture", 1_200_000)] {
            let profile = Profile()
            profile.displayName = name
            profile.nameUpdatedAt = now
            profile.avatarData = Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 31) })
            profile.avatarUpdatedAt = now
            profile.updatedAt = now
            context.insert(profile)
        }
        try save("Sample profiles created for the schema push", fields: ["records": "2"])
    }

    // MARK: Helpers

    static func cleanName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    static func precedes(_ a: Profile, _ b: Profile) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    static func shortID(_ profile: Profile) -> String { String(profile.id.uuidString.prefix(8)) }

    private func save(_ message: String, fields: [String: String]) throws {
        do {
            try context.save()
            log(message, .info, fields)
        } catch {
            context.rollback()
            log("\(message) failed to save: \(error.localizedDescription)", .error, SyncLogFormat.errorFields(error))
            throw error
        }
    }
}

/// The profile picture: downscaling before it is saved, and the initials shown when there is none.
enum ProfileAvatar {
    static let maxPixels = 512
    static let maxBytes = 200_000

    /// A JPEG of `data`'s image at most `maxPixels` on its long side (never upscaled) and `maxBytes` long,
    /// with the photo's orientation applied. Lowers the quality, then the size, until it fits.
    static func prepare(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let original = pixelSize(of: source) else { throw ProfileStore.ProfileError.unreadablePicture }
        var side = min(maxPixels, max(original.width, original.height))
        while side >= 64 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { break }
            for quality in [0.85, 0.7, 0.55, 0.4] {
                if let jpeg = jpeg(image, quality: quality), jpeg.count <= maxBytes { return jpeg }
            }
            side = side * 3 / 4
        }
        throw ProfileStore.ProfileError.unreadablePicture
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(pixelSize(of:))
    }

    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// "GT" for "George Trammell": the first letters of the first and last words, uppercased. Nil for a
    /// blank name (the avatar then shows a person symbol).
    static func initials(for name: String) -> String? {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return nil }
        let last = words.count > 1 ? words.last?.first : nil
        return ([first] + (last.map { [$0] } ?? [])).map { String($0).uppercased() }.joined()
    }
}
