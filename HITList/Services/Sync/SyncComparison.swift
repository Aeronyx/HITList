import Foundation

/// Brief 95: this device's store against iCloud's copy, record by record, for every kind the store syncs: what
/// "Check iCloud…" runs, on request, against a fresh read of the whole zone (`SyncAudit`). The bolt no longer waits
/// on it (0.9.10, `SyncSessionGate`).
///
/// A record is known by its kind (the model's entity) and its own `id` (CloudKit's `CD_id` field), never by CloudKit's
/// record name, which this device's store doesn't show. Two records in iCloud with one id (the mirror wrote a record
/// twice) count once, and are counted apart (`duplicatesThere`). The change stamp is the model's `updatedAt`
/// (`CD_updatedAt`): a value newer on one side by more than `tolerance` is a change the other side hasn't got. CloudKit
/// keeps dates to the millisecond and the store to the microsecond, so a hundredth of a second of tolerance never
/// reads the same value as two. A change that doesn't touch `updatedAt` (the day anchors, brief 82) isn't seen here.
///
/// Pure: tests feed it records.
enum SyncComparison {
    /// One record in iCloud: its kind, its `CD_id`, its change stamp, CloudKit's record name and last-changed time.
    struct Remote: Equatable, Sendable {
        var entity: String
        var id: UUID
        var updatedAt: Date?
        var recordName: String
        var modifiedAt: Date?
    }

    /// One record on this device.
    struct Local: Equatable, Sendable {
        var entity: String
        var id: UUID
        var updatedAt: Date
        var createdAt: Date
    }

    struct Difference: Equatable, Sendable, Identifiable {
        enum Kind: String, Equatable, Sendable, CaseIterable {
            /// Here, and not in iCloud: never sent, or deleted elsewhere and the deletion never arrived.
            case onlyHere
            /// In iCloud, and not here: never arrived, or deleted here and the deletion never left.
            case onlyThere
            /// Changed here after iCloud's copy.
            case newerHere
            /// Changed in iCloud after this device's copy.
            case newerThere
        }

        var kind: Kind
        var entity: String
        var id: UUID
        var local: Local?
        var remote: Remote?

        /// "TaskItem/<id>".
        var identifier: String { "\(entity)/\(id.uuidString)" }
    }

    /// How many records of one kind each side holds.
    struct Count: Equatable, Sendable {
        var here = 0
        var there = 0
    }

    struct Result: Equatable, Sendable {
        /// In a fixed order: by kind of difference, then entity, then id.
        var differences: [Difference] = []
        /// By entity, for every entity either side holds.
        var counts: [String: Count] = [:]
        /// Records in iCloud that share an id with another of their kind (counted once in `counts`).
        var duplicatesThere = 0

        var agree: Bool { differences.isEmpty }

        func differences(_ kind: Difference.Kind) -> [Difference] { differences.filter { $0.kind == kind } }
    }

    static let tolerance: TimeInterval = 0.01

    /// `remote` against `local`, for the entities in `entities` (the kinds this build syncs; a record of any other kind,
    /// from a newer build, is left out of both sides).
    static func compare(remote: [Remote], local: [Local], entities: Set<String>, tolerance: TimeInterval = tolerance) -> Result {
        var result = Result()
        var there: [String: Remote] = [:]
        for record in remote where entities.contains(record.entity) {
            let key = "\(record.entity)/\(record.id.uuidString)"
            if let earlier = there[key] {
                result.duplicatesThere += 1
                // The copy with the newest stamp stands for the id: the one the mirror wrote last.
                if (record.updatedAt ?? .distantPast) > (earlier.updatedAt ?? .distantPast) { there[key] = record }
            } else {
                there[key] = record
            }
        }
        var here: [String: Local] = [:]
        for record in local where entities.contains(record.entity) {
            here["\(record.entity)/\(record.id.uuidString)"] = record
        }
        for record in here.values { result.counts[record.entity, default: Count()].here += 1 }
        for record in there.values { result.counts[record.entity, default: Count()].there += 1 }

        for (key, mine) in here {
            guard let theirs = there[key] else {
                result.differences.append(Difference(kind: .onlyHere, entity: mine.entity, id: mine.id, local: mine, remote: nil))
                continue
            }
            guard let stamp = theirs.updatedAt else { continue }
            let delta = mine.updatedAt.timeIntervalSince(stamp)
            if delta > tolerance {
                result.differences.append(Difference(kind: .newerHere, entity: mine.entity, id: mine.id, local: mine, remote: theirs))
            } else if delta < -tolerance {
                result.differences.append(Difference(kind: .newerThere, entity: mine.entity, id: mine.id, local: mine, remote: theirs))
            }
        }
        for (key, theirs) in there where here[key] == nil {
            result.differences.append(Difference(kind: .onlyThere, entity: theirs.entity, id: theirs.id, local: nil, remote: theirs))
        }
        let order = Difference.Kind.allCases
        result.differences.sort { a, b in
            let ka = order.firstIndex(of: a.kind) ?? 0, kb = order.firstIndex(of: b.kind) ?? 0
            if ka != kb { return ka < kb }
            if a.entity != b.entity { return a.entity < b.entity }
            return a.id.uuidString < b.id.uuidString
        }
        return result
    }

