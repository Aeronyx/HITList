import SwiftUI
import SwiftData
import HITListCore

/// The Task Flipboard: a wall of rocker switches, one per recurring chore. Red switches (due or
/// overdue) sit at the top, most overdue first; green ones follow, soonest due first.
struct FlipboardView: View {
    @Binding var selectedTask: TaskItem?

    @Environment(\.modelContext) private var context
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && $0.recurrence != nil }) private var recurring: [TaskItem]
    @State private var now = Date()
    @State private var width: CGFloat = 0
    @State private var adding = false
    @State private var editing: TaskItem?
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

    private var columns: [GridItem] {
        let count = FlipboardLayout.columnCount(width: width, compact: isCompact, spacing: Self.spacing)
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
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(switches) { task in
                            FlipSwitchTile(task: task, now: now, onEdit: { editing = task }, onOpen: { open(task) })
                        }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("Add Switch", systemImage: "plus") }
                    .help("Add a switch")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle(isOn: $soundOn) { Label("Flip Sound", systemImage: "speaker.wave.2") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Flipboard options")
            }
        }
        .onReceive(clock) { now = $0 }
        .onAppear {
            now = Date()
            FlipSound.prepare()
        }
        .sheet(isPresented: $adding) {
            FlipSwitchEditor(task: nil).slateSheet()
        }
        .sheet(item: $editing) { task in
            FlipSwitchEditor(task: task).slateSheet()
        }
    }

    /// Opens the task popout (`selectedTask` is `PopoutController.selection`).
    private func open(_ task: TaskItem) { selectedTask = task }
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
    static func columnCount(width: CGFloat, compact: Bool, spacing: CGFloat) -> Int {
        guard !compact else { return 2 }
        let fit = Int((width + spacing) / (minimumTileWidth + spacing))
        return min(5, max(3, fit))
    }
}

/// Adds a switch (title and "every N days/weeks"), or edits an existing switch's interval.
struct FlipSwitchEditor: View {
    /// Nil to create a new switch.
    let task: TaskItem?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var interval = FlipInterval.default
    @State private var error: String?
    @FocusState private var titleFocused: Bool

    private var currentRule: RecurrenceRule? { task?.recurrenceRule }

    var body: some View {
        NavigationStack {
            Form {
                if task == nil {
                    Section {
                        TextField("Shave", text: $title)
                            .focused($titleFocused)
                            .onSubmit(save)
                    }
                    .slateRow()
                }

                Section {
                    Stepper(value: $interval.count, in: 1...99) {
                        Text("Every \(interval.count) \(interval.unit == .days ? (interval.count == 1 ? "day" : "days") : (interval.count == 1 ? "week" : "weeks"))")
                            .monospacedDigit()
                    }
                    Picker("Unit", selection: $interval.unit) {
                        ForEach(FlipInterval.Unit.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Turns red")
                } footer: {
                    if let rule = currentRule, FlipInterval(rule) == nil {
                        Text("Currently “\(rule.displayText)”. Saving replaces it.")
                    } else if task == nil {
                        Text("Starts red. Flip it when it’s done; it turns red again after the interval.")
                    }
                }
                .slateRow()

                if let error {
                    Text(error).foregroundStyle(.red).font(.callout).slateRow()
                }
            }
            .formStyle(.grouped)
            .slateList()
            .navigationTitle(task == nil ? "New Switch" : task!.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Add" : "Save", action: save)
                        .disabled(task == nil && title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 260)
        #endif
        .onAppear {
            if let rule = currentRule, let shown = FlipInterval(rule) { interval = shown }
            if task == nil { titleFocused = true }
        }
    }

    private func save() {
        do {
            if let task {
                if task.recurrenceRule != interval.rule { Flipboard.setRule(interval.rule, for: task, in: context) }
            } else {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                try Flipboard.createSwitch(title: trimmed, rule: interval.rule, in: context)
            }
            Task { await NotificationScheduler.reschedule(context: context) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
