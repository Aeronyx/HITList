import SwiftUI
import SwiftData
import Combine
import HITListCore

/// The Task Flipboard: a wall of rocker switches, one per recurring chore. Red switches (due or
/// overdue) sit at the top, most overdue first; green ones follow, soonest due first.
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
    @State private var now = Date()
    @State private var width: CGFloat = 0
    /// The switch card open in the grid (Mac and iPad, brief 69): adding, or editing a switch.
    @State private var inlineCard: SwitchCardRequest?
    /// The switch card over the board (iPhone).
    @State private var floatingCard: SwitchCardRequest?
    /// The inline card's "something to lose", read on a click away (a box: typing redraws nothing here).
    @State private var cardContent = SwitchCardContent()
    @State private var confirmingDiscard = false
    /// When the inline card offered "Discard": one Esc can reach both × and the exit command, and must not
    /// ask and discard in the same press.
    @State private var discardOfferedAt = Date.distantPast
    /// Where the inline card is, in the board's scroll view: a click inside it is never a click away.
    @State private var cardFrame = CGRect.null
    private static let boardSpace = "flipboard"
    /// The switch just deleted, while its "Deleted · Undo" toast shows.
    @State private var deleted: Flipboard.DeletedSwitch?
    @State private var deleteGeneration = 0
    @AppStorage(FlipSound.key, store: AppGroup.defaults) private var soundOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private static let spacing: CGFloat = 14

    private var switches: [TaskItem] { Flipboard.sorted(recurring.filter(Flipboard.isMember)) }

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

    /// The columns the inline card takes (`FlipboardLayout.cardSpan`).
    private var cardSpan: Int {
        let columns = columnCount
        let cell = (width - CGFloat(columns - 1) * Self.spacing) / CGFloat(max(1, columns))
        return FlipboardLayout.cardSpan(columns: columns, cellWidth: cell, spacing: Self.spacing)
    }

    /// iPhone: the card floats over the board; the Mac and iPad open it in the grid.
    private var cardFloats: Bool { isCompact }

    var body: some View {
        let switches = switches
        SwiftUI.Group {
            if switches.isEmpty && inlineCard == nil {
                ContentUnavailableView {
                    Label("No Switches Yet", systemImage: "switch.2")
                } description: {
                    Text(Self.emptyMessage)
                } actions: {
                    Button("Add a Switch") { openCard(.add) }
                        .buttonStyle(.hitPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        FlipboardGrid(columns: columnCount, spacing: Self.spacing) {
                            ForEach(switches) { task in
                                cell(for: task, first: task.id == switches.first?.id)
                            }
                            // The last cell adds a switch: a dashed outline of one, with a big +; on the Mac
                            // and iPad the card opens in its place.
                            if inlineCard == .add {
                                inlineCardView(.add)
                            } else {
                                AddSwitchTile { openCard(.add) }
                                    .allowsHitTesting(inlineCard == nil)
                            }
                        }
                        .padding(16)
                        .animation(.snappy(duration: 0.35), value: switches.map(\.id))
                    }
                    // While the card is open in the grid, a click anywhere off it is a click away: the tiles
                    // stop taking clicks (no switch flips by accident) and the click reaches the board. A click
                    // in the card's name reaches it too (the text view is AppKit's or UIKit's and claims no
                    // SwiftUI gesture), so a click inside the card's frame only ever means keep editing.
                    .gesture(SpatialTapGesture(coordinateSpace: .named(Self.boardSpace)).onEnded { tap in
                        if cardFrame.contains(tap.location) {
                            if confirmingDiscard { keepEditing() }
                        } else {
                            clickAway()
                        }
                    }, including: inlineCard == nil ? .subviews : .all)
                    .coordinateSpace(.named(Self.boardSpace))
                    .onChange(of: inlineCard?.id) { _, id in
                        guard let id else { return }
                        Task { @MainActor in
                            withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { width = $0 }
        .background(Theme.background)
        .navigationTitle("Flipboard")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        // Adding lives in the grid (`AddSwitchTile`); the toolbar's control is the flip sound. Add switch…
        // is a second route: in the "…" on the Mac and iPad, a long press on the sound button on iPhone.
        .screenChrome {
            ScreenOptionButton { soundOn.toggle() } label: {
                Label(soundOn ? "Flip sound on" : "Flip sound off", systemImage: soundOn ? "speaker.wave.2" : "speaker.slash")
                    .labelStyle(.iconOnly)
            }
            .help(soundOn ? "Flip sound on" : "Flip sound off")
            .accessibilityIdentifier("flipSound")
        } menu: {
            Button { openCard(.add) } label: { Label("Add Switch…", systemImage: "plus") }
        }
        // A switch deleted or taken off the board elsewhere (another device, Siri) while its card is open: the
        // card goes with it.
        .onChange(of: switches.map(\.id)) { _, ids in
            if let task = inlineCard?.task, !ids.contains(task.id) { closeCard() }
            if let task = floatingCard?.task, !ids.contains(task.id) { withoutAnimation { floatingCard = nil } }
        }
        .onReceive(clock) { now = $0 }
        .onAppear {
            now = Date()
            FlipSound.prepare()
        }
        .completionToast(deleted.map { "Deleted ‘\($0.title)’" }, onUndo: undoDelete,
                         onDismiss: { withAnimation(HITMotion.exit) { deleted = nil } })
        #if os(iOS)
        .fullScreenCover(item: $floatingCard) { request in
            FloatingSwitchCard(request: request) { _ in
                withoutAnimation { floatingCard = nil }
            }
            .presentationBackground(.clear)
        }
        #endif
    }

    /// A switch's tile, or the card editing it.
    @ViewBuilder
    private func cell(for task: TaskItem, first: Bool) -> some View {
        if inlineCard == .edit(task) {
            inlineCardView(.edit(task))
        } else {
            FlipSwitchTile(task: task, now: now, onEdit: { openCard(.edit(task)) },
                           onOpen: { open(task) }, onDelete: { delete(task) })
                .hitTip(first ? HITTip(.flipboard) : nil)
                .allowsHitTesting(inlineCard == nil)
                .id(task.id)
        }
    }

    // MARK: The switch card (brief 69)

    /// The card in the grid, as wide as `cardSpan` columns.
    private func inlineCardView(_ request: SwitchCardRequest) -> some View {
        SwitchCard(editing: request.task, style: .inline, isConfirmingDiscard: confirmingDiscard,
                   onClose: requestClose,
                   onSaved: { _ in if request != .add { closeCard() } },
                   onDraftChange: { cardContent.hasContent = $0 },
                   onDiscard: closeCard,
                   onKeepEditing: keepEditing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.boardSpace)) } action: { cardFrame = $0 }
            .id(request.id)
            .flipboardGridSpan(cardSpan)
            .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity)
                                        .animation(HITMotion.enter(reduceMotion: reduceMotion)),
                                    removal: .opacity.animation(HITMotion.exit(reduceMotion: reduceMotion))))
    }

    /// The + tile, the toolbar's Add Switch… or a tile's menu: the card, in the grid or over the board.
    private func openCard(_ request: SwitchCardRequest) {
        if cardFloats {
            withoutAnimation { floatingCard = request }
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

    /// A click on the board off the card. An empty card closes and `then` runs; with something to lose,
    /// "Discard" shows and nothing else happens; with "Discard" showing, back to typing.
    private func clickAway(then action: (() -> Void)? = nil) {
        guard inlineCard != nil else { action?(); return }
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
            confirmingDiscard = false
            cardContent.hasContent = false
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// The empty board's rule, in one sentence (brief 59), then how to add a switch.
    static let emptyRule = "A switch is a chore that repeats within an interval: it stays off your lists until it’s due, then waits in Today, red, until you flip it."
    static let emptyMessage = emptyRule + "\n\nTap + to add one, or open any task and choose Add to Flipboard."

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

/// The grid's last tile: the outline of a switch drawn with a dashed hairline (the plate, a smaller dashed
/// rocker in it) and a large accent "+", in the tiles' 18 pt shape. Tapping it opens the switch card in its place
/// (brief 69).
struct AddSwitchTile: View {
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let plate = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: action) {
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
                .padding(.vertical, 22)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .contentShape(plate)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: hovered)
        .accessibilityLabel("Add switch")
        .accessibilityIdentifier("addSwitchTile")
    }
}
