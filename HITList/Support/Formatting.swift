import SwiftUI
import HITListCore

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }

    static let palette: [(name: String, hex: String)] = [
        ("Red", "#E5484D"), ("Orange", "#F76B15"), ("Yellow", "#F5D90A"), ("Green", "#30A46C"),
        ("Teal", "#12A594"), ("Blue", "#5E81F4"), ("Purple", "#B07CF5"), ("Pink", "#E93D82"),
        ("Brown", "#AD7F58"), ("Gray", "#9A9A9A"),
    ]
}

extension Priority {
    var color: Color {
        switch self {
        case .p1: return Color(hex: "#FF6B6B")
        case .p2: return Color(hex: "#FFA657")
        case .p3: return Color(hex: "#6C9EFF")
        case .p4: return Color.secondary
        }
    }
    var symbol: String { self == .p4 ? "flag" : "flag.fill" }
}

enum DueFormatter {
    /// "Today", "Tomorrow", "Mon", "Oct 31", "Jan 5, 2027", with an optional time suffix.
    static func text(for date: Date, hasTime: Bool, now: Date = Date(), calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        var dayText: String
        switch days {
        case 0: dayText = "Today"
        case 1: dayText = "Tomorrow"
        case -1: dayText = "Yesterday"
        case 2...6: dayText = date.formatted(.dateTime.weekday(.wide))
        default:
            if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
                dayText = date.formatted(.dateTime.month(.abbreviated).day())
            } else {
                dayText = date.formatted(.dateTime.month(.abbreviated).day().year())
            }
        }
        if hasTime { dayText += " " + date.formatted(.dateTime.hour().minute()) }
        return dayText
    }

    static func isOverdue(_ date: Date, hasTime: Bool, isCompleted: Bool, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isCompleted else { return false }
        return hasTime ? date < now : date < calendar.startOfDay(for: now)
    }

    /// How `sectionTitle` names days from today on.
    enum SectionStyle {
        /// "Today", "Tomorrow", "Monday, Nov 2", "Mon, Nov 9, 2026": the widgets and the Duo's next days.
        case relative
        /// Every day in the lists' one form (`dayHeading`): "Oct 31 · Today · Saturday", "Nov 3 · Tuesday".
        case dated
    }

    /// Section header for grouping by due day. Days before today are all "Overdue".
    static func sectionTitle(for date: Date?, now: Date = Date(), style: SectionStyle = .relative,
                             calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date else { return "No date" }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        if day < today { return "Overdue" }
        if style == .dated { return dayHeading(for: date, now: now, calendar: calendar, locale: locale) }
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return date.formatted(format.weekday(.wide).month(.abbreviated).day())
        default: return date.formatted(format.weekday(.abbreviated).month(.abbreviated).day().year())
        }
    }

    /// A day as every list's header writes it (brief 99: Today's header, a Group's and a filter's date sections,
    /// Upcoming and the Mac board had four forms): the date, then "Today", "Tomorrow" or "Yesterday" when it is one,
    /// then the weekday. "Nov 11 · Today · Wednesday", "Nov 13 · Friday", another year "Jan 1, 2027 · Friday".
    /// `shortWeekday` gives "Wed", for a line that does not fit (`DayHeadingLine`).
    static func dayHeading(for date: Date, now: Date = Date(), shortWeekday: Bool = false, calendar: Calendar = .current,
                           locale: Locale = .current) -> String {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var parts = [date.formatted(sameYear ? format.month(.abbreviated).day() : format.month(.abbreviated).day().year())]
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                             to: calendar.startOfDay(for: date)).day ?? 0
        switch offset {
        case 0: parts.append("Today")
        case 1: parts.append("Tomorrow")
        case -1: parts.append("Yesterday")
        default: break
        }
        parts.append(date.formatted(format.weekday(shortWeekday ? .abbreviated : .wide)))
        return parts.joined(separator: " · ")
    }

    /// "Oct 31, Saturday"; another year adds it: "Jan 2, 2027, Saturday". The Today widget's header.
    static func dayTitle(for date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = date.formatted(sameYear ? format.month(.abbreviated).day() : format.month(.abbreviated).day().year())
        return "\(day), \(date.formatted(format.weekday(.wide)))"
    }

    /// The time alone, "5:30 PM", for rows whose day the section header already says.
    static func timeText(for date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
    }

    /// A day section header's colour: "Overdue" red, today green (`HITColor.due`'s rule), others grey.
    static func sectionColor(for date: Date?, now: Date = Date(), calendar: Calendar = .current) -> Color {
        guard let date else { return Theme.secondaryText }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        if day < today { return HITColor.dueOverdue }
        return day == today ? HITColor.dueToday : Theme.secondaryText
    }
}
