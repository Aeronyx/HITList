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
        #if DEBUG
        SyncTransportProbe.runIfAsked() // brief 142: the engine's transport proved on CloudKit Development, side stores only
        #endif
        IntentStore.register(container) // Siri and Shortcuts write through this one container (brief 46).
        HITTips.configure() // first-run tips, once, on this store's own datastore (brief 52).
        // Briefs 80, 83: the companions' sky and local time when the app comes forward, and the location question
        // once, after the first screen has settled in front (never in a Debug build without -askLocationAtLaunch YES).
        CompanionWeather.shared.start()
        if ModelContainerFactory.didResetStore { CloudSyncMonitor.shared.forgetLastSync() }
        let context = container.mainContext
        DateServices.start(container: container) // brief 82: one day in every zone, and catching up when the zone or day changes
        TaskActions.seedDefaultsIfNeeded(in: context)
        // HITList's own sync engine, when this store is switched to it (never in a released build:
        // `SyncEngineSwitch.isAvailable`); on the mirror it only tells the board so, and makes nothing. Before anything
        // below writes the store: the engine takes down each deletion as it is saved.
        SyncEngine.launchIfSwitchedOn(container: container)
        Deduplicator.runAndLog(in: context, trigger: "launch")
        TaskActions.seedSampleDataIfRequested(in: context)
        TaskActions.seedDemoDataIfRequested(in: context) // screenshots and sessions: a believable week on a side store
        #if DEBUG
        TaskActions.seedSyncLoadIfRequested(in: context) // a store of a few thousand tasks, to time a first sync
        TaskActions.seedFromNewestBackupIfRequested(in: context) // the move's rehearsal: a side store from the newest backup
        #endif
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
        ShareInbox.start(container: container) // brief 90: makes the share sheet's tasks, once each, by quick add's road
        StreamInbox.start(container: container) // brief 176: what the Stream ring heard, from the relay, a few seconds on
        #if DEBUG
        SyncEngineRehearsal.runIfAsked(container: container) // round 32: the move rehearsed from a terminal, side stores only
        #endif
        // The move to the new sync made by the app itself (round 33, brief 167; on from 0.9.16, and waiting for
        // George's word: `SyncEngineAutoMove` R0), and the quiet finish of any move that waits for the next start.
        SyncEngineAutoMove.Runner.start(container: container)
        SyncEngineMoveFinish.install(container: container)
        if !isTesting { SyncEngineMoveCheck.startIfDue() } // a device the app moved checks itself once, at rest
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
                    SyncEngine.shared?.cameForward() // brief 143: everything compared, then a sync (nil on the mirror)
                    SyncEngineAutoMove.Runner.shared?.cameForward() // George's word may have come meanwhile
                    #if os(iOS)
                    StreamInbox.shared?.cameForward() // brief 176 (the Mac asks on its app's own activation)
                    #endif
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
            QuickAddGuideCommands() // brief 98: Help ▸ Quick Add Guide
            #endif
        }
        #if os(iOS)
        // Brief 81: a background refresh lets CloudKit import, rewrites the widgets' snapshot and drains their outbox;
        // then (brief 176) the Stream ring's relay is asked for what was said meanwhile.
        .backgroundTask(.appRefresh(WidgetRefresh.identifier)) {
            await WidgetRefresh.run()
            await StreamInbox.shared?.check(.backgroundRefresh)
        }
        #endif
    }
}
