import SwiftUI
import HITListCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// "Add to Calendar" (brief 136): the one item a dated task's context menu (long-press on iPhone) and its editor's
/// "…" menu get. It puts one event on the calendar picked on the Calendar page (`CalendarAdds`), then a toast says
/// "Added to Work · Undo" or "Already on your calendar". Nothing for an undated or completed task.
struct AddToCalendarButton: View {
    let task: TaskItem

    static let title = "Add to Calendar"

    var body: some View {
        if CalendarAdds.canAdd(due: task.dueDate, isCompleted: task.isCompleted) {
            Button(Self.title, systemImage: "calendar.badge.plus") { Self.add(task) }
                .accessibilityIdentifier("addToCalendar")
        }
    }

    /// Reads the task now (an editor's unsaved typing included) and adds it.
    @MainActor
    static func add(_ task: TaskItem) {
        guard let due = task.dueDate else { return }
        CalendarNoticeWindow.shared.install()
        let id = task.id, title = task.title, notes = task.notes, hasTime = task.hasDueTime
        Task { await CalendarAdds.shared.add(taskID: id, title: title, notes: notes, due: due, hasTime: hasTime) }
    }
}

/// The pill Add to Calendar's toast shows: "Added to Work · Undo" (the whole pill is the Undo, as the completion
/// toast's is), or words alone ("Already on your calendar"). The completion toast's look: 48 pt, elevated, a hairline.
struct CalendarNoticeToast: View {
    let notice: CalendarAdds.Notice
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button {
            if notice.canUndo { onUndo() } else { onDismiss() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol(for: notice.kind))
                    .foregroundStyle(notice.kind == .refused || notice.kind == .failed ? HITColor.danger : Theme.accent)
                Text(notice.message)
                    .foregroundStyle(HITColor.text)
                    .lineLimit(1)
                if notice.canUndo {
                    Text("·").foregroundStyle(Theme.secondaryText)
                    Text("Undo")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                        .layoutPriority(1)
                }
            }
            .font(HITType.subheadline)
            .padding(.horizontal, 18)
            .frame(height: CompletionToast.height)
            .background(Theme.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.separator))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .accessibilityLabel(notice.canUndo ? "\(notice.message), Undo" : notice.message)
        .accessibilityHint(notice.canUndo ? "Removes the event from your calendar" : "")
        .accessibilityAction(named: "Dismiss", onDismiss)
        .accessibilityIdentifier("calendarNotice")
    }

    static func symbol(for kind: CalendarAdds.Notice.Kind) -> String {
        switch kind {
        case .added, .already: "calendar.badge.checkmark"
        case .removed: "calendar"
        case .refused, .failed: "exclamationmark.circle"
        }
    }
}

/// Draws Add to Calendar's toast in a small window of its own over the app's, so it shows wherever the menu was
/// used (any list, the editor's sheet on iPhone, the editor's panel on the Mac) without a list having to host it.
/// iPhone: beside the "+", where the undo toasts sit (`PopoutHost.phoneToastInsets`); iPad and Mac: the window's
/// bottom-trailing corner, a toast's height above where a list's own toast sits. Gone with the notice.
@MainActor
final class CalendarNoticeWindow {
    static let shared = CalendarNoticeWindow()

    /// The room around the pill for its shadow.
    private static let shadowRoom: CGFloat = 16

    #if os(iOS)
    private var window: UIWindow?
    #else
    private var panel: NSPanel?
    #endif

    /// Hands `CalendarAdds` the way to show its notices; once is enough.
    func install() {
        guard CalendarAdds.shared.onNotice == nil else { return }
        CalendarAdds.shared.onNotice = { [weak self] notice in self?.show(notice) }
    }

    private func show(_ notice: CalendarAdds.Notice?) {
        guard let notice else { return hide() }
        AccessibilityNotification.Announcement(notice.message).post()
        let toast = CalendarNoticeToast(notice: notice,
                                        onUndo: { Task { await CalendarAdds.shared.undo() } },
                                        onDismiss: { CalendarAdds.shared.dismiss() })
            .padding(Self.shadowRoom)
            .environment(\.colorScheme, .dark)
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let main = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { return }
        let host = UIHostingController(rootView: AnyView(toast))
        host.view.backgroundColor = .clear
        let bounds = main.bounds, safe = main.safeAreaInsets
        let compact = main.traitCollection.horizontalSizeClass == .compact
        let room = Self.shadowRoom
        let insets = PopoutHost.phoneToastInsets
        let available = compact ? bounds.width - insets.leading - insets.trailing + 2 * room
                                : CompletionToast.panelMaxWidth + 2 * room
        var size = host.sizeThatFits(in: CGSize(width: available, height: CompletionToast.height + 2 * room))
        size.width = min(size.width, available)
        size.height = CompletionToast.height + 2 * room
        let origin: CGPoint
        if compact {
            origin = CGPoint(x: insets.leading - room, y: bounds.height - safe.bottom - insets.bottom - CompletionToast.height - room)
        } else {
            // Above the iPad's floating "+" at that corner, and a gap.
            let lift = HITSpacing.l + FloatingAddButton.size.height + HITSpacing.m
            origin = CGPoint(x: bounds.width - safe.right - HITSpacing.l - size.width + room,
                             y: bounds.height - safe.bottom - lift - CompletionToast.height - room)
        }
        let window = self.window ?? UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = host
        window.frame = CGRect(origin: origin, size: size)
        window.isHidden = false
        self.window = window
        #else
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let host = NSHostingView(rootView: toast)
        let size = host.fittingSize
        let panel = self.panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = host
        let frame = parent.frame
        let lift = HITSpacing.l + CompletionToast.height + HITSpacing.s
        panel.setFrame(NSRect(x: frame.maxX - HITSpacing.l - size.width + Self.shadowRoom,
                              y: frame.minY + lift - Self.shadowRoom,
                              width: size.width, height: size.height), display: true)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        self.panel = panel
        #endif
    }

    private func hide() {
        #if os(iOS)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        #else
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        #endif
    }
}
