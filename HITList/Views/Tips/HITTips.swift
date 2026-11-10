import Foundation
import SwiftUI
import TipKit
import OSLog
import SwiftData

/// The first-run tips (brief 52): one short tip at the moment it helps, each shown once, instead of a tour
/// (HIG, Onboarding: "teach by doing"). TipKit keeps what was shown; Settings → About → Show tips again
/// brings them all back.
///
/// Where each one attaches (`hitTip`, `quickAddTips`):
/// - `quickAddSyntax`, `keepAsText`: the quick-add card's title field, in that order (`quickAddTips`);
///   the second waits until a highlight has appeared in a card.
/// - `browse`: the iPhone's magnifying glass at the top right of a tab's first screen (`ScreenMenu`).
/// - `flipboard`: the Flipboard's first switch; `switchesStay` there instead for someone whose switches came from
///   before Switchboards (brief 72: `FlipboardTips`).
/// - `boardAddTask`: today's "Add task" on the Upcoming board (Mac, full-width iPad).
/// - `reviewSwipe`: inline on Review Inbox's card on iPhone (brief 60); gone after the first swipe.
///
/// A tip never takes a friend's first tap (brief 56): on iPhone a popover tip closes on the first tap
/// outside it and that tap goes nowhere. So the quick-add tips sit inside the card, inline (`quickAddTips`),
/// and the popover tips (`browse`, `boardAddTask`, `flipboard`) wait until the person has settled in
/// (`HITTip.settled`, `TipSettling`: back in the app after their first task, or any later launch), never
/// popping up on a first screen or the moment something lands.
enum HITTipKind: String, CaseIterable, Identifiable {
    case quickAddSyntax, keepAsText, browse, flipboard, boardAddTask, reviewSwipe, switchesStay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickAddSyntax: "Type it all in one line"
        case .keepAsText: "Keep the words as text"
        case .browse: "Find anything"
        case .flipboard: "Flip a switch when it’s done"
        case .boardAddTask: "Add straight to a day"
        case .reviewSwipe: "Swipe to sort"
        case .switchesStay: "Switches stay on the Flipboard"
        }
    }

    var message: String {
        switch self {
        case .quickAddSyntax: "Try ‘Call mom tomorrow 5pm p1 #Home’: date and priority fill in. # picks its one Group; @ adds any labels."
        case .keepAsText: "Tap a highlight, or press Backspace right after it, to keep the words as text."
        case .browse: "The magnifying glass opens Browse: Groups, labels and filters, and a search that understands #Work or p1."
        case .flipboard: "A switch is a routine, green when it’s done and red when it’s due: flip it when you’ve done it."
        case .boardAddTask: "Add task under a day adds a task due that day. Drag a card to another day to move it."
        case .reviewSwipe: "Swipe right for Today, left to delete."
        case .switchesStay: "Red switches no longer wait in Today; turn on Overdue becomes task to bring one back when it’s due."
        }
    }

    var symbol: String {
        switch self {
        case .quickAddSyntax: "text.cursor"
        case .keepAsText: "highlighter"
        case .browse: "magnifyingglass"
        case .flipboard: "switch.2"
        case .boardAddTask: "calendar.badge.plus"
        case .reviewSwipe: "hand.draw"
        case .switchesStay: "switch.2"
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

    /// The person has settled in (`TipSettling`; `HITTips.configure` watches for it and donates it).
    /// Never renamed: TipKit keeps its donations under this id.
    static let settled = Tips.Event(id: "settled")

    /// Shows only once the person has settled in, so it never sits on their very first screen.
    var waitsUntilSettled: Bool { kind == .browse || kind == .boardAddTask || kind == .flipboard || kind == .switchesStay }

    var rules: [Rule] {
        if kind == .keepAsText {
            #Rule(Self.highlightShown) { $0.donations.count > 0 }
        } else if waitsUntilSettled {
            #Rule(Self.settled) { $0.donations.count > 0 }
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
            return
        }
        settleWhenReady(storeName: storeName)
    }

    // MARK: Settled in (brief 56)

    private static var settling = TipSettling()
    private static var observers: [NSObjectProtocol] = []

    /// Watches for the moments `TipSettling` counts: a save that adds a task (quick add, the board, Siri, a
    /// Shortcut: every one saves through a `ModelContext`) and the app coming back to the foreground.
    private static func settleWhenReady(storeName: String) {
        handle(.launched(later: recordLaunch(storeName: storeName)))
        guard !settling.isSettled else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { note in
                guard insertsTask(note) else { return }
                MainActor.assumeIsolated { handle(.addedTask) }
            },
            center.addObserver(forName: returnNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handle(.cameBack) }
            },
        ]
    }

    private static func handle(_ event: TipSettling.Event) {
        let settles = settling.handle(event)
        log.info("tips: \(String(describing: event), privacy: .public) → \(settles ? "settled" : "not yet", privacy: .public)")
        guard settles else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        Task { await HITTip.settled.donate() }
    }

    /// The app comes back from the background (iPhone, iPad) or from another app (Mac). Not the iPhone's
    /// `didBecomeActive`, which also follows a system alert such as the notification permission.
    nonisolated static var returnNotification: Notification.Name {
        #if os(macOS)
        NSApplication.didBecomeActiveNotification
        #else
        UIApplication.willEnterForegroundNotification
        #endif
    }

    nonisolated static func launchKey(storeName: String) -> String {
        storeName == ModelContainerFactory.mainStoreName ? "tips.launched" : "tips.launched.\(storeName)"
    }

    /// Notes this launch; true if an earlier launch on the same store was noted (a later launch).
    @discardableResult
    nonisolated static func recordLaunch(in defaults: UserDefaults = AppGroup.defaults,
                                         storeName: String = ModelContainerFactory.storeName) -> Bool {
        let key = launchKey(storeName: storeName)
        let earlier = defaults.bool(forKey: key)
        if !earlier { defaults.set(true, forKey: key) }
        return earlier
    }

    /// Whether a `ModelContext.didSave` inserted a task (not only a Group, label or filter, nor an edit).
    nonisolated static func insertsTask(_ note: Notification) -> Bool {
        let inserted = note.userInfo?[ModelContext.NotificationKey.insertedIdentifiers.rawValue] as? [PersistentIdentifier] ?? []
        return inserted.contains { $0.entityName == String(describing: TaskItem.self) }
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

/// When the person has settled in (brief 56), so Browse's and the board's tips may show: at once on a later
/// launch; on the first launch, once they have added a task and then come back to the app. Not the moment
/// the task is saved: a popover tip then would take the very next tap (the "+" again, or the new task).
struct TipSettling: Equatable {
    enum Event: Equatable { case launched(later: Bool), addedTask, cameBack }

    private(set) var hasTask = false
    private(set) var isSettled = false

    /// True once, for the event that settles it (the moment to donate `HITTip.settled`).
    mutating func handle(_ event: Event) -> Bool {
        guard !isSettled else { return false }
        switch event {
        case .launched(let later): isSettled = later
        case .addedTask: hasTask = true
        case .cameBack: isSettled = hasTask
        }
        return isSettled
    }
}
