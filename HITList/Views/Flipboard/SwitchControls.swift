import SwiftUI
#if os(macOS)
import AppKit
#endif

/// One detent of the switch card's controls (brief 69: "tactile without being annoying"): the selection tick on
/// iPhone (`TapHaptic`), the trackpad's alignment click on the Mac. Silent: the flip sound is for flips.
@MainActor
enum SwitchDetent {
    static func prepare() {
        TapHaptic.prepareSelection()
    }

    static func tick() {
        #if os(iOS)
        TapHaptic.selectionChanged()
        #else
        guard CompletionFeedback.shared.areHapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
}

/// The switch card's quick choices (brief 69): Daily, 3 days, Weekly, 2 weeks, Monthly in one capsule track, the
/// chosen one under a highlight that slides between them. It is one control: a press anywhere picks the choice
/// under the finger (or pointer), and sliding along the strip carries the highlight with it, a detent at each
/// choice. None is lit for an interval that isn't one of them.
struct IntervalChoiceStrip: View {
    /// The lit choice; nil when the interval is none of them.
    let selected: FlipInterval.Choice?
    var onChoose: (FlipInterval.Choice) -> Void

    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    /// The choice under a press, while the press lasts (it sinks a touch).
    @State private var pressed: Int?

    private static let choices = FlipInterval.quickChoices
    private static let inset: CGFloat = 2

    /// Which of `count` equal segments `x` falls in, clamped to the strip.
    static func index(at x: CGFloat, width: CGFloat, count: Int) -> Int {
        guard width > 0, count > 0 else { return 0 }
        return min(count - 1, max(0, Int((x / width) * CGFloat(count))))
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.choices.enumerated()), id: \.element.id) { index, choice in
                segment(choice, index: index)
            }
        }
        .padding(Self.inset)
        .background(Capsule().fill(Theme.elevated))
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * Self.inset } action: { width = $0 }
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let index = Self.index(at: drag.location.x - Self.inset, width: width, count: Self.choices.count)
                    if pressed != index {
                        withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { pressed = index }
                    }
                    choose(Self.choices[index])
                }
                .onEnded { _ in
                    withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { pressed = nil }
                }
        )
        .onAppear(perform: SwitchDetent.prepare)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interval")
    }

    private func segment(_ choice: FlipInterval.Choice, index: Int) -> some View {
        let isSelected = choice == selected
        return Text(choice.title)
            .font(HITType.control)
            .foregroundStyle(isSelected ? HITColor.text : Theme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background {
                if isSelected {
                    Capsule().fill(Theme.surface)
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "choice", in: highlight)
                }
            }
            .scaleEffect(pressed == index && !reduceMotion ? 0.95 : 1)
            .accessibilityElement()
            .accessibilityLabel(choice.title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { choose(choice) }
            .accessibilityIdentifier("switchChoice-\(choice.title)")
    }

    private func choose(_ choice: FlipInterval.Choice) {
        guard choice != selected else { return }
        SwitchDetent.tick()
        withAnimation(HITMotion.emphasis(reduceMotion: reduceMotion)) { onChoose(choice) }
    }
}

/// A small number you can turn like a thumbwheel: "‹ 3 ›" in a capsule with a ruler of ticks behind the number.
/// Drag it sideways or up and down and it moves a detent every `stepLength`, the ticks sliding under the finger
/// and a detent haptic at each step (`SwitchDetent`); on the Mac a scroll over it turns it too; the chevrons step
/// by one. The switch card's interval and flips (brief 69).
struct FlipDial: View {
    let value: Int
    let range: ClosedRange<Int>
    /// What VoiceOver calls it: "Every", "Flips per interval".
    let accessibilityName: String
    /// The dial moved `delta` detents (the owner clamps).
    var onStep: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Detents already applied by the drag in progress.
    @State private var dragSteps = 0
    /// The drag's travel past its last detent, for the ticks.
    @State private var tickOffset: CGFloat = 0
    @State private var isDragging = false
    #if os(macOS)
    @State private var scroll = DialScrollMonitor()
    #endif

    static let size = CGSize(width: 84, height: 30)
    /// The drag that moves one detent.
    static let stepLength: CGFloat = 16
    private static let tickSpacing: CGFloat = 6

    /// Detents for a drag that has travelled `translation`: along its stronger axis, right or up being more.
    static func steps(for translation: CGSize) -> Int {
        let along = abs(translation.width) >= abs(translation.height) ? translation.width : -translation.height
        return Int(along / stepLength)
    }

