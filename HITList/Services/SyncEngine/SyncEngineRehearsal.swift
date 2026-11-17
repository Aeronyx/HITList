#if DEBUG
import Foundation
import SwiftData
import HITListCore

/// Debug builds on a side store only: the move between the engines rehearsed from a terminal, on a Mac and on a
/// phone (`dev/SYNC-ENGINE.md` section 14, stage 4). Each hook runs what Settings runs, through the board's own
/// actions, and prints one line per thing (`REHEARSAL …`) and never a title, so two devices' runs can be read side
/// by side.
///
/// - `-syncEngineMoveNow own|mirror [-rehearsalDelay <seconds>]`: after the delay (the mirror's first import and
///   export need a while), the move, as the Settings row does it. A side store then asks to be reopened.
/// - `-syncEngineCheck YES`: on the engine, once the launch's sync has ended with nothing waiting, Check iCloud…
///   (`SyncEngineAudit`), printed line by line.
/// - `-syncMirrorAudit YES [-rehearsalDelay <seconds>]`: on the mirror, after the delay, the mirror's own audit
///   (`SyncAudit`), printed: how the way back is checked.
/// - `-rehearsalEdits <seed>`: on the engine, after the first check, a handful of ordinary edits made the way a
///   person makes them (`TaskActions`): two tasks completed, one renamed, one moved to another Group, one made, one
///   deleted, chosen by `seed` so that two devices choose differently; then another check once they have gone.
@MainActor
enum SyncEngineRehearsal {
    static func runIfAsked(container: ModelContainer, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard !ModelContainerFactory.isMainStoreOpen, !ModelContainerFactory.isRunningInMemory else { return }
        let delay = value("-rehearsalDelay", arguments).flatMap(Double.init) ?? 8
        if let target = value("-syncEngineMoveNow", arguments).flatMap(SyncEngineBoard.Engine.init(rawValue:)) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                let counts = Self.counts(container)
                do {
                    guard let actions = SyncEngineBoard.shared.actions else { return say("move: nothing is wired") }
                    try await actions.move(target)
                    say("move to \(target.rawValue): done; \(counts)")
                } catch {
                    say("move to \(target.rawValue): \(error.localizedDescription); \(counts)")
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
            guard open.count >= 12 else { return say("edits: only \(open.count) open tasks, nothing edited") }
            let groups = try context.fetch(FetchDescriptor<Project>()).sorted { $0.id.uuidString < $1.id.uuidString }
            func pick(_ n: Int) -> TaskItem { open[(seed * 7 + n * 13) % open.count] }
            var picked: [TaskItem] = []
            var n = 0
            while picked.count < 5 { let task = pick(n); n += 1; if !picked.contains(where: { $0 === task }) { picked.append(task) } }
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
