import SwiftUI
import SwiftData
import HITListCore

/// One switch on the wall: title in small caps, the LED, the rocker, and the light bar.
///
/// Tapping a red switch flips it: the rocker springs over (with a little overshoot), the LED goes out,
/// the bar resets, and only then does the task complete, so the board re-sorts after the flip has
/// landed. A green switch asks before it is flipped early.
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

    private static let flipDuration: Duration = .milliseconds(380)

    private var rule: RecurrenceRule { task.recurrenceRule ?? Flipboard.defaultRule }
    private var shownDue: Date? {
        flipping ? Flipboard.dueAfterFlip(due: task.dueDate, rule: rule, now: now) : task.dueDate
    }
    private var side: Flipboard.Side { Flipboard.side(due: shownDue, now: now) }
    private var isOverdue: Bool { Flipboard.isOverdue(due: shownDue, now: now) }
    private var tilt: Double { dipping ? -0.35 : side == .green ? 1 : -1 }
    private var fraction: Double { Flipboard.elapsedFraction(due: shownDue, rule: rule, now: now) }

    private var caption: String {
        guard let due = shownDue else { return "Not started" }
        switch side {
        case .green:
            let total = Flipboard.intervalDays(due: due, rule: rule)
            let done = Flipboard.elapsedDays(due: due, rule: rule, now: now)
            return "\(done) of \(total) \(total == 1 ? "day" : "days")"
        case .red:
            let late = Flipboard.daysOverdue(due: due, now: now)
            return late == 0 ? "Due today" : "\(late) \(late == 1 ? "day" : "days") overdue"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).smallCaps())
                        .tracking(0.6)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(rule.displayText.lowercased())
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                FlipLED(isOn: side == .red, pulsing: isOverdue && !reduceMotion)
            }

            Button(action: tapped) {
                RockerSwitch(tilt: tilt)
            }
            .buttonStyle(RockerPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel(task.title)
            .accessibilityValue(side == .red ? "Red, \(caption)" : "Green, \(caption)")
            .accessibilityHint(side == .red ? "Flips the switch back to green" : "Marks it done early")

            VStack(spacing: 5) {
                FlipLightBar(fraction: fraction, side: side)
                Text(caption)
                    .font(.caption2.monospacedDigit())
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
        #if os(iOS)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        #endif
        .contextMenu {
            Button { onEdit() } label: { Label("Edit Interval…", systemImage: "timer") }
            Button { onOpen() } label: { Label("Open Task", systemImage: "arrow.up.forward.square") }
            Divider()
            Button(role: .destructive) {
                withAnimation(.snappy) { Flipboard.remove(task, in: context) }
            } label: { Label("Remove from Flipboard", systemImage: "minus.circle") }
        }
        .confirmationDialog("Mark “\(task.title)” done early?", isPresented: $confirmEarly, titleVisibility: .visible) {
            Button("Mark Done") { flip() }
        } message: {
            if let due = task.dueDate {
                Text("It isn’t due until \(DueFormatter.text(for: due, hasTime: false, now: now)).")
            }
        }
        .onAppear { FlipHaptic.prepare() }
    }

    private func tapped() {
        guard !flipping else { return }
        if side == .red { flip() } else { confirmEarly = true }
    }

    private func flip() {
        let wasGreen = side == .green
        let spring: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.52)
        FlipHaptic.play()
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

/// Pressing the rocker sinks the whole switch a touch, like pushing real plastic.
private struct RockerPressStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Rectangle())
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
