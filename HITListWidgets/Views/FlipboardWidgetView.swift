import SwiftUI
import WidgetKit
import HITListCore

/// The Flipboard widget (brief 74): the board as a status check. The loose switches or one Switchboard (chosen in the
/// widget's settings), its line ("Daily · resets 4:00 AM · 2 of 4"), then each switch as a small pill with its name,
/// green or red exactly as the board judges it at that minute (`WidgetContent.flipboard`). No counts of what is late:
/// the Flipboard is a calm status check. A tap opens the Flipboard.
///
/// Brief 81: a red pill flips its switch (`WidgetCompletionIntent`, the same road and the same waiting as a row's
/// check); until iCloud has the flip it is drawn flipping, green and dimmed. A green pill does nothing but open the
/// Flipboard, like the rest of the widget.
struct FlipboardWidgetView: View {
    let snapshot: WidgetSnapshot?
    /// The Switchboard chosen in the widget's settings; nil for the loose switches.
    let boardID: UUID?
    let now: Date
    let family: WidgetFamily
    /// The taps in the outbox, as the extension read them with the snapshot.
    var requests: [WidgetRequest] = []
    @Environment(\.widgetPalette) private var palette
    @Environment(\.widgetOffscreen) private var offscreen

    private var marks: WidgetContent.Marks? {
        snapshot.map { WidgetContent.marks($0, requests: requests, at: now) }
    }

    private var board: WidgetContent.Flipboard? {
        marks.map { WidgetContent.flipboard($0.snapshot, board: boardID, at: now) }
    }

    static let kind = "flipboard"

    var body: some View {
        let marks = marks
        VStack(alignment: .leading, spacing: WidgetLook.headerGap) {
            header
            if let board {
                if board.lights.isEmpty {
                    WidgetNote(text: board.boardID == nil ? "No loose switches." : "No switches on this board yet.")
                } else {
                    FlipboardPills(lights: board.lights, flipping: marks?.checked ?? [], interactive: !offscreen)
                }
                if let note = marks?.note {
                    Spacer(minLength: 0)
                    WidgetQuietLine(note: note, now: now)
                }
            } else {
                WidgetNote(text: WidgetEmpty.openOnce)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.flipboard.url)
    }

    /// The board's name; under it its line and count ("Daily · resets 4:00 AM · 2 of 4"). A small widget has no room
    /// for both on one line, so its count stands at the end of the name's line.
    private var header: some View {
        let small = family == .systemSmall
        let line = small ? board?.line : board?.summary
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !small {
                    Image(systemName: "switch.2")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .widgetAccentable()
                }
                Text(board?.title ?? WidgetContent.looseTitle)
                    .font(WidgetLook.header)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                if small, let board, !board.lights.isEmpty {
                    Spacer(minLength: 4)
                    // Compact, as a row's checklist count ("2/5"): "2 of 4" crowds the name out of a small widget.
                    Text("\(board.done)/\(board.lights.count)")
                        .font(WidgetLook.section.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize()
                }
            }
            if let line, !line.isEmpty {
                Text(line)
                    .font(WidgetLook.section.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// The board's two lights (`FlipboardPalette.ledOn` and `.ledGreen`, in the Flipboard's own files);
/// WidgetFlipboardTests fails if these ever differ from the board's.
enum WidgetLights {
    static let red = Color(hex: "#FF4D4F")
    static let green = Color(hex: "#4BEA8F")

    static func color(_ side: FlipboardSwitch.Side) -> Color { side == .green ? green : red }
}

/// The switches as pills, flowing onto as many lines as fit; the rest become one "+N" pill. Each pill sits in a frame
/// `WidgetLook.pillTargetInset` larger on every side, the flow's spacing, so a red pill's button is the minimum target.
struct FlipboardPills: View {
    let lights: [WidgetContent.Flipboard.Light]
    /// Switches whose flip is on its way (`WidgetContent.Marks.checked`).
    var flipping: Set<UUID> = []
    /// A red pill is a button; false in the hosted tests' renders.
    var interactive = false

    var body: some View {
        let inset = WidgetLook.pillTargetInset
        ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: lights.count, through: 1, by: -1)), id: \.self) { shown in
                WidgetFlowLayout(spacing: 0, lineSpacing: 0) {
                    ForEach(lights.prefix(shown)) { light in
                        FlipboardPillButton(light: light, flipping: flipping.contains(light.id), interactive: interactive)
                    }
                    if shown < lights.count { FlipboardMorePill(count: lights.count - shown).padding(inset) }
                }
            }
        }
        .padding(-inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A pill and its target: a red one flips its switch; a flipping or green one is drawn only.
struct FlipboardPillButton: View {
    let light: WidgetContent.Flipboard.Light
    var flipping = false
    var interactive = false

    var body: some View {
        let pill = FlipboardPill(light: light, flipping: flipping)
            .padding(WidgetLook.pillTargetInset)
            .contentShape(Rectangle())
        if interactive, light.side == .red, !flipping {
            Button(intent: WidgetCompletionIntent(task: light.task, action: .flip, widget: FlipboardWidgetView.kind)) { pill }
                .buttonStyle(.plain)
                .accessibilityLabel("Flip \(light.task.title)")
        } else {
            pill
        }
    }
}

/// One switch: a small capsule in its light's colour with the switch's name, the board's light at its start. Flipping
/// (brief 81): green, dimmed, until iCloud has the flip.
struct FlipboardPill: View {
    let light: WidgetContent.Flipboard.Light
    var flipping = false
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let side: FlipboardSwitch.Side = flipping ? .green : light.side
        let color = WidgetLights.color(side)
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 6, height: 6)
                .shadow(color: color.opacity(side == .red ? 0.6 : 0.3), radius: 2)
                .widgetAccentable()
            Text(light.task.title)
                .font(WidgetLook.pill)
                .foregroundStyle(palette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: WidgetLook.pillHeight)
        .background(Capsule().fill(color.opacity(side == .red ? 0.2 : 0.13)))
        .overlay(Capsule().strokeBorder(color.opacity(side == .red ? 0.45 : 0.3), lineWidth: 1))
        .opacity(flipping ? WidgetLook.pendingOpacity : 1)
        .frame(maxWidth: WidgetLook.pillMaxWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .privacySensitive()
        .accessibilityLabel("\(light.task.title), \(flipping ? "flipping" : side == .green ? "done" : "to do")")
    }
}

private struct FlipboardMorePill: View {
    let count: Int
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        Text("+\(count)")
            .font(WidgetLook.pill.monospacedDigit())
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: WidgetLook.pillHeight)
            .background(Capsule().fill(palette.elevated))
    }
}

/// Items left to right, onto a new line when the next doesn't fit; an item wider than the line gets the line's width.
struct WidgetFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(line.indices, line.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width { size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            let end = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            if !line.indices.isEmpty, end > width {
                lines.append(line)
                line = Line()
            }
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.indices.append(index)
            line.sizes.append(size)
            line.height = max(line.height, size.height)
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }
}
