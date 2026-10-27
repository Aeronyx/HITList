import Foundation
import XCTest
@testable import HITListCore

/// Fixed clock: Wednesday 2026-10-21 14:30 UTC, Gregorian calendar, week starts Sunday (US).
enum Fixed {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }
    static let now: Date = date(2026, 10, 21, 14, 30)

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h; comps.minute = min
        return calendar.date(from: comps)!
    }

    static var dateParser: DateExpressionParser { DateExpressionParser(calendar: calendar, now: now) }
}

extension XCTestCase {
    func assertDate(_ actual: Date?, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0,
                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual, Fixed.date(y, m, d, h, min), file: file, line: line)
    }
}
