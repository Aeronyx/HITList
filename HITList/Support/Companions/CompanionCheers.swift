import Foundation

/// Brief 132: each creature's cheer for a completed task, one to two seconds of frames it already has (no new
/// drawings), by character id; a place of its own where its frames differ there. A creature without one plays its
/// awake answer. `CompanionCheerTests` checks every name.
enum CompanionCheers {
    /// One creature's cheer: its ticks on the "+" (and wherever no `field` is given), and on the Mac's field.
    struct Cheer {
        let plus: [CompanionCharacter.Tick]
        var field: [CompanionCharacter.Tick]?

        func ticks(_ place: CompanionPlace) -> [CompanionCharacter.Tick] {
            switch place {
            case .plus: plus
            case .field: field ?? plus
            }
        }
    }

    static let table: [String: Cheer] = [:]

    /// The ticks `character` cheers with in `place`: its own, else its awake answer.
    static func ticks(for character: CompanionCharacter, place: CompanionPlace) -> [CompanionCharacter.Tick] {
        table[character.id]?.ticks(place) ?? character.posture(place).awake.answer.ticks
    }
}
