import Foundation
import HITListCore

/// The quick add guide (brief 98, George 2026-11-11: "a '?' help page … to explain/show very concisely to users how
/// to use the quickadd system to the fullest"). Each example is something a person would type, drawn with the real
/// parser's highlights (`QuickAddGuideLine`), with a caption of a few words. What each caption says is written down
/// as claims beside it, and `QuickAddGuideTests` parses every example and checks every claim, so the page cannot
/// drift from the parser. Dates are computed from today: a picture taken tomorrow is still right.
enum QuickAddGuide {
    /// The page's title in the Settings sheet (a back control's words stay within ten characters).
    static let pageTitle = "Quick add"
    /// The row in Settings → General and in Browse.
    static let rowTitle = "Quick add guide"
    static let rowSubtitle = "Words a task's name understands"
    /// The Mac's Help menu item.
    static let menuTitle = "Quick Add Guide"
    static let systemImage = "questionmark.circle"

    struct Section: Identifiable, Equatable {
        let title: String
        let examples: [Example]
        var id: String { title }
    }

    struct Example: Identifiable, Equatable {
        let typed: String
        let caption: String
        /// What the caption says, as the parser must read it.
        let claims: [Claim]
        var id: String { typed }
    }

    /// One thing an example's caption says the parser does with it.
    enum Claim: Equatable {
        /// What is left as the task's name.
        case title(String)
        /// Due on that day, with no time.
        case day(Date)
        /// Due at that moment.
        case moment(Date)
        /// No due date at all.
        case noDate
        /// The repeat, by its stored form (`RecurrenceRule.encoded`).
        case repeats(String)
        case priority(Priority)
        case group(String)
        case labels([String])
        /// A reminder this many minutes before the due time.
        case reminderBefore(Int)
        /// A reminder this many minutes from now.
        case reminderIn(Int)
        /// The name once the example's (only) highlight is tapped off.
        case titleWhenTapped(String)
    }

    /// The parser the page draws with (and the tests check with): no known Groups or labels, so `#Work` and
    /// `@errand` read as anyone's would.
    static func parser(now: Date, calendar: Calendar, weekStart: Int) -> QuickAddParser {
        QuickAddParser(now: now, calendar: calendar, weekStart: weekStart)
    }

