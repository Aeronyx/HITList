import XCTest
import SwiftUI
import HITListCore
@testable import HITList

@MainActor
final class DesignSystemTests: XCTestCase {
    private var originalPalette: ThemePalette?

    // The colour checks below are written against Slate; pin it whatever theme this Mac has chosen
    // (without saving, so the real preference is untouched).
    override func setUp() {
        super.setUp()
        originalPalette = ThemeStore.shared.palette
        ThemeStore.shared.select(.slate, persist: false)
    }

    override func tearDown() {
        if let originalPalette { ThemeStore.shared.select(originalPalette, persist: false) }
        super.tearDown()
    }

    private func resolved(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }

    private func assertColor(_ a: Color, _ b: Color, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let x = resolved(a), y = resolved(b)
        XCTAssertEqual(x.red, y.red, accuracy: 0.002, message, file: file, line: line)
        XCTAssertEqual(x.green, y.green, accuracy: 0.002, message, file: file, line: line)
        XCTAssertEqual(x.blue, y.blue, accuracy: 0.002, message, file: file, line: line)
        XCTAssertEqual(x.opacity, y.opacity, accuracy: 0.002, message, file: file, line: line)
    }

    /// Renders a view offscreen, which evaluates every body in it. A crash or a nil image fails.
    private func render<V: View>(_ view: V, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let renderer = ImageRenderer(content: view.frame(width: 420).preferredColorScheme(.dark))
        XCTAssertNotNil(renderer.cgImage, "\(name) didn't render", file: file, line: line)
    }

    // MARK: - Instantiation

    func testEveryComponentRenders() {
        for kind in HITButtonStyle.Kind.allCases {
            for size in HITButtonStyle.Size.allCases {
                render(Button("Save") {}.buttonStyle(HITButtonStyle(kind, size: size)), "button \(kind) \(size)")
                render(Button("Save") {}.buttonStyle(HITButtonStyle(kind, size: size)).disabled(true), "disabled \(kind)")
            }
            render(Button {} label: { Image(systemName: "arrow.up") }.buttonStyle(HITButtonStyle(kind, shape: .circle)), "circle \(kind)")
        }
        render(Button {} label: { Image(systemName: "plus") }.buttonStyle(.hitIcon), "icon button")
        render(Toggle("On", isOn: .constant(true)).toggleStyle(.hit), "toggle on")
        render(Toggle("Off", isOn: .constant(false)).toggleStyle(.hit).disabled(true), "toggle off")
        render(HITSwitchTrack(isOn: true), "switch track")
        render(HITChipRow {
            HITChip("Today", systemImage: "calendar", tint: .green, isSelected: true) {}
            HITChip("@calls", onDismiss: {})
            HITChipLabel("P1", systemImage: "flag.fill", tint: Priority.p1.color)
        }, "chips")
        render(HITField("Name", text: .constant("x"), systemImage: "tag", clearable: true, isInvalid: true), "field")
        render(HITField("Notes", text: .constant(""), axis: .vertical), "multi-line field")
        render(TextField("q", text: .constant("today")).textFieldStyle(HITTextFieldStyle(isInvalid: true)), "text field style")
        render(HITSegmented(selection: .constant(Priority.p1), segments: Priority.allCases.map { HITSegment($0, "P\($0.rawValue)") }), "segmented")
        render(HITColorDots(selection: .constant("#12A594")), "colour dots")
        render(HITGroup("Group", footer: "Footer") {
            HITMenuRow("Row", systemImage: "gear", value: "Value") {}
            HITMenuRow("Read-only", value: "x")
            HITMenuRow("Trailing") { Text("•") }
        }, "group")
        render(HITSheetChrome("Title", isPrimaryEnabled: false, onPrimary: {}) { Text("Body") }, "sheet chrome")
        render(DesignSystemGallery().frame(height: 1400), "gallery")
        render(DesignSystemGalleryContent(), "gallery content")
        for role in HITMotion.Role.allCases { render(HITMotionSample(role: role), "motion sample \(role)") }
        render(Text("Glass").padding().hitGlass(in: Capsule()), "glass")
        render(Image(systemName: "plus").padding().hitGlass(in: Circle(), tint: Theme.accent, interactive: true), "tinted glass")
        render(Image(systemName: "checkmark.circle.fill").hitCelebratePop(trigger: 1), "celebrate pop")
    }

