import Foundation
import CloudKit

/// The word that lets every device move to the new sync (round 34, brief 170). George, 2026-11-18: "I also want it to
/// force everyone to move over to the new sync engine so we can settle this once and for all", and the same day, "I'd
/// even rather the update just automatically move their tasks after we've confirmed the new engine is working." One
/// build reaches everyone and moves nobody until George says so, by one record every device can read:
///
/// - **Where**: the **public** database of the engine's container (`SyncEngineSwitch.containerID`), its default zone,
///   record type `HLRollout`, record name `everyone`. Its schema is in `dev/cloudkit/sync-engine.ckdb`, with the
///   grants every type of the file has (the world reads; a signed-in account creates; the creator writes). Nobody
///   but an app signed for this container can reach its public database at all, and no released code path writes
///   the record (`SyncEngineRolloutTests` greps for one): George makes it in the CloudKit Console, and a Debug
///   build's rehearsal hook makes it on iCloud's test side. (The first draft kept creation to a custom security
///   role; that cost George two more steps in the Console for no one it could stop.)
/// - **Fields**: `minBuild` (INT64, optional: only builds whose build number is at least this move; absent means every
///   build) and `paused` (INT64, optional: anything but 0 means wait).
/// - **The answer**: the record there, this build allowed and not paused → `go`; paused → `paused`; no such record
///   (`unknownItem`) or `minBuild` above this build → `notYet`; anything else (offline, signed out of a network that
///   answers nothing, a throttle, a field of the wrong kind) → `unknown`. Only `go` lets a device move.
///
/// - **Several records** (one made in the Console under a name of its own beside `everyone`, or two made by
///   mistake): a record that says wait wins over every other, whichever was changed last, because the pause is the
///   brake; otherwise the one changed last is the word (`word(among:)`).
///
/// One fetch by the record's id and one query for the type's records. It never throws, never retries by itself,
/// keeps nothing on disk, and writes one line in the sync log per answer through the closure it is given.
enum SyncEngineRollout {
    enum Answer: String, Equatable, Sendable {
        /// The word is there and this build may move.
        case go
        /// No word yet, or not for this build.
        case notYet
        /// The word is there and says wait.
        case paused
        /// iCloud did not answer: nothing is known (treated as not yet by whoever asks).
        case unknown
    }

    /// CloudKit's names for the record and its fields (the schema file's test reads them from here).
    static let recordType = "HLRollout"
    static let recordName = "everyone"
    static let minBuildField = "minBuild"
    static let pausedField = "paused"

    static var recordID: CKRecord.ID { CKRecord.ID(recordName: recordName, zoneID: CKRecordZone.default().zoneID) }

    /// The two fields as read from the record. `unreadable`: a field held something that is not a whole number.
    struct Fields: Equatable, Sendable {
        var minBuild: Int64?
        var paused: Int64?
        var unreadable = false

        init(minBuild: Int64? = nil, paused: Int64? = nil, unreadable: Bool = false) {
            self.minBuild = minBuild
            self.paused = paused
            self.unreadable = unreadable
        }

        init(record: CKRecord) {
            func number(_ key: String) -> (Int64?, Bool) {
                guard let value = record[key] else { return (nil, true) }
                guard let number = value as? NSNumber, CFNumberIsFloatType(number) == false else { return (nil, false) }
                return (number.int64Value, true)
            }
            let (minBuild, minOK) = number(SyncEngineRollout.minBuildField)
            let (paused, pausedOK) = number(SyncEngineRollout.pausedField)
            self.init(minBuild: minBuild, paused: paused, unreadable: !minOK || !pausedOK)
        }
    }

    // MARK: - The rules (pure)

    /// The word among several records, each with the time it was last changed: one that says wait (or cannot be
    /// read) before any other, then the one changed last. Nil for none.
    static func word(among records: [(fields: Fields, changed: Date)]) -> Fields? {
        let newestFirst = records.sorted { $0.changed > $1.changed }
        if let brake = newestFirst.first(where: { $0.fields.unreadable || ($0.fields.paused ?? 0) != 0 }) { return brake.fields }
        return newestFirst.first?.fields
    }

    /// The answer for these fields (nil: no such record) and this build's number (`AppInfo.build`, a string).
    static func answer(fields: Fields?, build: String) -> Answer {
        guard let fields else { return .notYet }
        if fields.unreadable { return .unknown }
        if let paused = fields.paused, paused != 0 { return .paused }
        guard let minBuild = fields.minBuild else { return .go }
        // A build whose number cannot be read is never let through by a minimum: the safe side.
        guard let mine = Int64(build.trimmingCharacters(in: .whitespaces)) else { return .notYet }
        return mine >= minBuild ? .go : .notYet
    }

    /// The answer for a fetch that threw: no such record is "not yet", anything else is not known.
    static func answer(error: Error) -> Answer {
        isUnknownItem(error) ? .notYet : .unknown
    }

    static func isUnknownItem(_ error: Error) -> Bool {
        if let error = error as? CKError {
            if error.code == .unknownItem { return true }
            if error.code == .partialFailure, let inner = error.partialErrorsByItemID?.values.first {
                return isUnknownItem(inner)
            }
            return false
        }
        let ns = error as NSError
        return ns.domain == CKErrorDomain && ns.code == CKError.Code.unknownItem.rawValue
    }

