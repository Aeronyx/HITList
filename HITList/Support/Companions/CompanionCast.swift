import Foundation

extension CompanionCharacter {
    /// Every companion drawn so far.
    static let all: [CompanionCharacter] = [.nod, .quill]

    static func named(_ id: String) -> CompanionCharacter? { all.first { $0.id == id } }
}

/// One companion per colour theme (brief 79), and only that one shows. Slate has Nod (the default), Midnight has
/// Quill; a theme whose companion isn't drawn yet has Nod. There are no points, unlocks or collecting of any kind:
/// the theme alone decides. Debug: `-companion quill` picks one whatever the theme.
enum CompanionCast {
    /// Theme id → companion id.
    static let byTheme: [String: String] = [
        "slate": "nod",
        "midnight": "quill",
    ]

    /// The companion for the theme `themeID`.
    static func character(forTheme themeID: String, launch: CompanionLaunchOptions = .current) -> CompanionCharacter {
        if let forced = launch.companion, let character = CompanionCharacter.named(forced) { return character }
        return byTheme[themeID].flatMap(CompanionCharacter.named) ?? .nod
    }

    /// The companion for the theme in use (`ThemeStore` is observable, so a view reading this redraws when it changes).
    static var current: CompanionCharacter { character(forTheme: ThemeStore.shared.palette.id) }
}
