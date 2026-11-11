import SwiftUI

/// A sheet whose pages open inside it (brief 86: iPhone and iPad Settings). The first screen sits under the
/// sheet's bar (its title centred, the primary action on the right, as `HITSheetChrome`); a page pushes in from the
/// trailing edge over it and the bar says where you are: "‹ Settings" on the left (back), the page's title in the
/// middle, the primary action still on the right. Never a second sheet.
///
/// Motion: a page arrives on `enter` (200 ms ease-out) and leaves on `exit` (150 ms ease-in), the screen under it
/// drifting a third of the way left and back; Reduce Motion (or Reduce Effects) makes both a plain crossfade. A
/// swipe from the leading edge takes a page back, following the finger; let go past a third of the width (or with a
/// flick) and it goes, otherwise it settles back. Esc (a hardware keyboard), the back control and VoiceOver's
/// two-finger scrub go back too.
///
///     HITSheetPages("Settings", path: $path, title: \.title, onPrimary: { dismiss() }) {
///         HITGroup { HITMenuRow("General", systemImage: "gearshape") { path.append(.general) } }
///     } destination: { page in
///         page.content
///     }
///
/// Inside, any view can open a page with `@Environment(\.hitPages) private var pages` and `pages.open(page)`.
struct HITSheetPages<Page: Hashable, Root: View, Destination: View>: View {
    let title: String
    @Binding var path: [Page]
    let pageTitle: (Page) -> String
    /// The back control's words on a page opened from `page` (nil: the first screen's `title`).
    var backTitle: (Page) -> String
    var primaryTitle = "Done"
    var background: Color = Theme.background
    let onPrimary: () -> Void
    @ViewBuilder var root: Root
    @ViewBuilder var destination: (Page) -> Destination

    init(_ title: String, path: Binding<[Page]>, title pageTitle: @escaping (Page) -> String,
         backTitle: ((Page) -> String)? = nil, primaryTitle: String = "Done", background: Color = Theme.background,
         onPrimary: @escaping () -> Void, @ViewBuilder root: () -> Root,
         @ViewBuilder destination: @escaping (Page) -> Destination) {
        self.title = title
        _path = path
        self.pageTitle = pageTitle
        self.backTitle = backTitle ?? pageTitle
        self.primaryTitle = primaryTitle
        self.background = background
        self.onPrimary = onPrimary
        self.root = root()
        self.destination = destination
    }

    @HITEffectsSetting private var effects
    /// How far the top page has been dragged towards the trailing edge by the edge swipe.
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    /// VoiceOver's place: on the bar's title when a page opens or closes (brief 94), so it starts at the top of
    /// the page it is on rather than wherever the last page left it.
    @AccessibilityFocusState private var titleFocused: Bool

    /// From the leading edge, where a drag takes the page back (the cards start 16 pt in; this stays in the gutter).
    static var edgeWidth: CGFloat { 20 }
    /// How far the screen under a page drifts left, as a share of the width.
    static var coveredShift: CGFloat { 0.3 }
    /// Let go past this share of the width (or with a flick past half) and the page goes back.
    static var popThreshold: CGFloat { 1.0 / 3.0 }

    /// Whether a drag that ended `translation` along with a predicted end of `predicted` takes the page back.
    static func popsBack(translation: CGFloat, predicted: CGFloat, width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        return translation > width * popThreshold || predicted > width * 0.5
    }

    /// The screen under the top page: shifted left by `coveredShift` of the width, less as the top page is dragged away.
    static func coveredOffset(width: CGFloat, drag: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let progress = min(max(drag / width, 0), 1)
        return -width * coveredShift * (1 - progress)
    }

