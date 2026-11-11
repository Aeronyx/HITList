import Foundation

extension CompanionCharacter {
    /// Every companion that lives in the app, in the order their demos take turns (`-companionDemo all`).
    static let all: [CompanionCharacter] = []

    static func named(_ id: String) -> CompanionCharacter? { all.first { $0.id == id } }
}
