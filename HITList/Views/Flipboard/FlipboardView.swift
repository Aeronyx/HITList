import SwiftUI
import SwiftData
import Combine
import HITListCore

/// The Task Flipboard: a wall of rocker switches, one per recurring chore, and a calm status check rather than a
/// second to-do list (brief 72). Loose switches come first, exactly as before Switchboards: red ones (due or overdue)
/// at the top, most overdue first; green ones follow, soonest due first. Then each Switchboard as a section in its
/// order: its name in the list section header style with a "+" 6 pt after it, its cadence line ("Daily · resets
/// 04:00") and how many are done ("3 of 5"), then its switches, the timed ones by their time, then the rest. Every
/// tile on the screen is one size.
struct FlipboardView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    /// Optional: a board drawn outside the app shell (previews) deletes without asking.
    @Environment(PopoutController.self) private var popouts: PopoutController?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The iPhone Duo's inner display: an even number of columns (brief 50).
    @Environment(\.appShell) private var shell
    #endif
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && $0.recurrence != nil }) private var recurring: [TaskItem]
    @Query private var allBoards: [Switchboard]
    @State private var now = FlipboardView.clockNow()
    @State private var width: CGFloat = 0
    /// The switch card open in the grid (Mac and iPad, brief 69): adding, or editing a switch.
    @State private var inlineCard: SwitchCardRequest?
    /// The Switchboard card open in place (Mac and iPad, brief 72): a new board at the foot, or a board's in place of
    /// its header. Never at the same time as `inlineCard`.
    @State private var boardCard: SwitchboardCardRequest?
    /// The card over the board (iPhone): a switch's or a Switchboard's.
    @State private var floatingCard: FloatingCardRequest?
    /// The inline card's "something to lose", read on a click away (a box: typing redraws nothing here).
    @State private var cardContent = SwitchCardContent()
    @State private var confirmingDiscard = false
    /// When the inline card offered "Discard": one Esc can reach both × and the exit command, and must not
    /// ask and discard in the same press.
    @State private var discardOfferedAt = Date.distantPast
    /// Where the inline card is, in the board's scroll view: a click inside it is never a click away.
    @State private var cardFrame = CGRect.null
    /// The switch just added or edited, which settles into its place in the grid (`SwitchLanding`).
    @State private var landing: SwitchLanding.Mark?
    private static let boardSpace = "flipboard"
    /// Where a dragged switch would land, lit while it is over it (brief 96).
    @State private var dropTarget: SwitchDrop.Target?
    /// The switch a drag began with on this board, and the board it was on (nil: loose).
    @State private var dragging: DraggedSwitch?
    /// The switch just deleted, while its "Deleted · Undo" toast shows.
    @State private var deleted: Flipboard.DeletedSwitch?
    @State private var deleteGeneration = 0
    @AppStorage(FlipSound.key, store: AppGroup.defaults) private var soundOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private static let spacing: CGFloat = 14
    /// Between the loose switches and the first board, and between boards.
    private static let sectionSpacing: CGFloat = 28

    /// The board's clock: now, or in a Debug build the moment `-flipboardNow` names (screenshots either side of a
    /// reset).
    static func clockNow() -> Date {
        #if DEBUG
        return FlipboardDebug.now ?? Date()
        #else
        return Date()
        #endif
    }

    private var switches: [TaskItem] { recurring.filter(Flipboard.isMember) }
    private var boards: [Switchboard] { Flipboard.ordered(allBoards) }

    /// The loose switches (on no board, or on one this device hasn't received yet), in the board's red-first order.
    private func looseSwitches(_ all: [TaskItem], boards: [Switchboard]) -> [TaskItem] {
        let ids = Set(boards.map(\.id))
        return Flipboard.sorted(all.filter { $0.switchboard.map { !ids.contains($0.id) } ?? true })
    }

    private func switches(on board: Switchboard, _ all: [TaskItem]) -> [TaskItem] {
        Flipboard.sorted(onBoard: all.filter { $0.switchboard?.id == board.id }, board)
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var onDuoInnerDisplay: Bool {
        #if os(iOS)
        shell == .duo
        #else
        false
        #endif
    }

    private var columnCount: Int {
        FlipboardLayout.columnCount(width: width, compact: isCompact, spacing: Self.spacing, even: onDuoInnerDisplay)
    }

    private var cellWidth: CGFloat {
        let columns = columnCount
        return (width - CGFloat(columns - 1) * Self.spacing) / CGFloat(max(1, columns))
    }

    /// The columns the inline card takes (`FlipboardLayout.cardSpan`).
    private var cardSpan: Int {
        FlipboardLayout.cardSpan(columns: columnCount, cellWidth: cellWidth, spacing: Self.spacing)
    }

    /// The Switchboard card's width in place: as many columns as give it `boardCardMinWidth`.
    private var boardCardWidth: CGFloat {
        let span = FlipboardLayout.cardSpan(columns: columnCount, cellWidth: cellWidth, spacing: Self.spacing,
                                            minWidth: FlipboardLayout.boardCardMinWidth)
        return CGFloat(span) * cellWidth + CGFloat(span - 1) * Self.spacing
    }

    /// iPhone: the card floats over the board; the Mac and iPad open it in the grid.
    private var cardFloats: Bool { isCompact }

    /// A card is open in place (Mac and iPad).
    private var hasInlineCard: Bool { inlineCard != nil || boardCard != nil }

    var body: some View {
        let switches = switches
        let boards = boards
        let loose = looseSwitches(switches, boards: boards)
        let onBoards = boards.map { self.switches(on: $0, switches) }
        // The tip sits on the first switch on the screen.
        let tipID = loose.first?.id ?? onBoards.lazy.compactMap(\.first?.id).first
        let tip = tip(for: switches)
        let offersBoard = Self.offersNewSwitchboard(switches: switches.count, boards: boards.count)
        // Empty, the board is its Add a Switch tile alone, in a first switch's place and size (brief 96: no
        // paragraphs, no New Switchboard until there is a switch to put on one).
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                    looseGrid(loose, tip: tip, tipID: tipID)
                    ForEach(Array(zip(boards, onBoards)), id: \.0.id) { board, onBoard in
                        section(board, switches: onBoard, tip: tip, tipID: tipID)
                    }
                    if boardCard == .new {
                        inlineBoardCard(.new)
                    } else if offersBoard {
                        // The way to a first Switchboard that everyone can see: on iPhone the menu's New
                        // Switchboard… sits behind a long press on the sound button.
                        NewSwitchboardRow { openBoardCard(.new) }
                            .allowsHitTesting(!hasInlineCard)
                    }
                }
                .padding(16)
                .animation(.snappy(duration: 0.35), value: switches.map(\.id))
                .animation(.snappy(duration: 0.35), value: boards.map(\.id))
            }
            // While a card is open in place, a click anywhere off it is a click away: the tiles stop taking
            // clicks (no switch flips by accident) and the click reaches the board. A click in the card's
            // name reaches it too (the text view is AppKit's or UIKit's and claims no SwiftUI gesture), so a
            // click inside the card's frame only ever means keep editing.
            .gesture(SpatialTapGesture(coordinateSpace: .named(Self.boardSpace)).onEnded { tap in
                if cardFrame.contains(tap.location) {
                    if confirmingDiscard { keepEditing() }
                } else {
                    clickAway()
                }
            }, including: hasInlineCard ? .all : .subviews)
            .coordinateSpace(.named(Self.boardSpace))
            // iPhone: the new switch may sort above the fold; bring it into view as it settles.
            .onChange(of: landing) { _, mark in
                guard cardFloats, let mark else { return }
                withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(mark.id, anchor: .center) }
            }
            .onChange(of: inlineCard?.id ?? boardCard?.id) { _, id in
                guard let id else { return }
                Task { @MainActor in
                    withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { width = $0 }
        .background(Theme.background)
        .navigationTitle("Flipboard")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        // Adding lives on the board (`AddSwitchTile`, a board's "+", `NewSwitchboardRow` at its foot); the toolbar's
        // control is the flip sound. Add Switch… and New Switchboard… are second routes: in the "…" on the Mac and
        // iPad, a long press on the sound button on iPhone.
        .screenChrome {
            ScreenOptionButton { soundOn.toggle() } label: {
                Label(soundOn ? "Flip sound on" : "Flip sound off", systemImage: soundOn ? "speaker.wave.2" : "speaker.slash")
                    .labelStyle(.iconOnly)
            }
            .help(soundOn ? "Flip sound on" : "Flip sound off")
            .accessibilityIdentifier("flipSound")
        } menu: {
            Button { openCard(.add) } label: { Label("Add Switch…", systemImage: "plus") }
            if offersBoard {
                Button { openBoardCard(.new) } label: { Label("New Switchboard…", systemImage: "square.grid.2x2") }
            }
        }
        // A switch or a board deleted elsewhere (another device, Siri) while its card is open: the card goes with it.
        .onChange(of: switches.map(\.id)) { _, ids in
            if let task = inlineCard?.task, !ids.contains(task.id) { closeCard() }
            if let task = floatingCard?.task, !ids.contains(task.id) { withoutAnimation { floatingCard = nil } }
        }
        .onChange(of: boards.map(\.id)) { _, ids in
            if let board = boardCard?.board ?? inlineCard?.board, !ids.contains(board.id) { closeCard() }
            if let board = floatingCard?.board, !ids.contains(board.id) { withoutAnimation { floatingCard = nil } }
        }
        .onReceive(clock) { _ in now = Self.clockNow() }
        .onReceive(CalendarChange.moments) { _ in now = Self.clockNow() } // brief 82: a board resets at its hour where you are
        .onAppear {
            now = Self.clockNow()
            FlipSound.prepare()
            #if DEBUG
            FlipboardDebug.seedStatesIfRequested(in: context)
            #endif
        }
        .completionToast(deleted.map { "Deleted ‘\($0.title)’" }, onUndo: undoDelete,
                         onDismiss: { withAnimation(HITMotion.exit) { deleted = nil } })
        #if os(iOS)
        .fullScreenCover(item: $floatingCard) { request in
            FloatingSwitchCard(request: request) { saved in
                withoutAnimation { floatingCard = nil }
                // The board is in view again: the switch settles into its place.
                if let saved { land(saved) }
            }
            .presentationBackground(.clear)
        }
        #endif
    }

    // MARK: Sections

    /// The loose switches, exactly as the board was before Switchboards, with the + tile (or the card) last. A switch
    /// dragged here leaves its Switchboard (brief 96).
    private func looseGrid(_ loose: [TaskItem], tip: HITTip?, tipID: UUID?) -> some View {
        FlipboardGrid(columns: columnCount, spacing: Self.spacing) {
            ForEach(loose) { task in
                cell(for: task, tip: task.id == tipID ? tip : nil)
            }
            // The last cell adds a switch: a dashed outline of one, with a big +; on the Mac and iPad the card
            // opens in its place.
            if inlineCard == .add {
                inlineCardView(.add)
            } else {
                AddSwitchTile { openCard(.add) }
                    .allowsHitTesting(!hasInlineCard)
            }
        }
        .switchDropTarget(.loose, dragging: dragging, lit: $dropTarget) { drop($0, onto: .loose) }
    }

    /// A Switchboard: its header (or its card, in place), then its switches. An empty board shows the + tile, so it
    /// is never just a header.
    private func section(_ board: Switchboard, switches: [TaskItem], tip: HITTip?, tipID: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let request = boardCard, request.board?.id == board.id {
                inlineBoardCard(request)
            } else {
                SwitchboardHeader(board: board, line: SwitchboardDraft.cadenceLine(board),
                                  done: switches.isEmpty ? nil : SwitchboardDraft.doneCount(switches, now: now),
                                  isFirst: board.id == boards.first?.id, isLast: board.id == boards.last?.id,
                                  onAdd: { openCard(.addTo(board)) },
                                  onEdit: { openBoardCard(.edit(board)) },
                                  onMove: { offset in withAnimation(.snappy) { Flipboard.moveSwitchboard(board, by: offset, in: context) } },
                                  onDelete: { openBoardCard(.delete(board)) })
                    .allowsHitTesting(!hasInlineCard)
            }
            if !switches.isEmpty || inlineCard == .addTo(board) {
                FlipboardGrid(columns: columnCount, spacing: Self.spacing) {
                    ForEach(switches) { task in cell(for: task, tip: task.id == tipID ? tip : nil) }
                    if inlineCard == .addTo(board) { inlineCardView(.addTo(board)) }
                }
            } else {
                FlipboardGrid(columns: columnCount, spacing: Self.spacing) {
                    AddSwitchTile { openCard(.addTo(board)) }
                        .allowsHitTesting(!hasInlineCard)
                }
            }
        }
        // Brief 96: a switch dragged over the board lights it; let go, and it is on the board.
        .switchDropTarget(.board(board.id), dragging: dragging, lit: $dropTarget) { drop($0, onto: .board(board.id)) }
        .id("board-\(board.id.uuidString)")
    }

    /// A switch's tile, or the card editing it.
    @ViewBuilder
    private func cell(for task: TaskItem, tip: HITTip?) -> some View {
        if inlineCard == .edit(task) {
            inlineCardView(.edit(task))
        } else {
            FlipSwitchTile(task: task, now: now, onEdit: { openCard(.edit(task)) },
                           onOpen: { open(task) }, onDelete: { delete(task) },
                           moves: SwitchDrop.moves(for: task, boards: boards),
                           onMove: { drop(task.id, onto: $0) },
                           onDragStart: { dragging = DraggedSwitch(id: task.id, board: boardID(of: task)) })
                .hitTip(tip)
                .modifier(SwitchLanding(mark: landing?.id == task.id ? landing : nil))
                .allowsHitTesting(!hasInlineCard)
                .id(task.id)
        }
    }

    /// The tip on the first switch: for someone whose red switches used to wait in Today, that they stay on the
    /// Flipboard now (brief 72); for everyone else, the Flipboard's own.
    private func tip(for switches: [TaskItem]) -> HITTip? {
        FlipboardTips.kind(for: switches.map(\.createdAt)).map { HITTip($0) }
    }

    // MARK: The switch card (brief 69)

    /// The card in the grid, as wide as `cardSpan` columns.
    private func inlineCardView(_ request: SwitchCardRequest) -> some View {
        SwitchCard(editing: request.task, style: .inline, board: request.board, isConfirmingDiscard: confirmingDiscard,
                   onClose: requestClose,
                   onSaved: { saved in
                       if !request.isAdding { closeCard() }
                       land(saved)
                   },
                   onDraftChange: { cardContent.hasContent = $0 },
                   onDiscard: closeCard,
                   onKeepEditing: keepEditing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.boardSpace)) } action: { cardFrame = $0 }
            .id(request.id)
            .flipboardGridSpan(cardSpan)
            .flipboardGridKeepsOwnHeight()
            .transition(cardTransition)
    }

    private var cardTransition: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity).animation(HITMotion.enter(reduceMotion: reduceMotion)),
                    removal: .opacity.animation(HITMotion.exit(reduceMotion: reduceMotion)))
    }

    /// The + tile, the toolbar's Add Switch…, a board's "+" or a tile's menu: the card, in the grid or over the board.
    private func openCard(_ request: SwitchCardRequest) {
        if cardFloats {
            withoutAnimation { floatingCard = .switchCard(request) }
            return
        }
        guard inlineCard != request else { return }
        clickAway {
            withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) {
                confirmingDiscard = false
                cardContent.hasContent = false
                inlineCard = request
            }
        }
    }

    // MARK: The Switchboard card (brief 72)

    /// The Switchboard card in place: at the foot for a new board, in place of the board's header otherwise.
    private func inlineBoardCard(_ request: SwitchboardCardRequest) -> some View {
        let asksToDelete: Bool = if case .delete = request { true } else { false }
        return SwitchboardCard(editing: request.board, style: .inline, asksToDelete: asksToDelete,
                               isConfirmingDiscard: confirmingDiscard, onClose: requestClose,
                               onSaved: { _ in closeCard() }, onDeleted: closeCard,
                               onDraftChange: { cardContent.hasContent = $0 },
                               onDiscard: closeCard, onKeepEditing: keepEditing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.boardSpace)) } action: { cardFrame = $0 }
            .frame(width: max(FlipboardLayout.cardMinWidth, boardCardWidth))
            .id(request.id)
            .transition(cardTransition)
    }

    /// New Switchboard…, a board's name, or Edit… / Delete… in its menu.
    private func openBoardCard(_ request: SwitchboardCardRequest) {
        if cardFloats {
            withoutAnimation { floatingCard = .switchboard(request) }
            return
        }
        guard boardCard != request else { return }
        clickAway {
            withAnimation(HITMotion.enter(reduceMotion: reduceMotion)) {
                confirmingDiscard = false
                cardContent.hasContent = false
                boardCard = request
            }
        }
    }

    // MARK: Closing either card

    /// A click on the board off the card. An empty card closes and `then` runs; with something to lose,
    /// "Discard" shows and nothing else happens; with "Discard" showing, back to typing.
    private func clickAway(then action: (() -> Void)? = nil) {
        guard hasInlineCard else { action?(); return }
        switch BoardInlineAdd.clickAway(hasContent: cardContent.hasContent, confirmingDiscard: confirmingDiscard) {
        case .close:
            closeCard()
            action?()
        case .askDiscard:
            discardOfferedAt = Date()
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .keepEditing:
            keepEditing()
        }
    }

    private func keepEditing() {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = false }
    }

    /// × or Escape on the card: an empty card closes; with something to lose "Discard" shows first, and a
    /// second × or Escape discards.
    private func requestClose() {
        switch BoardInlineAdd.close(hasContent: cardContent.hasContent, confirmingDiscard: confirmingDiscard) {
        case .close:
            closeCard()
        case .askDiscard:
            discardOfferedAt = Date()
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { confirmingDiscard = true }
        case .discard:
            guard Date().timeIntervalSince(discardOfferedAt) > 0.3 else { return }
            closeCard()
        }
    }

    private func closeCard() {
        cardFrame = .null
        withAnimation(HITMotion.exit(reduceMotion: reduceMotion)) {
            inlineCard = nil
            boardCard = nil
            confirmingDiscard = false
            cardContent.hasContent = false
        }
    }

    /// A switch was added or saved: its tile settles into the grid (a new one lands as the board's own
    /// animation inserts it).
    private func land(_ task: TaskItem) {
        let mark = SwitchLanding.Mark(id: task.id, generation: (landing?.generation ?? 0) + 1)
        landing = mark
        // Landed: the mark goes, so the tile doesn't settle again when the board comes back on screen.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if landing == mark { landing = nil }
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// Whether the board offers a new Switchboard, at its foot and in its menu (brief 96, George: "New Switchboard
    /// shouldn't be a starting option"): once there is a switch to put on one, or a board already. The empty board is
    /// its Add a Switch tile alone; the switch card's Switchboard picker offers a new one whenever it is open.
    static func offersNewSwitchboard(switches: Int, boards: Int) -> Bool { switches > 0 || boards > 0 }

    // MARK: Dragging a switch (brief 96)

    /// The board a switch shows on: its Switchboard, or nil when it is loose (or on one this device hasn't received).
    private func boardID(of task: TaskItem) -> UUID? {
        guard let id = task.switchboard?.id, boards.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// A drop (or VoiceOver's Move to…): the switch moves as choosing that Switchboard in its card does, and settles
    /// into its new place.
    private func drop(_ id: UUID, onto target: SwitchDrop.Target) {
        dragging = nil
        dropTarget = nil
        let moved = withAnimation(.snappy(duration: 0.35)) { SwitchDrop.move(id, onto: target, in: context) }
        guard moved, let task = switches.first(where: { $0.id == id }) else { return }
        #if os(iOS)
        TapHaptic.play()
        #endif
        land(task)
        let place: String = switch target {
        case .loose: "the Flipboard"
        case .board(let boardID): boards.first { $0.id == boardID }?.name ?? "its Switchboard"
        }
        AccessibilityNotification.Announcement("Moved \(task.title) to \(place)").post()
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    /// Opens the task popout (`selectedTask` is `PopoutController.selection`).
    private func open(_ task: TaskItem) { selectedTask = task }

    /// "Delete" from a switch's menu (brief 59): gone from the store at once, sub-tasks too, so the delete
    /// syncs now and Today, Spotlight and the other devices drop it; the toast offers Undo for its lifetime.
    private func delete(_ task: TaskItem) {
        let perform = {
            if selectedTask?.id == task.id { selectedTask = nil }
            let gone = withAnimation(.snappy) { Flipboard.delete(task, in: context) }
            deleteGeneration += 1
            let generation = deleteGeneration
            withAnimation(HITMotion.enter) { deleted = gone }
            AccessibilityNotification.Announcement("Deleted \(gone.title)").post()
            Task {
                await NotificationScheduler.reschedule(context: context)
                try? await Task.sleep(for: CompletionToastState.lifetime)
                if deleteGeneration == generation { withAnimation(HITMotion.exit) { deleted = nil } }
            }
        }
        if let popouts { popouts.requestDelete(task, perform: perform) } else { perform() }
    }

    private func undoDelete() {
        guard let gone = deleted else { return }
        withAnimation(HITMotion.exit) { deleted = nil }
        withAnimation(.snappy) { _ = Flipboard.restore(gone, in: context) }
        Task { await NotificationScheduler.reschedule(context: context) }
    }
}

/// A Switchboard's header (brief 72): its name in the list section header style, a "+" 6 pt after it that adds a switch
/// to the board (the pattern of the sidebar's "Groups +"), then its cadence line and how many are done ("3 of 5"). The
/// name opens the board's card; a long press (iPhone) or right-click (Mac) offers Edit…, Move Up, Move Down and Delete….
/// No overdue colours, no counts of what is late: the Flipboard is a calm status check.
struct SwitchboardHeader: View {
    let board: Switchboard
    let line: String
    /// "3 of 5"; nil for a board with no switches yet.
    let done: String?
    let isFirst: Bool
    let isLast: Bool
    var onAdd: () -> Void
    var onEdit: () -> Void
    var onMove: (Int) -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Text(board.name)
                        .font(HITType.listSectionHeader)
                        .foregroundStyle(HITColor.text)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Edit \(board.name)")
                .accessibilityHint("Opens the Switchboard")
                .accessibilityIdentifier("switchboardHeader")
                Button(action: onAdd) { Image(systemName: "plus") }
                    .buttonStyle(HITIconButtonStyle(font: .system(size: 13, weight: .semibold), alignment: .leading))
                    .help("Add a switch to \(board.name)")
                    .accessibilityLabel("Add a switch to \(board.name)")
                    .accessibilityIdentifier("switchboardAdd")
                Spacer(minLength: 0)
            }
            Text([line, done].compactMap { $0 }.joined(separator: " · "))
                .font(HITType.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .contentTransition(.numericText())
                .accessibilityIdentifier("switchboardLine")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onEdit) { Label("Edit…", systemImage: "slider.horizontal.3") }
            Button(action: onAdd) { Label("Add Switch…", systemImage: "plus") }
            Divider()
            Button { onMove(-1) } label: { Label("Move Up", systemImage: "arrow.up") }
                .disabled(isFirst)
            Button { onMove(1) } label: { Label("Move Down", systemImage: "arrow.down") }
                .disabled(isLast)
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete…", systemImage: "trash") }
        }
    }
}

