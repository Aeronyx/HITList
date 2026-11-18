import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Brief 161: Upcoming's Week layout shows on each day exactly what Upcoming's list shows on it (the same tasks, from
/// the same source, in the same order), split into the all-day band and the timed grid; tasks at overlapping times
/// share the column; the window of days and the layout's default.
@MainActor
final class UpcomingWeekTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    /// What Upcoming builds its rows from: its open tasks, as `UpcomingView.entries` makes them with no completion
    /// animating.
    private func entries() throws -> [TaskListRow] {
        try context.fetch(UpcomingView.openTasks).map {
            TaskListRow(task: $0, filterDueDate: $0.dueDate, filterIsCompleted: $0.isCompleted)
        }
    }

    /// For every shown week (three days from several starts, and whole weeks), each day's items equal the list's for
    /// that day, its band is the list's all-day items and its grid the timed ones, each once.
    private func assertWeekMatchesList(at moments: [Date], file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try entries()
        let calendar = Calendar.current
        let strip = WeekStrip(calendar: calendar, weekStart: Preferences.weekStartWeekday())
        var compared = 0
        for now in moments {
            let list = UpcomingSchedule(items: rows, now: now, dayCount: 60, calendar: calendar)
            var listByDay: [Date: [UUID]] = [:]
            for day in list.days { listByDay[day.date] = day.items.map(\.id) }
            let today = calendar.startOfDay(for: now)
            for offset in [0, 1, 2, 5, 7, 14, 30] {
                for count in [3, 7] {
                    var window = UpcomingWeekWindow.startingToday(strip: strip, now: now)
                    window.move(by: offset)
                    let days = window.days(count: count, strip: strip, now: now)
                    let model = UpcomingWeekModel(items: rows, days: days, now: now, calendar: calendar)
                    XCTAssertEqual(model.days.map(\.date), days, file: file, line: line)
                    XCTAssertEqual(model.overdue.map(\.id), list.overdue.map(\.id), "Overdue is the list's",
                                   file: file, line: line)
                    for day in model.days {
                        let expected = day.date < today ? [] : listByDay[day.date] ?? []
                        XCTAssertEqual(day.items.map(\.id), expected, "\(day.date) at \(now)", file: file, line: line)
                        XCTAssertEqual(day.allDay.map(\.id), day.items.filter { !$0.filterHasDueTime }.map(\.id),
                                       file: file, line: line)
                        XCTAssertEqual(Set(day.timed.map(\.item.id)),
                                       Set(day.items.filter(\.filterHasDueTime).map(\.id)), file: file, line: line)
                        XCTAssertEqual(day.timed.count + day.allDay.count, day.items.count, file: file, line: line)
                        compared += day.items.count
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "the weeks showed tasks", file: file, line: line)
    }

    func testTheDemoWeekShowsWhatTheListShows() throws {
        let now = Date()
        TaskActions.seedDemoDataIfRequested(in: context, arguments: ["-seedDemoData"], storeName: "HITList-161.store",
                                            now: now)
        try assertWeekMatchesList(at: [now, now.addingTimeInterval(5 * 3600), now.addingTimeInterval(30 * 3600)])
    }

    func testAMixedStoreShowsWhatTheListShows() throws {
        let now = Date()
        try ListSamenessStore.fill(context, now: now)
        let every = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(every.contains { $0.isCompleted }, "the store has completed tasks")
        XCTAssertTrue(every.contains { $0.isSubtask }, "and sub-tasks")
        XCTAssertTrue(every.contains { $0.recurrenceRule != nil }, "and repeats")
        try assertWeekMatchesList(at: [now, now.addingTimeInterval(4 * 3600), now.addingTimeInterval(26 * 3600),
                                       now.addingTimeInterval(8 * 86_400)])
        // A completed task and a sub-task are never on the week, as never in the list.
        let rows = try entries()
        let strip = WeekStrip(weekStart: Preferences.weekStartWeekday())
        let days = UpcomingWeekWindow.startingToday(strip: strip, now: now).days(count: 7, strip: strip, now: now)
        let shown = UpcomingWeekModel(items: rows, days: days, now: now).days.flatMap(\.items)
        XCTAssertFalse(shown.contains { $0.filterIsCompleted || $0.filterIsSubtask })
    }

    /// Two tasks at one time share the column; one a quarter of an hour later overlaps both and takes a third column; one
    /// half an hour after them starts where their chips end and stands alone at full width, as does one at 11.
    func testTasksAtTheSameTimeShareTheColumn() throws {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        func at(_ hour: Int, _ minute: Int, _ title: String) -> TaskItem {
            var parts = DateComponents()
            parts.hour = hour
            parts.minute = minute
            let task = TaskItem(title: title, dueDate: calendar.date(byAdding: parts, to: tomorrow)!)
            task.hasDueTime = true
            context.insert(task)
            return task
        }
        let a = at(9, 0, "A"), b = at(9, 0, "B"), q = at(9, 15, "Q"), c = at(9, 45, "C"), d = at(11, 0, "D")
        let allDay = TaskItem(title: "All day", dueDate: tomorrow)
        context.insert(allDay)
        try context.save()

        let model = UpcomingWeekModel(items: try entries(), days: [tomorrow], now: now, calendar: calendar)
        let day = try XCTUnwrap(model.days.first)
        XCTAssertEqual(day.allDay.map(\.id), [allDay.id])
        let byID = Dictionary(uniqueKeysWithValues: day.timed.map { ($0.item.id, $0) })
        XCTAssertEqual(byID[a.id]?.minute, 9 * 60)
        XCTAssertEqual(byID[b.id]?.columns, 3)
        XCTAssertNotEqual(byID[a.id]?.column, byID[b.id]?.column)
        XCTAssertEqual(byID[q.id]?.column, 2)
        XCTAssertEqual(byID[q.id]?.columns, 3, "Q overlaps A and B")
        XCTAssertEqual(byID[a.id]?.columns, 3, "so the three share the width")
        XCTAssertEqual(byID[c.id]?.minute, 9 * 60 + 45)
        XCTAssertEqual(byID[c.id]?.columns, 1, "C starts as Q's chip ends")
        XCTAssertEqual(byID[d.id]?.column, 0)
        XCTAssertEqual(byID[d.id]?.columns, 1, "D stands alone")
    }

    /// iPhone's three days start today and move a day at a time; a whole week starts on the week's first day and moves a
    /// week at a time; neither goes before the current week.
    func testTheWindowOfDays() {
        let calendar = Calendar.current
        let strip = WeekStrip(calendar: calendar, weekStart: 2)
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var window = UpcomingWeekWindow.startingToday(strip: strip, now: now)
        XCTAssertEqual(window.days(count: 3, strip: strip, now: now).first, today)
        XCTAssertTrue(window.showsToday(count: 7, strip: strip, now: now))
        XCTAssertEqual(window.days(count: 7, strip: strip, now: now).first, strip.startOfWeek(containing: today))
        window.move(by: 1)
        XCTAssertEqual(window.days(count: 3, strip: strip, now: now).first,
                       calendar.date(byAdding: .day, value: 1, to: today))
        window.move(by: -100)
        XCTAssertEqual(window.offset, 0)
        XCTAssertEqual(window.days(count: 3, strip: strip, now: now).first, strip.startOfWeek(containing: today))
        window.move(by: 7)
        XCTAssertEqual(window.days(count: 7, strip: strip, now: now).first, strip.week(1, from: today))
        XCTAssertFalse(window.showsToday(count: 7, strip: strip, now: now))
    }

    /// Nobody's Upcoming changes until they choose: today's layout is the default and an unknown value reads as it.
    func testTodaysLayoutIsTheDefault() {
        XCTAssertEqual(UpcomingLayout.defaultValue, .tasks)
        XCTAssertNil(UpcomingLayout(rawValue: "board"))
        XCTAssertEqual(UpcomingLayout.tasks.title(showsBoard: false), "List")
        XCTAssertEqual(UpcomingLayout.tasks.title(showsBoard: true), "Board")
        XCTAssertEqual(UpcomingLayout.week.title(showsBoard: true), "Week")
    }

    #if os(macOS)
    /// The Mac's seven days, drawn offscreen in a window of the board's size with the demo week, two tasks at one time
    /// and a crowded all-day band: for the hand-over picture (`upcoming-week-mac.png` in the test host's temporary
    /// folder, and attached), and a check that the grid and the chips drew.
    func testTheMacsSevenDaysDraw() throws {
        let now = Date()
        TaskActions.seedDemoDataIfRequested(in: context, arguments: ["-seedDemoData"], storeName: "HITList-161.store",
                                            now: now)
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        for (title, priority) in [("Dentist forms", 3), ("Water filter", 1)] {
            context.insert(TaskItem(title: title, priority: priority,
                                    dueDate: calendar.date(byAdding: .hour, value: 9, to: tomorrow)!, hasDueTime: true))
        }
        for title in ["Pick up the parcel", "Call the bank", "Order printer ink"] {
            context.insert(TaskItem(title: title, dueDate: tomorrow))
        }
        try context.save()

        let size = CGSize(width: 1280, height: 760)
        let strip = WeekStrip(weekStart: Preferences.weekStartWeekday())
        let root = UpcomingWeekView(entries: try entries(), now: now, strip: strip, wholeWeek: true)
            .frame(width: size.width, height: size.height)
            .environment(PopoutController())
            .modelContainer(container)
            .font(HITType.body)
            .preferredColorScheme(.dark)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        defer { window.close() }
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        host.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("upcoming-week-mac.png")
        try png.write(to: url)
        print("UPCOMING_WEEK_PNG \(url.path)")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "upcoming-week-mac"
        attachment.lifetime = .keepAlways
        add(attachment)

        let background = rep.colorAt(x: 2, y: rep.pixelsHigh - 2)
        var differing = 0
        for y in stride(from: rep.pixelsHigh / 3, to: rep.pixelsHigh, by: 6) {
            for x in stride(from: rep.pixelsWide / 8, to: rep.pixelsWide, by: 6) where rep.colorAt(x: x, y: y) != background {
                differing += 1
            }
        }
        XCTAssertGreaterThan(differing, 200, "the grid and its chips drew")
    }
    #endif
}
