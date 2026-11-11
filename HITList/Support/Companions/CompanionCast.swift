import Foundation

extension CompanionCharacter {
    /// Every companion, in the themes' order.
    static let all: [CompanionCharacter] = [
        CompanionCharacter.nod,
        CompanionCharacter.gargle,
        CompanionCharacter.quill,
        CompanionCharacter.tuck,
        CompanionCharacter.hush,
        CompanionCharacter.glim,
        CompanionCharacter.mallow,
        CompanionCharacter.button,
    ]

    static func named(_ id: String) -> CompanionCharacter? { all.first { $0.id == id } }
}

/// One companion per colour theme (briefs 79, 85 and 87 to 89), and only that one shows: Slate has Nod (the default),
/// Graphite Gargle, Midnight Quill, Moss Tuck, Nord Hush, Tokyo Night Glim, Mocha Mallow, Rosé Button. A theme from a
/// newer build, with no companion drawn here, borrows Nod. There are no points, unlocks or collecting of any kind:
/// the theme alone decides. Debug: `-companion quill` picks one whatever the theme.
enum CompanionCast {
    /// Theme id → companion id.
    static let byTheme: [String: String] = [
        "slate": "nod",
        // A gargoyle pup in stone greys, crouched on the "+" as its elders crouch on a parapet (brief 102).
        "graphite": "gargle",
        "midnight": "quill",
        // A snail whose shell is a flowerpot, its seedling in Moss's leaf green (brief 88).
        "moss": "tuck",
        // Its own ears keep it warm, and its nose is cold: Nord's ice-blue accent (brief 79).
        "nord": "hush",
        // A small mouse whose tail ends in a lantern: the one warm light in an indigo night (brief 89).
        "tokyo": "glim",
        // Round 18's plushy sketch, fatter and rounder, in a knitted band: a marshmallow for a mocha (brief 85).
        "mocha": "mallow",
        // A button mushroom in the theme's own rose, its cap its hat, umbrella and bed, for George's favourite (brief 102).
        "rose": "button",
    ]

    /// The companion for the theme `themeID`.
    static func character(forTheme themeID: String, launch: CompanionLaunchOptions = .current) -> CompanionCharacter {
        if let forced = launch.companion, let character = CompanionCharacter.named(forced) { return character }
        return byTheme[themeID].flatMap(CompanionCharacter.named) ?? .nod
    }

    /// The companion for the theme in use (`ThemeStore` is observable, so a view reading this redraws when it changes).
    static var current: CompanionCharacter { character(forTheme: ThemeStore.shared.palette.id) }
}
