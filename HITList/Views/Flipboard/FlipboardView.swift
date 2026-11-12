import SwiftUI
import SwiftData
import Combine
import HITListCore

/// The Task Flipboard: a wall of rocker switches, one per recurring chore, and a calm status check rather than a
/// second to-do list (brief 72). Loose switches come first, in a grid, exactly as before Switchboards: red ones (due or
/// overdue) at the top, most overdue first; green ones follow, soonest due first. With a Switchboard on the board they
/// sit under an "Ungrouped" header with their lights, which folds them away (brief 126). Then each Switchboard in its
/// order, on a panel of its own (`SwitchboardPanel`): its name, its lights (one a switch, in the row's order) and its
/// cadence line ("Daily · resets 04:00"), then its switches in one row that scrolls sideways, the timed ones by their
/// time, then the rest, and the Add switch outline last. Every tile on the screen is one size.
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
    /// The board's whole width; `width` is what is left inside its margins.
    @State private var boardWidth: CGFloat = 0
    /// The board's side margin: the large title's (the system's, `followsSystemListMargin`), never under 16. 16 on an
    /// iPhone 16, the iPad and the Mac, as before; 20 on the Duo's outer display, where a fixed 16 set the tiles and
    /// the Switchboards' names 4 pt left of "Flipboard" (brief 115).
    @State private var margin: CGFloat = FlipboardView.minimumMargin
    static let minimumMargin: CGFloat = 16
    private var width: CGFloat { max(0, boardWidth - 2 * margin) }
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
    /// The loose switches folded away under their header (brief 126), remembered on this device.
    @AppStorage(FlipboardView.ungroupedFoldedKey, store: AppGroup.defaults) private var ungroupedFolded = false
    static let ungroupedFoldedKey = "flipboard.ungroupedFolded"
    /// Where each board's row was last asked to scroll (a light tapped, a switch added or opened), by board.
    @State private var rowScroll: [UUID: SwitchRowRequest] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    static let spacing: CGFloat = 14
    /// Between the loose switches and the first board, and between boards.
    private static let sectionSpacing: CGFloat = 20

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

    /// A Switchboard row's tiles: whole ones and about a fifth of the next (`FlipboardLayout.rowTileWidth`).
    private var rowTileWidth: CGFloat {
        FlipboardLayout.rowTileWidth(width: width, inset: BoardPanel.inset, spacing: Self.spacing, gridTile: cellWidth)
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
                    looseSection(loose, hasBoards: !boards.isEmpty, tip: tip, tipID: tipID, proxy: proxy)
                    ForEach(Array(zip(boards, onBoards)), id: \.0.id) { board, onBoard in
                        panel(board, switches: onBoard, tip: tip, tipID: tipID)
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
                .padding(.vertical, 16)
                .padding(.horizontal, margin)
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
            // iPhone: the new switch may sort out of view; bring it (or its board) into view as it lands, by the
            // least scroll that shows it whole (a centred scroll near the top pulled the board under the large
            // title and let it spring back).
            .onChange(of: landing) { _, mark in
                guard cardFloats, let mark, !mark.waiting else { return }
                let target: AnyHashable = switches.first { $0.id == mark.id }.flatMap { boardID(of: $0) }
                    .map { AnyHashable(Self.panelID($0)) } ?? AnyHashable(mark.id)
                withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(target, anchor: nil) }
            }
            .onChange(of: inlineCard?.id ?? boardCard?.id) { _, id in
                guard let id else { return }
                Task { @MainActor in
                    withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .background {
            BoardMarginReader { measured in
                let next = max(Self.minimumMargin, measured)
                if next != margin { margin = next }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boardWidth = $0 }
        .background(Theme.background)
        .followsSystemListMargin()
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
            Button {
                // Brief 126: adding an ungrouped switch from the menu unfolds them.
                setFolded(false)
                openCard(.add)
            } label: { Label("Add Switch…", systemImage: "plus") }
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
            FlipboardDebug.seedRowsIfRequested(in: context)
            #endif
        }
        .completionToast(deleted.map { "Deleted ‘\($0.title)’" }, onUndo: undoDelete,
                         onDismiss: { withAnimation(HITMotion.exit) { deleted = nil } })
        #if os(iOS)
        .fullScreenCover(item: $floatingCard) { request in
            FloatingSwitchCard(request: request, onFinished: { saved in
                withoutAnimation { floatingCard = nil }
                // The board is in view again: the switch settles into its place.
                if let saved { land(saved) }
            }, onAdded: { added in
                // Brief 126: on the board already, held unseen until the card has gone, so it appears once.
                land(added, waiting: true)
            })
            .presentationBackground(.clear)
        }
        #endif
    }

    // MARK: Sections

    /// The loose switches, exactly as the board was before Switchboards, with the + tile (or the card) last. With a
    /// Switchboard on the board an "Ungrouped" header with their lights sits over them and folds them away (brief
    /// 126). A switch dragged here, or onto the folded header, leaves its Switchboard (brief 96).
    private func looseSection(_ loose: [TaskItem], hasBoards: Bool, tip: HITTip?, tipID: UUID?,
                              proxy: ScrollViewProxy) -> some View {
        let folded = hasBoards && ungroupedFolded
        return VStack(alignment: .leading, spacing: 10) {
            if hasBoards {
                UngroupedHeader(lights: lights(loose), folded: folded, onToggle: { setFolded(!ungroupedFolded) },
                                onSelectLight: { index in
                                    guard loose.indices.contains(index) else { return }
                                    setFolded(false)
                                    let id = loose[index].id
                                    Task { @MainActor in
                                        withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: nil) }
                                    }
                                })
                    .allowsHitTesting(!hasInlineCard)
            }
            if !folded {
                looseGrid(loose, tip: tip, tipID: tipID)
                    .transition(.opacity)
            }
        }
        .switchDropTarget(.loose, dragging: dragging, lit: $dropTarget) { drop($0, onto: .loose) }
    }

    private func looseGrid(_ loose: [TaskItem], tip: HITTip?, tipID: UUID?) -> some View {
        FlipboardGrid(columns: columnCount, spacing: Self.spacing) {
            ForEach(loose) { task in
                cell(for: task, tip: task.id == tipID ? tip : nil, inGrid: true)
            }
            // The last cell adds a switch: a dashed outline of one, with a big +; on the Mac and iPad the card
            // opens in its place (adding, or duplicating a loose switch).
            if let request = inlineCard, cardPlace(request) == .some(nil) {
                inlineCardView(request)
                    .flipboardGridSpan(cardSpan)
                    .flipboardGridKeepsOwnHeight()
            } else {
                AddSwitchTile { openCard(.add) }
                    .allowsHitTesting(!hasInlineCard)
            }
        }
    }

    /// Folds the loose switches away or back.
    private func setFolded(_ folded: Bool) {
        guard folded != ungroupedFolded else { return }
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { ungroupedFolded = folded }
    }

    /// Each switch's light, in the order the switches stand.
    private func lights(_ switches: [TaskItem]) -> [BoardLight] {
        switches.map { BoardLight(id: $0.id, title: $0.title, isOn: Flipboard.side(of: $0, now: now) == .green) }
    }

    static func panelID(_ board: UUID) -> String { "board-\(board.uuidString)" }

    /// A Switchboard on its panel (brief 126): its header (or its card, in place), its row of switches with the Add
    /// switch outline at the end, and on the Mac and iPad the switch card under the row when it opens for this board.
    private func panel(_ board: Switchboard, switches: [TaskItem], tip: HITTip?, tipID: UUID?) -> some View {
        let lights = lights(switches)
        let request = inlineRequest(on: board)
        let editing = request?.task?.id
        return SwitchboardPanel {
            if let request = boardCard, request.board?.id == board.id {
                inlineBoardCard(request)
            } else {
                SwitchboardHeader(board: board, line: SwitchboardDraft.cadenceLine(board), lights: lights,
                                  isFirst: board.id == boards.first?.id, isLast: board.id == boards.last?.id,
                                  onAdd: { openCard(.addTo(board)) },
                                  onEdit: { openBoardCard(.edit(board)) },
                                  onMove: { offset in withAnimation(.snappy) { Flipboard.moveSwitchboard(board, by: offset, in: context) } },
                                  onDelete: { openBoardCard(.delete(board)) },
                                  onSelectLight: { index in
                                      guard switches.indices.contains(index) else { return }
                                      scrollRow(board.id, to: switches[index].id)
                                  })
                    .allowsHitTesting(!hasInlineCard)
            }
        } row: {
            SwitchRow(tileWidth: rowTileWidth, spacing: Self.spacing, inset: BoardPanel.inset,
                      ids: switches.map(\.id) + [board.id], trace: switches.isEmpty ? nil : lights.allSatisfy(\.isOn),
                      request: rowScroll[board.id]) {
                ForEach(switches) { task in
                    cell(for: task, tip: task.id == tipID ? tip : nil, inGrid: false)
                        .overlay {
                            // The switch the card under the row edits (Mac and iPad).
                            if editing == task.id {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1.5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: rowTileWidth)
                        .frame(maxHeight: .infinity)
                }
                AddSwitchTile(board: board.name) { openCard(.addTo(board)) }
                    .allowsHitTesting(!hasInlineCard)
                    .frame(width: rowTileWidth)
                    .frame(maxHeight: .infinity)
                    .id(board.id)
            }
        } card: {
            if let request {
                inlineCardView(request)
                    .frame(width: min(max(0, width - 2 * BoardPanel.inset), cardUnderRowWidth))
            }
        }
        // Brief 96: a switch dragged over the board lights it; let go, and it is on the board.
        .switchDropTarget(.board(board.id), dragging: dragging, lit: $dropTarget, style: .panel) {
            drop($0, onto: .board(board.id))
        }
        .id(Self.panelID(board.id))
    }

    /// The switch card under a board's row (Mac and iPad): two tiles wide, as in the grid, never under its narrowest.
    private var cardUnderRowWidth: CGFloat {
        max(FlipboardLayout.cardMinWidth, CGFloat(cardSpan) * cellWidth + CGFloat(cardSpan - 1) * Self.spacing)
    }

    /// The board's row scrolls to `id` (a switch, or the board's own id for its Add switch outline).
    private func scrollRow(_ board: UUID, to id: UUID) {
        rowScroll[board] = SwitchRowRequest(target: id, generation: (rowScroll[board]?.generation ?? 0) + 1)
    }

    /// A switch's tile, or (in the loose grid) the card editing it.
    @ViewBuilder
    private func cell(for task: TaskItem, tip: HITTip?, inGrid: Bool) -> some View {
        if inGrid, inlineCard == .edit(task) {
            inlineCardView(.edit(task))
                .flipboardGridSpan(cardSpan)
                .flipboardGridKeepsOwnHeight()
        } else {
            FlipSwitchTile(task: task, now: now, onEdit: { openCard(.edit(task)) },
                           onOpen: { open(task) }, onDelete: { delete(task) },
                           onDuplicate: { openCard(.duplicate(task)) },
                           moves: SwitchDrop.moves(for: task, boards: boards),
                           onMove: { drop(task.id, onto: $0) },
                           onDragStart: {
                               dropTarget = nil
                               dragging = DraggedSwitch(id: task.id, board: boardID(of: task))
                           },
                           onDragEnd: {
                               dragging = nil
                               dropTarget = nil
                           })
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
        SwitchCard(editing: request.task, style: .inline, board: request.board, duplicating: request.source,
                   isConfirmingDiscard: confirmingDiscard,
                   onClose: requestClose,
                   onSaved: { saved in
                       if !request.staysOpenAfterAdd { closeCard() }
                       land(saved)
                   },
                   onDraftChange: { cardContent.hasContent = $0 },
                   onDiscard: closeCard,
                   onKeepEditing: keepEditing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.boardSpace)) } action: { cardFrame = $0 }
            .id(request.id)
            .transition(cardTransition)
    }

    private var cardTransition: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity).animation(HITMotion.enter(reduceMotion: reduceMotion)),
                    removal: .opacity.animation(HITMotion.exit(reduceMotion: reduceMotion)))
    }

    /// The + tile, the toolbar's Add Switch…, a board's "+" or a tile's menu: the card, in the grid or over the board.
    private func openCard(_ request: SwitchCardRequest) {
        // The row brings the switch a card opens for into view (its Add switch outline when adding to it).
        switch request {
        case .addTo(let board): scrollRow(board.id, to: board.id)
        case .edit(let task), .duplicate(let task):
            if let board = boardID(of: task) { scrollRow(board, to: task.id) }
        case .add: break
        }
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
    /// `waiting` (iPhone, brief 126): the switch is in, the card that added it still going; its tile is held unseen
    /// until it lands (and lands on its own if the card never says it has gone).
    private func land(_ task: TaskItem, waiting: Bool = false) {
        let mark = SwitchLanding.Mark(id: task.id, generation: (landing?.generation ?? 0) + 1, waiting: waiting)
        landing = mark
        if waiting {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if landing == mark { land(task) }
            }
            return
        }
        // Its row scrolls to show it; a loose one folded away comes back into view.
        if let board = boardID(of: task) {
            scrollRow(board, to: task.id)
        } else {
            setFolded(false)
        }
        // Landed: the mark goes, so the tile doesn't settle again when the board comes back on screen.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if landing == mark { landing = nil }
        }
    }

    /// The card open for a switch on this board (Mac and iPad), which opens under its row: adding to it, or
    /// editing or duplicating one of its switches.
    private func inlineRequest(on board: Switchboard) -> SwitchCardRequest? {
        guard let request = inlineCard else { return nil }
        switch request {
        case .addTo(let target): return target.id == board.id ? request : nil
        case .edit(let task), .duplicate(let task): return boardID(of: task) == board.id ? request : nil
        case .add: return nil
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

    /// Where an adding card opens in the grid (Mac and iPad): at the end of the switches of the board it adds to, or
    /// (`.some(nil)`) in place of the loose switches' + tile; nil for an edit, which opens in place of its switch. A
    /// duplicate opens where its switch is.
    private func cardPlace(_ request: SwitchCardRequest) -> UUID?? {
        switch request {
        case .add: .some(nil)
        case .addTo(let board): .some(board.id)
        case .duplicate(let task): .some(boardID(of: task))
        case .edit: nil
        }
    }

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

/// A Switchboard's header (brief 72; brief 126): its name in the list section header style, its lights on the name's
/// line at the trailing end (`BoardLightsStrip`, one a switch in the row's order, in place of the "3 of 5" it had), and
/// its cadence line under the name ("Daily · resets 04:00"). The name opens the board's card; a long press (iPhone) or
/// right-click (Mac) offers Edit…, Add Switch…, Move Up, Move Down and Delete… (the "+" by the name went: the row ends
/// in the Add switch outline). No overdue colours, no counts of what is late: the Flipboard is a calm status check.
struct SwitchboardHeader: View {
    let board: Switchboard
    let line: String
    let lights: [BoardLight]
    let isFirst: Bool
    let isLast: Bool
    var onAdd: () -> Void
    var onEdit: () -> Void
    var onMove: (Int) -> Void
    var onDelete: () -> Void
    var onSelectLight: (Int) -> Void = { _ in }

    var body: some View {
        BoardHeaderLayout {
            Button(action: onEdit) {
                Text(board.name)
                    .font(HITType.listSectionHeader)
                    .foregroundStyle(HITColor.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit \(board.name)")
            .accessibilityHint("Opens the Switchboard")
            .accessibilityIdentifier("switchboardHeader")
            BoardLightsStrip(lights: lights, onSelect: onSelectLight)
            Text(line)
                .font(HITType.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("switchboardLine")
        }
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

/// The header over the loose switches once there is a Switchboard (brief 126, George: "Ungrouped"): the section-header
/// style (`HITSectionHeader`'s type in grey, on the tiles' edge) with a chevron that turns down while they show, and
/// their lights at the trailing end. Tapping it folds the grid away to this one line, and back.
struct UngroupedHeader: View {
    let lights: [BoardLight]
    let folded: Bool
    var onToggle: () -> Void
    var onSelectLight: (Int) -> Void = { _ in }

    var body: some View {
        BoardHeaderLayout {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Text("Ungrouped")
                        .font(HITType.listSectionHeader)
                        .foregroundStyle(Theme.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(folded ? 0 : 90))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: HITSectionHeader.minHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(folded ? "Show the switches on no Switchboard" : "Fold away the switches on no Switchboard")
            .accessibilityLabel("Ungrouped")
            .accessibilityValue(folded ? "Folded" : "Open")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("ungroupedHeader")
            BoardLightsStrip(lights: lights, onSelect: onSelectLight)
        }
    }
}

/// A header's line (brief 126): the title on the left, the lights at the trailing end on the title's first line, and
/// any third view (the cadence) under the title. Where the lights don't fit beside the title, even as segments or the
/// bar (a long name, the largest type), they take a line of their own under the rest, leading. The lights are offered
/// the width the title leaves them, so `BoardLightsStrip` picks dots, segments or the bar by the room it really has.
struct BoardHeaderLayout: Layout {
    var gap: CGFloat = HITSpacing.m
    var lineSpacing: CGFloat = 3

    /// Where the title, the lights and the line under the title go, and the header's size.
    struct Arrangement: Equatable {
        var title: CGRect
        var lights: CGRect
        var below: CGRect?
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 360, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        let frames = [arrangement.title, arrangement.lights] + (arrangement.below.map { [$0] } ?? [])
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
        guard subviews.count >= 2 else { return Arrangement(title: .zero, lights: .zero, size: .zero) }
        let title = subviews[0], lights = subviews[1]
        let below = subviews.count > 2 ? subviews[2] : nil
        func offered(_ view: LayoutSubview) -> (CGFloat) -> CGSize {
            { view.sizeThatFits(ProposedViewSize(width: $0, height: nil)) }
        }
        return Self.arrange(width: width, gap: gap, lineSpacing: lineSpacing, titleIdeal: title.sizeThatFits(.unspecified),
                            title: offered(title), lights: offered(lights), below: below.map(offered))
    }

    /// The arithmetic, from what each part answers when offered a width. Pure, so tests pin it.
    static func arrange(width: CGFloat, gap: CGFloat, lineSpacing: CGFloat, titleIdeal: CGSize,
                        title: (CGFloat) -> CGSize, lights: (CGFloat) -> CGSize,
                        below: ((CGFloat) -> CGSize)?) -> Arrangement {
        let room = max(0, width - min(titleIdeal.width, width) - gap)
        let fitted = lights(room)
        if fitted.width <= room + 0.5 {
            // One line: the lights beside the title, centred on its first line.
            let titleWidth = width - fitted.width - gap
            let titleSize = title(titleWidth)
            let firstLine = min(titleSize.height, titleIdeal.height)
            let lightsFrame = CGRect(x: width - fitted.width, y: (firstLine - fitted.height) / 2,
                                     width: fitted.width, height: fitted.height)
            var top = max(titleSize.height, lightsFrame.maxY)
            var belowFrame: CGRect?
            if let below {
                belowFrame = CGRect(x: 0, y: top + lineSpacing, width: width, height: below(width).height)
                top = belowFrame!.maxY
            }
            return Arrangement(title: CGRect(x: 0, y: 0, width: titleWidth, height: titleSize.height), lights: lightsFrame,
                               below: belowFrame, size: CGSize(width: width, height: top))
        }
        // The lights on a line of their own, under the title and the cadence.
        let titleSize = title(width)
        var top = titleSize.height
        var belowFrame: CGRect?
        if let below {
            belowFrame = CGRect(x: 0, y: top + lineSpacing, width: width, height: below(width).height)
            top = belowFrame!.maxY
        }
        let own = lights(width)
        let lightsFrame = CGRect(x: 0, y: top + HITSpacing.xs, width: min(own.width, width), height: own.height)
        return Arrangement(title: CGRect(x: 0, y: 0, width: width, height: titleSize.height), lights: lightsFrame,
                           below: belowFrame, size: CGSize(width: width, height: lightsFrame.maxY))
    }
}

/// A Switchboard panel's measures.
enum BoardPanel {
    /// From the panel's edge to its header and its first tile (the floor for text by a border, round 22).
    static let inset: CGFloat = HITSpacing.m
    /// The tiles' corners (18) and the inset: the panel's corners run round the tiles' at an even distance.
    static let radius: CGFloat = 18 + inset
}

/// A Switchboard's board (brief 126, George: "some kind of mild background UI so that they actually feel like they're a
/// part of the same circuitboard rather than just switches in a group"): one quiet surface, the design system's card
/// surface and hairline (`HITGroup`'s), holding the header, the row of switches and, on the Mac and iPad, the switch
/// card under the row. The row runs to the panel's edges and scrolls under them; everything else stands `inset` in.
struct SwitchboardPanel<Header: View, Row: View, Card: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var row: Row
    @ViewBuilder var card: Card

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BoardPanel.radius, style: .continuous)
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            header
                .padding(.horizontal, BoardPanel.inset)
            row
            card
                .padding(.horizontal, BoardPanel.inset)
        }
        .padding(.top, HITSpacing.m + 2)
        .padding(.bottom, BoardPanel.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.surface.opacity(0.5)))
        .overlay(shape.strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1).allowsHitTesting(false))
        .clipShape(shape)
    }
}

/// A board's row asked to scroll to `target`: a light tapped, a switch added or opened.
struct SwitchRowRequest: Equatable {
    let target: UUID
    let generation: Int
}

/// A Switchboard's switches in one row that scrolls sideways (brief 126, George: "Switchboards should grow/scroll
/// horizontally, not vertically, and the "Add switch" button outline should appear at the right end of each Switchboard
/// scroll"). Tiles sized so whole ones show and about a fifth of the next (`FlipboardLayout.rowTileWidth`); the row
/// runs to the panel's edges, its first tile `inset` in, and comes to rest on tile edges. Behind the tiles, at the
/// rockers' height, one thin trace joins them from the first to the last switch: the separator's grey, green when every switch on the board is on. On the Mac, while the pointer is over a
/// row with more to one side, a small chevron at that end pages it; a trackpad and shift-wheel scroll it.
struct SwitchRow<Content: View>: View {
    let tileWidth: CGFloat
    let spacing: CGFloat
    let inset: CGFloat
    /// The tiles' ids in order (the Add switch outline last, under the board's id).
    let ids: [UUID]
    /// The trace: nil without a switch; true when every switch is on.
    let trace: Bool?
    let request: Request?
    @ViewBuilder var content: Content

    typealias Request = SwitchRowRequest

    struct Edges: Equatable {
        var leading = false
        var trailing = false
    }

    @State private var position = ScrollPosition(idType: UUID.self)
    @State private var edges = Edges()
    @State private var leadingIndex = 0
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var traceWidth: CGFloat { 1.5 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) { content }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
                .background(alignment: .leading) { traceLine }
        }
        .scrollPosition($position, anchor: .leading)
        .contentMargins(.horizontal, inset, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .onScrollGeometryChange(for: Edges.self) { geometry in
            let visible = geometry.visibleRect
            return Edges(leading: visible.minX > -geometry.contentInsets.leading + 1,
                         trailing: visible.maxX < geometry.contentSize.width + geometry.contentInsets.trailing - 1)
        } action: { _, new in edges = new }
        .onScrollGeometryChange(for: Int.self) { geometry in
            Int(((geometry.visibleRect.minX + geometry.contentInsets.leading) / (tileWidth + spacing)).rounded())
        } action: { _, new in leadingIndex = new }
        #if os(macOS)
        .overlay { chevrons }
        .onHover { hovering = $0 }
        #endif
        .onChange(of: request) { _, request in
            guard let request else { return }
            withAnimation(reduceMotion ? nil : .snappy) { position.scrollTo(id: request.target, anchor: .leading) }
        }
    }

    /// From the first tile to the middle of the last switch, behind the tiles, at the rockers' height: it shows between
    /// the tiles only, never poking in from the panel's edge.
    @ViewBuilder
    private var traceLine: some View {
        if let allOn = trace {
            let switches = max(0, ids.count - 1)
            let length = CGFloat(max(0, switches - 1)) * (tileWidth + spacing) + tileWidth / 2
            Capsule(style: .continuous)
                .fill(allOn ? FlipLightStyle.green.opacity(0.75) : Theme.separator)
                .shadow(color: allOn ? FlipLightStyle.green.opacity(0.5) : .clear, radius: 2)
                .frame(width: length, height: Self.traceWidth)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: allOn)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    #if os(macOS)
    /// Pages the row by the tiles it shows whole: the one cut by the edge comes first.
    private func page(_ direction: Int) {
        guard !ids.isEmpty else { return }
        let step = visibleTiles
        let index = min(ids.count - 1, max(0, leadingIndex + direction * step))
        withAnimation(reduceMotion ? nil : .snappy) { position.scrollTo(id: ids[index], anchor: .leading) }
    }

    @State private var rowWidth: CGFloat = 0
    private var visibleTiles: Int { max(1, Int(((rowWidth - inset) / (tileWidth + spacing)).rounded(.down))) }

    private var chevrons: some View {
        HStack {
            if hovering && edges.leading { chevron("chevron.left", label: "Scroll back") { page(-1) } }
            Spacer(minLength: 0)
            if hovering && edges.trailing { chevron("chevron.right", label: "Scroll on") { page(1) } }
        }
        .padding(.horizontal, 6)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .animation(HITMotion.quick, value: hovering && edges.leading)
        .animation(HITMotion.quick, value: hovering && edges.trailing)
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(HITColor.text)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.elevated))
                .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .transition(.opacity)
    }
    #endif
}

