import SwiftUI

/// The Duo's sidebar column width; fixed, so `DuoColumns.plan` can count on it.
enum DuoSplit {
    static let sidebarWidth: CGFloat = 240
}

/// The Duo's detail column (brief 45): the list, and beside it either the task being edited (instead of
/// the sheet the phone uses) or, on Today, the next days. `DuoColumns.plan` divides the width; when the
/// editor needs the sidebar's room the sidebar steps aside until it closes.
struct DuoDetail: View {
    let item: SidebarItem
    let geometry: WindowGeometry
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var plan: DuoColumns {
        DuoColumns.plan(width: geometry.width, sidebarWidth: DuoSplit.sidebarWidth,
                        editorOpen: popouts.task != nil, showsToday: item == .today, fold: geometry.fold,
                        crease: geometry.crease)
    }

    var body: some View {
        let plan = plan
        HStack(spacing: 0) {
            ListScreen(item: item)
                .frame(maxWidth: .infinity)
            if let width = plan.nextDaysWidth {
                DuoColumnDivider()
                DuoNextDays()
                    .frame(width: width)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if let task = popouts.task, let width = plan.editorWidth {
                DuoColumnDivider(width: plan.gutter)
                DuoEditorColumn(task: task)
                    .frame(width: width)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // Partly open upright the sidebar ends at the crease; the detail's content starts past it (brief 50).
        .padding(.leading, plan.detailLeadingInset)
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: popouts.state.taskID)
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: plan)
        .onChange(of: plan.showsSidebar, initial: true) { _, shows in
            let wanted: NavigationSplitViewVisibility = shows ? .all : .detailOnly
            guard columnVisibility != wanted else { return }
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { columnVisibility = wanted }
        }
    }
}

/// Between the Duo's columns: a hairline, or partly open, the crease itself, left empty (brief 50).
private struct DuoColumnDivider: View {
    var width: CGFloat = 1

    var body: some View {
        Rectangle()
            .fill(width > 1 ? Theme.background : Theme.separator)
            .frame(width: width)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .accessibilityHidden(true)
    }
}

/// The task editor as a column: the same `TaskPopout` the phone shows in its sheet, filling the column
/// the way it fills the sheet (it lays out as a sheet when the width is compact). Closing it (×, Confirm,
/// completing the task) closes the column.
struct DuoEditorColumn: View {
    let task: TaskItem
    /// Typing from the outer display's sheet arrives here on unfolding, and leaves with the column on folding.
    @Environment(\.editorCarryOver) private var carryOver

    var body: some View {
        TaskPopout(task: task, carryOver: carryOver)
            .id(task.id)
            .environment(\.horizontalSizeClass, .compact)
            .background(Theme.background)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Task editor")
    }
}