    func testGalleryAndAppearanceRenderInEveryTheme() {
        for palette in ThemePalette.all {
            ThemeStore.shared.select(palette, persist: false)
            render(DesignSystemGalleryContent(), "gallery in \(palette.name)")
            render(AppearanceSettingsSection(), "appearance in \(palette.name)")
            render(ThemeSwatch(palette: palette, isSelected: true), "swatch \(palette.name)")
        }
        render(ThemeSwatchRow(selection: .moss) { _ in }, "swatch row")
    }

    // MARK: - Motion

    func testEveryRoleArrivesWithin250msExceptCelebrate() {
        for role in HITMotion.Role.allCases where role != .celebrate {
            XCTAssertLessThanOrEqual(role.arrival, 0.25, "\(role) takes \(role.arrival)s")
        }
        XCTAssertEqual(HITMotion.Role.quick.arrival, 0.1)
        XCTAssertEqual(HITMotion.Role.standard.arrival, 0.15)
        XCTAssertEqual(HITMotion.Role.enter.arrival, 0.2)
        XCTAssertEqual(HITMotion.Role.exit.arrival, 0.15)
        XCTAssertEqual(HITMotion.Role.emphasis.arrival, 0.233, accuracy: 0.005)
    }

    func testEmphasisIsTheBriefsSpringAndBarelyOvershoots() {
        XCTAssertEqual(HITMotion.SpringSpec.emphasis.response, 0.28)
        XCTAssertEqual(HITMotion.SpringSpec.emphasis.damping, 0.8)
        XCTAssertLessThan(HITMotion.SpringSpec.emphasis.overshoot, 0.02, "under half a point on a 30 pt move")
        // Only the completion check may bounce, and even it stays modest.
        XCTAssertLessThan(HITMotion.SpringSpec.celebrate.overshoot, 0.15)
    }

    func testCelebrateIsCrisperAndNoSmallerThanBuildFive() {
        XCTAssertGreaterThanOrEqual(HITMotion.Celebrate.peakScale, 1.15, "build 5 popped to 1.15")
        XCTAssertLessThan(HITMotion.Celebrate.popDuration, 0.1, "build 5 took 100 ms to peak")
        XCTAssertLessThanOrEqual(HITMotion.Celebrate.totalDuration, 0.35)
    }

    func testEveryRoleHasAReduceMotionVariant() {
        for role in HITMotion.Role.allCases {
            XCTAssertNotNil(role.animation(reduceMotion: false), "\(role)")
        }
        XCTAssertNil(HITMotion.quick(reduceMotion: true))
        XCTAssertNil(HITMotion.standard(reduceMotion: true))
        XCTAssertNil(HITMotion.celebrate(reduceMotion: true))
        XCTAssertNotNil(HITMotion.enter(reduceMotion: true), "a short fade stands in for movement")
        XCTAssertNotNil(HITMotion.exit(reduceMotion: true))
        XCTAssertNotNil(HITMotion.emphasis(reduceMotion: true))
        XCTAssertEqual(HITMotion.emphasis(reduceMotion: false), HITMotion.emphasis)
    }

    func testReduceEffectsCalmsOnlyTheLargerMovements() {
        let calm = HITEffects(reduceEffects: true, reduceTransparency: false, reduceMotion: false)
        XCTAssertTrue(calm.calmMotion)
        XCTAssertEqual(calm.animation(.quick), HITMotion.quick, "hover fades stay")
        XCTAssertEqual(calm.animation(.standard), HITMotion.standard)
        XCTAssertEqual(calm.animation(.emphasis), HITMotion.Role.emphasis.reducedAnimation)
        XCTAssertNil(calm.animation(.celebrate))

        let systemReduceMotion = HITEffects(reduceEffects: false, reduceTransparency: false, reduceMotion: true)
        XCTAssertNil(systemReduceMotion.animation(.quick))
        XCTAssertEqual(systemReduceMotion.animation(.enter), HITMotion.Role.enter.reducedAnimation)

        let full = HITEffects()
        XCTAssertFalse(full.calmMotion)
        XCTAssertEqual(full.animation(.emphasis), HITMotion.emphasis)
    }

    // MARK: - Glass

