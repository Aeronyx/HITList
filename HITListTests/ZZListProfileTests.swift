import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Throwaway (round 34): where a tab switch's time goes with 1,500 tasks.
@MainActor
final class ZZListProfileTests: XCTestCase {
    func testProfile() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HITLIST_PROFILE"] == "1")
        let url = FileManager.default.temporaryDirectory.appending(path: "zzprofile-\(UUID().uuidString).store")
        let schema = ModelContainerFactory.preview().schema
        let opened = ModelContainerFactory.open(schema: schema, url: url, useCloudKit: false)
        let container = opened.container
        let context = container.mainContext
        TaskActions.seedSyncLoadIfRequested(in: context, arguments: ["x", "-seedSyncLoad", "1500"], storeName: "HITList-zz.store")
        try context.save()
        func time<T>(_ name: String, runs: Int = 5, _ work: () throws -> T) rethrows -> T {
            var best = Double.infinity
            var result: T!
            for _ in 0..<runs {
                let start = CFAbsoluteTimeGetCurrent()
                result = try work()
                best = min(best, CFAbsoluteTimeGetCurrent() - start)
            }
            print("PROFILE \(name): \(String(format: "%.1f", best * 1000)) ms")
            return result
        }
        let now = Date()
        let all: [TaskItem] = try time("fetch all (new context)") {
            try ModelContext(container).fetch(FetchDescriptor<TaskItem>())
        }
        _ = try time("fetch all + touch (new context)") { () -> Int in
            let items = try ModelContext(container).fetch(FetchDescriptor<TaskItem>())
            var n = 0
            for item in items { n += item.title.count + (item.dueDate == nil ? 0 : 1) + (item.isCompleted ? 1 : 0) + (item.project == nil ? 0 : 1) + item.priority }
            return n
        }
        let held: [TaskItem] = try context.fetch(FetchDescriptor<TaskItem>())
        _ = time("touch 5 properties of each (held)") { () -> Int in
            var n = 0
            for item in held { n += item.title.count + (item.dueDate == nil ? 0 : 1) + (item.isCompleted ? 1 : 0) + (item.project == nil ? 0 : 1) + item.priority }
            return n
        }
        let own: [TaskItem] = time("TaskOrdering.inbox") { TaskOrdering.inbox(held, includeCompleted: false, now: now) }
        let noShared: [SharedRow] = []
        let rows: [TaskListRow] = time("ListRows.rows") { ListRows.rows(own: own, shared: noShared) }
        let sorted: [TaskListRow] = time("TaskOrdering.sorted") { TaskOrdering.sorted(rows, now: now) }
        _ = time("InboxReview.count") { InboxReview.count(held) }
        _ = time("ListClock.next") { ListClock.next(after: now, tasks: held, shared: noShared) }
        _ = time("ListSources.of") { ListSources.of(held) }
        let open: [TaskItem] = try context.fetch(UpcomingView.openTasks)
        _ = time("fetch open (new context)") { (try? ModelContext(container).fetch(UpcomingView.openTasks))?.count ?? 0 }
        let top: [TaskItem] = time("topLevel") { TaskOrdering.topLevel(open) }
        _ = time("UpcomingSchedule (14 days)") { UpcomingSchedule(items: top, now: now, dayCount: 14, calendar: .current) }
        _ = time("UpcomingSchedule.counts") { UpcomingSchedule.counts(of: top, calendar: .current) }
        _ = time("isInToday filter") { held.filter { TaskOrdering.isInToday($0, now: now) }.count }
        print("PROFILE counts: all \(all.count), inbox \(own.count), sorted \(sorted.count), open \(open.count)")
    }
}
