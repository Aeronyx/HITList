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
    @State private var adding = false
    @State private var editing: EditRequest?
    /// The switch just deleted, while its "Deleted · Undo" toast shows.
    @State private var deleted: Flipboard.DeletedSwitch?
    @State private var deleteGeneration = 0
    @AppStorage(FlipSound.key, store: AppGroup.defaults) private var soundOn = true

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

    private var columns: [GridItem] {
        let count = FlipboardLayout.columnCount(width: width, compact: isCompact, spacing: Self.spacing,
                                                even: onDuoInnerDisplay)
        return Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: count)
    }

    var body: some View {
        let switches = switches
        SwiftUI.Group {
            if switches.isEmpty {
                ContentUnavailableView {
                    Label("No Switches Yet", systemImage: "switch.2")
                } description: {
                    Text("Each switch is a recurring chore. It starts red; flip it when the chore is done and it stays green for its interval, then turns red again.\n\nTap + to add one, or open any task and choose Add to Flipboard.")
                } actions: {
                    Button("Add a Switch") { adding = true }
                        .buttonStyle(.hitPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(switches) { task in
                            FlipSwitchTile(task: task, now: now, onEdit: { editing = EditRequest(task: task, focus: $0) },
                                           onOpen: { open(task) }, onDelete: { delete(task) })
                                .hitTip(task.id == switches.first?.id ? HITTip(.flipboard) : nil)
                        }
                        // The last cell adds a switch: a dashed outline of one, with a big +.
                        AddSwitchTile { adding = true }
                    }
                    .padding(16)
                    .animation(.snappy(duration: 0.35), value: switches.map(\.id))
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
            Button { adding = true } label: { Label("Add Switch…", systemImage: "plus") }
        }
        .onReceive(clock) { now = $0 }
        .onAppear {
            now = Date()
            FlipSound.prepare()
        }
        .completionToast(deleted.map { "Deleted ‘\($0.title)’" }, onUndo: undoDelete,
                         onDismiss: { withAnimation(HITMotion.exit) { deleted = nil } })
        .sheet(isPresented: $adding) {
            FlipSwitchEditor(task: nil).slateSheet()
        }
        .sheet(item: $editing) { request in
            FlipSwitchEditor(task: request.task, focus: request.focus).slateSheet()
        }
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

    /// "Edit interval…" or "Flips per interval…" from a switch's menu.
    struct EditRequest: Identifiable {
        let task: TaskItem
        let focus: FlipSwitchEditor.Focus
        var id: String { "\(task.id)-\(focus)" }
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

/// Adds a switch (title, "every N days/weeks", flips per interval), or edits an existing switch's
/// interval and flips. A live preview tile shows the switch as it will look; tap its rocker to try the
/// lamps (nothing is saved).
struct FlipSwitchEditor: View {
    /// Which part of an existing switch the menu asked to edit.
    enum Focus { case interval, flips }

    /// Nil to create a new switch.
    let task: TaskItem?
    var focus: Focus = .interval

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var interval = FlipInterval.default
    @State private var flipTarget = 1
    @State private var error: String?

    private var currentRule: RecurrenceRule? { task?.recurrenceRule }
    private var showsInterval: Bool { task == nil || focus == .interval }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The rule the preview and Save use: a current rule the steppers can't show (monthly, chosen
    /// weekdays) is kept until the steppers are changed.
    private var rule: RecurrenceRule {
        if let currentRule, FlipInterval(currentRule) == nil, interval == .default { return currentRule }
        return interval.rule
    }

    private var sheetTitle: String {
        guard let task else { return "New Switch" }
        return focus == .flips ? "Flips per Interval" : task.title
    }

    var body: some View {
        HITSheetChrome(sheetTitle, primaryTitle: task == nil ? "Add" : "Save",
                       isPrimaryEnabled: task != nil || !trimmedTitle.isEmpty, onPrimary: save) {
            if task == nil {
                HITSection("Name") {
                    HITField("Shave", text: $title, autofocus: true).onSubmit(save)
                }
            }

            if showsInterval {
                HITSection("Turns red", footer: intervalFooter) {
                    FlipStepper(value: $interval.count, range: 1...99) {
                        Text("Every \(interval.count) \(unitWord(interval.unit, interval.count))")
                    }
                    HITSegmented(selection: $interval.unit, segments: FlipInterval.Unit.allCases.map {
                        HITSegment($0, $0.rawValue.capitalized)
                    })
                }
            }

            HITSection("Flips per interval", footer: flipsFooter) {
                FlipStepper(value: $flipTarget, range: 1...Flipboard.maxFlipTarget) {
                    Text(flipTarget == 1 ? "1 flip" : "\(flipTarget) flips")
                }
            }

            HITSection("Preview") {
                FlipSwitchPreview(title: trimmedTitle.isEmpty ? (task?.title ?? "Shave") : trimmedTitle,
                                  rule: rule, target: flipTarget)
                    .frame(maxWidth: .infinity)
            }

            if let error {
                Text(error).foregroundStyle(HITColor.danger).font(HITType.callout)
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 520)
        #endif
        .onAppear {
            if let rule = currentRule, let shown = FlipInterval(rule) { interval = shown }
            if let task { flipTarget = Flipboard.clampedTarget(task.flipTarget) }
        }
    }

    private var intervalFooter: String? {
        if let rule = currentRule, FlipInterval(rule) == nil {
            return "Currently “\(rule.displayText)”. Changing it here replaces it."
        }
        return task == nil ? "Starts red. Flip it when it’s done; it turns red again after the interval." : nil
    }

    private var flipsFooter: String {
        guard flipTarget > 1 else { return "One flip turns it green. More make it charge up: flip it each time, and it turns green when every lamp is lit." }
        return "Flip it \(flipTarget) times and it turns green; the count starts again \(Self.restartPhrase(rule))."
    }

    /// "each week", "each day", "every 3 days".
    private static func restartPhrase(_ rule: RecurrenceRule) -> String {
        if let weekdays = rule.weekdays, !weekdays.isEmpty { return "each time it turns red" }
        let n = rule.interval
        switch rule.frequency {
        case .daily: return n == 1 ? "each day" : "every \(n) days"
        case .weekly: return n == 1 ? "each week" : "every \(n) weeks"
        case .monthly: return n == 1 ? "each month" : "every \(n) months"
        case .yearly: return n == 1 ? "each year" : "every \(n) years"
        }
    }

    private func unitWord(_ unit: FlipInterval.Unit, _ count: Int) -> String {
        switch unit {
        case .days: count == 1 ? "day" : "days"
        case .weeks: count == 1 ? "week" : "weeks"
        }
    }

    private func save() {
        do {
            if let task {
                if showsInterval, task.recurrenceRule != rule { Flipboard.setRule(rule, for: task, in: context) }
                if task.flipTarget != flipTarget { Flipboard.setTarget(flipTarget, for: task, in: context) }
            } else {
                guard !trimmedTitle.isEmpty else { return }
                try Flipboard.createSwitch(title: trimmedTitle, rule: rule, flipTarget: flipTarget, in: context)
            }
            Task { await NotificationScheduler.reschedule(context: context) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A number with − and + buttons in the design system's small circular style; the board's editors use
/// it for "every N" and "flips per interval".
struct FlipStepper<Label: View>: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @ViewBuilder var label: Label

    var body: some View {
        HStack(spacing: HITSpacing.m) {
            label
                .font(HITType.body.monospacedDigit())
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.2), value: value)
            Spacer(minLength: HITSpacing.s)
            Button { value = max(range.lowerBound, value - 1) } label: {
                Image(systemName: "minus").font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(HITButtonStyle(.secondary, size: .small, shape: .circle))
            .disabled(value <= range.lowerBound)
            .accessibilityLabel("Fewer")
            Button { value = min(range.upperBound, value + 1) } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(HITButtonStyle(.secondary, size: .small, shape: .circle))
            .disabled(value >= range.upperBound)
            .accessibilityLabel("More")
        }
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }
}

/// The editor's live preview: a fresh switch with the chosen interval and lamps. Tapping the rocker
/// plays the real flips (sound, haptic, lamps, bloom) on a local count; once green, a tap drains it
/// and starts over. Nothing is saved.
struct FlipSwitchPreview: View {
    let title: String
    let rule: RecurrenceRule
    let target: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flips = 0
    @State private var dip: Double?

    private var isGreen: Bool { flips >= target }
    private var side: Flipboard.Side { isGreen ? .green : .red }
    private var caption: String {
        if target <= 1 { return isGreen ? "0 of \(Flipboard.intervalDays(due: Date(), rule: rule)) days" : "Flip to start" }
        if isGreen { return "Done \(Flipboard.periodPhrase(rule))" }
        return flips == 0 ? "Flip to start" : "\(flips) of \(target) \(Flipboard.periodPhrase(rule))"
    }

    var body: some View {
        FlipSwitchFace(title: title, ruleText: rule.displayText.lowercased(), target: target,
                       lamps: isGreen ? target : flips, side: side, isOverdue: false, fraction: 0,
                       caption: caption, reduceMotion: reduceMotion) {
            RockerSwitch(tilt: dip ?? (isGreen ? 1 : -1))
                .contentShape(Rectangle())
                .onTapGesture(perform: tap)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Preview switch")
                .accessibilityValue(caption)
                .accessibilityAction { tap() }
        }
        .frame(width: 176)
        .onChange(of: target) { flips = min(flips, target) }
    }

    private func tap() {
        FlipHaptic.play()
        FlipSound.play()
        if isGreen {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.6)) { flips = 0 }
            return
        }
        let charging = flips + 1 >= target
        if charging, target > 1 {
            Task {
                try? await Task.sleep(for: .milliseconds(170))
                FlipHaptic.charged()
                FlipSound.playCharged()
            }
        }
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.2)) { flips += 1 }
            return
        }
        if charging {
            withAnimation(target > 1 ? .spring(response: 0.3, dampingFraction: 0.42) : .spring(response: 0.35, dampingFraction: 0.52)) {
                flips += 1
            }
        } else {
            withAnimation(.easeIn(duration: 0.09)) { dip = -0.2 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { flips += 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { dip = nil }
            }
        }
    }
}


/// The grid's last tile: the outline of a switch drawn with a dashed hairline (the plate, a smaller dashed
/// rocker in it) and a large accent "+", in the tiles' 18 pt shape. Tapping it opens the switch editor.
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
