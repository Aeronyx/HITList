import SwiftUI

/// Where a companion lives, placed with one overlay line in the view that hosts it (brief 76):
/// `.overlay(alignment: CompanionPerch.alignment(.searchField)) { CompanionPerch(.searchField) }`.
/// It never changes its host's layout (it is drawn with an offset), takes no tap meant for the field or a row
/// (only its own pixels above the field, and none at the Mac sidebar's foot), is hidden from VoiceOver, makes no
/// sound, and is gone when Settings → Extras → Companions is off. Reduce Motion draws the rest frame and runs
/// nothing; Reduce Effects and Low Power Mode keep the idle and drop the flourish.
struct CompanionPerch: View {
    enum Spot {
        /// Nod, sitting on the top edge of a search field (the Mac sidebar's, Browse's on iPhone), legs over it.
        case searchField
        /// Quill, asleep on the top edge of Browse's last card (iPhone).
        case browseFoot
        /// Quill, asleep at the right of the Mac sidebar's Settings row.
        case sidebarFoot

        var character: CompanionCharacter {
            switch self {
            case .searchField: .nod
            case .browseFoot, .sidebarFoot: .quill
            }
        }

        var alignment: Alignment {
            switch self {
            case .searchField: .topTrailing
            case .browseFoot, .sidebarFoot: .bottomTrailing
            }
        }

        /// From the host's trailing edge to the sprite's right edge, and from the host's top (a seat) or bottom
        /// (a floor) to the line it sits or lies on, in points. Whole points, so every pixel stays crisp. On Browse,
        /// Quill's last row (its shadow) lies a pixel into the card's top edge, clear of the card's rounded corner.
        var inset: (trailing: CGFloat, edge: CGFloat) {
            switch self {
            #if os(macOS)
            case .searchField: (12, 0)
            case .sidebarFoot: (16, 12)
            case .browseFoot: (16, 0)
            #else
            case .searchField: (14, 0)
            case .browseFoot: (26, -2)
            case .sidebarFoot: (16, 12)
            #endif
            }
        }

        /// Whether a tap on the companion plays its flourish. The Mac's Settings row keeps every click.
        var takesTaps: Bool { self != .sidebarFoot }
    }

    let spot: Spot
    @AppStorage(Preferences.companions, store: AppGroup.defaults) private var enabled = true
    @HITEffectsSetting private var effects

    init(_ spot: Spot) {
        self.spot = spot
    }

    /// The overlay alignment that goes with `spot`.
    static func alignment(_ spot: Spot) -> Alignment { spot.alignment }

    var body: some View {
        if enabled {
            CompanionLife(character: spot.character, spot: spot, still: effects.reduceMotion,
                          calm: effects.calmMotion)
                .offset(offset)
                .accessibilityHidden(true)
        }
    }

    private var offset: CGSize {
        let c = spot.character
        let p = CompanionCharacter.pointsPerPixel
        switch c.footing {
        case .seat(let row):
            return CGSize(width: -spot.inset.trailing, height: spot.inset.edge - CGFloat(row) * p)
        case .floor:
            return CGSize(width: -spot.inset.trailing, height: -spot.inset.edge)
        }
    }
}

/// A companion on screen: registers with the director while it shows, and draws its pose on the clock's
/// timeline (only while the app is active and motion is allowed).
private struct CompanionLife: View {
    let character: CompanionCharacter
    let spot: CompanionPerch.Spot
    let still: Bool
    let calm: Bool

    var body: some View {
        let director = CompanionDirector.shared
        let clock = director.clock(for: character)
        let stage = director.stages[character.id]
        Group {
            if let stage, !still, director.isAppActive {
                TimelineView(CompanionTimeline(clock: clock, stage: stage)) { context in
                    CompanionSprite(character: character, pose: clock.pose(at: context.date, stage: stage))
                }
            } else {
                CompanionSprite(character: character, pose: stage.map { clock.pose(at: .now, stage: $0, still: true) }
                                ?? CompanionPose(frame: character.restFrame, mirrored: false))
            }
        }
        .contentShape(TapArea(character: character, spot: spot, mirrored: facing(stage, clock)))
        .onTapGesture { director.tap(character.id) }
        .allowsHitTesting(spot.takesTaps)
        .onAppear { director.appear(character.id, calm: calm || still) }
        .onDisappear { director.disappear(character.id) }
        .onChange(of: calm || still) { _, new in director.setCalm(character.id, new) }
    }

    private func facing(_ stage: CompanionStage?, _ clock: CompanionClock) -> Bool {
        stage.map { clock.pose(at: .now, stage: $0, still: true).mirrored } ?? false
    }
}

/// The companion's own pixels (a pixel's slack around them), above the field it sits on.
private struct TapArea: Shape {
    let character: CompanionCharacter
    let spot: CompanionPerch.Spot
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        var seat: Int?
        if case .seat(let row) = character.footing { seat = row }
        let path = character.tapShape(mirrored: mirrored, belowRow: seat)
        guard let seat else { return path }
        let above = CGRect(x: -CompanionCharacter.pointsPerPixel, y: -CompanionCharacter.pointsPerPixel,
                           width: rect.width + 2 * CompanionCharacter.pointsPerPixel,
                           height: CGFloat(seat) * CompanionCharacter.pointsPerPixel + CompanionCharacter.pointsPerPixel)
        return path.intersection(Path(above))
    }
}

#if os(iOS)
/// The header of Browse's last section on iPhone: room above the card for Quill to sleep on its top edge, at the
/// right. Nothing (and no room) while Companions is off.
struct CompanionShelf: View {
    @AppStorage(Preferences.companions, store: AppGroup.defaults) private var enabled = true

    /// Quill's height, less the two empty rows above its sleeping curl: the stand and the stretch use them, and may
    /// reach a little into the gap above.
    static let height = CGFloat(CompanionCharacter.quill.height - 2) * CompanionCharacter.pointsPerPixel

    var body: some View {
        if enabled {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .overlay(alignment: CompanionPerch.alignment(.browseFoot)) { CompanionPerch(.browseFoot) }
                .listRowInsets(EdgeInsets())
                .textCase(nil)
        }
    }
}
#endif
