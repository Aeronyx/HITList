import SwiftUI
import OSLog
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The bursts (and the rare visitor) on stage at one moment, pure so tests can check the bookkeeping.
/// Positions are in the window's coordinates (SwiftUI's `.global` space).
struct DelightStageModel {
    struct Burst {
        let field: ParticleField
        let origin: CGPoint
        let start: Date
        var end: Date { start.addingTimeInterval(field.duration) }
    }

    /// Completions in quick succession overlap; past this many, the oldest burst gives way.
    static let maxBursts = 3

    private(set) var bursts: [Burst] = []
    /// When the rare visitor set off, and the line it swims along; nil when it isn't crossing.
    private(set) var visitorStart: Date?
    private(set) var visitorCruise: CGFloat = 0

    var isIdle: Bool { bursts.isEmpty && visitorStart == nil }

    private var visitorEnd: Date? { visitorStart?.addingTimeInterval(RareVisitor.duration) }

    /// When the last thing on stage finishes; nil when idle.
    var endsAt: Date? { (bursts.map(\.end) + [visitorEnd].compactMap { $0 }).max() }

    mutating func add(_ field: ParticleField, at origin: CGPoint, now: Date) {
        bursts.append(Burst(field: field, origin: origin, start: now))
        if bursts.count > Self.maxBursts { bursts.removeFirst(bursts.count - Self.maxBursts) }
    }

    /// Sends the visitor across along `cruise` (a y in window coordinates), unless it is already crossing.
    mutating func launchVisitor(now: Date, cruise: CGFloat) {
        if let end = visitorEnd, end > now { return }
        visitorStart = now
        visitorCruise = cruise
    }

    mutating func prune(now: Date) {
        bursts.removeAll { $0.end <= now }
        if let end = visitorEnd, end <= now { visitorStart = nil }
    }

    /// Draws everything on stage at `now`.
    func draw(in context: GraphicsContext, size: CGSize, now: Date) {
        for burst in bursts {
            burst.field.draw(at: now.timeIntervalSince(burst.start), origin: burst.origin, in: context)
        }
        if let visitorStart {
            RareVisitor.draw(at: now.timeIntervalSince(visitorStart), width: size.width, cruise: visitorCruise, in: context)
        }
    }
}

/// Plays completion celebrations in a transparent overlay above the app's window: a pass-through
/// `UIWindow` on iPhone, a mouse-transparent child panel on the Mac. The overlay exists only while
/// something is playing, so it never sits over the app otherwise, and it never takes a tap or a click.
/// Being above the window rather than in the row, a burst outlives the row's collapse and can spill
/// over its neighbours and the board's card edges.
@MainActor
@Observable
final class DelightStage {
    static let shared = DelightStage()

    private(set) var model = DelightStageModel()
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var seed = UInt64(Date.now.timeIntervalSinceReferenceDate * 1000)
    @ObservationIgnored private let overlay = DelightOverlay()
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "delight")

    /// `origin` is the checkbox's centre in its window's coordinates.
    func play(_ celebration: CompletionCelebration, at origin: CGPoint) {
        guard celebration != .none else { return }
        let now = Date.now
        model.prune(now: now)
        if let kind = celebration.burst {
            seed &+= 0x9E37_79B9
            model.add(ParticleField(kind: kind, seed: seed), at: origin, now: now)
            Self.log.debug("Holiday burst: \(kind.rawValue, privacy: .public)")
        }
        if celebration.visitor {
            model.launchVisitor(now: now, cruise: overlay.visitorCruise)
            Self.log.info("The rare visitor is crossing")
        }
        guard !model.isIdle else { return }
        overlay.show(stage: self)
        scheduleCleanup()
    }

    /// Hides the overlay once the last thing on stage has finished.
    private func scheduleCleanup() {
        cleanup?.cancel()
        guard let end = model.endsAt else { return }
        cleanup = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.model.prune(now: .now)
            if self.model.isIdle { self.overlay.hide() } else { self.scheduleCleanup() }
        }
    }
}

/// The overlay's content: one Canvas redrawn every frame while anything is on stage.
struct DelightStageView: View {
    let stage: DelightStage

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: stage.model.isIdle)) { timeline in
            Canvas { context, size in
                stage.model.draw(in: context, size: size, now: timeline.date)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if os(iOS)
/// A window above the app's that lets every touch through.
private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Keeps the status bar as the app has it (light on dark) while the overlay is on top.
private final class OverlayHostingController: UIHostingController<DelightStageView> {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersStatusBarHidden: Bool { false }
}

@MainActor
private final class DelightOverlay {
    private var window: UIWindow?

    /// Just under the status bar and the Dynamic Island, above the screen's title.
    var visitorCruise: CGFloat {
        let top = activeScene?.keyWindow?.safeAreaInsets.top ?? 47
        return top + RareVisitor.size.height / 2 + 6
    }

    private var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    func show(stage: DelightStage) {
        guard let scene = activeScene else { return }
        if window?.windowScene !== scene {
            let w = PassThroughWindow(windowScene: scene)
            w.windowLevel = .normal + 1
            w.isUserInteractionEnabled = false
            w.backgroundColor = .clear
            let host = OverlayHostingController(rootView: DelightStageView(stage: stage))
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            w.rootViewController = host
            window = w
        }
        window?.isHidden = false
    }

    func hide() {
        window?.isHidden = true
    }
}
#else
/// A borderless, click-through panel the size of the app window's content, kept above it as a child window.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DelightOverlay {
    private(set) var panel: OverlayPanel?
    private weak var parent: NSWindow?

    /// Just below the toolbar (the content view runs under the title bar).
    var visitorCruise: CGFloat {
        guard let host = hostWindow else { return 72 }
        let titleBar = host.frame.height - host.contentLayoutRect.height
        return titleBar + RareVisitor.size.height / 2 + 10
    }

    /// The window the user just completed a task in.
    private var hostWindow: NSWindow? {
        let candidates = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
        return candidates.first { !($0 is NSPanel) && $0.contentView != nil && $0.isVisible }
    }

    func show(stage: DelightStage) {
        guard let host = hostWindow else { return }
        show(stage: stage, over: host)
    }

    /// Lays the panel exactly over `host`'s content view and keeps it above as a child window.
    func show(stage: DelightStage, over host: NSWindow) {
        guard let content = host.contentView else { return }
        let panel = self.panel ?? makePanel(stage: stage)
        self.panel = panel
        // SwiftUI's `.global` space is the content view's, top-left origin.
        panel.setFrame(host.convertToScreen(content.convert(content.bounds, to: nil)), display: false)
        if parent !== host {
            parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
            parent = host
        }
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        parent?.removeChildWindow(panel)
        parent = nil
        panel.orderOut(nil)
    }

    private func makePanel(stage: DelightStage) -> OverlayPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .transient]
        let hosting = NSHostingView(rootView: DelightStageView(stage: stage))
        // The panel follows the app window; the overlay must not size it (or the app window) to fit.
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}
#endif
