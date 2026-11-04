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
                        editorOpen: popouts.task != nil, showsToday: item == .today, fold: geometry.fold)
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
                DuoColumnDivider()
                DuoEditorColumn(task: task)
                    .frame(width: width)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: popouts.state.taskID)
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: plan)
        .onChange(of: plan.showsSidebar, initial: true) { _, shows in
            let wanted: NavigationSplitViewVisibility = shows ? .all : .detailOnly
            guard columnVisibility != wanted else { return }
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { columnVisibility = wanted }
        }
    }
}

/// The hairline between the Duo's columns.
private struct DuoColumnDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1)
            .ignoresSafeArea(.container, edges: .bottom)
            .accessibilityHidden(true)
    }
}

/// The task editor as a column: the same `TaskPopout` the phone shows in its sheet, filling the column
/// the way it fills the sheet (it lays out as a sheet when the width is compact). Closing it (×, Confirm,
/// completing the task) closes the column.
struct DuoEditorColumn: View {
    let task: TaskItem

    var body: some View {
        TaskPopout(task: task)
            .id(task.id)
            .environment(\.horizontalSizeClass, .compact)
            .background(Theme.background)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Task editor")
    }
}
