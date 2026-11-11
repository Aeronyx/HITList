import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HITListCore

/// Dragging a switch onto a Switchboard, or off one onto the loose switches (brief 96, George: "Add force-touch
/// drag-and-drop for switches onto Switchboards"). iPhone and iPad: press and hold a tile, then move; holding still
/// opens its menu instead (the system joins the two: the lifted tile is the menu's preview until the finger moves). The
/// Mac: a plain drag. A tap still flips, and a scroll never drags. What travels is the switch's id, in a type of the
/// app's own that no other app is offered; a drop moves the switch with the board's own rule (`Flipboard.move`), as the
/// card's Switchboard chip does.
enum SwitchDrag {
    /// The app's own type for a dragged switch: a dynamic type (nothing to declare in the app's Info.plist), offered to
    /// this process only.
    static let type: UTType = UTType(tag: "hitlist-switch", tagClass: .filenameExtension, conformingTo: .data) ?? .data

    private static let prefix = "hitlist-switch:"

    /// What a dragged switch carries: its id, and nothing that names it.
    static func payload(for id: UUID) -> Data { Data((prefix + id.uuidString).utf8) }

    static func switchID(from data: Data) -> UUID? {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(prefix.count)))
    }

    static func provider(for task: TaskItem) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = payload(for: task.id)
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        provider.suggestedName = task.title
        return provider
    }
}

/// Where a dragged switch can land, and the move itself.
enum SwitchDrop {
    enum Target: Hashable {
        /// The loose switches at the top of the board: a drop there takes a switch off its Switchboard.
        case loose
        case board(UUID)

        /// Whether a drop here moves a switch now on `board` (nil: loose). Its own place takes nothing.
        func takes(switchOn board: UUID?) -> Bool {
            switch self {
            case .loose: board != nil
            case .board(let id): board != id
            }
        }
    }

    /// One of VoiceOver's "Move to…" actions on a switch.
    struct Move: Identifiable, Equatable {
        let title: String
        let target: Target
        var id: Target { target }
    }

    /// VoiceOver's moves for a switch: to each other board, in the board's order, then off the one it is on.
    static func moves(for task: TaskItem, boards: [Switchboard]) -> [Move] {
        let on = boards.first { $0.id == task.switchboard?.id }
        var moves = boards.filter { $0.id != on?.id }.map { Move(title: "Move to \($0.name)", target: .board($0.id)) }
        if let on { moves.append(Move(title: "Move off \(on.name)", target: .loose)) }
        return moves
    }

    /// Moves the switch `id` onto `target`, as choosing that Switchboard in its card does; false when nothing moved
    /// (it is there already, or the switch or the board is gone).
    @MainActor
    @discardableResult
    static func move(_ id: UUID, onto target: Target, in context: ModelContext) -> Bool {
        guard let task = try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first,
              Flipboard.isMember(task), target.takes(switchOn: task.switchboard?.id) else { return false }
        var board: Switchboard?
        if case .board(let boardID) = target {
            guard let found = try? context.fetch(FetchDescriptor<Switchboard>(predicate: #Predicate { $0.id == boardID })).first
            else { return false }
            board = found
        }
        Flipboard.move(task, to: board, in: context)
        return true
    }
}

/// A board section (or the loose switches) as a drop target: it lights while a switch it would take is over it, and a
/// drop moves the switch in.
struct SwitchDropDelegate: DropDelegate {
    let target: SwitchDrop.Target
    /// The board of the switch being dragged, when the drag began on a tile here (nil: loose; unknown: assume it moves).
    let draggedFrom: UUID??
    @Binding var lit: SwitchDrop.Target?
    var perform: (UUID) -> Void

    private var takes: Bool { draggedFrom.map { target.takes(switchOn: $0) } ?? true }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [SwitchDrag.type]) }

    func dropEntered(info: DropInfo) {
        guard takes else { return }
        lit = target
        SwitchDetent.tick()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: takes ? .move : .cancel)
    }

    func dropExited(info: DropInfo) {
        if lit == target { lit = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        if lit == target { lit = nil }
        guard takes, let provider = info.itemProviders(for: [SwitchDrag.type]).first else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: SwitchDrag.type.identifier) { data, _ in
            guard let data, let id = SwitchDrag.switchID(from: data) else { return }
            Task { @MainActor in perform(id) }
        }
        return true
    }
}

/// A drop target taking a switch: the section under a soft accent wash and outline, a little outside its contents.
struct SwitchDropHighlight: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        shape.fill(Theme.accent.opacity(0.08))
            .overlay(shape.strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5))
            .padding(-10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
