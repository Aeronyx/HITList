import SwiftUI
import SwiftData
import HITListCore

/// One switch on the wall: title in small caps, the LED, the rocker, and the light bar.
///
/// Tapping a red switch flips it back to green by completing the task.
struct FlipSwitchTile: View {
    let task: TaskItem
    let now: Date

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rule: RecurrenceRule { task.recurrenceRule ?? Flipboard.defaultRule }
    private var shownDue: Date? { task.dueDate }
    private var side: Flipboard.Side { Flipboard.side(due: shownDue, now: now) }
    private var isOverdue: Bool { Flipboard.isOverdue(due: shownDue, now: now) }
    private var tilt: Double { side == .green ? 1 : -1 }
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
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(side == .red ? "Red, \(caption)" : "Green, \(caption)")
            .accessibilityHint(side == .red ? "Flips the switch back to green" : "")

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
    }

    private func tapped() {
        guard side == .red else { return }
        withAnimation(.snappy(duration: 0.35)) { Flipboard.flip(task, in: context) }
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
