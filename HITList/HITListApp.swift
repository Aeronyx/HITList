import SwiftUI
import SwiftData

@main
struct HITListApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CloudSyncMonitor.shared.start()
        container = ModelContainerFactory.make()
        TaskActions.seedDefaultsIfNeeded(in: container.mainContext)
        TaskActions.seedSampleDataIfRequested(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    let context = container.mainContext
                    Task { await NotificationScheduler.reschedule(context: context) }
                }
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { NotificationCenter.default.post(name: .focusQuickAdd, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .frame(minWidth: 520, minHeight: 420)
        }
        .modelContainer(container)
        #endif
    }
}

extension Notification.Name {
    static let focusQuickAdd = Notification.Name("HITList.focusQuickAdd")
}
