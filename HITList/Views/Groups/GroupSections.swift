import SwiftUI
import HITListCore

/// What a grouped list's section header shows (brief 57): a Group's colour dot, name and open count; "No
/// Group" last with a hollow grey dot; "Priority 1" in its colour. Pure, so `GroupsTests` checks it without
/// drawing anything.
struct GroupSectionHeading: Equatable {
    var title: String
    /// The dot before the title; nil draws none (priority sections).
    var dot: Dot?
    /// The title's colour: the day/priority colours as before, the text colour for a Group.
    var titleColor: Color
    var count: Int
    /// The list the header opens on iPhone (a Group's own screen); nil for "No Group" and priorities.
    var opens: SidebarItem?

    enum Dot: Equatable {
        case filled(Color)
        /// "No Group": an outline, since there is no Group colour to show.
        case hollow
    }

    /// The heading for `key`, looking the Group up among `projects`. A Group deleted a moment ago (the
    /// list still holds its tasks until SwiftData catches up) reads as "No Group".
    static func make(for key: ListSectionKey<UUID>, count: Int, projects: [Project]) -> GroupSectionHeading {
        switch key {
        case .all:
            return GroupSectionHeading(title: "", dot: nil, titleColor: Theme.secondaryText, count: count)
        case .group(let id):
            guard let project = projects.first(where: { $0.id == id }) else {
                return make(for: .noGroup, count: count, projects: projects)
            }
            return GroupSectionHeading(title: project.name, dot: .filled(Color(hex: project.colorHex)),
                                       titleColor: HITColor.text, count: count, opens: .project(project.id))
        case .noGroup:
            return GroupSectionHeading(title: "No Group", dot: .hollow, titleColor: Theme.secondaryText, count: count)
        case .priority(let level):
            let priority = Priority(rawValue: level) ?? .p4
            return GroupSectionHeading(title: "Priority \(priority.rawValue)", dot: nil,
                                       titleColor: priority == .p4 ? Theme.secondaryText : priority.color, count: count)
        }
    }

    /// VoiceOver: "Work, 3 tasks".
    var accessibilityLabel: String {
        "\(title), \(count) \(count == 1 ? "task" : "tasks")"
    }
}

/// A grouped section's header row, laid out like every task list's (`taskSectionHeader`): the dot, the
/// title, the count after it in grey. On iPhone a Group's header opens that Group on the current tab's
/// stack, with a chevron to say so (brief 57).
struct GroupSectionHeader: View {
    let heading: GroupSectionHeading
    /// Whether a Group's header pushes its screen (iPhone's tab stacks, where a `SidebarItem` value opens it).
    var pushes = false
    /// Right under Today's "Overdue" or day title (one header, two lines): closer to it than to a row.
    var belowBanner = false

    var body: some View {
        if pushes, let item = heading.opens {
            NavigationLink(value: item) { content(chevron: true) }
                .buttonStyle(.plain)
                .taskSectionHeader(color: heading.titleColor)
                .padding(.top, belowBanner ? -ListMetrics.headerTop / 2 : 0)
                .accessibilityHint("Opens the Group")
        } else {
            content(chevron: false)
                .taskSectionHeader(color: heading.titleColor)
                .padding(.top, belowBanner ? -ListMetrics.headerTop / 2 : 0)
        }
    }

    private func content(chevron: Bool) -> some View {
        HStack(spacing: HITSpacing.s) {
            switch heading.dot {
            case .filled(let color)?:
                Circle().fill(color).frame(width: 8, height: 8)
            case .hollow?:
                Circle().strokeBorder(Theme.secondaryText, lineWidth: 1.5).frame(width: 8, height: 8)
            case nil:
                EmptyView()
            }
            Text(heading.title)
            if heading.count > 0 {
                Text("\(heading.count)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heading.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The view options' "Group by: None · Group · Priority" (brief 57), a submenu that shows the choice.
struct GroupByPicker: View {
    @Binding var selection: ListGrouping

    var body: some View {
        Picker(selection: $selection) {
            ForEach(ListGrouping.allCases) { grouping in
                Text(grouping.title).tag(grouping)
            }
        } label: {
            Label("Group by", systemImage: "rectangle.3.group")
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("groupByPicker")
    }
}

/// A Group's own screen, at the top (brief 57): its colour dot, name and open count, "● Work · 3", in the
/// Inbox header's type and place, so a Group reads as a place of its own. On iPhone the navigation title
/// goes inline above it, as the Inbox's does.
struct GroupScreenHeader: View {
    let name: String
    let colorHex: String
    let openCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: HITSpacing.s) {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 12, height: 12)
            Text(openCount > 0 ? "\(name) · \(openCount)" : name)
                .font(HITType.title2Bold)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(openCount)))
                .animation(reduceMotion ? nil : .snappy, value: openCount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(name), \(openCount) \(openCount == 1 ? "task" : "tasks")")
        .accessibilityIdentifier("groupScreenHeader")
    }
}
