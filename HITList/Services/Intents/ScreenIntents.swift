import AppIntents
import Observation
import SwiftUI

/// The screens Siri and Shortcuts can open: "Open Today in HITList".
enum HITScreen: String, AppEnum, CaseIterable {
    case today, inbox, upcoming

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    static let caseDisplayRepresentations: [HITScreen: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today", image: .init(systemName: "star")),
        .inbox: DisplayRepresentation(title: "Inbox", image: .init(systemName: "tray")),
        .upcoming: DisplayRepresentation(title: "Upcoming", image: .init(systemName: "calendar")),
    ]

    /// The iPhone tab that shows it.
    var mobileTab: MobileTab {
        switch self {
        case .today: .today
        case .inbox: .inbox
        case .upcoming: .upcoming
        }
    }

    /// The sidebar item that shows it (iPad, Mac).
    var sidebarItem: SidebarItem {
        switch self {
        case .today: .today
        case .inbox: .inbox
        case .upcoming: .upcoming
        }
    }
}

/// "Open Today / Inbox / Upcoming in HITList": brings the app forward on that screen.
struct OpenScreenIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Screen"
    static let description: IntentDescription? = IntentDescription("Opens HITList on Today, the Inbox or Upcoming.",
                                                                   categoryName: "Navigation")
    static let openAppWhenRun = true

    @Parameter(title: "Screen", default: .today)
    var target: HITScreen

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    init() {}

    init(_ screen: HITScreen) {
        target = screen
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.open(target)
        return .result()
    }
}

/// Carries an Open intent's screen, or the task a Spotlight result opens, to whichever shell is on show.
/// The intent can run before any window exists (a cold launch from Siri or Spotlight), so the request
/// waits here until a shell takes it (`intentRouting`).
@MainActor
@Observable
final class IntentRouter {
    static let shared = IntentRouter()

    struct Request: Equatable {
        var screen: HITScreen?
        /// A task to open in the editor (`OpenTaskIntent`, a Spotlight result).
        var task: UUID?
        /// Opening the same screen twice is two requests.
        let id = UUID()
    }

    private(set) var request: Request?

    func open(_ screen: HITScreen) {
        request = Request(screen: screen)
    }

    func open(task id: UUID) {
        request = Request(task: id)
    }

    /// The waiting screen, once: the shell that takes it switches to it. A task request stays.
    func take() -> HITScreen? {
        guard let screen = request?.screen else { return nil }
        request = nil
        return screen
    }

    /// The waiting task, once: the shell that takes it opens it. A screen request stays.
    func takeTask() -> UUID? {
        guard let task = request?.task else { return nil }
        request = nil
        return task
    }
}

extension View {
    /// iPhone shell: switches `tab` to the screen an Open intent asked for (`IntentRouter`), and opens the
    /// task a Spotlight result names.
    func intentRouting(tab: Binding<MobileTab>, router: IntentRouter = .shared) -> some View {
        modifier(IntentRouting(router: router) { tab.wrappedValue = $0.mobileTab })
    }

    /// Sidebar shell (iPad, Mac): selects the screen an Open intent asked for, and opens the task a
    /// Spotlight result names.
    func intentRouting(selection: Binding<SidebarItem?>, router: IntentRouter = .shared) -> some View {
        modifier(IntentRouting(router: router) { selection.wrappedValue = $0.sidebarItem })
    }
}

private struct IntentRouting: ViewModifier {
    let router: IntentRouter
    let apply: (HITScreen) -> Void
    @Environment(PopoutController.self) private var popouts: PopoutController?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .onAppear(perform: route)
            .onChange(of: router.request) { _, _ in route() }
            // A Spotlight result for an indexed task, when the system hands it over as an activity
            // rather than through `OpenTaskIntent` (brief 52).
            .onContinueUserActivity(SpotlightSync.activityType) { activity in
                if let id = SpotlightSync.taskID(from: activity) { router.open(task: id) }
            }
    }

    private func route() {
        if let screen = router.take() { apply(screen) }
        // Only a shell inside the popouts' environment opens tasks; the request waits for one otherwise.
        if let popouts, router.request?.task != nil, let id = router.takeTask(),
           let task = IntentActions.task(id: id, in: context) {
            popouts.open(task)
        }
    }
}
