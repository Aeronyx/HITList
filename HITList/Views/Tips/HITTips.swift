import Foundation
import SwiftUI
import TipKit
import OSLog

/// The first-run tips (brief 52): one short tip at the moment it helps, each shown once, instead of a tour
/// (HIG, Onboarding: "teach by doing"). TipKit keeps what was shown; Settings → About → Show tips again
/// brings them all back.
///
/// Where each one attaches (`hitTip`, `quickAddTips`):
/// - `quickAddSyntax`, `keepAsText`: the quick-add card's title field, in that order (`quickAddTips`);
///   the second waits until a highlight has appeared in a card.
/// - `browse`: the iPhone's magnifying glass at the top right of a tab's first screen (`ScreenMenu`).
/// - `flipboard`: the Flipboard's grid.
/// - `boardAddTask`: today's "Add task" on the Upcoming board (Mac, full-width iPad).
enum HITTipKind: String, CaseIterable, Identifiable {
    case quickAddSyntax, keepAsText, browse, flipboard, boardAddTask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickAddSyntax: "Type it all in one line"
        case .keepAsText: "Keep the words as text"
        case .browse: "Find anything"
        case .flipboard: "Flip a switch when it’s done"
        case .boardAddTask: "Add straight to a day"
        }
    }

    var message: String {
        switch self {
        case .quickAddSyntax: "Try ‘Call mom tomorrow 5pm p1 #Home’: the date, priority and Group fill themselves in."
        case .keepAsText: "Tap a highlight, or press Backspace right after it, to keep the words as text."
        case .browse: "The magnifying glass opens Browse: search every task, and find your Groups, labels and filters."
        case .flipboard: "Each switch is a repeating chore. Flip it when it’s done; it turns red again when it’s due."
        case .boardAddTask: "Add task under a day adds a task due that day. Drag a card to another day to move it."
        }
    }

    var symbol: String {
        switch self {
        case .quickAddSyntax: "text.cursor"
        case .keepAsText: "character.cursor.ibeam"
        case .browse: "magnifyingglass"
        case .flipboard: "switch.2"
        case .boardAddTask: "calendar.badge.plus"
        }
    }
}

/// One tip. Its id carries the "Show tips again" generation: generation 0 is the plain name ("browse"),
/// later ones add it ("browse.2"), which TipKit treats as a tip it has never shown.
struct HITTip: Tip {
    let kind: HITTipKind
    let generation: Int

    init(_ kind: HITTipKind, generation: Int = HITTips.generation()) {
        self.kind = kind
        self.generation = generation
    }

    var id: String { generation == 0 ? kind.rawValue : "\(kind.rawValue).\(generation)" }
    var title: Text { Text(kind.title) }
    var message: Text? { Text(kind.message) }
    var image: Image? { Image(systemName: kind.symbol) }

    /// A highlight appeared in a quick-add card (`quickAddTips(hasHighlight:)` donates it).
    static let highlightShown = Tips.Event(id: "highlightShown")

    var rules: [Rule] {
        if kind == .keepAsText {
            #Rule(Self.highlightShown) { $0.donations.count > 0 }
        } else {
            [Rule]()
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

/// Configuring TipKit and bringing the tips back.
@MainActor
enum HITTips {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "tips")
    private static var configured = false

    /// Called once in `HITListApp.init`, after the store name is settled. Never under tests or with
    /// `-hideTips` (screenshots that should show no tip). A Debug side-store run keeps its tips apart
    /// (`datastoreFolderName`), since every build on a Mac shares one container. `-showAllTips` (Debug)
    /// shows every tip whatever its rules, for screenshots.
    static func configure(storeName: String = ModelContainerFactory.storeName) {
        guard !configured, shouldConfigure() else { return }
        configured = true
        var options: [Tips.ConfigurationOption] = [.displayFrequency(.immediate)]
        if let folder = datastoreFolderName(storeName: storeName) {
            let url = URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            options.append(.datastoreLocation(.url(url)))
        }
        if showsAllForTesting() { Tips.showAllTipsForTesting() }
        do {
            try Tips.configure(options)
        } catch {
            log.error("TipKit not configured: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func shouldConfigure(environment: [String: String] = ProcessInfo.processInfo.environment,
                                            arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil && !arguments.contains("-hideTips")
    }

    nonisolated static func showsAllForTesting(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        arguments.contains("-showAllTips")
        #else
        false
        #endif
    }

    /// nil for the real store (TipKit's default place); "Tips-HITList-Development" for a side store.
    nonisolated static func datastoreFolderName(storeName: String) -> String? {
        guard storeName != ModelContainerFactory.mainStoreName else { return nil }
        let base = storeName.hasSuffix(".store") ? String(storeName.dropLast(".store".count)) : storeName
        return "Tips-\(base)"
    }

    // MARK: Show tips again

    nonisolated static func generationKey(storeName: String) -> String {
        storeName == ModelContainerFactory.mainStoreName ? "tips.generation" : "tips.generation.\(storeName)"
    }

    nonisolated static func generation(in defaults: UserDefaults = AppGroup.defaults,
                                       storeName: String = ModelContainerFactory.storeName) -> Int {
        defaults.integer(forKey: generationKey(storeName: storeName))
    }

    /// Settings → About → Show tips again: every tip is new again and shows the next time its moment comes.
    nonisolated static func showAgain(in defaults: UserDefaults = AppGroup.defaults,
                                      storeName: String = ModelContainerFactory.storeName) {
        let key = generationKey(storeName: storeName)
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }
}
