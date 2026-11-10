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
    /// "Edit switch…": the switch card on this tile, filled in (brief 69).
    var onEdit: () -> Void
    var onOpen: () -> Void
    /// Deletes the switch; the board asks first (if that setting is on) and offers Undo.
    var onDelete: () -> Void = {}

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
    /// The switch's clock (brief 72): its interval, or its Switchboard's day; and whether it has a time.
    private var clock: Flipboard.Clock { Flipboard.Clock(task) }
    private var rule: RecurrenceRule { clock.rule }
    private var target: Int { Flipboard.clampedTarget(task.flipTarget) }
    private var charge: Flipboard.Charge { landing ?? Flipboard.Charge(task) }
    private var side: Flipboard.Side { clock.side(charge.due, now: now) }
    /// The breathing light: a loose switch past its day, or a switch past its time.
    private var isOverdue: Bool { clock.isLate(charge.due, now: now) }
    private var count: Int { Flipboard.effectiveCount(charge, target: target, clock: clock, now: now) }
    private var tilt: Double { dip ?? (side == .green ? 1 : -1) }
    private var started: Bool {
        clock.board != nil || Flipboard.hasStarted(due: charge.due, createdAt: task.createdAt) || count > 0
    }
    private var fraction: Double { started ? Flipboard.elapsedFraction(clock: clock, due: charge.due, now: now) : 0 }
    private var caption: String {
        Flipboard.caption(clock: clock, due: charge.due, started: started, count: count, target: target, now: now)
    }
    /// A green switch that a tap can't flip again: a charged charger, or a switch done for its board day.
    private var isDoneForNow: Bool { side == .green && (target > 1 || clock.board != nil) }

    var body: some View {
        FlipSwitchFace(title: task.title, ruleText: Self.detailLine(rule: rule, onBoard: clock.board != nil,
                                                                     time: Flipboard.time(of: task)), target: target,
                       lamps: lampsOverride ?? count, side: side, isOverdue: isOverdue, fraction: fraction,
                       caption: caption, reduceMotion: reduceMotion) {
            rocker
        }
        // One element per tile for tests and VoiceOver's rotor; the rocker inside stays the button.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flipSwitchTile")
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
                Text("It isn’t due until \(DueFormatter.text(for: due, hasTime: task.hasDueTime, now: now)).")
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
        if clock.board != nil { return "Done for now" }
        return target > 1 ? "Already charged" : "Marks it done early"
    }

    /// The line under the title (brief 72): the interval ("every 3 days"), with the switch's time after it ("every 3
    /// days · 21:00"); on a Switchboard, whose header names the cadence, its time alone, or the cadence if it has none.
    static func detailLine(rule: RecurrenceRule, onBoard: Bool, time: PickerTime?, calendar: Calendar = .current,
                           locale: Locale = .current) -> String {
        let interval = rule.displayText.lowercased()
        guard let time else { return interval }
        let text = Flipboard.timeText(time.on(Date(), calendar: calendar), calendar: calendar, locale: locale)
        return onBoard ? text : "\(interval) · \(text)"
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
        } else if isDoneForNow {
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
        let (next, outcome) = Flipboard.afterFlip(Flipboard.Charge(task), target: target, clock: clock, now: now)
        switch outcome {
        case .ignored: bounce()
        case .counted: countFlip(to: next)
        case .charged: chargeUp(to: next, markDone: false)
        }
    }

    private func markDone() {
        guard !flipping else { return }
        let (next, outcome) = Flipboard.afterMarkDone(Flipboard.Charge(task), target: target, clock: clock, now: now)
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
        guard !flipping, Flipboard.canFlipBack(Flipboard.Charge(task), target: target, clock: clock, now: now) else { return }
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
              Flipboard.shouldDrain(recordedDue: recorded, due: task.dueDate, count: count, now: now, clock: clock) else { return }
        lampsOverride = target
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            lampsOverride = nil
        }
    }

    // MARK: The menu

    /// Brief 59's order: Flip (or Mark done), Flip back to red, Edit task…, Edit switch… (the interval, flips
    /// and name, brief 69), then Remove from Flipboard and Delete.
    private var menuItems: [FlipMenuItem] {
        let canFlipBack = Flipboard.canFlipBack(Flipboard.Charge(task), target: target, clock: clock, now: now)
        let chargedCharger = isDoneForNow
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
            // Name, interval and flips in the switch card (brief 69; it replaced "Edit interval…" and "Flips per
            // interval…", which opened a sheet).
            FlipMenuItem(id: "edit", title: "Edit switch…", systemImage: "slider.horizontal.3") { onEdit() },
            FlipMenuItem(id: "remove", title: "Remove from Flipboard", systemImage: "minus.circle", role: .destructive) {
                withAnimation(.snappy) { Flipboard.remove(task, in: context) }
            },
            FlipMenuItem(id: "delete", title: "Delete", systemImage: "trash", role: .destructive) { onDelete() },
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

/// The look of a switch, from plain values. Every switch is laid out the same way, so every tile on a board is the
/// same size (George, 2026-11-08: "all switches should be the same width and height"): the lights' row at the top (one
/// pill for a plain switch, one per flip for a charger), the title in room for two lines whether it needs one or two,
/// the interval, the rocker, the interval's line and its caption. The plate fills the height the grid gives it.
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

    static var padding: CGFloat { 14 }
    static var titleFont: Font { HITType.subheadlineSemibold.smallCaps() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlipLights(target: target, count: lamps, side: side, isOverdue: isOverdue, reduceMotion: reduceMotion)

            // Room for two lines of title and the interval whatever the title, so every tile is one height: a hidden
            // stand-in sets the height alone, and the real title and interval are drawn over it from the top (the
            // interval right under a one-line title, not a blank line below it).
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "A").font(Self.titleFont).lineLimit(2, reservesSpace: true)
                Text(verbatim: "a").font(HITType.caption2)
            }
            .hidden()
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Self.titleFont)
                        .tracking(0.6)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                    Text(ruleText)
                        .font(HITType.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                // Its own height, not the stand-in's: offered exactly that, a two-line title rounded down to one.
                .fixedSize(horizontal: false, vertical: true)
            }

            rocker
                .frame(maxWidth: .infinity)

            VStack(spacing: 5) {
                FlipLightBar(fraction: fraction, side: side)
                Text(caption)
                    .font(HITType.caption2.monospacedDigit())
                    .foregroundStyle(side == .red ? FlipboardPalette.redTop : Theme.secondaryText)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
