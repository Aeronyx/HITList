import SwiftUI
import SwiftData
import HITListCore

/// One switch on the wall: title in small caps, the LED (or a charger's row of lamps), the rocker, and
/// the light bar.
///
/// Tapping a red switch flips it: the rocker springs over (with a little overshoot), the LED settles to
/// faint green, the bar resets, a click plays (`FlipSound`), and only then does the task roll on, so the
/// board re-sorts after the flip has landed. A green switch asks before it is flipped early.
///
/// A charger (`flipTarget` > 1) takes several flips: each one presses the rocker toward green and lets
/// it spring back while the next lamp pops on; the last one lights the row, snaps the rocker to green and
/// runs a bloom along the lamps, with the bubble after the click. Tapping a charged switch only bounces.
///
/// Long press anywhere on the tile, the rocker included (iPhone: the system's context menu, with its own
/// haptic and a lifted preview of the tile), or right-click (Mac) opens the switch's menu; on the Mac a
/// long press opens the same actions in a popover. The rocker is not a `Button`, so the long press reaches
/// the menu instead of being swallowed by the button. On iPhone nothing else may listen for the long
/// press: a `LongPressGesture` on the tile (the Mac's popover trigger) won over the context menu's own,
/// so the menu never opened there (brief 59).
struct FlipSwitchTile: View {
    let task: TaskItem
    let now: Date
    var onEdit: (FlipSwitchEditor.Focus) -> Void
    var onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where a flip in progress will land: the tile shows it while the rocker moves, before the task
    /// itself changes.
    @State private var landing: Flipboard.Charge?
    /// Overrides the rocker's tilt while it dips and springs back.
    @State private var dip: Double?
    @State private var confirmEarly = false
    /// The rocker sinks a touch under the finger.
    @State private var pressed = false
    /// When the last long press fired: the tap that ends it must not also flip the switch.
    @State private var longPressedAt: Date?
    @State private var showMenuPanel = false
    /// The lamps a charger shows instead of its count, while a drain is about to play.
    @State private var lampsOverride: Int?

    private static let flipDuration: Duration = .milliseconds(380)
    private static let countDuration: Duration = .milliseconds(240)

    private var flipping: Bool { landing != nil }
    private var rule: RecurrenceRule { task.recurrenceRule ?? Flipboard.defaultRule }
    private var target: Int { Flipboard.clampedTarget(task.flipTarget) }
    private var charge: Flipboard.Charge { landing ?? Flipboard.Charge(task) }
    private var side: Flipboard.Side { Flipboard.side(due: charge.due, now: now) }
    private var isOverdue: Bool { Flipboard.isOverdue(due: charge.due, now: now) }
    private var count: Int { Flipboard.effectiveCount(charge, target: target, rule: rule, now: now) }
    private var tilt: Double { dip ?? (side == .green ? 1 : -1) }
    private var started: Bool {
        Flipboard.hasStarted(due: charge.due, createdAt: task.createdAt) || count > 0
    }
    private var fraction: Double { started ? Flipboard.elapsedFraction(due: charge.due, rule: rule, now: now) : 0 }
    private var caption: String {
        Flipboard.caption(due: charge.due, rule: rule, started: started, count: count, target: target, now: now)
    }

    var body: some View {
        FlipSwitchFace(title: task.title, ruleText: rule.displayText.lowercased(), target: target,
                       lamps: lampsOverride ?? count, side: side, isOverdue: isOverdue, fraction: fraction,
                       caption: caption, reduceMotion: reduceMotion) {
            rocker
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        #if os(iOS)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        #else
        // Mac: a haptic as the hold registers, then the popover. Simultaneous, so the rocker's click and
        // the scroll view keep working.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.longPressDuration).onEnded { _ in longPressed() }
        )
        #endif
        .contextMenu { menuButtons }
        #if os(macOS)
        .popover(isPresented: $showMenuPanel, arrowEdge: .trailing) {
            FlipSwitchMenuPanel(items: menuItems) { showMenuPanel = false }
        }
        #endif
        .confirmationDialog("Mark “\(task.title)” done early?", isPresented: $confirmEarly, titleVisibility: .visible) {
            Button("Mark Done") { flip() }
        } message: {
            if let due = task.dueDate {
                Text("It isn’t due until \(DueFormatter.text(for: due, hasTime: false, now: now)).")
            }
        }
        .onAppear {
            FlipHaptic.prepare()
            noteLamps(firstAppearance: true)
        }
        .onChange(of: side) { noteLamps(firstAppearance: false) }
        .onChange(of: charge) { noteLamps(firstAppearance: false) }
    }

    private var accessibilityValue: String { side == .red ? "Red, \(caption)" : "Green, \(caption)" }
    private var accessibilityHint: String {
        if side == .red { return target > 1 ? "Counts one flip" : "Flips the switch back to green" }
        return target > 1 ? "Already charged" : "Marks it done early"
    }

