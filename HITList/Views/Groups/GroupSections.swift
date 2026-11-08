import SwiftUI
import HITListCore

/// What a sorted list's section header shows (briefs 57, 61): a Group's colour dot, name and open count;
/// "Ungrouped" last with a hollow grey dot; a due day ("Overdue", "Today", "Friday, Nov 13", "Later", "No
/// date") in the due colours. Pure, so `GroupsTests` checks it without drawing anything.
struct GroupSectionHeading: Equatable {
    var title: String
    /// The dot before the title; nil draws none (date sections).
    var dot: Dot?
    /// The title's colour: the due colours for a day, the text colour for a Group.
    var titleColor: Color
    var count: Int

    enum Dot: Equatable {
        case filled(Color)
        /// "Ungrouped": an outline, since there is no Group colour to show.
        case hollow
    }

    /// The heading for `key`, looking the Group up among `projects`. A Group deleted a moment ago (the
    /// list still holds its tasks until SwiftData catches up) reads as "Ungrouped". `now` names the days.
    static func make(for key: ListSectionKey<UUID>, count: Int, projects: [Project], now: Date = Date()) -> GroupSectionHeading {
        switch key {
        case .all:
            return GroupSectionHeading(title: "", dot: nil, titleColor: Theme.secondaryText, count: count)
        case .group(let id):
            guard let project = projects.first(where: { $0.id == id }) else {
                return make(for: .ungrouped, count: count, projects: projects)
            }
            return GroupSectionHeading(title: project.name, dot: .filled(Color(hex: project.colorHex)),
                                       titleColor: HITColor.text, count: count)
        case .ungrouped:
            return GroupSectionHeading(title: "Ungrouped", dot: .hollow, titleColor: Theme.secondaryText, count: count)
        case .due(let section):
            return GroupSectionHeading(title: title(of: section, now: now), dot: nil, titleColor: color(of: section),
                                       count: count)
        }
    }

    /// The heading for a section of a list that holds shared tasks among yours (briefs 62, 64): a Group's, "Ungrouped"
    /// and a day's as above, and Shared Tasks' like any Group's, its dot in its colour.
    static func make(row key: ListSectionKey<ListRowGroup>, count: Int, projects: [Project], now: Date = Date()) -> GroupSectionHeading {
        switch key {
        case .all: make(for: ListSectionKey<UUID>.all, count: count, projects: projects, now: now)
        case .ungrouped: make(for: ListSectionKey<UUID>.ungrouped, count: count, projects: projects, now: now)
        case .due(let section): make(for: ListSectionKey<UUID>.due(section), count: count, projects: projects, now: now)
        case .group(.group(let id)): make(for: ListSectionKey<UUID>.group(id), count: count, projects: projects, now: now)
        case .group(.sharedTasks): sharedTasks(count: count)
        }
    }

    /// Shared Tasks' heading: "Shared Tasks · 3" after its dot (brief 64).
    static func sharedTasks(count: Int) -> GroupSectionHeading {
        GroupSectionHeading(title: SharedTasksGroup.name, dot: .filled(Color(hex: SharedTasksGroup.colorHex)),
                            titleColor: HITColor.text, count: count)
    }

    /// The filter lists' day titles (`DueFormatter.sectionTitle`), with the week's last days as "Later".
    private static func title(of section: DueSection, now: Date) -> String {
        switch section {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .day(let day): DueFormatter.sectionTitle(for: day, now: now)
        case .later: "Later"
        case .noDate: DueFormatter.sectionTitle(for: nil, now: now)
        }
    }

    /// "Overdue" red, today green, the rest grey (`DueFormatter.sectionColor`).
    private static func color(of section: DueSection) -> Color {
        switch section {
        case .overdue: HITColor.dueOverdue
        case .today: HITColor.dueToday
        case .tomorrow, .day, .later, .noDate: Theme.secondaryText
        }
    }

    /// "Work · 3": the title and the count after a middle dot as one run of text, so both are set in the
    /// header's one font (George, 0.8.0: "Priority 4 1 in different fonts"); the count in grey. Just the
    /// title when nothing is open.
    var label: AttributedString {
        var label = AttributedString(title)
        guard count > 0 else { return label }
        var suffix = AttributedString(" · \(count)")
        suffix.swiftUI.foregroundColor = Theme.secondaryText
        label.append(suffix)
        return label
    }

    /// VoiceOver: "Work, 3 tasks".
    var accessibilityLabel: String {
        "\(title), \(count) \(count == 1 ? "task" : "tasks")"
    }
}

/// A sorted section's header row, laid out like every task list's (`taskSectionHeader`): the dot, then the
/// title and count as one `Text` (`GroupSectionHeading.label`). Not a button (brief 61): a Group opens from
/// Browse or the sidebar.
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
            Text(heading.label)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heading.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .taskSectionHeader(color: heading.titleColor)
        .padding(.top, belowBanner ? -ListMetrics.headerTop / 2 : 0)
    }
}

/// The view options' "Sort by" (brief 61): Priority · Group · Date on the Inbox, Priority · Group on Today, a
/// submenu that shows the choice.
struct SortPicker: View {
    @Binding var selection: ListSort
    let choices: [ListSort]

    var body: some View {
        Picker(selection: $selection) {
            ForEach(choices) { sort in
                Text(sort.title).tag(sort)
            }
        } label: {
            Label("Sort by", systemImage: "arrow.up.arrow.down")
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("sortPicker")
    }
}