/// "+ New Switchboard" at the foot of the board, drawn like a list's "Add task" row: a quiet line, never a tile.
struct NewSwitchboardRow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HITSpacing.s) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("New Switchboard").foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
            }
            .font(HITType.body)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("A group of switches that resets daily or weekly, like Before Bed")
        .accessibilityIdentifier("newSwitchboardRow")
    }
}

/// Which tip the Flipboard's first switch carries (brief 72). Someone with a switch from before Switchboards had red
/// switches in Today (round 13's rule): they get the tip that switches stay on the Flipboard now, and that Overdue
/// becomes task brings one back. Everyone else gets the Flipboard's own tip. Pure, so tests pin it.
enum FlipboardTips {
    /// The day 0.9.0 (21) arrived: switches stopped being tasks.
    static let switchesStayFrom: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 11, day: 11))!
    }()

    static func kind(for createdDates: [Date]) -> HITTipKind? {
        guard !createdDates.isEmpty else { return nil }
        return createdDates.contains { $0 < switchesStayFrom } ? .switchesStay : .flipboard
    }
}

extension SidebarItem {
    /// The board's sidebar item. A constant rather than a new `case` so `TaskListView`'s exhaustive
    /// switches stay untouched; ContentView routes it to `FlipboardView` before `TaskListView` sees it.
    static let flipboard = SidebarItem.filter(SeedIdentity.uuid(for: "SidebarItem/flipboard"))
}

