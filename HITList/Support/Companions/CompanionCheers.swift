import Foundation

/// Brief 132: each creature's cheer for a completed task, one to two seconds of frames it already has and already
/// shows (no new drawings: the six George signed off are frozen, Flint and Phase are being redrawn by siblings and keep
/// every frame's name), at the gesture rate (8 ticks a second), by character id; a place of its own where its frames
/// differ there (Quill sits on the "+" and lies in a loaf on the Mac's field). A creature without one plays its awake
/// answer. `CompanionCheerTests` checks every name, the length and that no two are the same; the picture George saw is
/// `132-alive/cheers-strip.png` in the round's notes folder.
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

    private typealias C = CompanionCharacter

    static let table: [String: Cheer] = [
        // Sleepy: a contented smile while its lamp flares twice, then a slow blink. 1.4 s.
        "nod": Cheer(plus: C.ticks(("content", 2), ("glowUp", 3), ("content", 2), ("glowUp", 2), ("content", 1),
                                   ("blink", 1))),
        // A cat: its tail tip flicks up, it kneads twice, a slow blink. 1.4 s.
        "quill": Cheer(
            plus: C.ticks(("sitTipUp", 2), ("sitKneadL", 1), ("sitKneadR", 1), ("sitKneadL", 1), ("sitKneadR", 1),
                          ("sitBlink", 4), ("sitHalf", 1)),
            field: C.ticks(("loafTipUp", 2), ("loafKneadL", 1), ("loafKneadR", 1), ("loafKneadL", 1),
                           ("loafKneadR", 1), ("loafBlink", 4), ("loafHalf", 1))),
        // Slow: it smiles while its sprout puts up a bud and draws it back (no bloom: that is the flourish's). 1.5 s.
        "tuck": Cheer(plus: C.ticks(("happy", 2), ("bud1", 2), ("bud2", 3), ("bud1", 2), ("happy", 3))),
        // Listens: its ears swing left, then right, then shoot up. 1.1 s.
        "hush": Cheer(plus: C.ticks(("listenL", 1), ("listenR", 1), ("earsHalf", 1), ("earsUp", 4), ("earsHalf", 2))),
        // Tends its lantern: lifts it, the flame burns brighter, a pleased squint. 1.4 s.
        "glim": Cheer(plus: C.ticks(("lift", 2), ("brighter", 3), ("pleased", 3), ("brighter", 2), ("lift", 1))),
        // Sudden: eyes wide, it jumps up tall, bobs, a sly look. 1.25 s.
        "phase": Cheer(plus: C.ticks(("wide", 1), ("boo", 3), ("bobUp", 2), ("bobDown", 2), ("sly", 2))),
        // A mushroom: it squashes, springs up beaming and blushes. 1.25 s.
        "button": Cheer(plus: C.ticks(("squash", 1), ("rise", 1), ("riseHappy", 3), ("happyBlush", 3), ("happy", 2))),
        // A gryphon cub: a chirp, wings up, happy, a giggle. 1.25 s.
        "flint": Cheer(plus: C.ticks(("chirp", 1), ("wingsUp", 3), ("happy", 2), ("giggle", 2), ("happy", 2))),
    ]

    /// The ticks `character` cheers with in `place`: its own, else its awake answer.
    static func ticks(for character: CompanionCharacter, place: CompanionPlace) -> [CompanionCharacter.Tick] {
        table[character.id]?.ticks(place) ?? character.posture(place).awake.answer.ticks
    }
}
