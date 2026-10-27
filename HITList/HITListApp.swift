import SwiftUI
import SwiftData

@main
struct HITListApp: App {
    let container: ModelContainer
    private var importObserver: NSObjectProtocol?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Unit tests run hosted in the app; keep them off the real store and CloudKit.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            container = ModelContainerFactory.preview()
            return
        }
        CloudSyncMonitor.shared.start()
        container = ModelContainerFactory.make()
        let context = container.mainContext
        TaskActions.seedDefaultsIfNeeded(in: context)
        Deduplicator.runAndLog(in: context, trigger: "launch")
        TaskActions.seedSampleDataIfRequested(in: context)
        // Imports arrive in bursts (one event per zone fetch); dedupe once the burst settles.
        let debounce = Debouncer(delay: .seconds(2))
        importObserver = NotificationCenter.default.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                debounce.schedule { Deduplicator.runAndLog(in: context, trigger: "import") }
            }
        }
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
