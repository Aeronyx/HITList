import SwiftUI
import HITListCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The Inbox's filter control (brief 57), beside the view options: Group (several, and No Group), Label,
/// Priority and No date, then Clear and Save as filter…. It edits a `ListFilter`, whose query the list
/// evaluates; the active choices show as chips under the header (`ListFilterChips`).
struct ListFilterMenu: View {
    @Binding var filter: ListFilter
    let projects: [Project]
    let labels: [TaskLabel]
    /// Saves the filter as a saved filter (the Inbox rule and the choices); nil hides the item.
    var onSave: (() -> Void)?

    var body: some View {
        Menu {
            Menu {
                ForEach(projects) { project in
                    Toggle(isOn: binding(.group(project.name))) {
                        Label { Text(project.name) } icon: { ColorDot.image(hex: project.colorHex) }
                    }
                }
                Toggle("No Group", isOn: binding(.noGroup))
            } label: {
                Label("Group", systemImage: "circle.grid.2x1")
            }
            Menu {
                if labels.isEmpty { Text("No labels yet") }
                ForEach(labels) { label in
                    Toggle(isOn: binding(.label(label.name))) {
                        Label { Text(label.name) } icon: { ColorDot.image(hex: label.colorHex) }
                    }
                }
            } label: {
                Label("Label", systemImage: "tag")
            }
            Menu {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Toggle(priority.filterMenuTitle, isOn: binding(.priority(priority.rawValue)))
                }
            } label: {
                Label("Priority", systemImage: "flag")
            }
            Toggle(isOn: binding(.noDate)) { Label("No date", systemImage: "calendar.badge.minus") }
            if !filter.isEmpty {
                Section {
                    Button { filter = ListFilter() } label: { Label("Clear", systemImage: "xmark.circle") }
                    if let onSave {
                        Button(action: onSave) { Label("Save as filter…", systemImage: "square.and.arrow.down") }
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: filter.isEmpty ? "line.3.horizontal.decrease.circle"
                                                        : "line.3.horizontal.decrease.circle.fill")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .help("Filter")
        .accessibilityLabel(filter.isEmpty ? "Filter" : "Filter, on")
        .accessibilityIdentifier("listFilter")
    }

    private func binding(_ chip: ListFilter.Chip) -> Binding<Bool> {
        Binding(get: { filter.contains(chip) }, set: { on in
            if on != filter.contains(chip) { filter.toggle(chip) }
        })
    }
}

/// The active filter under the header: a chip per choice, each with its ×, then Clear. Scrolls sideways
/// when there are more than fit.
struct ListFilterChips: View {
    @Binding var filter: ListFilter
    let projects: [Project]
    let labels: [TaskLabel]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HITSpacing.s) {
                ForEach(filter.chips, id: \.self) { chip in
                    HITChip(chip.title, systemImage: symbol(chip), tint: tint(chip), isSelected: true,
                            onDismiss: { withAnimation(HITMotion.quick) { filter.remove(chip) } })
                        .accessibilityLabel("Filter: \(chip.title)")
                }
                Button("Clear") { withAnimation(HITMotion.quick) { filter = ListFilter() } }
                    .buttonStyle(.plain)
                    .font(HITType.subheadlineMedium)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, HITSpacing.xs)
                    .accessibilityIdentifier("clearListFilter")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, HITSpacing.xs)
        }
        .accessibilityIdentifier("listFilterChips")
    }

    private func symbol(_ chip: ListFilter.Chip) -> String {
        switch chip {
        case .group: "circle.fill"
        case .noGroup: "circle"
        case .label: "tag.fill"
        case .priority: "flag.fill"
        case .noDate: "calendar.badge.minus"
        }
    }

    private func tint(_ chip: ListFilter.Chip) -> Color? {
        switch chip {
        case .group(let name): projects.first { $0.name == name }.map { Color(hex: $0.colorHex) }
        case .label(let name): labels.first { $0.name == name }.map { Color(hex: $0.colorHex) }
        case .priority(let level): Priority(rawValue: level).flatMap { $0 == .p4 ? nil : $0.color }
        case .noGroup, .noDate: nil
        }
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

extension Priority {
    /// "Priority 1" … "No priority" for the filter menu.
    fileprivate var filterMenuTitle: String { self == .p4 ? "Priority 4 (none)" : "Priority \(rawValue)" }
}
