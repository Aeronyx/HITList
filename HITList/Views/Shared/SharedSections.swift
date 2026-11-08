import SwiftUI
import HITListCore

/// A section header of a list that shows shared tasks among yours (brief 62): a Group's, "Ungrouped" or a day's as
/// `GroupSectionHeading` draws them, or a shared list's: "👥 Trip · 2", the two-person marker in the list's colour in
/// place of a Group's dot, the name and count as one run of text in the one header style (`taskSectionHeader`).
struct RowSectionHeading: Equatable {
    var heading: GroupSectionHeading
    /// A shared list's colour: the marker before its name. Nil for every other section.
    var sharedColor: Color?

    var isShared: Bool { sharedColor != nil }

    /// The heading for `key`: a Group looked up among `projects`, a shared list among `sharedLists`. A list that went a
    /// moment ago (left on another device) keeps its section, untitled, until its tasks go with it.
    static func make(for key: ListSectionKey<ListRowGroup>, count: Int, projects: [Project], sharedLists: [SharedList],
                     now: Date = Date()) -> RowSectionHeading {
        let plain: ListSectionKey<UUID>
        switch key {
        case .all: plain = .all
        case .ungrouped: plain = .ungrouped
        case .due(let section): plain = .due(section)
        case .group(.group(let id)): plain = .group(id)
        case .group(.shared(let id)):
            let list = sharedLists.first { $0.id == id }
            let title = list.map { $0.title.isEmpty ? SharedRow.untitled : $0.title } ?? SharedRow.untitled
            return RowSectionHeading(heading: GroupSectionHeading(title: title, dot: nil, titleColor: HITColor.text, count: count),
                                     sharedColor: Color(hex: list?.colorHex ?? SharedTasksStore.defaultColor))
        }
        return RowSectionHeading(heading: .make(for: plain, count: count, projects: projects, now: now))
    }

    /// VoiceOver: "Trip, shared list, 2 tasks".
    var accessibilityLabel: String {
        guard isShared else { return heading.accessibilityLabel }
        let count = heading.count
        return "\(heading.title), shared list, \(count) \(count == 1 ? "task" : "tasks")"
    }
}

/// Draws a `RowSectionHeading`: a Group's, "Ungrouped" and a day's with `GroupSectionHeader`, a shared list's the same
/// way with the two-person marker in place of the dot.
struct RowSectionHeader: View {
    let heading: RowSectionHeading
    /// Right under Today's "Overdue" or day title (one header, two lines): closer to it than to a row.
    var belowBanner = false

    var body: some View {
        if let color = heading.sharedColor {
            HStack(spacing: HITSpacing.s) {
                // In the dot's 8 pt, overhanging it evenly, so the name lines up with the Groups' names above it.
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 8)
                Text(heading.heading.label)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heading.accessibilityLabel)
            .accessibilityAddTraits(.isHeader)
            .taskSectionHeader(color: heading.heading.titleColor)
            .padding(.top, belowBanner ? -ListMetrics.headerTop / 2 : 0)
        } else {
            GroupSectionHeader(heading: heading.heading, belowBanner: belowBanner)
        }
    }
}
