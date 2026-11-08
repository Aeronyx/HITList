import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(iOS)
extension View {
    /// iPhone (brief 57: "there was no easy way to view your Groups"): the screen's title ("Inbox", "Today")
    /// becomes a menu with a chevron listing the Groups (dot, name, open count), then the labels, then
    /// Browse…. Choosing one pushes that list on the current tab's stack, as Browse does: a `SidebarItem`
    /// value, which `MobileShell`'s destinations open and `PhoneStack` records. Only inside the phone shell
    /// (`mobileChrome`); iPad and the Mac have the sidebar.
    ///
    /// The system draws a title menu only on an inline title, so a screen that has one shows its title inline
    /// (Today's was large).
    func groupsTitleMenu() -> some View {
        modifier(GroupsTitleMenu())
    }
}

private struct GroupsTitleMenu: ViewModifier {
    @Environment(\.mobileChrome) private var mobileChrome

    func body(content: Content) -> some View {
        if let mobileChrome {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbarTitleMenu {
                    GroupsTitleMenuItems(openBrowse: mobileChrome.openBrowse)
                }
        } else {
            content
        }
    }
}

/// The title menu's items: Groups, Labels, Browse….
struct GroupsTitleMenuItems: View {
    var openBrowse: () -> Void
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]
    // The counts skip sub-tasks, as the sidebar's and Browse's do.
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && $0.parent == nil }) private var openTasks: [TaskItem]

    var body: some View {
        let counts = GroupsTitleMenuCounts(openTasks)
        Section("Groups") {
            if projects.isEmpty { Text("No Groups yet") }
            ForEach(projects) { project in
                // The open count is in the title: a link in the title menu shows neither a subtitle Text nor a
                // badge (iOS 27).
                NavigationLink(value: SidebarItem.project(project.id)) {
                    Label { Text(GroupsTitleMenuCounts.title(project.name, count: counts.byProject[project.id] ?? 0)) }
                          icon: { ColorDot.image(hex: project.colorHex) }
                }
            }
        }
        if !labels.isEmpty {
            Section("Labels") {
                ForEach(labels) { label in
                    NavigationLink(value: SidebarItem.label(label.id)) {
                        Label { Text(GroupsTitleMenuCounts.title("@" + label.name, count: counts.byLabel[label.id] ?? 0)) }
                              icon: { ColorDot.image(hex: label.colorHex) }
                    }
                }
            }
        }
        Section {
            Button(action: openBrowse) { Label("Browse…", systemImage: "magnifyingglass") }
        }
    }
}
#endif

/// Open-task counts per Group and per label, for the title menu's items.
struct GroupsTitleMenuCounts {
    var byProject: [UUID: Int] = [:]
    var byLabel: [UUID: Int] = [:]

    init(_ openTasks: [TaskItem]) {
        for task in openTasks {
            if let id = task.project?.id { byProject[id, default: 0] += 1 }
            for label in task.labelList { byLabel[label.id, default: 0] += 1 }
        }
    }

    /// "Work · 3"; just "Work" with nothing open.
    static func title(_ name: String, count: Int) -> String {
        count == 0 ? name : "\(name) · \(count)"
    }
}

/// A small filled circle in a Group's or label's colour, as an image menus keep in colour (they draw
/// template images in the text colour).
enum ColorDot {
    static let diameter: CGFloat = 10

    static func image(hex: String) -> Image {
        #if os(macOS)
        let color = NSColor(Color(hex: hex))
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image)
        #else
        let color = UIColor(Color(hex: hex))
        let size = CGSize(width: diameter, height: diameter)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
        #endif
    }
}
