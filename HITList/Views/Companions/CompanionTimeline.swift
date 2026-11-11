import SwiftUI

/// The moments a companion's drawing changes, from its clock: SwiftUI redraws only then (four to ten times a
/// second while it moves, never during a held frame), and not at all while the view is off screen.
struct CompanionTimeline: TimelineSchedule {
    let clock: CompanionClock
    let stage: CompanionStage

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(clock: clock, stage: stage, upcoming: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        let clock: CompanionClock
        let stage: CompanionStage
        var upcoming: Date

        mutating func next() -> Date? {
            let now = upcoming
            upcoming = clock.nextChange(after: now, stage: stage)
            return now
        }
    }
}