    func testGlassIsOffUnderReduceEffectsOrReduceTransparencyAndOnOldSystems() {
        XCTAssertTrue(HITEffects.allowsGlass(osSupportsGlass: true, reduceEffects: false, reduceTransparency: false))
        XCTAssertFalse(HITEffects.allowsGlass(osSupportsGlass: true, reduceEffects: true, reduceTransparency: false))
        XCTAssertFalse(HITEffects.allowsGlass(osSupportsGlass: true, reduceEffects: false, reduceTransparency: true))
        XCTAssertFalse(HITEffects.allowsGlass(osSupportsGlass: false, reduceEffects: false, reduceTransparency: false))
        XCTAssertFalse(HITEffects(reduceEffects: true).allowsGlass)
        XCTAssertFalse(HITEffects(reduceTransparency: true).allowsGlass)
        XCTAssertEqual(HITEffects().allowsGlass, HITEffects.osSupportsGlass)
    }

    func testReduceEffectsKeyIsTheSharedOne() {
        // Session 20's chrome reads the same key; its meaning (true = no glass) is fixed.
        XCTAssertEqual(Preferences.reduceEffects, "pref.reduceEffects")
        XCTAssertEqual(AppearanceSettingsSection.footer,
                       "Turns off glass, blur and the larger movements. HITList also follows Reduce Motion and Reduce Transparency.")
    }

    // MARK: - Buttons

    func testPrimaryButtonDarkensEightPercentWhenPressedAndFadesWhenDisabled() {
        let rest = HITButtonStyle.Appearance(kind: .primary, isPressed: false, isHovered: false, isEnabled: true)
        let pressed = HITButtonStyle.Appearance(kind: .primary, isPressed: true, isHovered: false, isEnabled: true)
        let disabled = HITButtonStyle.Appearance(kind: .primary, isPressed: true, isHovered: true, isEnabled: false)
        assertColor(rest.fill, Theme.accent)
        assertColor(rest.foreground, HITColor.onAccent)
        assertColor(pressed.fill, Theme.accent.darkened(by: 0.08))
        // Each sRGB channel drops by 8%: the accent's green 0x9E → 0x91.
        XCTAssertEqual(Double(resolved(pressed.fill).green), 0x9E / 255.0 * 0.92, accuracy: 0.002)
        XCTAssertEqual(rest.opacity, 1)
        XCTAssertEqual(disabled.opacity, 0.35)
        assertColor(disabled.fill, Theme.accent, "disabled ignores press and hover")
    }

    func testEveryKindIsDimmedWhenDisabled() {
        for kind in HITButtonStyle.Kind.allCases {
            XCTAssertEqual(HITButtonStyle.Appearance(kind: kind, isPressed: false, isHovered: false, isEnabled: false).opacity, 0.35)
        }
    }

    func testDestructiveIsAnOutlineThatFillsOnHoverAndPress() {
        let rest = HITButtonStyle.Appearance(kind: .destructive, isPressed: false, isHovered: false, isEnabled: true)
        let hover = HITButtonStyle.Appearance(kind: .destructive, isPressed: false, isHovered: true, isEnabled: true)
        let pressed = HITButtonStyle.Appearance(kind: .destructive, isPressed: true, isHovered: false, isEnabled: true)
        XCTAssertEqual(resolved(rest.fill).opacity, 0)
        assertColor(rest.border, HITColor.danger)
        assertColor(rest.foreground, HITColor.danger)
        assertColor(hover.fill, HITColor.danger)
        assertColor(hover.foreground, HITColor.onAccent)
        assertColor(pressed.fill, HITColor.danger.darkened(by: 0.08))
    }

    func testSecondaryIsOutlinedAndGhostHasNoBorder() {
        let secondary = HITButtonStyle.Appearance(kind: .secondary, isPressed: false, isHovered: false, isEnabled: true)
        assertColor(secondary.border, Theme.separator)
        assertColor(secondary.foreground, Theme.secondaryText)
        XCTAssertEqual(resolved(secondary.fill).opacity, 0)
        let ghost = HITButtonStyle.Appearance(kind: .ghost, isPressed: false, isHovered: false, isEnabled: true)
        XCTAssertEqual(resolved(ghost.border).opacity, 0)
        XCTAssertEqual(resolved(ghost.fill).opacity, 0)
        let ghostHover = HITButtonStyle.Appearance(kind: .ghost, isPressed: false, isHovered: true, isEnabled: true)
        assertColor(ghostHover.fill, Theme.elevated)
    }

