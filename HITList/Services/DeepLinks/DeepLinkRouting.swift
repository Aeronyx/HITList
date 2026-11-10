import SwiftUI

extension DeepLink {
    /// Hands the link to whichever shell is on show, as an Open intent (a screen) or a Spotlight result (a task) does:
    /// the request waits in the router until a shell takes it, so a cold launch from a widget lands too.
    @MainActor
    func open(router: IntentRouter = .shared) {
        switch self {
        case .task(let id): router.open(task: id)
        case .today: router.open(.today)
        case .upcoming: router.open(.upcoming)
        case .flipboard: router.open(.flipboard)
        }
    }
}

extension View {
    /// The window's one `onOpenURL` (brief 74, `HITListApp`): `hitlist://` links from the widgets. On the Mac the
    /// window that is already open takes the link, rather than SwiftUI opening a second window for it.
    func deepLinkRouting() -> some View {
        self
            .onOpenURL { url in DeepLink(url)?.open() }
            #if os(macOS)
            .handlesExternalEvents(preferring: [DeepLink.scheme], allowing: ["*"])
            #endif
    }
}
