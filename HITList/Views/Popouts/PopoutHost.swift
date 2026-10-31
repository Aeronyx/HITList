import SwiftUI
import SwiftData

extension View {
    /// Draws the window's popouts over this view. Applied once, by `ContentView`.
    func popoutHost(_ popouts: PopoutController) -> some View {
        modifier(PopoutHost(popouts: popouts))
    }
}

/// Presents the selected task. (The task popout replaces this sheet.)
struct PopoutHost: ViewModifier {
    @Bindable var popouts: PopoutController

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { popouts.task }, set: { if $0 == nil { popouts.closeTask() } })) { task in
                NavigationStack {
                    TaskDetailView(task: task) { popouts.closeTask() }
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { popouts.closeTask() } }
                        }
                }
                .slateSheet()
            }
    }
}
