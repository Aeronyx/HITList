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
                                       titleColor: HITColor.text, count: count)
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
/// title, the count after it in grey. Not a button (brief 61): a Group opens from Browse or the sidebar.
struct GroupSectionHeader: View {
    let heading: GroupSectionHeading
    /// Right under Today's "Overdue" or day title (one header, two lines): closer to it than to a row.
    var belowBanner = false

    var body: some View {
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
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heading.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .taskSectionHeader(color: heading.titleColor)
        .padding(.top, belowBanner ? -ListMetrics.headerTop / 2 : 0)
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
