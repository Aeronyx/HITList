#if DEBUG
import CloudKit
import Foundation
import SwiftData
import HITListCore

/// Debug builds on a side store only: the move between the engines rehearsed from a terminal, on a Mac and on a
/// phone (`dev/SYNC-ENGINE.md` section 14, stage 4). Each hook runs what Settings runs, through the board's own
/// actions, and prints one line per thing (`REHEARSAL …`) and never a title, so two devices' runs can be read side
/// by side.
///
/// - `-syncEngineMoveNow own|mirror|mirror-fresh [-rehearsalDelay <seconds>]`: after the delay (the mirror's first
///   import and export need a while), the move, as the Settings row does it (`mirror-fresh`: the way back with a
///   fresh copy, for every device but the first). A side store then asks to be reopened.
/// - `-syncEngineCheck YES`: on the engine, once the launch's sync has ended with nothing waiting, Check iCloud…
///   (`SyncEngineAudit`), printed line by line.
/// - `-syncMirrorAudit YES [-rehearsalDelay <seconds>]`: on the mirror, after the delay, the mirror's own audit
///   (`SyncAudit`), printed: how the way back is checked.
/// - `-rehearsalEdits <seed>`: on the engine, after the first check, a handful of ordinary edits made the way a
///   person makes them (`TaskActions`): two tasks completed, one renamed, one moved to another Group, one made, one
///   deleted, chosen by `seed` so that two devices choose differently; then another check once they have gone.
/// - `-rehearsalRollout go|pause|clear [-rehearsalRolloutMinBuild <n>]` (round 34, brief 170): writes, pauses or
///   deletes the word that lets every device move (`SyncEngineRollout`, `HLRollout/everyone` in the engine's
///   container's public database: Development for a Debug build). `go` writes `paused` 0 and `minBuild` as given
///   (none: every build); `pause` writes `paused` 1 and keeps `minBuild`.
/// - `-rehearsalRolloutAsk YES`: asks the question as a release build asks it (`CloudKitRollout`) and prints the
///   answer, the sync log's line, and this account's user record name in this environment.
@MainActor
enum SyncEngineRehearsal {
    static func runIfAsked(container: ModelContainer, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard !ModelContainerFactory.isMainStoreOpen, !ModelContainerFactory.isRunningInMemory else { return }
        let delay = value("-rehearsalDelay", arguments).flatMap(Double.init) ?? 8
        // `mirror-fresh`: the way back for every device but the first (a fresh copy at the next launch).
        let asked = value("-syncEngineMoveNow", arguments)
        let fresh = asked == "mirror-fresh"
        if let target = (fresh ? "mirror" : asked).flatMap(SyncEngineBoard.Engine.init(rawValue:)) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                let counts = Self.counts(container)
                do {
                    guard let actions = SyncEngineBoard.shared.actions else { return say("move: nothing is wired") }
                    try await actions.move(target, fresh)
                    say("move to \(target.rawValue)\(fresh ? " with a fresh copy" : ""): done; \(counts)")
                } catch {
                    say("move to \(target.rawValue)\(fresh ? " with a fresh copy" : ""): \(error.localizedDescription); \(counts)")
                }
            }
        }
        if arguments.contains("-syncMirrorAudit") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                switch await SyncAudit.run(container: container) {
                case .failed(let words):
                    say("mirror audit failed: \(words)")
                case .report(let report):
                    say("mirror audit: \(report.agree ? "agree" : "DIFFER"); \(SyncAuditWords.logLine(report).message); "
                        + "read \(report.recordsRead), \(Self.counts(container))")
                    for kind in [SyncComparison.Difference.Kind.onlyHere, .onlyThere, .newerHere, .newerThere] {
                        let items = report.items(kind)
                        if !items.isEmpty { say("mirror audit \(kind.rawValue): \(items.count)") }
                    }
                }
            }
        }
        if arguments.contains("-rehearsalListBackups") {
            // File names and dates only: when the real store's daily backups were last written on this device.
            let names = LocalBackup.backups(in: LocalBackup.directory).map(\.lastPathComponent)
            say("backups in Documents: \(names.count): \(names.suffix(6).joined(separator: ", "))")
            let aside = (try? FileManager.default.contentsOfDirectory(atPath: LocalBackup.setAsideRoot.path)) ?? []
            for folder in aside {
                let inside = LocalBackup.backups(in: LocalBackup.setAsideRoot.appending(path: folder)).map(\.lastPathComponent)
                say("backups set aside (\(folder.prefix(8))): \(inside.count): \(inside.suffix(4).joined(separator: ", "))")
            }
            let real = UserDefaults(suiteName: AppGroup.suiteName(suffix: nil))?.object(forKey: LocalBackup.lastBackupKey) as? Date
            say("the real store's last backup, by its own note: \(real.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "none")")
        }
        if arguments.contains("-rehearsalRawChanges") {
            // CloudKit asked directly, beside the engine: which zones the database says changed since the token this
            // hook kept at its last run, and which subscriptions exist. To tell the engine's fault from iCloud's.
            Task { @MainActor in
                let database = CKContainer(identifier: SyncEngineSwitch.containerID).privateCloudDatabase
                let key = "rehearsal.rawDatabaseToken"
                let kept = AppGroup.defaults.data(forKey: key)
                    .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
                do {
                    let changes = try await database.databaseChanges(since: kept)
                    say("raw database changes since \(kept == nil ? "nothing" : "the kept token"): changed \(changes.modifications.map(\.zoneID.zoneName).sorted()), deleted \(changes.deletions.map(\.zoneID.zoneName).sorted()), more \(changes.moreComing)")
                    if let data = try? NSKeyedArchiver.archivedData(withRootObject: changes.changeToken, requiringSecureCoding: true) {
                        AppGroup.defaults.set(data, forKey: key)
                    }
                } catch {
                    say("raw database changes failed: \(SyncState.shortReason(for: error))")
                }
                do {
                    let subscriptions = try await database.allSubscriptions()
                    say("subscriptions: \(subscriptions.map(\.subscriptionID).sorted())")
                } catch {
                    say("subscriptions failed: \(SyncState.shortReason(for: error))")
                }
            }
        }
        if let word = value("-rehearsalRollout", arguments) {
            let minBuild = value("-rehearsalRolloutMinBuild", arguments).flatMap(Int64.init)
            Task { @MainActor in say(await rollout(word, minBuild: minBuild)) }
        }
        if value("-rehearsalRolloutAsk", arguments) == "YES" {
            Task { @MainActor in
                let answer = await CloudKitRollout(log: { say("rollout log: \($0)") }).answer()
                say("rollout ask: \(answer.rawValue)")
                do {
                    let me = try await CKContainer(identifier: SyncEngineSwitch.containerID).userRecordID()
                    say("rollout: this account's user record here is \(me.recordName)")
                } catch {
                    say("rollout: this account's user record failed: \(SyncState.shortReason(for: error))")
                }
            }
        }
        let edits = value("-rehearsalEdits", arguments).flatMap(Int.init)
        if arguments.contains("-syncEngineCheck") || edits != nil {
            Task { @MainActor in
                await quiet()
                await check("first")
                guard let edits else { return }
                Self.edit(container, seed: edits)
                // The saves' hints reach the brain, the sends go, and the status comes back to idle with nothing waiting.
                try? await Task.sleep(for: .seconds(2))
                await quiet()
                await check("after the edits")
            }
        }
    }

    /// The word written, paused or deleted in the engine's container's public database: one line back.
    private static func rollout(_ word: String, minBuild: Int64?) async -> String {
        let database = CKContainer(identifier: SyncEngineSwitch.containerID).publicCloudDatabase
        let id = SyncEngineRollout.recordID
        do {
            switch word {
            case "go", "pause":
                // The record as it is (to change it in place), or a new one.
                let record: CKRecord
                do {
                    record = try await database.record(for: id)
                } catch let error where SyncEngineRollout.isUnknownItem(error) {
                    record = CKRecord(recordType: SyncEngineRollout.recordType, recordID: id)
                }
                record[SyncEngineRollout.pausedField] = (word == "pause" ? 1 : 0) as Int64
                if word == "go" { record[SyncEngineRollout.minBuildField] = minBuild.map { $0 as NSNumber } }
                let saved = try await database.save(record)
                let fields = SyncEngineRollout.Fields(record: saved)
                return "rollout \(word): saved, paused \(fields.paused.map { "\($0)" } ?? "none"), "
                    + "minBuild \(fields.minBuild.map { "\($0)" } ?? "none")"
            case "clear":
                do {
                    _ = try await database.deleteRecord(withID: id)
                    return "rollout clear: deleted"
                } catch let error where SyncEngineRollout.isUnknownItem(error) {
                    return "rollout clear: there was no record"
                }
            default:
                return "rollout: unknown word \(word) (go, pause or clear)"
            }
        } catch {
            return "rollout \(word) failed: \(SyncState.shortReason(for: error))"
        }
    }

    private static func say(_ line: String) {
        print("REHEARSAL \(line)")
        fflush(stdout)
    }

    private static func value(_ name: String, _ arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// "26 tasks, 3 Groups, 3 labels, 4 filters, 2 boards".
    static func counts(_ container: ModelContainer) -> String {
        let context = container.mainContext
        func count<M: PersistentModel>(_ model: M.Type) -> Int { (try? context.fetchCount(FetchDescriptor<M>())) ?? -1 }
        return "\(count(TaskItem.self)) tasks, \(count(Project.self)) Groups, \(count(TaskLabel.self)) labels, "
            + "\(count(SavedFilter.self)) filters, \(count(Switchboard.self)) boards"
    }

    /// Waits until the engine is idle after its first whole fetch with nothing waiting, for five minutes at most.
    private static func quiet() async {
        for _ in 0..<600 {
            if let status = SyncEngineBoard.shared.status, status.state == .idle, status.firstFetchDone, status.waiting == 0 {
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        say("the engine did not come to rest in five minutes: \(SyncEngineBoard.shared.status.map { "\($0.state), waiting \($0.waiting)" } ?? "no status")")
    }

    private static func check(_ when: String) async {
        guard let check = SyncEngineBoard.shared.actions?.check else { return say("check (\(when)): not on the engine") }
        do {
            let started = Date()
            let report = try await check { _ in }
            say("check (\(when)): \(report.isSame ? "SAME" : "DIFFERS") in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
            for line in report.logLines { say("check (\(when)): \(line)") }
        } catch {
            say("check (\(when)) failed: \(SyncEngineWords.error(error))")
        }
    }

    /// A handful of ordinary edits, each through the road a person's tap takes.
    private static func edit(_ container: ModelContainer, seed: Int) {
        let context = container.mainContext
        do {
            let open = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted && $0.parent == nil }))
                .sorted { $0.id.uuidString < $1.id.uuidString }
            guard open.count >= 5 else {
                // A short list (the earlier runs completed and deleted most of it): one made, one renamed if any.
                let made = TaskItem(title: "Rehearsal task \(seed)")
                context.insert(made)
                if let first = open.first {
                    first.title += " (edited \(seed))"
                    first.updatedAt = Date()
                }
                try context.save()
                return say("edits (seed \(seed), a short list): made \(short(made.id))\(open.first.map { ", renamed \(short($0.id))" } ?? ""); \(counts(container))")
            }
            let groups = try context.fetch(FetchDescriptor<Project>()).sorted { $0.id.uuidString < $1.id.uuidString }
            // Five different tasks, starting where the seed says, so two devices mostly choose differently.
            let picked = (0..<5).map { open[(seed + $0) % open.count] }
            let now = Date()
            TaskActions.toggleCompletion(picked[0], in: context)
            TaskActions.toggleCompletion(picked[1], in: context)
            picked[2].title += " (edited \(seed))"
            picked[2].updatedAt = now
            if let group = groups.first(where: { $0 !== picked[3].project }) { TaskActions.setProject(group, of: picked[3], in: context) }
            let deleted = picked[4].id
            TaskActions.delete(picked[4], in: context)
            let made = TaskItem(title: "Rehearsal task \(seed)")
            context.insert(made)
            try context.save()
            say("edits (seed \(seed)): completed \(short(picked[0].id)) and \(short(picked[1].id)), renamed \(short(picked[2].id)), "
                + "moved \(short(picked[3].id)), deleted \(short(deleted)), made \(short(made.id)); \(counts(container))")
        } catch {
            say("edits failed: \(error)")
        }
    }

    private static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
}
#endif