/// Hands the board the list margin its screen follows (`followsSystemListMargin`).
private struct BoardMarginReader: View {
    @Environment(\.listMargin) private var listMargin
    var report: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .onAppear { report(listMargin) }
            .onChange(of: listMargin) { _, margin in report(margin) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
    /// The Switchboard it adds to, at the end of the board's row (brief 126); nil: a loose switch.
    var board: String?
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
        .accessibilityLabel(board.map { "Add a switch to \($0)" } ?? "Add switch")
        .accessibilityIdentifier(board == nil ? "addSwitchTile" : "switchboardAdd")
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
                          style: SwitchDropHighlight.Style = .section,
                          perform: @escaping (UUID) -> Void) -> some View {
        let isLit = lit.wrappedValue == target
        return overlay {
            // A board's panel lights on its own edge; the loose switches under a wash a little outside them.
            if isLit, style == .panel { SwitchDropHighlight(style: .panel).transition(.opacity) }
        }
        .background {
            if isLit, style == .section { SwitchDropHighlight().transition(.opacity) }
        }
        .animation(HITMotion.quick, value: isLit)
        .onDrop(of: [SwitchDrag.type], delegate: SwitchDropDelegate(target: target, draggedFrom: dragging.map(\.board),
                                                                     lit: lit, perform: perform))
    }
}
