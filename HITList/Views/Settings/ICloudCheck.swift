import Foundation
import CloudKit
import OSLog

/// Settings → iCloud Sync → "Check iCloud…": one real round trip to CloudKit (account status, the
/// signed-in user's record id, the private database's zones) and a one-line report of what came back.
/// CloudKit mirroring itself can't be forced; this only proves the path to iCloud works.
struct ICloudCheck: Equatable, Sendable {
    /// The zone `NSPersistentCloudKitContainer` mirrors SwiftData into.
    static let mirrorZoneName = "com.apple.coredata.cloudkit.zone"
    /// A check that hasn't answered by then is reported as timed out.
    static let timeout: Duration = .seconds(20)

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    var account: CKAccountStatus?
    /// The container answered `fetchUserRecordID`; nil when not tried (no account).
    var reachable: Bool?
    /// Whether the mirror zone exists in the private database; nil when not tried.
    var zoneExists: Bool?
    /// A short reason when a step failed ("network unavailable", "timed out").
    var failure: String?
    var duration: TimeInterval
    /// This build talks to CloudKit Development (`SyncEnvironment.current`), whose data Production builds
    /// (TestFlight, App Store) never see, so the summary says so.
    var isDevelopmentEnvironment: Bool

    /// "iCloud available · container reachable · sync zone found · 0.8 s", or what failed, in plain words.
    var summary: String {
        var parts: [String] = []
        switch account {
        case .available?: parts.append("iCloud available")
        case .noAccount?: parts.append("Not signed in to iCloud")
        case .restricted?: parts.append("iCloud restricted on this device")
        case .temporarilyUnavailable?: parts.append("iCloud needs you to sign in again")
        case .couldNotDetermine?: parts.append("iCloud account unknown")
        case nil: break
        case let other?: parts.append("iCloud account status \(other.rawValue)")
        }
        switch reachable {
        case true?: parts.append("container reachable")
        case false?: parts.append("container unreachable")
        case nil: break
        }
        switch zoneExists {
        case true?: parts.append("sync zone found")
        case false?: parts.append("sync zone not created yet")
        case nil: break
        }
        if let failure { parts.append(account == nil ? "Couldn't reach iCloud: \(failure)" : failure) }
        parts.append(Self.seconds(duration))
        if isDevelopmentEnvironment { parts.append("Development environment") }
        return parts.joined(separator: " · ")
    }

    /// Everything that matters looked fine.
    var isHealthy: Bool { account == .available && reachable == true && zoneExists == true && failure == nil }

    static func seconds(_ interval: TimeInterval) -> String {
        interval < 10 ? String(format: "%.1f s", interval) : "\(Int(interval.rounded())) s"
    }

    /// Whether this build talks to CloudKit Development. It used to be true for every Mac build, the
    /// TestFlight one (Production) included, and false for an iPhone Debug build (Development).
    static var developmentEnvironment: Bool { SyncEnvironment.current.isDevelopment }

    // MARK: - Running it

    /// Runs the three calls in order, stopping at the first failure, within `timeout`.
    static func run(containerID: String = HITListSchema.cloudKitContainerID) async -> ICloudCheck {
        let clock = ContinuousClock()
        let start = clock.now
        let initial = ICloudCheck(duration: 0, isDevelopmentEnvironment: developmentEnvironment)
        let steps = Steps(containerID: containerID)
        // A race rather than a task group: a group waits for every child, and a CloudKit call that hangs
        // (no network, cloudd stuck) doesn't stop when cancelled.
        let finished: ICloudCheck? = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { once.resume(await steps.perform(into: initial)) }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(nil)
            }
        }
        var result = finished ?? initial
        if finished == nil { result.failure = "timed out after \(Int(timeout.components.seconds)) s" }
        let elapsed = clock.now - start
        result.duration = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        log.notice("Check iCloud: \(result.summary, privacy: .public)")
        return result
    }

    /// Resumes a continuation with the first value only.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ICloudCheck?, Never>?

        init(_ continuation: CheckedContinuation<ICloudCheck?, Never>) { self.continuation = continuation }

        func resume(_ value: ICloudCheck?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    private struct Steps: Sendable {
        let containerID: String

        func perform(into initial: ICloudCheck) async -> ICloudCheck {
            var result = initial
            let container = CKContainer(identifier: containerID)
            do {
                result.account = try await container.accountStatus()
            } catch {
                result.failure = SyncState.shortReason(for: error)
                return result
            }
            guard result.account == .available else { return result }
            do {
                _ = try await container.userRecordID()
                result.reachable = true
            } catch {
                result.reachable = false
                result.failure = SyncState.shortReason(for: error)
                return result
            }
            do {
                let zones = try await container.privateCloudDatabase.allRecordZones()
                result.zoneExists = zones.contains { $0.zoneID.zoneName == mirrorZoneName }
            } catch {
                result.failure = SyncState.shortReason(for: error)
            }
            return result
        }
    }
}
