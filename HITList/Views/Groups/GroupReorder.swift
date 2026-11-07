import Foundation

/// Dragging a Group to a new place in the Mac sidebar or in Browse (brief 57): every Group gets its place
/// in the new order as its `sortOrder` (0, 1, 2…), which also repairs duplicates left by Groups made on two
/// devices before they synced. Only Groups whose place changed are touched, so only they sync.
@MainActor
enum GroupReorder {
    static func move(_ projects: [Project], from source: IndexSet, to destination: Int) {
        var reordered = projects
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, project) in reordered.enumerated() where project.sortOrder != index {
            project.sortOrder = index
            project.touch()
        }
        try? reordered.first?.modelContext?.save()
    }
}