    var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", delta: -1, enabled: value > range.lowerBound)
            Text("\(value)")
                .font(HITType.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(HITColor.text)
                .contentTransition(.numericText(value: Double(value)))
                .animation(HITMotion.quick(reduceMotion: reduceMotion), value: value)
                .frame(maxWidth: .infinity)
                .frame(height: Self.size.height)
                .background { ticks }
                .contentShape(Rectangle())
                .gesture(drag)
            chevron("chevron.right", delta: 1, enabled: value < range.upperBound)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Capsule().fill(Theme.elevated))
        .overlay(Capsule().strokeBorder(isDragging ? Theme.accent.opacity(0.6) : Theme.separator, lineWidth: 1))
        .scaleEffect(isDragging && !reduceMotion ? 1.04 : 1)
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isDragging)
        #if os(macOS)
        .onHover { scroll.isHovering = $0 }
        // The monitor steps from the value on show now, not the one it started with.
        .onChange(of: value, initial: true) { scroll.onStep = { step($0) } }
        .onAppear { scroll.start() }
        .onDisappear { scroll.stop() }
        #endif
        .onAppear(perform: SwitchDetent.prepare)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    /// The ruler behind the number: fine ticks that slide with the drag and fade towards the ends.
    private var ticks: some View {
        Canvas { context, size in
            let spacing = Self.tickSpacing
            var x = (tickOffset.truncatingRemainder(dividingBy: spacing) + spacing).truncatingRemainder(dividingBy: spacing)
            while x < size.width {
                let fade = 1 - abs(x - size.width / 2) / (size.width / 2)
                let rect = CGRect(x: x - 0.5, y: size.height - 7, width: 1, height: 4)
                context.fill(Path(rect), with: .color(Theme.secondaryText.opacity(0.35 * fade)))
                x += spacing
            }
        }
        .opacity(isDragging ? 1 : 0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { drag in
                if !isDragging { isDragging = true; dragSteps = 0 }
                let steps = Self.steps(for: drag.translation)
                let along = abs(drag.translation.width) >= abs(drag.translation.height) ? drag.translation.width : -drag.translation.height
                tickOffset = along
                if steps != dragSteps {
                    step(steps - dragSteps)
                    dragSteps = steps
                }
            }
            .onEnded { _ in
                isDragging = false
                dragSteps = 0
                withAnimation(HITMotion.quick(reduceMotion: reduceMotion)) { tickOffset = 0 }
            }
    }

    /// Moves the dial and ticks once per detent that actually changes the value.
    private func step(_ delta: Int) {
        let target = min(range.upperBound, max(range.lowerBound, value + delta))
        guard target != value else { return }
        SwitchDetent.tick()
        onStep(target - value)
    }

    private func chevron(_ symbol: String, delta: Int, enabled: Bool) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: Self.size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(HITIconButtonStyle(font: .system(size: 10, weight: .bold)))
        .disabled(!enabled)
    }
}

/// Turns scroll-wheel and trackpad scrolling into dial detents (the Mac). A trackpad's fine deltas add up to a
/// detent every `preciseStep` points; a mouse wheel's notch is one detent. Fingers or wheel moving up is more,
/// whichever way the system's scrolling direction is set (`inverted`: natural scrolling).
struct DialScrollDetents {
    static let preciseStep: CGFloat = 12
    private var travel: CGFloat = 0

    mutating func add(deltaY: CGFloat, precise: Bool, inverted: Bool) -> Int {
        let physical = inverted ? -deltaY : deltaY
        guard precise else {
            guard physical != 0 else { return 0 }
            let notches = max(1, Int(abs(physical).rounded()))
            return physical > 0 ? notches : -notches
        }
        // Turning back starts afresh: what was left of a detent the other way doesn't hold the dial up.
        if travel * physical < 0 { travel = 0 }
        travel += physical
        let steps = Int(travel / Self.preciseStep)
        travel -= CGFloat(steps) * Self.preciseStep
        return steps
    }
}

#if os(macOS)
/// Listens for scrolling while the pointer is over a dial and turns it into detents; the scroll is the dial's
/// then, not the board's.
@MainActor
final class DialScrollMonitor {
    var isHovering = false
    var onStep: (Int) -> Void = { _ in }
    private var monitor: Any?
    private var detents = DialScrollDetents()

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isHovering else { return event }
                let steps = self.detents.add(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
                if steps != 0 { self.onStep(steps) }
                return nil
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
#endif

/// The card's little preview (brief 69): the switch's rocker, small and green, with a charger's lamps over it.
/// A tap flips it, with the board's own click and bump, and back again; nothing is saved.
struct SwitchPreviewRocker: View {
    let flips: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isGreen = true

    static let size = CGSize(width: 30, height: 44)

    /// A lamp over the rocker (glass; its bezel adds a little).
    private static let lampSize: CGFloat = 5

    var body: some View {
        RockerSwitch(tilt: isGreen ? 1 : -1, size: Self.size)
            // Over the rocker, outside the layout: the card's controls never move as the count changes. One
            // lamp per flip, each popping in as the count goes up (the tile's charger lamps, small).
            .overlay(alignment: .topTrailing) {
                if flips > 1 {
                    HStack(spacing: 2) {
                        ForEach(0..<flips, id: \.self) { _ in
                            FlipLamp(green: isGreen ? 0.9 : 0, greenBloom: isGreen ? 0.35 : 0, ember: isGreen ? 0 : 0.16,
                                     size: Self.lampSize)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(FlipboardPalette.bezelTop))
                    .fixedSize()
                    .offset(y: -(Self.lampSize * 1.4 + 8))
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .animation(HITMotion.emphasis(reduceMotion: reduceMotion), value: flips)
            .contentShape(Rectangle())
            .onTapGesture(perform: flip)
            .onAppear { FlipHaptic.prepare() }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Preview switch")
            .accessibilityValue(isGreen ? "Green" : "Red")
            .accessibilityAction { flip() }
            .accessibilityIdentifier("switchPreview")
    }

    private func flip() {
        FlipHaptic.play()
        FlipSound.play()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.52)) {
            isGreen.toggle()
        }
    }
}
