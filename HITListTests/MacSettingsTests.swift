import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// The Mac Settings page (brief 24): its sections, the remembered selection, each section rendering,
/// and the logic behind the shortcuts table, the Data counts, the iCloud "Last change" row and About.
@MainActor
final class MacSettingsTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
    }

    override func tearDown() async throws {
        container = nil
    }

    // MARK: Sections

    func testSectionsAreStableInIdsAndOrder() {
        XCTAssertEqual(MacSettingsSection.allCases.map(\.rawValue),
                       ["general", "iCloud", "reminders", "completing", "appearance", "data", "about"],
                       "stored in preferences: never rename, only append")
        XCTAssertEqual(MacSettingsSection.allCases.map(\.title),
                       ["General", "iCloud", "Reminders", "Completing tasks", "Appearance", "Data", "About"])
        for section in MacSettingsSection.allCases {
            XCTAssertFalse(section.caption.isEmpty, "\(section) has a caption")
            // About 23 characters of caption2 fit beside the icon in the 200 pt column without "…".
            XCTAssertLessThanOrEqual(section.caption.count, 24, "\(section)'s caption fits one line of the 200 pt list")
            XCTAssertEqual(section.id, section.rawValue)
        }
        XCTAssertEqual(Set(MacSettingsSection.allCases.map(\.systemImage)).count, MacSettingsSection.allCases.count)
        XCTAssertEqual(MacSettingsPage.listWidth, 200)
        XCTAssertEqual(MacSettingsPage.contentMaxWidth, 620)
    }

    func testRememberedSelectionRoundTrips() throws {
        let suite = "MacSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(MacSettingsSection.load(from: defaults), .general, "nothing saved yet")
        for section in MacSettingsSection.allCases {
            MacSettingsSection.save(section, to: defaults)
            XCTAssertEqual(MacSettingsSection.load(from: defaults), section)
            XCTAssertEqual(defaults.string(forKey: Preferences.macSettingsSection), section.rawValue)
        }
        defaults.set("someFutureSection", forKey: Preferences.macSettingsSection)
        XCTAssertEqual(MacSettingsSection.load(from: defaults), .general, "an unknown section falls back")
        XCTAssertEqual(MacSettingsSection.remembered(nil), .general)
        XCTAssertEqual(Preferences.macSettingsSection, "pref.mac.settingsSection")
    }

    func testArrowKeysMoveBetweenSectionsAndStopAtTheEnds() {
        XCTAssertEqual(MacSettingsSectionList.moved(.general, by: 1), .iCloud)
        XCTAssertEqual(MacSettingsSectionList.moved(.data, by: -1), .appearance)
        XCTAssertNil(MacSettingsSectionList.moved(.general, by: -1))
        XCTAssertNil(MacSettingsSectionList.moved(.about, by: 1))
    }

    func testRouterCountsEveryOpenRequest() {
        let router = SettingsRouter()
        XCTAssertEqual(router.openRequests, 0)
        router.open()
        router.open()
        XCTAssertEqual(router.openRequests, 2, "a second request while the page shows still counts")
    }

    func testSettingsItemIsItsOwnDestination() {
        XCTAssertNotEqual(SidebarItem.settings, SidebarItem.flipboard)
        XCTAssertNotEqual(SidebarItem.settings, SidebarItem.today)
        XCTAssertEqual(SidebarItem.settings, SidebarItem.settings, "a fixed id, the same every launch")
    }

    // MARK: Keyboard shortcuts

    func testShortcutsHaveNoDuplicateKeysOrIds() {
        let all = HITShortcuts.all
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "ids are unique")
        // The same keys may mean different things in different places (Return in a card and in Inbox
        // review), never twice in one place.
        for group in HITShortcuts.byContext {
            let keys = group.shortcuts.map { $0.keys.joined(separator: " ") }
            XCTAssertEqual(Set(keys).count, keys.count, "duplicate keys in \(group.context.title): \(keys)")
        }
        let sharedShortcuts = all.compactMap(\.shortcut)
        for context in HITShortcut.Context.allCases {
            let inContext = all.filter { $0.context == context }.compactMap(\.shortcut)
            XCTAssertEqual(Set(inContext.map(HITShortcuts.symbols)).count, inContext.count, "\(context)")
        }
        XCTAssertFalse(sharedShortcuts.isEmpty)
        XCTAssertTrue(all.allSatisfy { !$0.keys.isEmpty && !$0.title.isEmpty })
        XCTAssertEqual(HITShortcuts.byContext.flatMap(\.shortcuts).map(\.id), all.map(\.id),
                       "every shortcut shows in exactly one group, in order")
    }

    func testShortcutListCoversTheAppsShortcuts() {
        // The values the commands and views use (NewTaskCommands ⌘N, the Settings command ⌘,, Show completed
        // ⇧⌘C, PopoutHost ⌘← ⌘→, the toast's ⌘Z, the editor sheets' ⌘Return, Inbox review's letter keys).
        let symbols = Set(HITShortcuts.all.compactMap(\.shortcut).map(HITShortcuts.symbols))
        for expected in ["⌘N", "⌘,", "⇧⌘C", "⌘←", "⌘→", "⌘Z", "⌘Return", "Esc", "Return", "Tab",
                         "T", "M", "D", "P", "L", "→", "⌫"] {
            XCTAssertTrue(symbols.contains(expected), "missing \(expected)")
        }
        XCTAssertEqual(HITShortcuts.settings.shortcut?.key, KeyEquivalent(","))
        XCTAssertEqual(HITShortcuts.settings.shortcut?.modifiers, .command)
        XCTAssertEqual(HITShortcuts.newTask.shortcut?.key, KeyEquivalent("n"))
        XCTAssertEqual(HITShortcuts.calendarMove.keys, ["←", "→", "↑", "↓"])
        XCTAssertNil(HITShortcuts.calendarMove.shortcut)
    }

    func testKeycapsUseTheMenuOrder() {
        XCTAssertEqual(HITShortcuts.keycaps(KeyboardShortcut("c", modifiers: [.command, .shift])), ["⇧", "⌘", "C"])
        XCTAssertEqual(HITShortcuts.keycaps(KeyboardShortcut("k", modifiers: [.command, .option, .control, .shift])),
                       ["⌃", "⌥", "⇧", "⌘", "K"])
        XCTAssertEqual(HITShortcuts.symbols(KeyboardShortcut(.escape, modifiers: [])), "Esc")
        XCTAssertEqual(HITShortcuts.symbols(KeyboardShortcut(.delete, modifiers: [])), "⌫")
        XCTAssertEqual(HITShortcuts.symbols(KeyboardShortcut(.leftArrow, modifiers: .command)), "⌘←")
        XCTAssertEqual(HITShortcuts.symbols(KeyboardShortcut(.return, modifiers: .command)), "⌘Return")
    }

    // MARK: Data

    func testDataCountsFromAnInMemoryContainer() throws {
        let context = container.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 15))!
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            let d = cal.date(byAdding: .day, value: offset, to: today)!
            return hour.map { cal.date(bySettingHour: $0, minute: 0, second: 0, of: d)! } ?? d
        }

        XCTAssertEqual(try DataStats.count(in: context, now: now, calendar: cal), DataStats(), "empty store")

        let home = Project(name: "Home")
        context.insert(home)
        context.insert(Project(name: "Work"))
        context.insert(TaskLabel(name: "calls"))
        context.insert(SavedFilter(name: "P1", query: "p1"))
        context.insert(TaskItem(title: "yesterday, all day", dueDate: day(-1)))             // overdue
        context.insert(TaskItem(title: "today 9 am", dueDate: day(0, hour: 9), hasDueTime: true)) // overdue at 3 pm
        context.insert(TaskItem(title: "today, all day", dueDate: day(0)))                  // not yet
        context.insert(TaskItem(title: "today 6 pm", dueDate: day(0, hour: 18), hasDueTime: true))
        context.insert(TaskItem(title: "no date", project: home))
        let done = TaskItem(title: "done last week", dueDate: day(-7))
        done.isCompleted = true
        context.insert(done)
        try context.save()

        let stats = try DataStats.count(in: context, now: now, calendar: cal)
        XCTAssertEqual(stats, DataStats(openTasks: 5, completedTasks: 1, overdueTasks: 2, groups: 2, labels: 1, filters: 1))
    }

    func testStoreSizeAddsTheWalAndShmFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "MacSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appending(path: "HITList.store")

        XCTAssertNil(DataStats.storeSize(at: store), "no file yet")
        XCTAssertNil(DataStats.storeSize(at: nil))
        XCTAssertNil(DataStats.storeSize(at: URL(fileURLWithPath: "/dev/null")), "an in-memory store's URL")
        XCTAssertNil(DataStats.storeSize(at: dir), "a folder isn't a store")
        try Data(count: 4096).write(to: store)
        XCTAssertEqual(DataStats.storeSize(at: store), 4096)
        try Data(count: 1000).write(to: URL(fileURLWithPath: store.path + "-wal"))
        try Data(count: 24).write(to: URL(fileURLWithPath: store.path + "-shm"))
        XCTAssertEqual(DataStats.storeSize(at: store), 5120)
        XCTAssertFalse(DataStats.sizeText(5120).isEmpty)
    }

    // MARK: Rendering

    /// Renders a view offscreen, which evaluates every body in it. A crash or a nil image fails.
    private func render<V: View>(_ view: V, _ name: String, width: CGFloat = 560, height: CGFloat? = nil,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let content = view
            .modelContainer(container)
            .frame(width: width, height: height)
            .background(Theme.background)
            .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: content)
        XCTAssertNotNil(renderer.cgImage, "\(name) didn't render", file: file, line: line)
    }

    func testEverySectionRenders() {
        for section in MacSettingsSection.allCases {
            render(MacSettingsSectionContent(section: section), "section \(section)")
            render(MacSettingsHeader(section: section), "header \(section)")
        }
        render(MacSettingsSectionList(selection: .data) { _ in }, "section list", width: 200, height: 560)
        render(KeyboardShortcutsGroups(), "shortcuts table")
        render(KeyCaps(keys: ["⇧", "⌘", "C"]), "keycaps", width: 120)
        render(DataCountTiles(stats: DataStats(openTasks: 12, completedTasks: 340, overdueTasks: 2, groups: 4,
                                               labels: 6, filters: 3)), "count tiles", width: 312)
    }

    func testPageRendersAtTheWindowsMinimumAndWide() {
        // The detail column at the 760 × 560 minimum window (sidebar 200) and at 1200 wide (sidebar 240).
        render(MacSettingsPage(), "page at minimum", width: 560, height: 560)
        render(MacSettingsPage(), "page wide", width: 960, height: 700)
    }
}
