import Foundation
import CloudKit
import OSLog
import SwiftData
import HITListCore

/// Check iCloud… on HITList's own engine (round 32): every record of the engine's zone read afresh, straight from
/// iCloud, and compared with this device's, field by field. It is the person's own proof that the bolt is true, and
/// the supervisor's proof after a move (`dev/SYNC-ENGINE.md` section 14, stages 4 and 5).
///
/// It reads and says; it changes nothing, here or in iCloud. Whatever it finds is the engine's to settle by its own
/// rules: an item here that iCloud lacks is waiting to go, an item iCloud holds that is not here comes at the next
/// fetch. A difference that is still there when nothing is waiting and a sync has just ended is a fault of the
/// engine's, and the sync log then holds its name.
///
/// The read does not go through the engine's transport: a second road (one `CKFetchRecordZoneChangesOperation` with
/// no token) that shares nothing with `CKSyncEngine`'s bookmark, so it cannot repeat the engine's own mistake.
enum SyncEngineAudit {
    /// One record both sides hold, and the fields in which they differ.
    struct Difference: Equatable, Sendable {
        var key: SyncKey
        var fields: [String]
    }

    struct Report: Equatable, Sendable {
        /// Items alive on this device.
        var here = 0
        /// Records alive in iCloud.
        var inCloud = 0
        /// Markers of deleted items in iCloud.
        var markers = 0
        /// Held by both, every field this build knows the same.
        var same = 0
        /// On this device and not in iCloud at all: never sent, or waiting to go.
        var onlyHere: [SyncKey] = []
        /// Alive in iCloud and not on this device.
        var onlyInCloud: [SyncKey] = []
        /// Alive here while iCloud holds its deletion.
        var deletedInCloud: [SyncKey] = []
        var different: [Difference] = []
        /// Records iCloud holds that this build could not read (an asset that did not download).
        var unreadable: [String] = []
        /// Records of a type this build does not know (a newer build's): counted, never compared.
        var unknown = 0
        /// What the engine said was waiting to go when the read began.
        var waiting = 0

        var differences: Int { onlyHere.count + onlyInCloud.count + deletedInCloud.count + different.count + unreadable.count }
        var isSame: Bool { differences == 0 }

        /// "iCloud and this device hold the same 1,204 items." or what differs, in a sentence.
        var summary: String {
            if isSame {
                return "iCloud and this device hold the same \(Self.count(same, "item"))."
            }
            var parts: [String] = []
            if !onlyHere.isEmpty { parts.append("\(onlyHere.count) on this device \(onlyHere.count == 1 ? "isn't" : "aren't") in iCloud") }
            if !onlyInCloud.isEmpty { parts.append("\(onlyInCloud.count) in iCloud \(onlyInCloud.count == 1 ? "isn't" : "aren't") on this device") }
            if !deletedInCloud.isEmpty { parts.append("\(deletedInCloud.count) deleted in iCloud \(deletedInCloud.count == 1 ? "is" : "are") still here") }
            if !different.isEmpty { parts.append("\(different.count) \(different.count == 1 ? "differs" : "differ")") }
            if !unreadable.isEmpty { parts.append("\(unreadable.count) in iCloud couldn't be read") }
            let waitingNote = waiting > 0 ? " \(Self.count(waiting, "change")) \(waiting == 1 ? "was" : "were") waiting to go when it was read." : ""
            return "\(Self.count(same, "item")) the same; " + parts.joined(separator: ", ") + "." + waitingNote
        }

        /// Lines for the sync log: the counts, then each difference by key (ids and field names, never a title).
        var logLines: [String] {
            var lines = ["here \(here), in iCloud \(inCloud) and \(markers) marker(s), same \(same), differences \(differences), waiting \(waiting), unknown types \(unknown)"]
            lines += onlyHere.prefix(Self.listed).map { "only here: \($0)" }
            lines += onlyInCloud.prefix(Self.listed).map { "only in iCloud: \($0)" }
            lines += deletedInCloud.prefix(Self.listed).map { "deleted in iCloud, alive here: \($0)" }
            lines += different.prefix(Self.listed).map { "differs: \($0.key) in \($0.fields.joined(separator: ", "))" }
            lines += unreadable.prefix(Self.listed).map { "unreadable in iCloud: \($0)" }
            return lines
        }

