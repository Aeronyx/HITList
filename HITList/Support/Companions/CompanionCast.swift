import Foundation

extension CompanionCharacter {
    /// Every companion drawn so far.
    static let all: [CompanionCharacter] = [
        CompanionCharacter.nod,
        CompanionCharacter.quill,
        CompanionCharacter.hush,
        CompanionCharacter.posy,
        CompanionCharacter.mallow,
        CompanionCharacter.tuck,
    ]

    static func named(_ id: String) -> CompanionCharacter? { all.first { $0.id == id } }
}

/// One companion per colour theme (briefs 79 and 85), and only that one shows. Slate has Nod (the default), Midnight
/// has Quill, Nord has Hush, Rosé has Posy, Mocha has Mallow; a theme whose companion isn't drawn yet has Nod. There
/// are no points, unlocks or collecting of any kind: the theme alone decides. Debug: `-companion quill` picks one
/// whatever the theme.
enum CompanionCast {
    /// Theme id → companion id.
    static let byTheme: [String: String] = [
        "slate": "nod",
        "midnight": "quill",
        // Its own ears keep it warm, and its nose is cold: Nord's ice-blue accent (brief 79).
        "nord": "hush",
        // A piglet with wings too small for it and a snout in the theme's rose pink, for George's favourite (brief 85).
        "rose": "posy",
        // Round 18's plushy sketch, fatter and rounder, in a knitted band: a marshmallow for a mocha (brief 85).
        "mocha": "mallow",
        // A snail whose shell is a flowerpot, its seedling in Moss's leaf green (brief 88).
        "moss": "tuck",
    ]

    /// The companion for the theme `themeID`.
    static func character(forTheme themeID: String, launch: CompanionLaunchOptions = .current) -> CompanionCharacter {
        if let forced = launch.companion, let character = CompanionCharacter.named(forced) { return character }
        return byTheme[themeID].flatMap(CompanionCharacter.named) ?? .nod
    }

    /// The companion for the theme in use (`ThemeStore` is observable, so a view reading this redraws when it changes).
    static var current: CompanionCharacter { character(forTheme: ThemeStore.shared.palette.id) }
}
