import SwiftUI
import SwiftData

@main
struct HITListApp: App {
    let container: ModelContainer
    private let isTesting: Bool
    private var importObserver: NSObjectProtocol?
    @Environment(\.scenePhase) private var scenePhase
    // Logs push registration and every push to the sync log (SyncAppDelegate).
    #if os(macOS)
    @NSApplicationDelegateAdaptor(SyncAppDelegate.self) private var syncDelegate
    #else
    @UIApplicationDelegateAdaptor(SyncAppDelegate.self) private var syncDelegate
    #endif

    init() {
        #if DEBUG
        WidgetDebug.adoptBakedSideStore() // brief 81: a launch for a widget's tap opens the session's side store, sync off
        #endif
        HITFont.installPlatformAppearance()
        // Unit tests run hosted in the app; keep them off the real store and CloudKit.
        isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isTesting {
            container = ModelContainerFactory.preview()
            return
        }
        // Sync (brief 25): an instance relaunched to restart a stuck sync waits for the one it replaces,
        // and a Development build keeps its own store, apart from the TestFlight build's Production one.
        let waited = SyncRecovery.waitForPreviousInstance()
        let isolated = SyncStoreGuard.isolateDevelopmentStore()
        CloudSyncMonitor.shared.start()
        CloudSyncMonitor.shared.recordLaunchGuards(waitedForPrevious: waited, isolatedStoreSuffix: isolated)
        container = ModelContainerFactory.make()
        CloudSyncMonitor.shared.containerReady(container)
        IntentStore.register(container) // Siri and Shortcuts write through this one container (brief 46).
        HITTips.configure() // first-run tips, once, on this store's own datastore (brief 52).
        CompanionWeather.shared.start() // brief 80: the companions' sky, when the app comes forward (off by default)
        if ModelContainerFactory.didResetStore { CloudSyncMonitor.shared.forgetLastSync() }
        let context = container.mainContext
        DateServices.start(container: container) // brief 82: one day in every zone, and catching up when the zone or day changes
        TaskActions.seedDefaultsIfNeeded(in: context)
        Deduplicator.runAndLog(in: context, trigger: "launch")
        TaskActions.seedSampleDataIfRequested(in: context)
        TaskActions.seedDemoDataIfRequested(in: context) // screenshots and sessions: a believable week on a side store
        // Imports arrive in bursts (one event per zone fetch); dedupe once the burst settles.
        let debounce = Debouncer(delay: .seconds(2))
        importObserver = NotificationCenter.default.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                debounce.schedule { Deduplicator.runAndLog(in: context, trigger: "import") }
            }
        }
        NotificationScheduler.bootstrap(container: container)
        ClaudeConnector.start(container: container)  // brief 43: the Mac's Claude connector, if allowed
        WidgetSnapshotWriter.start(container: container) // brief 74: the widgets' snapshot, after every change
        WidgetCompletionCenter.start(container: container) // brief 81: completes what the widgets ask, once iCloud can have it
        WidgetRefresh.start() // brief 81: the background refresh (iOS) or the hourly settle (Mac) that keeps widgets true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .safeAreaInset(edge: .top, spacing: 0) { AccountChangeBanner() }
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .font(HITType.body)
                .deepLinkRouting() // brief 74: hitlist:// links from the widgets, through IntentRouter
                #if os(macOS)
                // Closing the window hides it, so the Dock icon brings it back at once (`MacWindowKeeper`).
                .keepsWindowOnClose()
                #endif
                .onChange(of: scenePhase) { _, phase in
                    if !isTesting { CloudSyncMonitor.shared.sceneChanged(to: phase) }
                    guard phase == .active else { return }
                    let context = container.mainContext
                    Task { await NotificationScheduler.reschedule(context: context) }
                    if !isTesting { LocalBackup.runIfDue(context: context) }
                }
        }
        .modelContainer(container)
        .commands {
            NewTaskCommands()
            #if os(macOS)
            // ⌘, opens Settings inside the window (`MacSettingsPage`); there is no Settings window.
            SettingsCommands()
            #endif
        }
        #if os(iOS)
        // Brief 81: a background refresh lets CloudKit import, rewrites the widgets' snapshot and drains their outbox.
        .backgroundTask(.appRefresh(WidgetRefresh.identifier)) { await WidgetRefresh.run() }
        #endif
    }
}
