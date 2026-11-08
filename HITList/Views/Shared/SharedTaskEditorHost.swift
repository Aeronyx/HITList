import SwiftUI

extension View {
    /// Draws the editor of a shared task this list opened (brief 62, `PopoutController.openShared`): the one
    /// `SharedListScreen` uses, in a sheet on the iPhone and iPad and in the panel on the Mac, where a task of yours
    /// opens too. `owner` is the list's own id, so on the iPhone a list under another on its stack never presents it
    /// as well.
    func sharedTaskEditor(owner: UUID) -> some View {
        modifier(SharedTaskEditorHost(owner: owner))
    }
}

private struct SharedTaskEditorHost: ViewModifier {
    let owner: UUID
    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .overlay {
                if let ref = popouts.sharedTask(for: owner) {
                    // The panel a task of yours opens in: dimmed behind, 560 pt wide, near the top. It covers this
                    // list's column; the sidebar dims itself to match (`SidebarView`).
                    PanelBackdrop(onDismiss: close) {
                        editor(ref)
                            .frame(idealHeight: 530)
                            .panelChrome()
                    }
                    .transition(.opacity)
                }
            }
            .animation(HITMotion.enter(reduceMotion: reduceMotion), value: popouts.sharedTask(for: owner) != nil)
        #else
        content
            .sheet(item: Binding(get: { popouts.sharedTask(for: owner) }, set: { if $0 == nil { close() } })) { ref in
                editor(ref).slateSheet()
            }
        #endif
    }

    @ViewBuilder
    private func editor(_ ref: SharedTaskRef) -> some View {
        if let list = SharedRows.shared.list(ref.listID), let task = list.task(ref.taskID) {
            SharedTaskEditor(task: task, list: list, now: Date(), onClose: close)
                .id(ref.taskID)
        } else {
            // Deleted, or its list left, on another device while it was open: nothing to edit.
            Color.clear.onAppear(perform: close)
        }
    }

    private func close() { popouts.closeSharedTask() }
}
