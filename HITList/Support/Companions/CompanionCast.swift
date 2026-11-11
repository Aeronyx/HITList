import Foundation

extension CompanionCharacter {
    /// Every companion, in the themes' order.
    static let all: [CompanionCharacter] = [
        CompanionCharacter.nod,
        CompanionCharacter.smudge,
        CompanionCharacter.quill,
        CompanionCharacter.tuck,
        CompanionCharacter.hush,
        CompanionCharacter.glim,
        CompanionCharacter.mallow,
        CompanionCharacter.posy,
    ]

    static func named(_ id: String) -> CompanionCharacter? { all.first { $0.id == id } }
}

/// One companion per colour theme (briefs 79, 85 and 87 to 89), and only that one shows: Slate has Nod (the default),
/// Graphite Smudge, Midnight Quill, Moss Tuck, Nord Hush, Tokyo Night Glim, Mocha Mallow, Rosé Posy. A theme from a
/// newer build, with no companion drawn here, borrows Nod. There are no points, unlocks or collecting of any kind:
/// the theme alone decides. Debug: `-companion quill` picks one whatever the theme.
enum CompanionCast {
    /// Theme id → companion id.
    static let byTheme: [String: String] = [
        "slate": "nod",
        // An owlet on legs far too long, drawn in pencil greys with a paper-white face (brief 87).
        "graphite": "smudge",
        "midnight": "quill",
        // A snail whose shell is a flowerpot, its seedling in Moss's leaf green (brief 88).
        "moss": "tuck",
        // Its own ears keep it warm, and its nose is cold: Nord's ice-blue accent (brief 79).
        "nord": "hush",
        // A small mouse whose tail ends in a lantern: the one warm light in an indigo night (brief 89).
        "tokyo": "glim",
        // Round 18's plushy sketch, fatter and rounder, in a knitted band: a marshmallow for a mocha (brief 85).
        "mocha": "mallow",
        // A piglet with wings too small for it and a snout in the theme's rose pink, for George's favourite (brief 85).
        "rose": "posy",
    ]

    /// The companion for the theme `themeID`.
    static func character(forTheme themeID: String, launch: CompanionLaunchOptions = .current) -> CompanionCharacter {
        if let forced = launch.companion, let character = CompanionCharacter.named(forced) { return character }
        return byTheme[themeID].flatMap(CompanionCharacter.named) ?? .nod
    }

    /// The companion for the theme in use (`ThemeStore` is observable, so a view reading this redraws when it changes).
    static var current: CompanionCharacter { character(forTheme: ThemeStore.shared.palette.id) }
}