    func testButtonSizes() {
        XCTAssertEqual(HITButtonStyle.Size.regular.height, 34)
        XCTAssertEqual(HITButtonStyle.Size.small.height, 28)
    }

    func testDarkenedByZeroIsUnchanged() {
        assertColor(Theme.accent.darkened(by: 0), Theme.accent)
        assertColor(Theme.accent.darkened(by: 1), .black)
    }

    // MARK: - Toggle

    func testToggleThumbSitsInsideTheTrackAtEachEnd() {
        let track = HITToggleStyle.trackSize
        XCTAssertEqual(track, CGSize(width: 42, height: 24))
        XCTAssertEqual(HITToggleStyle.thumbDiameter, 20)
        XCTAssertEqual(HITToggleStyle.thumbOffset(isOn: true), 9)
        XCTAssertEqual(HITToggleStyle.thumbOffset(isOn: false), -9)
        // A 2 pt inset on each side, the same as top and bottom.
        let inset = track.width / 2 - (HITToggleStyle.thumbOffset(isOn: true) + HITToggleStyle.thumbDiameter / 2)
        XCTAssertEqual(inset, (track.height - HITToggleStyle.thumbDiameter) / 2)
    }

    // MARK: - Chips

    func testSelectedChipFillsWithItsTint() {
        let plain = HITChipAppearance(tint: .green, isSelected: false, isHovered: false)
        let selected = HITChipAppearance(tint: .green, isSelected: true, isHovered: false)
        XCTAssertEqual(resolved(plain.fill).opacity, 0)
        assertColor(plain.border, Theme.separator)
        assertColor(plain.label, Theme.secondaryText)
        assertColor(selected.fill, Color.green.opacity(0.16))
        assertColor(selected.label, .green)
        let untinted = HITChipAppearance(tint: nil, isSelected: true, isHovered: false)
        assertColor(untinted.label, Theme.accent)
    }

    func testFlowLayoutWrapsWhenTheNextItemDoesNotFit() {
        let item = CGSize(width: 100, height: 28)
        let (frames, size) = HITFlowLayout.arrange([item, item, item], maxWidth: 250, spacing: 6, lineSpacing: 8)
        XCTAssertEqual(frames.map(\.origin), [CGPoint(x: 0, y: 0), CGPoint(x: 106, y: 0), CGPoint(x: 0, y: 36)])
        XCTAssertEqual(size, CGSize(width: 206, height: 64))

        let oneLine = HITFlowLayout.arrange([item, item, item], maxWidth: nil, spacing: 6, lineSpacing: 8)
        XCTAssertEqual(oneLine.size, CGSize(width: 312, height: 28))

        let exact = HITFlowLayout.arrange([item, item], maxWidth: 206, spacing: 6, lineSpacing: 8)
        XCTAssertEqual(exact.size.height, 28, "exactly fitting items stay on one line")

        let wide = HITFlowLayout.arrange([CGSize(width: 500, height: 20), item], maxWidth: 300, spacing: 6, lineSpacing: 8)
        XCTAssertEqual(wide.frames[0].width, 300, "an item wider than the row is narrowed to it")
        XCTAssertEqual(wide.frames[1].origin, CGPoint(x: 0, y: 28))

        XCTAssertEqual(HITFlowLayout.arrange([], maxWidth: 100, spacing: 6, lineSpacing: 6).size, .zero)
    }

    // MARK: - Colour dots

    func testColorDotsShowEightColoursAndKeepAnOffPaletteSelectionVisible() {
        let palette = HITColorDots.defaultPalette
        XCTAssertEqual(palette.count, 8)
        XCTAssertEqual(HITColorDots.dots(for: palette[2].hex.lowercased(), palette: palette).count, 8, "match is case-insensitive")
        let teal = HITColorDots.dots(for: "#12A594", palette: palette)
        XCTAssertEqual(teal.count, 9)
        XCTAssertEqual(teal.last?.name, "Teal")
        XCTAssertEqual(HITColorDots.dots(for: "#123456", palette: palette).last?.name, "Current colour")
    }
}