    /// The rocker takes taps only; the long press goes to the tile's menu.
    private var rocker: some View {
        RockerSwitch(tilt: tilt)
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .brightness(pressed ? -0.04 : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: tapped)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(task.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
            .accessibilityAction { tapped() }
            .accessibilityActions { menuButtons }
    }

    private static let longPressDuration = 0.35

    private func tapped() {
        if let longPressedAt, Date().timeIntervalSince(longPressedAt) < 1.5 {
            self.longPressedAt = nil
            return
        }
        guard !flipping else { return }
        press()
        if side == .red {
            flip()
        } else if target > 1 {
            bounce()
        } else {
            confirmEarly = true
        }
    }

    /// The rocker sinks and comes back up, like pushing real plastic.
    private func press() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.07)) { pressed = true }
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.12)) { pressed = false }
        }
    }

    private func longPressed() {
        longPressedAt = Date()
        FlipHaptic.menu()
        #if os(macOS)
        showMenuPanel = true
        #endif
    }

    // MARK: Flipping

    private func flip() {
        guard !flipping else { return }
        let (next, outcome) = Flipboard.afterFlip(Flipboard.Charge(task), target: target, rule: rule, now: now)
        switch outcome {
        case .ignored: bounce()
        case .counted: countFlip(to: next)
        case .charged: chargeUp(to: next, markDone: false)
        }
    }

    private func markDone() {
        guard !flipping else { return }
        let (next, outcome) = Flipboard.afterMarkDone(Flipboard.Charge(task), target: target, rule: rule, now: now)
        switch outcome {
        case .ignored: bounce()
        case .counted: countFlip(to: next)
        case .charged: chargeUp(to: next, markDone: true)
        }
    }

    /// One flip toward a charger's target: the rocker presses toward green and springs back, a lamp
    /// pops on.
    private func countFlip(to next: Flipboard.Charge) {
        FlipHaptic.play()
        FlipSound.play()
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { landing = next }
        } else {
            withAnimation(.easeIn(duration: 0.09)) { dip = -0.2 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { landing = next }
            Task {
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { dip = nil }
            }
        }
        commit(after: Self.countDuration) { Flipboard.flip(task, in: context) }
    }

    /// The flip that turns the switch green. A charger snaps harder and blooms, with the bubble.
    private func chargeUp(to next: Flipboard.Charge, markDone: Bool) {
        let wasGreen = side == .green
        let isCharger = target > 1
        let spring: Animation = reduceMotion ? .easeInOut(duration: 0.2)
            : isCharger ? .spring(response: 0.3, dampingFraction: 0.42) : .spring(response: 0.35, dampingFraction: 0.52)
        FlipHaptic.play()
        FlipSound.play()
        if isCharger {
            Task {
                try? await Task.sleep(for: .milliseconds(170))
                FlipHaptic.charged()
                FlipSound.playCharged()
            }
        }
        if wasGreen && !reduceMotion {
            // Already green: press it through toward red, then let it spring home.
            withAnimation(.easeIn(duration: 0.11)) { dip = -0.35; landing = next }
            Task {
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(spring) { dip = nil }
            }
        } else {
            withAnimation(spring) { landing = next }
        }
        commit(after: Self.flipDuration) {
            if markDone { Flipboard.markDone(task, in: context) } else { Flipboard.flip(task, in: context) }
        }
    }

    /// A charged switch tapped again: a small bounce and a soft bump, nothing else.
    private func bounce() {
        FlipHaptic.menu()
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.08)) { dip = 0.62 }
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { dip = nil }
        }
    }

    /// Writes the flip once the animation has landed, then lets the tile follow the task again.
    private func commit(after delay: Duration, _ write: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: delay)
            withAnimation(.snappy(duration: 0.35)) {
                write()
                landing = nil
            }
            await NotificationScheduler.reschedule(context: context)
        }
    }

    /// "Flip back to red": the rocker springs back to red, a lamp goes out.
    private func flipBack() {
        guard !flipping, Flipboard.canFlipBack(Flipboard.Charge(task), target: target, rule: rule, now: now) else { return }
        FlipHaptic.play()
        FlipSound.play()
        let spring: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.6)
        withAnimation(spring) {
            Flipboard.flipBack(task, in: context)
        }
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    // MARK: Draining

    /// Remembers a charger shown full; the first time it shows the next interval (red, nothing counted)
    /// the lamps start full and drain right to left. While the board is open across the boundary the
    /// count falls on its own and the lamps drain the same way.
    private func noteLamps(firstAppearance: Bool) {
        guard target > 1, !flipping else { return }
        if side == .green {
            FlipDrainMemory.recordFull(task.id, due: task.dueDate)
            return
        }
        let recorded = FlipDrainMemory.recordedDue(for: task.id)
        FlipDrainMemory.forget(task.id)
        guard firstAppearance, !reduceMotion,
              Flipboard.shouldDrain(recordedDue: recorded, due: task.dueDate, count: count, now: now) else { return }
        lampsOverride = target
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            lampsOverride = nil
        }
    }

    // MARK: The menu

    /// Brief 59's order: Flip (or Mark done), Flip back to red, Edit task…, the interval and flips, then
    /// Remove from Flipboard and Delete.
    private var menuItems: [FlipMenuItem] {
        let canFlipBack = Flipboard.canFlipBack(Flipboard.Charge(task), target: target, rule: rule, now: now)
        let chargedCharger = target > 1 && side == .green
        var items: [FlipMenuItem] = []
        if side == .red {
            // A charger's flip counts one; "Mark done" charges it at once.
            items.append(FlipMenuItem(id: "flip", title: "Flip", systemImage: "switch.2", isDisabled: flipping) { flip() })
            if target > 1 {
                items.append(FlipMenuItem(id: "done", title: "Mark done", systemImage: "checkmark.circle",
                                          isDisabled: flipping) { markDone() })
            }
        } else {
            // Green: a plain switch can be done early (chosen from a menu, so no question first).
            items.append(FlipMenuItem(id: "done", title: "Mark done", systemImage: "checkmark.circle",
                                      isDisabled: flipping || chargedCharger) { markDone() })
        }
        items += [
            FlipMenuItem(id: "back", title: "Flip back to red", systemImage: "arrow.uturn.backward",
                         isDisabled: !canFlipBack || flipping) { flipBack() },
            FlipMenuItem(id: "open", title: "Edit task…", systemImage: "square.and.pencil") { onOpen() },
            FlipMenuItem(id: "interval", title: "Edit interval…", systemImage: "timer") { onEdit(.interval) },
            FlipMenuItem(id: "flips", title: "Flips per interval…", systemImage: "repeat") { onEdit(.flips) },
            FlipMenuItem(id: "remove", title: "Remove from Flipboard", systemImage: "minus.circle", role: .destructive) {
                withAnimation(.snappy) { Flipboard.remove(task, in: context) }
            },
        ]
        return items
    }

    @ViewBuilder private var menuButtons: some View {
        ForEach(Array(menuItems.enumerated()), id: \.element.id) { index, item in
            // One divider before the destructive group.
            if item.role == .destructive, index > 0, menuItems[index - 1].role != .destructive { Divider() }
            Button(role: item.role, action: item.action) { Label(item.title, systemImage: item.systemImage) }
                .disabled(item.isDisabled)
        }
    }
}