    private var slides: Bool { !effects.calmMotion }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            pages(width: width)
                .modifier(BarModifier(effects: effects, background: background, bar: { bar }))
        }
        .background(background)
        .foregroundStyle(HITColor.text)
        .environment(\.hitPages, HITPagesAction(open: { open($0) }, back: back))
    }

    // MARK: Pages

    private struct Entry: Hashable {
        let level: Int
        let page: Page
    }

    private var entries: [Entry] { path.enumerated().map { Entry(level: $0.offset + 1, page: $0.element) } }

    @ViewBuilder
    private func pages(width: CGFloat) -> some View {
        let top = path.count
        ZStack(alignment: .topLeading) {
            screen { root }
                .offset(x: offset(level: 0, top: top, width: width))
                .allowsHitTesting(top == 0)
                // `isEnabled`, never `accessibilityHidden(false)`: false un-hides everything inside (brief 94: the edge
                // strip below, hidden, was an unnamed VoiceOver stop on every page).
                .accessibilityHidden(true, isEnabled: top != 0)
            ForEach(entries, id: \.self) { entry in
                screen { destination(entry.page) }
                    .overlay(alignment: .leading) {
                        // The leading edge's shadow while the page is moving, so it reads as lying on top.
                        LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .trailing, endPoint: .leading)
                            .frame(width: 8)
                            .offset(x: -8)
                            .opacity(slides ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .leading) {
                        if entry.level == top { edgeSwipe(width: width) }
                    }
                    .offset(x: offset(level: entry.level, top: top, width: width))
                    .allowsHitTesting(entry.level == top)
                    .accessibilityHidden(true, isEnabled: entry.level != top)
                    .accessibilityAction(.escape) { back() }
                    .transition(slides ? .move(edge: .trailing) : .opacity)
                    .zIndex(Double(entry.level))
            }
        }
        .frame(width: width)
    }

    private func offset(level: Int, top: Int, width: CGFloat) -> CGFloat {
        guard slides else { return 0 }
        if level == top { return top == 0 ? 0 : dragOffset }
        if level == top - 1 { return Self.coveredOffset(width: width, drag: dragOffset) }
        return -width * Self.coveredShift
    }

    private func screen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HITSpacing.xl) { content() }
                .padding(HITSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .modifier(SoftTopEdge(effects: effects))
        .background(background)
    }

    /// A strip along the leading edge: dragging it right takes the page back.
    private func edgeSwipe(width: CGFloat) -> some View {
        Color.clear
            .frame(width: Self.edgeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { value in
                        guard slides else { return }
                        if !isDragging {
                            // Only a mostly sideways drag; an upward one is the scroll's.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            isDragging = true
                        }
                        dragOffset = max(0, value.translation.width)
                    }
                    .onEnded { value in
                        defer { isDragging = false }
                        guard slides else {
                            if value.translation.width > width * Self.popThreshold { back() }
                            return
                        }
                        guard isDragging else { return }
                        if Self.popsBack(translation: value.translation.width,
                                         predicted: value.predictedEndTranslation.width, width: width) {
                            withAnimation(effects.animation(.exit)) {
                                dragOffset = width
                            } completion: {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    if !path.isEmpty { path.removeLast() }
                                    dragOffset = 0
                                }
                            }
                        } else {
                            withAnimation(effects.animation(.enter)) { dragOffset = 0 }
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    private func open(_ page: AnyHashable) {
        guard let page = page.base as? Page else { return }
        withAnimation(effects.animation(.enter)) { path.append(page) }
    }

    private func back() {
        guard !path.isEmpty else { return }
        withAnimation(effects.animation(.exit)) { path.removeLast() }
    }

    // MARK: Bar

    private var bar: some View {
        ZStack {
            Text(path.last.map(pageTitle) ?? title)
                .font(HITType.title)
                .lineLimit(1)
                .padding(.horizontal, 104)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .id(path.count)
                .transition(.opacity)
            HStack {
                if !path.isEmpty {
                    Button(action: back) {
                        HStack(spacing: HITSpacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                            Text(path.count > 1 ? backTitle(path[path.count - 2]) : title)
                        }
                    }
                    .buttonStyle(.hitGhost)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Back to \(path.count > 1 ? backTitle(path[path.count - 2]) : title)"))
                    .accessibilityIdentifier("sheetBack")
                    .transition(.opacity)
                }
                Spacer()
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.hitPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .animation(effects.animation(.standard), value: path.count)
        // Once the page has arrived (`enter` is 200 ms), VoiceOver moves to its title.
        .onChange(of: path.count) {
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                titleFocused = true
            }
        }
        // No leading padding: the ghost back control carries its own 16 pt, so its chevron starts on the cards' left
        // edge, 16 pt in, as the content does.
        .padding(.trailing, HITSpacing.l)
        .padding(.vertical, HITSpacing.m)
        .frame(minHeight: 58)
    }
}

/// What `HITSheetPages` puts in the environment: open a page, or go back one.
struct HITPagesAction {
    var open: (AnyHashable) -> Void = { _ in }
    var back: () -> Void = {}

    func callAsFunction(_ page: AnyHashable) { open(page) }
}

extension EnvironmentValues {
    /// Inside a `HITSheetPages`: opens a page in it (`pages.open(SettingsPage.syncLog)`), or goes back.
    @Entry var hitPages = HITPagesAction()
}

/// The bar above the pages: Liquid Glass with the content scrolling under it (iOS 26 / macOS 26, effects allowed),
/// else build 5's slate bar with a hairline, as `HITSheetChrome` draws its own.
private struct BarModifier<Bar: View>: ViewModifier {
    let effects: HITEffects
    let background: Color
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *), effects.allowsGlass {
            content.safeAreaBar(edge: .top, spacing: 0) {
                bar().hitGlass(in: Rectangle(), fallback: background)
            }
        } else {
            VStack(spacing: 0) {
                bar()
                Rectangle().fill(Theme.separator).frame(height: 1)
                content
            }
        }
    }
}

/// The soft scroll-edge under a glass bar.
private struct SoftTopEdge: ViewModifier {
    let effects: HITEffects

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *), effects.allowsGlass {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
