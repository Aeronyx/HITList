import SwiftUI

// Liquid Glass, used as a highlight and never as a wallpaper. One helper, `hitGlass(in:tint:)`, so the
// design-system components and the iPhone chrome (tab island, "+", quick-add card) read as one material:
// glass on iOS 26 / macOS 26 when effects are allowed, the slate fill everywhere else.

/// The three switches that decide how much glass and movement HITList shows: the app's own Reduce Effects
/// (`Preferences.reduceEffects`, Settings → Appearance) and the system's Reduce Transparency and Reduce
/// Motion. Read it in a view with `@HITEffectsSetting private var effects`.
struct HITEffects: Equatable {
    var reduceEffects = false
    var reduceTransparency = false
    var reduceMotion = false

    /// Whether glass may be drawn on this OS. iOS 26 / macOS 26 (call sites still need `#available`).
    static var osSupportsGlass: Bool {
        if #available(iOS 26, macOS 26, *) { return true }
        return false
    }

    /// The glass decision, pure so tests can check it: the OS has glass, and neither Reduce Effects nor
    /// Reduce Transparency is on.
    static func allowsGlass(osSupportsGlass: Bool, reduceEffects: Bool, reduceTransparency: Bool) -> Bool {
        osSupportsGlass && !reduceEffects && !reduceTransparency
    }

    var allowsGlass: Bool {
        Self.allowsGlass(osSupportsGlass: Self.osSupportsGlass, reduceEffects: reduceEffects,
                         reduceTransparency: reduceTransparency)
    }

    /// True turns the larger movements (`enter`, `exit`, `emphasis`, `celebrate`) into their calm
    /// variants: Reduce Motion, or Reduce Effects ("calmer motion").
    var calmMotion: Bool { reduceMotion || reduceEffects }

    /// The animation for a role under these settings: `quick` and `standard` follow Reduce Motion only
    /// (they are fades, not movement); the rest also calm down under Reduce Effects.
    func animation(_ role: HITMotion.Role) -> Animation? {
        switch role {
        case .quick, .standard: role.animation(reduceMotion: reduceMotion)
        case .enter, .exit, .emphasis, .celebrate: role.animation(reduceMotion: calmMotion)
        }
    }
}

/// Reads `HITEffects` from the environment and the Reduce Effects preference, and updates the view when
/// any of them changes.
///
///     @HITEffectsSetting private var effects
///     … .animation(effects.animation(.emphasis), value: isOn)
@propertyWrapper
struct HITEffectsSetting: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(Preferences.reduceEffects, store: AppGroup.defaults) private var reduceEffects = false

    init() {}

    var wrappedValue: HITEffects {
        HITEffects(reduceEffects: reduceEffects, reduceTransparency: reduceTransparency, reduceMotion: reduceMotion)
    }
}

/// The shadow under a slate fallback (glass draws its own depth): the iPhone chrome's three weights.
struct HITGlassShadow: Equatable {
    var opacity: Double
    var radius: CGFloat
    var y: CGFloat

    static let chrome = HITGlassShadow(opacity: 0.35, radius: 16, y: 6)
    static let addButton = HITGlassShadow(opacity: 0.4, radius: 10, y: 4)
    static let card = HITGlassShadow(opacity: 0.45, radius: 24, y: 8)
}

/// `hitGlass(in:tint:)`: see the extension below.
struct HITGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = false
    /// The slate fill when glass is off. Nil: the tint (a tinted control stays that colour), else `Theme.surface`.
    var fallback: Color?
    /// A shadow under the slate fill only (floating chrome keeps its lift without glass).
    var fallbackShadow: HITGlassShadow?
    @HITEffectsSetting private var effects

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            if effects.allowsGlass {
                content.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
            } else {
                slate(content)
            }
        } else {
            slate(content)
        }
    }

    private func slate(_ content: Content) -> some View {
        content.background {
            if let fallbackShadow {
                shape.fill(fallback ?? tint ?? Theme.surface)
                    .shadow(color: .black.opacity(fallbackShadow.opacity), radius: fallbackShadow.radius, y: fallbackShadow.y)
            } else {
                shape.fill(fallback ?? tint ?? Theme.surface)
            }
        }
    }

    @available(iOS 26, macOS 26, *)
    static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// Liquid Glass in `shape` on iOS 26 / macOS 26 when effects are allowed (Reduce Effects and Reduce
    /// Transparency off); otherwise the slate fill: `fallback`, else the tint, else `Theme.surface`.
    /// `interactive` lets the glass react to touches (buttons, the "+").
    ///
    ///     header.hitGlass(in: Rectangle())
    ///     plus.hitGlass(in: Circle(), tint: Theme.accent, interactive: true)
    ///     highlight.hitGlass(in: Capsule(), fallback: Theme.separator)
    func hitGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false, fallback: Color? = nil,
                            fallbackShadow: HITGlassShadow? = nil) -> some View {
        modifier(HITGlassModifier(shape: shape, tint: tint, interactive: interactive, fallback: fallback,
                                  fallbackShadow: fallbackShadow))
    }
}

/// Neighbouring glass shapes (the iPhone's island and "+") rendered together: a `GlassEffectContainer`
/// on iOS 26 / macOS 26, a plain wrapper before. `spacing` below the gap between them keeps them separate.
struct HITGlassContainer<Content: View>: View {
    var spacing: CGFloat = HITSpacing.s
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