/// The look of a switch, from plain values: shared by the board's tiles and the editor's live preview.
/// One flip per interval shows the single LED top right; more show a row of lamps across the top.
struct FlipSwitchFace<Rocker: View>: View {
    let title: String
    let ruleText: String
    let target: Int
    /// Lamps lit (chargers only).
    let lamps: Int
    let side: Flipboard.Side
    let isOverdue: Bool
    let fraction: Double
    let caption: String
    let reduceMotion: Bool
    @ViewBuilder var rocker: Rocker

    var body: some View {
        VStack(spacing: 12) {
            if target > 1 {
                FlipChargeLamps(target: target, count: lamps, side: side, reduceMotion: reduceMotion)
                    .padding(.horizontal, 2)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HITType.subheadlineSemibold.smallCaps())
                        .tracking(0.6)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ruleText)
                        .font(HITType.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if target <= 1 {
                    FlipLED(glow: side == .green ? .done : isOverdue ? .overdue : .due, reduceMotion: reduceMotion)
                }
            }

            rocker

            VStack(spacing: 5) {
                FlipLightBar(fraction: fraction, side: side)
                Text(caption)
                    .font(HITType.caption2.monospacedDigit())
                    .foregroundStyle(side == .red ? FlipboardPalette.redTop : Theme.secondaryText)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay { ScrewHeads().padding(6) }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.07), .black.opacity(0.4)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
    }
}

/// One action in a switch's menu, shown as a context-menu button and, on the Mac, as a row in the
/// long-press popover.
struct FlipMenuItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var isDisabled = false
    let action: () -> Void
}

/// The switch menu as a popover of design-system rows (the Mac's long press; right-click gets the
/// system context menu with the same items).
struct FlipSwitchMenuPanel: View {
    let items: [FlipMenuItem]
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if item.role == .destructive, index > 0, items[index - 1].role != .destructive {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }
                HITMenuRow(item.title, systemImage: item.systemImage, role: item.role, accessory: .none) {
                    dismiss()
                    item.action()
                }
                .disabled(item.isDisabled)
            }
        }
        .padding(.vertical, HITSpacing.xs)
        .frame(width: 250)
        .background(Theme.elevated)
    }
}

/// Four slotted screw heads in the corners of a tile.
private struct ScrewHeads: View {
    var body: some View {
        VStack {
            HStack { screw(20); Spacer(); screw(-35) }
            Spacer()
            HStack { screw(70); Spacer(); screw(-10) }
        }
    }

    private func screw(_ angle: Double) -> some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.13)], startPoint: .top, endPoint: .bottom))
            .overlay {
                Rectangle().fill(.black.opacity(0.55)).frame(width: 4, height: 0.9).rotationEffect(.degrees(angle))
            }
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }
}
