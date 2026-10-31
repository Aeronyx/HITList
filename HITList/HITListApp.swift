import SwiftUI
import SwiftData

@main
struct HITListApp: App {
    let container: ModelContainer
    private let isTesting: Bool
    private var importObserver: NSObjectProtocol?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        HITFont.installPlatformAppearance()
        // Unit tests run hosted in the app; keep them off the real store and CloudKit.
        isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isTesting {
            container = ModelContainerFactory.preview()
            return
        }
        CloudSyncMonitor.shared.start()
        container = ModelContainerFactory.make()
        if ModelContainerFactory.didResetStore { CloudSyncMonitor.shared.forgetLastSync() }
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
        NotificationScheduler.bootstrap(container: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .safeAreaInset(edge: .top, spacing: 0) { AccountChangeBanner() }
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .font(HITType.body)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    let context = container.mainContext
                    Task { await NotificationScheduler.reschedule(context: context) }
                    if !isTesting { LocalBackup.runIfDue(context: context) }
                }
        }
        .modelContainer(container)
        .commands { NewTaskCommands() }
        #if os(macOS)
        Settings {
            SettingsView()
                .font(HITType.body)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .frame(minWidth: 520, minHeight: 420)
        }
        .modelContainer(container)
        #endif
    }
}
