import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Where Shared Tasks is reached (briefs 51, 64): the Shared Tasks Group, last under Groups in the Mac sidebar and
/// Browse, and a sheet over whatever is showing when an invitation link opens the app (`SharedTasksPresenter`).

/// The Sharing… sheet on its own (invitations, Debug launch hooks), with its own Done.
struct SharedTasksSheet: View {
    let onClose: () -> Void

    var body: some View {
        SharingSheet(onClose: onClose)
            .slateSheet()
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 600)
            #endif
    }
}

/// An invitation opened while the app runs or launches: a sheet over whatever is showing, on any shell, without a
/// hook in `ContentView`. It shows the invitation (Join switches Shared Tasks on) and then the joined list.
@MainActor
enum SharedTasksPresenter {
    static func presentInvitation() {
        // Weak: a sheet swiped away is gone, and the next invitation may show again.
        guard host == nil, SharedTasksCenter.shared.pendingInvitation != nil else { return }
        present(SharedInvitationSheet(onClose: dismiss))
    }

    /// Sharing… in a sheet: a list just joined, and Debug launch hooks (`SharedTasksDebug`).
    static func presentSharing() {
        guard host == nil else { return }
        present(SharedTasksSheet(onClose: dismiss))
    }

    /// A cold launch from an invitation link arrives before the window exists: try again a few times.
    private static func retry<V: View>(_ view: V, attempt: Int) {
        guard attempt < 10 else {
            Logger(subsystem: "com.trammells.hitlist", category: "sharing").error("Shared Tasks: no window to show the sheet in")
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            present(view, attempt: attempt + 1)
        }
    }

    #if os(iOS)
    private static weak var host: UIViewController?

    private static func present<V: View>(_ view: V, attempt: Int = 0) {
        guard host == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController else {
            retry(view, attempt: attempt)
            return
        }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIHostingController(rootView: view.preferredColorScheme(.dark).tint(Theme.accent).font(HITType.body))
        controller.overrideUserInterfaceStyle = .dark
        host = controller
        top.present(controller, animated: true)
    }

    static func dismiss() {
        host?.dismiss(animated: true)
        host = nil
    }
    #else
    private static weak var host: NSViewController?

    private static func present<V: View>(_ view: V, attempt: Int = 0) {
        guard host == nil else { return }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
              let root = window.contentViewController else {
            retry(view, attempt: attempt)
            return
        }
        let controller = NSHostingController(rootView: view.preferredColorScheme(.dark).tint(Theme.accent).font(HITType.body))
        controller.title = "Shared Tasks"
        controller.preferredContentSize = NSSize(width: 560, height: min(600, max(420, window.frame.height - 80)))
        host = controller
        root.presentAsSheet(controller)
    }

    static func dismiss() {
        if let host { host.presentingViewController?.dismiss(host) }
        host = nil
    }
    #endif
}

/// The invitation, then Sharing… once joined (who you now share with).
struct SharedInvitationSheet: View {
    let onClose: () -> Void
    @State private var joined: UUID?
    private var center: SharedTasksCenter { SharedTasksCenter.shared }

    var body: some View {
        if joined != nil {
            SharedTasksSheet(onClose: onClose)
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: HITSpacing.l) {
                        if let invitation = center.pendingInvitation {
                            SharedInvitationCard(invitation: invitation) { listID in
                                if let listID { joined = listID } else { onClose() }
                            }
                        }
                        SharedTasksExplainer(showsInvitation: false)
                    }
                    .padding(HITSpacing.l)
                }
                .background(Theme.background)
                .navigationTitle("Invitation")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not Now", action: onClose)
                    }
                }
            }
            .slateSheet()
            .onChange(of: center.pendingInvitation == nil) { _, gone in
                if gone, joined == nil { onClose() }
            }
        }
    }
}
