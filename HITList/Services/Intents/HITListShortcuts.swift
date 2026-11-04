import AppIntents

/// The phrases Siri knows without any setup, and the tiles in the Shortcuts app's HITList section. Every
/// phrase must name the app (`.applicationName`); Siri also hears the phrases with the app's name said
/// differently ("Hit List").
///
/// Spotlight: `TaskEntity` is not an `IndexedEntity`. Conforming is one line, but it indexes nothing on its
/// own: the app would have to add, update and remove tasks in Core Spotlight as they change, which is more
/// than this brief's one line (brief 46, item 4).
struct HITListShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(), phrases: [
            "Add a task in \(.applicationName)",
            "Add a task to \(.applicationName)",
            "New \(.applicationName) task",
            "Add to \(.applicationName)",
        ], shortTitle: "Add Task", systemImageName: "plus.circle")

        AppShortcut(intent: TodayTasksIntent(), phrases: [
            "What's on my \(.applicationName) today",
            "What's on \(.applicationName) today",
            "What's due today in \(.applicationName)",
            "Read my \(.applicationName) for today",
        ], shortTitle: "Today’s Tasks", systemImageName: "list.bullet")

        AppShortcut(intent: OpenScreenIntent(), phrases: [
            "Open \(\.$target) in \(.applicationName)",
            "Show \(\.$target) in \(.applicationName)",
            "Open \(.applicationName) \(\.$target)",
            "Open \(.applicationName)",
        ], shortTitle: "Open Screen", systemImageName: "rectangle.stack")

        AppShortcut(intent: CompleteTaskIntent(), phrases: [
            "Complete a task in \(.applicationName)",
            "Mark a \(.applicationName) task done",
            "Tick off a task in \(.applicationName)",
        ], shortTitle: "Complete Task", systemImageName: "checkmark.circle")
    }

    static let shortcutTileColor: ShortcutTileColor = .grayBlue
}
