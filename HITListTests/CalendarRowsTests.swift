import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Brief 77 items 3 and 4: an event row keeps the list's rhythm, and the lists ask for events only where they show.
@MainActor
final class CalendarRowsTests: XCTestCase {
    private func dayEvent(_ title: String = "Standup", start: Date, end: Date, allDay: Bool = false,
                          calendar: Calendar = .current) -> DayEvent {
        let event = CalendarEvent(id: title, title: title, start: start, end: end, isAllDay: allDay,
                                  calendarID: "work", colorHex: "#5E81F4")
        return CalendarDay.events([event], on: start, calendar: calendar)[0]
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: today)!
    }

    #if os(macOS)
    func testAnEventRowIsAsTallAsATaskRow() throws {
        let container = ModelContainerFactory.preview()
        let task = TaskItem(title: "Reply to Sam", dueDate: at(9, 30), hasDueTime: true)
        container.mainContext.insert(task)
        try container.mainContext.save()
        func height<V: View>(_ view: V) -> CGFloat {
            NSHostingView(rootView: view.frame(width: 420).modelContainer(container)).fittingSize.height
        }
        let taskRow = height(TaskRow(task: task, now: Date(), hidesDay: true, onToggleCompletion: {}))
        let eventRow = height(CalendarEventRow(event: dayEvent(start: at(9, 30), end: at(10, 15)), now: Date()))
        XCTAssertEqual(eventRow, taskRow, accuracy: 0.5)
        let allDay = height(CalendarEventRow(event: dayEvent("Off", start: today,
                                                             end: Calendar.current.date(byAdding: .day, value: 1, to: today)!,
                                                             allDay: true), now: Date()))
        XCTAssertEqual(allDay, taskRow, accuracy: 0.5)
        let long = height(CalendarEventRow(event: dayEvent(String(repeating: "A long meeting title ", count: 8),
                                                           start: at(9), end: at(10)), now: Date()))
        XCTAssertEqual(long, taskRow, accuracy: 0.5, "a long title truncates rather than wrapping")
    }
    #endif

    func testPastEventsDimOnlyOnceOver() {
        let morning = dayEvent(start: at(0, 10), end: at(0, 20))
        XCTAssertTrue(CalendarDay.isPast(morning, now: at(0, 30)))
        XCTAssertFalse(CalendarDay.isPast(morning, now: at(0, 15)))
    }
}
