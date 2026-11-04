import Foundation

/// The celebrations HITList marks (brief 44): US-centric, each with a window of days around it, plus the
/// March and September equinoxes and the June solstice. December's solstice always falls inside
/// Christmas's window, so it has no case of its own.
///
/// `Holiday.on(_:calendar:)` decides by the calendar's own day (its time zone), so a task completed at
/// 11 pm on December 17 in New York is not Christmas yet wherever the clock says otherwise.
public enum Holiday: String, CaseIterable, Sendable {
    /// December 31 and January 1.
    case newYear
    /// February 14.
    case valentines
    /// March 17.
    case stPatricks
    /// July 3 and 4.
    case independenceDay
    /// October 24 to 31.
    case halloween
    /// The fourth Thursday of November through that Sunday.
    case thanksgiving
    /// December 18 to 26.
    case christmas
    /// The day of the March equinox.
    case springEquinox
    /// The day of the June solstice.
    case summerSolstice
    /// The day of the September equinox.
    case autumnEquinox

    public var displayName: String {
        switch self {
        case .newYear: "New Year"
        case .valentines: "Valentine's Day"
        case .stPatricks: "St Patrick's Day"
        case .independenceDay: "July 4th"
        case .halloween: "Halloween"
        case .thanksgiving: "Thanksgiving"
        case .christmas: "Christmas"
        case .springEquinox: "Spring equinox"
        case .summerSolstice: "Summer solstice"
        case .autumnEquinox: "Autumn equinox"
        }
    }

    /// A name as typed on a command line (`-forceHoliday christmas`): the case name in any case, or a
    /// common short form ("july4", "newyear", "valentine").
    public init?(argument: String) {
        let key = argument.lowercased().filter { $0.isLetter || $0.isNumber }
        if let match = Holiday.allCases.first(where: { $0.rawValue.lowercased() == key }) {
            self = match
            return
        }
        switch key {
        case "july4", "july4th", "fourthofjuly", "4thofjuly", "independence": self = .independenceDay
        case "newyears", "newyearseve", "nye": self = .newYear
        case "valentine", "valentinesday": self = .valentines
        case "stpatrick", "stpatricksday", "stpaddys", "patricks": self = .stPatricks
        case "xmas": self = .christmas
        case "spring", "equinox": self = .springEquinox
        case "summer", "solstice": self = .summerSolstice
        case "autumn", "fall": self = .autumnEquinox
        default: return nil
        }
    }

    /// The celebration `date` falls in on `calendar`'s days, or nil on an ordinary day.
    public static func on(_ date: Date, calendar: Calendar = .current) -> Holiday? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        switch (month, day) {
        case (12, 31), (1, 1): return .newYear
        case (2, 14): return .valentines
        case (3, 17): return .stPatricks
        case (7, 3), (7, 4): return .independenceDay
        case (10, 24...31): return .halloween
        case (12, 18...26): return .christmas
        default: break
        }
        if month == 11, let thursday = thanksgiving(in: year, calendar: calendar) {
            let first = calendar.component(.day, from: thursday)
            if (first...(first + 3)).contains(day) { return .thanksgiving }
        }
        let seasons: [(Holiday, Int, (Int) -> Date)] = [
            (.springEquinox, 3, Seasons.marchEquinox),
            (.summerSolstice, 6, Seasons.juneSolstice),
            (.autumnEquinox, 9, Seasons.septemberEquinox),
        ]
        for (holiday, seasonMonth, instant) in seasons where month == seasonMonth {
            if calendar.isDate(date, inSameDayAs: instant(year)) { return holiday }
        }
        return nil
    }

    /// The fourth Thursday of November in `year`, at the start of its day on `calendar`.
    public static func thanksgiving(in year: Int, calendar: Calendar = .current) -> Date? {
        var parts = DateComponents(year: year, month: 11)
        parts.weekday = 5 // Thursday, whatever the calendar's first weekday
        parts.weekdayOrdinal = 4
        return calendar.date(from: parts).map { calendar.startOfDay(for: $0) }
    }
}

/// The instants of the solstices and equinoxes (Meeus, *Astronomical Algorithms*, ch. 27: the mean
/// instant for 2000–3000 plus the 24 periodic terms), good to a couple of minutes, which is all a day
/// needs. Times are in UTC; terrestrial time's ~70 s lead over it is ignored.
public enum Seasons {
    public static func marchEquinox(_ year: Int) -> Date {
        instant(year, [2451623.80984, 365242.37404, 0.05169, -0.00411, -0.00057])
    }

    public static func juneSolstice(_ year: Int) -> Date {
        instant(year, [2451716.56767, 365241.62603, 0.00325, 0.00888, -0.00030])
    }

    public static func septemberEquinox(_ year: Int) -> Date {
        instant(year, [2451810.21715, 365242.01767, -0.11575, 0.00337, 0.00078])
    }

    public static func decemberSolstice(_ year: Int) -> Date {
        instant(year, [2451900.05952, 365242.74049, -0.06223, -0.00823, 0.00032])
    }

    /// Amplitude, phase (degrees) and rate (degrees per Julian century): Meeus table 27.C.
    private static let terms: [(Double, Double, Double)] = [
        (485, 324.96, 1934.136), (203, 337.23, 32964.467), (199, 342.08, 20.186),
        (182, 27.85, 445267.112), (156, 73.14, 45036.886), (136, 171.52, 22518.443),
        (77, 222.54, 65928.934), (74, 296.72, 3034.906), (70, 243.58, 9037.513),
        (58, 119.81, 33718.147), (52, 297.17, 150.678), (50, 21.02, 2281.226),
        (45, 247.54, 29929.562), (44, 325.15, 31555.956), (29, 60.93, 4443.417),
        (18, 155.12, 67555.328), (17, 288.79, 4562.452), (16, 198.04, 62894.029),
        (14, 199.76, 31436.921), (12, 95.39, 14577.848), (12, 287.11, 31931.756),
        (12, 320.81, 34777.259), (9, 227.73, 1222.114), (8, 15.45, 16859.074),
    ]

    private static func instant(_ year: Int, _ mean: [Double]) -> Date {
        let y = (Double(year) - 2000) / 1000
        let jde0 = mean[0] + mean[1] * y + mean[2] * y * y + mean[3] * y * y * y + mean[4] * y * y * y * y
        let t = (jde0 - 2451545.0) / 36525
        let w = (35999.373 * t - 2.47) * .pi / 180
        let dLambda = 1 + 0.0334 * cos(w) + 0.0007 * cos(2 * w)
        let s = terms.reduce(0.0) { sum, term in sum + term.0 * cos((term.1 + term.2 * t) * .pi / 180) }
        let jde = jde0 + 0.00001 * s / dLambda
        // Julian day 2440587.5 is 1970-01-01 00:00 UTC.
        return Date(timeIntervalSince1970: (jde - 2440587.5) * 86400)
    }
}