    // MARK: Words

    /// The kinds the store syncs, in the order the audit names them, with the words for one and for several.
    struct KindName: Equatable, Sendable {
        var entity: String
        var one: String
        var many: String

        func count(_ n: Int) -> String { "\(n) \(n == 1 ? one : many)" }
    }

    static let kindNames: [KindName] = [
        KindName(entity: "TaskItem", one: "task", many: "tasks"),
        KindName(entity: "Project", one: "Group", many: "Groups"),
        KindName(entity: "TaskLabel", one: "label", many: "labels"),
        KindName(entity: "SavedFilter", one: "filter", many: "filters"),
        KindName(entity: "Switchboard", one: "Switchboard", many: "Switchboards"),
        KindName(entity: "Profile", one: "profile", many: "profiles"),
    ]

    static func name(of entity: String) -> KindName {
        kindNames.first { $0.entity == entity } ?? KindName(entity: entity, one: "\(entity) record", many: "\(entity) records")
    }

    /// "412 tasks, 9 Groups, 5 labels": every kind with a record on either side, in `kindNames` order.
    static func countsText(_ counts: [String: Count], side: KeyPath<Count, Int>) -> String {
        let known = kindNames.map(\.entity)
        let others = counts.keys.filter { !known.contains($0) }.sorted()
        let parts = (known + others).compactMap { entity -> String? in
            guard let count = counts[entity] else { return nil }
            return name(of: entity).count(count[keyPath: side])
        }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: ", ")
    }

    /// A record's id as the sync log may show it: 8 hex digits of a one-way hash, the same on every device, so two
    /// devices' logs can be matched without either showing the id itself.
    static func shortHash(_ id: UUID) -> String { SyncShortHash.of(id.uuidString) }

    // MARK: The log's words

    /// "2 only here, 1 only in iCloud": the log's summary.
    static func differenceSummary(_ result: SyncComparison.Result) -> String {
        SyncComparison.Difference.Kind.allCases.compactMap { kind -> String? in
            let n = result.differences(kind).count
            guard n > 0 else { return nil }
            switch kind {
            case .onlyHere: return "\(n) only here"
            case .onlyThere: return "\(n) only in iCloud"
            case .newerHere: return "\(n) newer here"
            case .newerThere: return "\(n) newer in iCloud"
            }
        }.joined(separator: ", ")
    }

    /// The log's fields: counts on both sides, and up to `limit` records per kind of difference as "task 3fa2c1d9
    /// created 2026-11-10 21:14 changed 2026-11-11 09:02" (this device's times) or "… in iCloud 2026-11-11 09:02".
    static func logFields(_ result: SyncComparison.Result, limit: Int = 10) -> [String: String] {
        var fields: [String: String] = [
            "here": SyncComparison.countsText(result.counts, side: \.here),
            "iCloud": SyncComparison.countsText(result.counts, side: \.there),
        ]
        if result.duplicatesThere > 0 { fields["duplicatesInICloud"] = "\(result.duplicatesThere)" }
        for kind in SyncComparison.Difference.Kind.allCases {
            let items = result.differences(kind)
            guard !items.isEmpty else { continue }
            var parts = items.prefix(limit).map(describe)
            if items.count > limit { parts.append("+\(items.count - limit) more") }
            fields[kind.rawValue] = parts.joined(separator: "; ")
        }
        return fields
    }

    private static func describe(_ difference: SyncComparison.Difference) -> String {
        var text = "\(SyncComparison.name(of: difference.entity).one) \(SyncComparison.shortHash(difference.id))"
        if let local = difference.local {
            text += " created \(stamp(local.createdAt)) changed \(stamp(local.updatedAt))"
        }
        if let remote = difference.remote {
            if let updated = remote.updatedAt { text += " iCloud changed \(stamp(updated))" }
            if let modified = remote.modifiedAt { text += " saved \(stamp(modified))" }
        }
        return text
    }

    /// "2026-11-11 09:02:13" in this device's zone: times are not personal, and two devices' logs line up by them.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
