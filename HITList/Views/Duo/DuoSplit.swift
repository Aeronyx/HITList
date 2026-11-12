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
    /// The trailing safe area where the columns meet it: the system's bar column on its side (brief 108). The editor
    /// and the next days, the trailing columns, stop there, as Upcoming's board does (brief 56); the background
    /// still runs under it.
    @State private var trailingBar: CGFloat = 0
    /// The detail as laid out, in the window's space, for the editor's edge at the hinge.
    @State private var detailFrame: CGRect = .zero

    /// Where the editor starts in the window: past the crease while partly open, else the hinge (the display's middle).
    private var editorStart: CGFloat {
        (geometry.crease?.maxX ?? geometry.middle) + geometry.leadingInset
    }

    /// The bar column this detail keeps clear of.
    private var trailingPad: CGFloat { min(trailingBar, geometry.trailingInset) }

    private var plan: DuoColumns {
        DuoColumns.plan(width: geometry.width, sidebarWidth: DuoSplit.sidebarWidth,
                        editorOpen: popouts.task != nil, showsToday: item == .today, fold: geometry.split,
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
            if let task = popouts.task, let planned = plan.editorWidth {
                DuoColumnDivider(width: plan.gutter)
                DuoEditorColumn(task: task)
                    .frame(width: plan.showsSidebar ? planned
                                : DuoColumns.editorWidth(planned: planned, detail: detailFrame, start: editorStart,
                                                         trailingBar: trailingPad))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // Partly open, the sidebar ends at a top-to-bottom crease; the detail's content starts past it (brief 50).
        .padding(.leading, plan.detailLeadingInset)
        // On its side the system's bars stand in a column down the trailing edge: the editor's "…" and Confirm, the
        // next days' Groups, were under it.
        // Never more than the window's own.
        .padding(.trailing, trailingPad)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: { trailingBar = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { detailFrame = $0 }
        .background(Theme.background)
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
