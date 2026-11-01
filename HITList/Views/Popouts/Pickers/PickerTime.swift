import Foundation
import HITListCore

/// A time of day picked in a card. Pure, so tests can pin the parsing.
struct PickerTime: Equatable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// What the time row accepts: "9am", "9:00 AM" (as the row itself writes it), "17:30", "noon",
    /// "midnight", "at 5" and a bare "5" (5 pm, the quick-add rule for 1–6), "9" (9 am). The whole text
    /// must be the time: "9am tomorrow" is not one. `DateExpressionParser.matchTime` does the work.
    static func parse(_ raw: String) -> PickerTime? {
        var text = raw.lowercased()
        // `Date.formatted` puts a narrow no-break space before AM/PM; "a.m." loses its dots.
        for space in ["\u{202F}", "\u{00A0}"] { text = text.replacingOccurrences(of: space, with: " ") }
        text = text.replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let parser = DateExpressionParser()
        if let match = parser.matchTime(in: words, at: 0), match.consumed == words.count {
            return PickerTime(hour: match.hour, minute: match.minute)
        }
        if words[0] != "at", let match = parser.matchTime(in: ["at"] + words, at: 0), match.consumed == words.count + 1 {
            return PickerTime(hour: match.hour, minute: match.minute)
        }
        return nil
    }

    /// "9:00 AM" (or "09:00" in a 24-hour locale), the way the row shows it.
    func text(locale: Locale = .current, calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.locale = locale
        let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.startOfDay(for: Date()))!
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.calendar = cal
        style.timeZone = cal.timeZone
        return date.formatted(style)
    }

    /// This time on `day`.
    func on(_ day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day))!
    }
}
