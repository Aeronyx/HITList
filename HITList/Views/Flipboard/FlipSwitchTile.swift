import SwiftUI
import SwiftData
import HITListCore

/// One switch on the wall: title in small caps, the LED, the rocker, and the light bar.
///
/// Tapping a red switch flips it: the rocker springs over (with a little overshoot), the LED goes out,
/// the bar resets, a click plays (`FlipSound`), and only then does the task complete, so the board re-sorts after the flip has
/// landed. A green switch asks before it is flipped early.
///
/// Long press anywhere on the tile, the rocker included (iPhone), or right-click (Mac) opens the switch's
/// menu; on the Mac a long press opens the same actions in a popover. The rocker is not a `Button`, so
/// the long press reaches the menu instead of being swallowed by the button.
struct FlipSwitchTile: View {
    let task: TaskItem
    let now: Date
    var onEdit: () -> Void
    var onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True while a flip animates: the tile already shows where the flip will land, before the task
    /// itself changes.
    @State private var flipping = false
    /// The rocker dips toward red and springs back when a green switch is flipped early.
    @State private var dipping = false
    @State private var confirmEarly = false
    /// The rocker sinks a touch under the finger.
    @State private var pressed = false
    /// When the last long press fired: the tap that ends it must not also flip the switch.
    @State private var longPressedAt: Date?
    @State private var showMenuPanel = false

    private static let flipDuration: Duration = .milliseconds(380)

    private var rule: RecurrenceRule { task.recurrenceRule ?? Flipboard.defaultRule }
    private var shownDue: Date? {
        flipping ? Flipboard.dueAfterFlip(due: task.dueDate, rule: rule, now: now) : task.dueDate
    }
    private var side: Flipboard.Side { Flipboard.side(due: shownDue, now: now) }
    private var isOverdue: Bool { Flipboard.isOverdue(due: shownDue, now: now) }
    private var tilt: Double { dipping ? -0.35 : side == .green ? 1 : -1 }
    /// A flip in progress lands on a started switch.
    private var started: Bool { flipping || Flipboard.hasStarted(task) }
    private var fraction: Double { started ? Flipboard.elapsedFraction(due: shownDue, rule: rule, now: now) : 0 }
    private var caption: String { Flipboard.caption(due: shownDue, rule: rule, started: started, now: now) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(HITType.subheadlineSemibold.smallCaps())
                        .tracking(0.6)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(rule.displayText.lowercased())
                        .font(HITType.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                FlipLED(isOn: side == .red, pulsing: isOverdue && !reduceMotion)
            }

            rocker

            VStack(spacing: 5) {
                FlipLightBar(fraction: fraction, side: side)
                Text(caption)
                    .font(HITType.caption2.monospacedDigit())
                    .foregroundStyle(side == .red ? FlipboardPalette.redTop : Theme.secondaryText)
                    .lineLimit(1)
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
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        #if os(iOS)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        #endif
        // A haptic as the hold registers, then the menu (iPhone) or the popover (Mac). Simultaneous, so
        // the rocker's tap and the scroll view keep working.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.longPressDuration).onEnded { _ in longPressed() }
        )
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
        .onAppear { FlipHaptic.prepare() }
    }

    private var accessibilityValue: String { side == .red ? "Red, \(caption)" : "Green, \(caption)" }
    private var accessibilityHint: String { side == .red ? "Flips the switch back to green" : "Marks it done early" }

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
        if side == .red { flip() } else { confirmEarly = true }
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

    // MARK: The menu

    private var menuItems: [FlipMenuItem] {
        [
            FlipMenuItem(id: "back", title: "Flip back to red", systemImage: "arrow.uturn.backward",
                         isDisabled: !Flipboard.canFlipBack(due: task.dueDate, now: now) || flipping) { flipBack() },
            FlipMenuItem(id: "interval", title: "Edit interval…", systemImage: "timer") { onEdit() },
            FlipMenuItem(id: "open", title: "Open task", systemImage: "arrow.up.forward.square") { onOpen() },
            FlipMenuItem(id: "done", title: "Mark done", systemImage: "checkmark.circle", isDisabled: flipping) { markDone() },
            FlipMenuItem(id: "remove", title: "Remove from Flipboard", systemImage: "minus.circle", role: .destructive) {
                withAnimation(.snappy) { Flipboard.remove(task, in: context) }
            },
        ]
    }

    @ViewBuilder private var menuButtons: some View {
        ForEach(menuItems) { item in
            if item.role == .destructive { Divider() }
            Button(role: item.role, action: item.action) { Label(item.title, systemImage: item.systemImage) }
                .disabled(item.isDisabled)
        }
    }

    /// "Mark done" from the menu: the same as flipping it, without asking when it is green.
    private func markDone() {
        guard !flipping else { return }
        flip()
    }

    /// "Flip back to red": the rocker springs back to red, then the due date returns to the flip day.
    private func flipBack() {
        guard !flipping, Flipboard.canFlipBack(due: task.dueDate, now: now) else { return }
        FlipHaptic.play()
        FlipSound.play()
        let spring: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.6)
        withAnimation(spring) {
            Flipboard.flipBack(task, in: context, now: now)
        }
        Task { await NotificationScheduler.reschedule(context: context) }
    }

    private func flip() {
        let wasGreen = side == .green
        let spring: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.52)
        FlipHaptic.play()
        FlipSound.play()
        if wasGreen && !reduceMotion {
            // Already green: press it through toward red, then let it spring home.
            withAnimation(.easeIn(duration: 0.11)) { dipping = true; flipping = true }
            Task {
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(spring) { dipping = false }
            }
        } else {
            withAnimation(spring) { flipping = true }
        }
        Task {
            try? await Task.sleep(for: Self.flipDuration)
            withAnimation(.snappy(duration: 0.35)) {
                Flipboard.flip(task, in: context)
                flipping = false
            }
            await NotificationScheduler.reschedule(context: context)
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
            ForEach(items) { item in
                if item.role == .destructive {
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
