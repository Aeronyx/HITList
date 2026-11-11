import SwiftUI

/// The moments a companion's drawing changes, from its clock: SwiftUI redraws only then (a few times while an act
/// plays, never during a held frame) and the schedule ends when the act does, so a still companion costs nothing.
struct CompanionTimeline: TimelineSchedule {
    let clock: CompanionClock
    let stage: CompanionStage

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(clock: clock, stage: stage, upcoming: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        let clock: CompanionClock
        let stage: CompanionStage
        var upcoming: Date?

        mutating func next() -> Date? {
            guard let now = upcoming else { return nil }
            upcoming = clock.nextChange(after: now, stage: stage)
            return now
        }
    }
}
