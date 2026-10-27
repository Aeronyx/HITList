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

    /// Section header for grouping by due day.
    static func sectionTitle(for date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "No date" }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        if day < today { return "Overdue" }
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        default: return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        }
    }
}
