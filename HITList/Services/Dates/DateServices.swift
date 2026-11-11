import Foundation
import SwiftData

/// Brief 82's start-up, from one line in `HITListApp` once the store is open: the app's one source of "the calendar
/// changed" (`CalendarChange`), then the days' anchoring (`DayAnchoring`: every save, each import, the first run).
@MainActor
enum DateServices {
    static func start(container: ModelContainer) {
        CalendarChange.shared.start()
        DayAnchoring.start(container: container)
    }
}