enum FlipboardLayout {
    /// The tile a column should not shrink below.
    static let minimumTileWidth: CGFloat = 150

    /// 2 columns on iPhone; 3 to 5 on the Mac and iPad, as many as fit.
    /// `even` (the iPhone Duo's inner display, brief 50; Apple: "In a grid-style layout, prefer an even
    /// number of columns so content divides cleanly"): 2 or 4, as many as fit.
    static func columnCount(width: CGFloat, compact: Bool, spacing: CGFloat, even: Bool = false) -> Int {
        guard !compact else { return 2 }
        let fit = Int((width + spacing) / (minimumTileWidth + spacing))
        if even { return min(4, max(2, fit)) / 2 * 2 }
        return min(5, max(3, fit))
    }
}

/// The grid's last tile, and the whole of an empty board (brief 96): the outline of a switch drawn with a dashed
/// hairline (the plate, a smaller dashed rocker in it) and a large accent "+", in the tiles' 18 pt shape, the size of a
/// real switch whether switches stand beside it or not. Tapping it opens the switch card in its place (brief 69).
struct AddSwitchTile: View {
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let plate = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: action) {
            // A switch's face, unseen, gives the tile its size: alone on an empty board it is a first switch's size
            // and place, never a smaller box (beside switches the grid gives every tile the tallest's height anyway).
            FlipSwitchFace.standIn
                .hidden()
                .accessibilityHidden(true)
                .overlay {
                    ZStack {
                        plate.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                            .foregroundStyle(hovered ? Theme.accent.opacity(0.9) : Theme.separator)
                        VStack(spacing: 10) {
                            // The rocker: a small dashed capsule, standing in for the switch itself.
                            Capsule(style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                                .frame(width: 34, height: 56)
                                .foregroundStyle(hovered ? Theme.accent.opacity(0.7) : Theme.separator)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                }
                            Text("Add switch")
                                .font(HITType.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                // As tall as the switches beside it (`FlipboardLayout.frames` gives every tile one height).
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(plate)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: hovered)
        .accessibilityLabel("Add switch")
        .accessibilityIdentifier("addSwitchTile")
    }
}

/// The switch a drag began with on the board (brief 96), so a place lights only when it would take it.
struct DraggedSwitch: Equatable {
    let id: UUID
    /// Its board then (nil: loose).
    let board: UUID?
}

extension View {
    /// A board section (or the loose switches) as a place to drop a switch: lit while a switch it would take is over
    /// it, the drop handed to `perform` as the switch's id.
    func switchDropTarget(_ target: SwitchDrop.Target, dragging: DraggedSwitch?, lit: Binding<SwitchDrop.Target?>,
                          perform: @escaping (UUID) -> Void) -> some View {
        let isLit = lit.wrappedValue == target
        return background {
            if isLit { SwitchDropHighlight().transition(.opacity) }
        }
        .animation(HITMotion.quick, value: isLit)
        .onDrop(of: [SwitchDrag.type], delegate: SwitchDropDelegate(target: target, draggedFrom: dragging.map(\.board),
                                                                     lit: lit, perform: perform))
    }
}