        static let listed = 40

        static func count(_ n: Int, _ noun: String) -> String {
            "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")"
        }
    }

    // MARK: - The comparison (pure)

    /// Compares what this device holds with what iCloud holds. `cloud` is every record of the zone, alive or a
    /// marker.
    ///
    /// A reference iCloud holds to an item that is not on this device is not a difference: the device shows what it
    /// can and the engine keeps the reference waiting (`dev/SYNC-ENGINE.md` section 8). The missing item itself is
    /// reported, under `onlyInCloud` or not at all when iCloud holds only its marker.
    static func compare(local: [SyncRecord], cloud: [SyncRecord], waiting: Int = 0) -> Report {
        var report = Report(waiting: waiting)
        var here: [SyncKey: SyncRecord] = [:]
        for record in local where SyncSchema.type(record.key.type) != nil && !record.isDeleted { here[record.key] = record }
        var there: [SyncKey: SyncRecord] = [:]
        var markers: Set<SyncKey> = []
        for record in cloud {
            guard record.key.type != SyncSchema.metaType else { continue }
            guard SyncSchema.type(record.key.type) != nil else { report.unknown += 1; continue }
            if record.isDeleted { markers.insert(record.key) } else { there[record.key] = record }
        }
        report.here = here.count
        report.inCloud = there.count
        report.markers = markers.count
        let present = Set(here.keys)
        for key in Set(here.keys).union(there.keys).union(markers).sorted() {
            switch (here[key], there[key]) {
            case (let mine?, let theirs?):
                let fields = differingFields(mine, shown(theirs, present: present))
                if fields.isEmpty { report.same += 1 } else { report.different.append(Difference(key: key, fields: fields)) }
            case (.some, nil):
                if markers.contains(key) { report.deletedInCloud.append(key) } else { report.onlyHere.append(key) }
            case (nil, .some):
                report.onlyInCloud.append(key)
            case (nil, nil):
                break // a marker for an item that is not here: as it should be
            }
        }
        return report
    }

    /// iCloud's record as this device can show it: without the references to items that are not here.
    static func shown(_ record: SyncRecord, present: Set<SyncKey>) -> SyncRecord {
        guard let type = SyncSchema.type(record.key.type) else { return record }
        var out = record
        for field in type.fields {
            switch (field.kind, record.fields[field.key]) {
            case (.reference(let target), .reference(let name)?):
                if !present.contains(SyncKey(type: target, name: name)) { out.fields[field.key] = nil }
            case (.references(let target), .referenceList(let names)?):
                let kept = names.filter { present.contains(SyncKey(type: target, name: $0)) }
                out.fields[field.key] = kept.isEmpty ? nil : .references(kept)
            default:
                break
            }
        }
        return out
    }

    /// The fields this build knows in which two records differ, as the merge reads them (`RecordMerge.normal`).
    static func differingFields(_ a: SyncRecord, _ b: SyncRecord) -> [String] {
        guard let one = RecordMerge.normal(a)?.comparable, let two = RecordMerge.normal(b)?.comparable else { return [] }
        return Set(one.fields.keys).union(two.fields.keys).filter { one.fields[$0] != two.fields[$0] }.sorted()
    }

    // MARK: - The read

    struct ZoneRead: Sendable {
        var records: [SyncRecord] = []
        var unreadable: [String] = []
        /// The zone is not there (nothing was ever sent, or it was removed).
        var zoneMissing = false
    }

    struct ReadFailed: Error, LocalizedError {
        var words: String
        var errorDescription: String? { words }
    }

    /// Every record of the zone as iCloud holds it now. Throws when iCloud did not answer to the end.
    static func readZone(containerID: String = SyncEngineSwitch.containerID, zoneName: String,
                         timeout: TimeInterval = 120,
                         progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> ZoneRead {
        let zoneID = CloudRecordCodec.zoneID(zoneName)
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: CKFetchRecordZoneChangesOperation.ZoneConfiguration()])
        operation.fetchAllChanges = true
        let configuration = CKOperation.Configuration()
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = timeout
        configuration.qualityOfService = .userInitiated
        operation.configuration = configuration
        let box = Box()
        operation.recordWasChangedBlock = { recordID, result in
            switch result {
            case .success(let record):
                do {
                    box.add(try CloudRecordCodec.cloudRecord(from: record).record)
                } catch CloudRecordCodec.DecodeProblem.notOurs {
                    // A record the engine did not write: nothing of the engine's to compare.
                } catch {
                    box.unreadable("\(recordID.recordName): \(error)")
                }
            case .failure(let error):
                box.unreadable("\(recordID.recordName): \(SyncState.shortReason(for: error))")
            }
            let count = box.count
            if count % 200 == 0 { progress(count) }
        }
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<ZoneRead, Error>) in
            let once = Once(done)
            operation.recordZoneFetchResultBlock = { _, result in
                if case .failure(let error) = result {
                    if ICloudZoneReader.isMissingZone(error) { box.zoneMissing() } else { box.fail(error) }
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    if let error = box.failure { once.fail(ReadFailed(words: SyncState.shortReason(for: error))) } else { once.give(box.value) }
                case .failure(let error):
                    if ICloudZoneReader.isMissingZone(error) || box.value.zoneMissing {
                        var read = box.value
                        read.zoneMissing = true
                        once.give(read)
                    } else {
                        once.fail(ReadFailed(words: SyncState.shortReason(for: box.failure ?? error)))
                    }
                }
            }
            database.add(operation)
            // A CloudKit call that hangs does not stop when cancelled (`ICloudCheck` learned it first): the answer is
            // raced against the clock, once, and the operation cancelled if the clock wins.
            Task {
                try? await Task.sleep(for: .seconds(timeout + 5))
                if once.fail(ReadFailed(words: "no answer within \(Int(timeout)) s")) { operation.cancel() }
            }
        }
    }

    // MARK: - The whole check

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// Reads iCloud and this device and compares them. `waiting` is what the engine says is waiting to go.
    static func run(container: ModelContainer, zoneName: String, waiting: Int,
                    progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> Report {
        let read = try await readZone(zoneName: zoneName, progress: progress)
        let local = try await Task.detached(priority: .userInitiated) {
            try SwiftDataSyncStore.read(nil, in: container)
        }.value
        var report = compare(local: local, cloud: read.records, waiting: waiting)
        report.unreadable = read.unreadable
        log.notice("engine audit: \(report.logLines.first ?? "", privacy: .public)")
        return report
    }

    // MARK: - Plumbing

    /// What CloudKit's callbacks gather, on its own queues.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var read = ZoneRead()
        private var error: Error?

        func add(_ record: SyncRecord) { lock.lock(); read.records.append(record); lock.unlock() }
        func unreadable(_ line: String) { lock.lock(); read.unreadable.append(line); lock.unlock() }
        func zoneMissing() { lock.lock(); read.zoneMissing = true; lock.unlock() }
        func fail(_ error: Error) { lock.lock(); self.error = error; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return read.records.count }
        var value: ZoneRead { lock.lock(); defer { lock.unlock() }; return read }
        var failure: Error? { lock.lock(); defer { lock.unlock() }; return error }
    }

    /// Resumes a continuation once, with whichever answer comes first; says whether this call was the one.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ZoneRead, Error>?
        init(_ continuation: CheckedContinuation<ZoneRead, Error>) { self.continuation = continuation }

        @discardableResult
        func give(_ value: ZoneRead) -> Bool {
            lock.lock(); let waiting = continuation; continuation = nil; lock.unlock()
            waiting?.resume(returning: value)
            return waiting != nil
        }

        @discardableResult
        func fail(_ error: Error) -> Bool {
            lock.lock(); let waiting = continuation; continuation = nil; lock.unlock()
            waiting?.resume(throwing: error)
            return waiting != nil
        }
    }
}
