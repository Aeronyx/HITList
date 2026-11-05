import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Where Shared Tasks is reached (brief 51): a row at the top of the iPhone's Browse, one row in the Mac and iPad
/// sidebar, and a sheet over whatever is showing when an invitation link opens the app.

/// Browse's first row: "Shared Tasks · Preview", the open count once on. Pushes the Shared screen.
struct SharedTasksBrowseRow: View {
    private var center: SharedTasksCenter { SharedTasksCenter.shared }

    var body: some View {
        NavigationLink {
            SharedTasksScreen()
        } label: {
            SharedTasksEntryLabel(symbolSize: 16)
        }
        .slateRow()
        .accessibilityIdentifier("browse-shared-tasks")
    }
}

/// The sidebar's row (Mac and iPad): opens the Shared screen in a sheet. A detail-column route would need a
/// `SidebarItem` case in `ListScreen`, which this brief doesn't own.
struct SharedTasksSidebarRow: View {
    @State private var showing = false
    private var center: SharedTasksCenter { SharedTasksCenter.shared }

    var body: some View {
        Button { showing = true } label: {
            // Drawn like the sidebar's other rows (`SidebarView.row`): icon in the accent, title, count.
            Label {
                HStack(spacing: 6) {
                    Text("Shared Tasks").lineLimit(1).layoutPriority(1)
                    SharedPreviewBadge(compact: true)
                    Spacer(minLength: 4)
                    if center.pendingInvitation != nil {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7).accessibilityLabel("Invitation waiting")
                    } else if let count = SharedTasksEntryLabel.openCount(center), count > 0 {
                        Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            } icon: {
                Image(systemName: "person.2").foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .slateRow()
        .accessibilityIdentifier("sidebar-shared-tasks")
        .task { center.startIfOn() }
        .sheet(isPresented: $showing) {
            SharedTasksSheet { showing = false }
        }
    }
}

/// The entry's label: two-person symbol, "Shared Tasks", the Preview badge, the open count (on) or a dot for a
/// waiting invitation.
struct SharedTasksEntryLabel: View {
    var symbolSize: CGFloat
    private var center: SharedTasksCenter { SharedTasksCenter.shared }

    var body: some View {
        HStack(spacing: HITSpacing.m) {
            Image(systemName: "person.2.fill")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text("Shared Tasks").foregroundStyle(HITColor.text).lineLimit(1)
            SharedPreviewBadge()
            Spacer(minLength: HITSpacing.s)
            if center.pendingInvitation != nil {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityLabel("Invitation waiting")
            } else if let count = Self.openCount(center), count > 0 {
                Text("\(count)").font(HITType.subheadline).monospacedDigit().foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Open tasks across the shared lists; nil while Shared Tasks isn't running.
    static func openCount(_ center: SharedTasksCenter) -> Int? {
        center.store.map { $0.lists.reduce(0) { $0 + $1.tasks.filter { !$0.isCompleted }.count } }
    }
}

/// The Shared screen in a sheet with Done (Mac and iPad sidebar, invitations).
struct SharedTasksSheet: View {
    var showsList: UUID?
    var showsPeople = false
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let showsList {
                    SharedListScreen(listID: showsList, opensPeople: showsPeople)
                } else {
                    SharedTasksScreen()
                }
            }
            .toolbar {
                // The system's own bar button: a custom style is clipped inside the iOS 26 bar's glass.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose).accessibilityIdentifier("sharedTasksDone")
                }
            }
        }
        .slateSheet()
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 560)
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

    /// The Shared screen (or one list, with its People open) in a sheet: Debug launch hooks (`SharedTasksDebug`).
    static func presentScreen(list: UUID? = nil, people: Bool = false) {
        guard host == nil else { return }
        present(SharedTasksSheet(showsList: list, showsPeople: people, onClose: dismiss))
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

/// The invitation, then the list once joined.
struct SharedInvitationSheet: View {
    let onClose: () -> Void
    @State private var joined: UUID?
    private var center: SharedTasksCenter { SharedTasksCenter.shared }

    var body: some View {
        if let joined {
            SharedTasksSheet(showsList: joined, onClose: onClose)
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