    /// The page, for a person typing at `now`.
    static func sections(now: Date = Date(), calendar: Calendar = .current,
                         weekStart: Int = Preferences.weekStartWeekday()) -> [Section] {
        let dates = Dates(now: now, calendar: calendar, weekStart: weekStart)
        let friday = dates.next(6, inclusive: false)
        let nextMonday = dates.nextWeeksMonday
        let later = dates.day(19)
        let laterTyped = dates.typed(later)
        let laterParts = calendar.dateComponents([.month, .day], from: later)
        let laterSlash = "\(laterParts.month ?? 1)/\(laterParts.day ?? 1)"

        return [
            Section(title: "When", examples: [
                Example(typed: "pay rent fri", caption: "The coming Friday, \(dates.caption(friday))",
                        claims: [.title("pay rent"), .day(friday)]),
                Example(typed: "dentist \(laterTyped)", caption: "That day; \(laterSlash) works too",
                        claims: [.title("dentist"), .day(later)]),
                Example(typed: "renew passport in 3 days", caption: "Weeks and months too",
                        claims: [.title("renew passport"), .day(dates.day(3))]),
                Example(typed: "team lunch next mon", caption: "Monday next week, \(dates.caption(nextMonday))",
                        claims: [.title("team lunch"), .day(nextMonday)]),
                Example(typed: "standup tom 9", caption: "Tomorrow 09:00; 24-hour unless am or pm",
                        claims: [.title("standup"), .moment(dates.at(dates.day(1), 9))]),
                // Brief 127: "tonight" is today, with no hour of its own.
                Example(typed: "dinner tonight 8pm", caption: "Today 8 PM; tonight is a day, not a time",
                        claims: [.title("dinner"), .moment(dates.at(dates.day(0), 20))]),
                Example(typed: "call back in 2 hours", caption: "Two hours from now",
                        claims: [.title("call back"), .moment(dates.minute.addingTimeInterval(2 * 3600))]),
            ]),
            Section(title: "Repeats", examples: [
                Example(typed: "water plants every 3 days starting fri", caption: "Every 3 days from Friday, \(dates.caption(friday))",
                        claims: [.title("water plants"), .repeats("daily;3"), .day(friday)]),
                Example(typed: "vacuum tue thu sat", caption: "Weekly on those days",
                        claims: [.title("vacuum"), .repeats("weekly;1;3,5,7")]),
                Example(typed: "standup weekdays 9am", caption: "Monday to Friday at 9:00",
                        claims: [.title("standup"), .repeats("weekly;1;2,3,4,5,6;;09:00")]),
                Example(typed: "rent every month on the 28th", caption: "Monthly on the 28th",
                        claims: [.title("rent"), .repeats("monthly;1;;28;;d28")]),
                Example(typed: "book club every last fri", caption: "The last Friday of each month",
                        claims: [.title("book club"), .repeats("monthly;1;;;;w6#-1")]),
            ]),
            Section(title: "Reminders", examples: [
                Example(typed: "haircut tom 11am !15mb", caption: "15 min before its time; !1hb, !1db",
                        claims: [.title("haircut"), .moment(dates.at(dates.day(1), 11)), .reminderBefore(15)]),
                Example(typed: "tea !10m", caption: "In 10 minutes; lights up after a space",
                        claims: [.title("tea"), .noDate, .reminderIn(10)]),
            ]),
            Section(title: "Priority, labels and Groups", examples: [
                Example(typed: "fix the leak p1", caption: "Priority 1; p2 and p3 too",
                        claims: [.title("fix the leak"), .priority(.p1)]),
                Example(typed: "buy stamps @errand", caption: "The errand label",
                        claims: [.title("buy stamps"), .labels(["errand"])]),
                Example(typed: "fix the sink #\"Home Repairs\"", caption: "A Group; quotes for a name with spaces",
                        claims: [.title("fix the sink"), .group("Home Repairs")]),
            ]),
            Section(title: "Good to know", examples: [
                Example(typed: "email \"tomorrow\" agenda fri", caption: "Quotes keep a word in the name",
                        claims: [.title("email tomorrow agenda"), .day(friday)]),
                Example(typed: "call mom fri tom", caption: "The last date wins: tomorrow",
                        claims: [.title("call mom fri"), .day(dates.day(1))]),
                Example(typed: "watch Friday Night Lights", caption: "Tap a highlight to keep its words",
                        claims: [.day(friday), .titleWhenTapped("watch Friday Night Lights")]),
            ]),
        ]
    }

    /// The dates the examples are typed on and land on, worked out on their own (not by the parser).
    struct Dates {
        let now: Date
        let calendar: Calendar
        let weekStart: Int

        var today: Date { calendar.startOfDay(for: now) }
        /// `now` to the minute, as "in 2 hours" counts from.
        var minute: Date { calendar.dateInterval(of: .minute, for: now)?.start ?? now }

        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        func at(_ day: Date, _ hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }

        /// The next day on `weekday` (1 = Sunday … 7 = Saturday): today counts only when `inclusive`.
        func next(_ weekday: Int, inclusive: Bool) -> Date {
            let todays = calendar.component(.weekday, from: today)
            var ahead = (weekday - todays + 7) % 7
            if ahead == 0, !inclusive { ahead = 7 }
            return day(ahead)
        }

        /// "next mon": the Monday of next week, the week starting on `weekStart`.
        var nextWeeksMonday: Date {
            let back = (calendar.component(.weekday, from: today) - weekStart + 7) % 7
            let nextWeek = day(7 - back)
            let ahead = (2 - calendar.component(.weekday, from: nextWeek) + 7) % 7
            return calendar.date(byAdding: .day, value: ahead, to: nextWeek) ?? nextWeek
        }

        private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

        /// "nov 30": how a person types the day.
        func typed(_ date: Date) -> String {
            let parts = calendar.dateComponents([.month, .day], from: date)
            return "\(Self.months[(parts.month ?? 1) - 1]) \(parts.day ?? 1)"
        }

        /// "Nov 13": the day in the caption (its weekday is in the caption's words).
        func caption(_ date: Date) -> String {
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }
    }
}