    /// The sync log's line for an answer.
    static func logLine(_ answer: Answer, fields: Fields?, build: String, error: Error? = nil) -> String {
        let head = "Asked iCloud whether this device may move to the new sync"
        switch answer {
        case .go:
            let from = fields?.minBuild.map { ", from build \($0)" } ?? ", every build"
            return "\(head): yes (build \(build)\(from))"
        case .paused:
            return "\(head): paused, waiting"
        case .notYet:
            if fields == nil { return "\(head): not yet (no word)" }
            return "\(head): not yet (from build \(fields?.minBuild.map { "\($0)" } ?? "?"), this is build \(build))"
        case .unknown:
            if let error { return "\(head): couldn't tell (\(SyncState.shortReason(for: error)))" }
            return "\(head): couldn't tell (the word holds something unreadable)"
        }
    }
}

// MARK: - The question

/// One question to iCloud: may this device move? A stand-in answers it in the tests. Never throws.
protocol SyncEngineRolloutAsking: Sendable {
    func answer() async -> SyncEngineRollout.Answer
}

/// The question asked through a fetch the caller gives: the record's fields, nil when there is none, or an error.
/// `CloudKitRollout` gives CloudKit's; the tests give their own.
struct SyncEngineRolloutAsker: SyncEngineRolloutAsking {
    typealias Fetch = @Sendable () async throws -> SyncEngineRollout.Fields?

    let build: String
    let fetch: Fetch
    let log: @MainActor @Sendable (String) -> Void

    init(build: String = AppInfo.build, fetch: @escaping Fetch, log: @escaping @MainActor @Sendable (String) -> Void) {
        self.build = build
        self.fetch = fetch
        self.log = log
    }

    func answer() async -> SyncEngineRollout.Answer {
        let answer: SyncEngineRollout.Answer
        let line: String
        do {
            let fields = try await fetch()
            answer = SyncEngineRollout.answer(fields: fields, build: build)
            line = SyncEngineRollout.logLine(answer, fields: fields, build: build)
        } catch {
            answer = SyncEngineRollout.answer(error: error)
            line = answer == .notYet
                ? SyncEngineRollout.logLine(.notYet, fields: nil, build: build)
                : SyncEngineRollout.logLine(.unknown, fields: nil, build: build, error: error)
        }
        await log(line)
        return answer
    }
}

/// The question on CloudKit: one fetch of `HLRollout/everyone` by its id from the engine's container's public
/// database (Development for a Debug build, Production for TestFlight), the two fields only, and one query for
/// every record of the type (a record made by hand may carry another name). Read access is the world's, so it
/// answers signed in or not.
struct CloudKitRollout: SyncEngineRolloutAsking {
    private let asker: SyncEngineRolloutAsker

    init(containerID: String = SyncEngineSwitch.containerID, build: String = AppInfo.build,
         log: @escaping @MainActor @Sendable (String) -> Void) {
        asker = SyncEngineRolloutAsker(build: build, fetch: { try await Self.fetch(containerID: containerID) }, log: log)
    }

    func answer() async -> SyncEngineRollout.Answer { await asker.answer() }

    /// The record's fields, or nil when CloudKit says there is no such record. One request; CloudKit's own errors
    /// otherwise, which the asker maps.
    static func fetch(containerID: String) async throws -> SyncEngineRollout.Fields? {
        let database = CKContainer(identifier: containerID).publicCloudDatabase
        let id = SyncEngineRollout.recordID
        let configuration = CKOperation.Configuration()
        // Offline, CloudKit may wait a long while for a network: a launch's question is not worth more than this.
        configuration.timeoutIntervalForResource = 30
        let results = try await database.configuredWith(configuration: configuration) { database in
            try await database.records(for: [id], desiredKeys: [SyncEngineRollout.minBuildField, SyncEngineRollout.pausedField])
        }
        var found: [CKRecord] = []
        if let result = results[id] {
            switch result {
            case .success(let record): found.append(record)
            case .failure(let error):
                if !SyncEngineRollout.isUnknownItem(error) { throw error }
            }
        }
        // George makes the word by hand in the CloudKit Console, where a record may be saved under a name the
        // console gave it: every record of the type counts (the type's record name is queryable in the schema file
        // for this). A query that fails (the type not yet deployed) adds nothing.
        let queried: [CKRecord]? = try? await database.configuredWith(configuration: configuration) { database in
            let query = CKQuery(recordType: SyncEngineRollout.recordType, predicate: NSPredicate(value: true))
            let (matches, _) = try await database.records(matching: query, desiredKeys: [SyncEngineRollout.minBuildField,
                                                                                         SyncEngineRollout.pausedField],
                                                          resultsLimit: 20)
            return matches.compactMap { try? $0.1.get() }
        }
        for record in queried ?? [] where !found.contains(where: { $0.recordID == record.recordID }) { found.append(record) }
        return SyncEngineRollout.word(among: found.map {
            (fields: SyncEngineRollout.Fields(record: $0), changed: $0.modificationDate ?? .distantPast)
        })
    }
}
