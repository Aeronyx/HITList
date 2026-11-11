import SwiftUI

/// Where the companion lives, placed with one overlay line in the view that hosts it (briefs 76 and 79):
/// `.overlay(alignment: CompanionPerch.alignment(.searchField)) { CompanionPerch(.searchField) }`. One place per
/// platform, the same for every companion: the Mac sidebar's search field, at its right-hand middle; the "+" on
/// iPhone and iPad, at its top right (it goes with the "+" when a card opens and comes back with it). Which
/// companion is the theme's (`CompanionCast`).
///
/// It never changes its host's layout (it is drawn with an offset), takes no tap meant for the field or the "+"
/// (only its own pixels above the edge it sits on), is hidden from VoiceOver, makes no sound, and is gone when
/// Settings → Extras → Companions is off. Reduce Motion draws the still pose for the hour and the weather and runs
/// nothing; Reduce Effects and Low Power Mode keep the flickers and drop the routines and the flourish.
struct CompanionPerch: View {
    enum Spot {
        /// The Mac sidebar's search field.
        case searchField
        /// The iPhone's and iPad's floating "+".
        case addButton

        var place: CompanionPlace {
            switch self {
            case .searchField: .field
            case .addButton: .plus
            }
        }

        init(_ place: CompanionPlace) {
            switch place {
            case .field: self = .searchField
            case .plus: self = .addButton
            }
        }

        /// From the host's trailing edge to the right edge of the companion's resting pose, in points (whole
        /// points, so every pixel stays crisp). Its seat row lies on the host's top edge.
        var trailing: CGFloat {
            switch self {
            case .searchField: 14
            case .addButton: 8
            }
        }
    }

    let spot: Spot
    @AppStorage(Preferences.companions, store: AppGroup.defaults) private var enabled = true
    @HITEffectsSetting private var effects

    init(_ spot: Spot) {
        self.spot = spot
    }

    /// The overlay alignment that goes with `spot`.
    static func alignment(_ spot: Spot) -> Alignment { .topTrailing }

    var body: some View {
        if enabled {
            let character = CompanionCast.current
            CompanionLife(character: character, place: spot.place, still: effects.reduceMotion,
                          calm: effects.reduceEffects)
                .offset(Self.offset(character, spot: spot))
                .accessibilityHidden(true)
                // A theme change is a different companion: the old one leaves the screen, the new one arrives.
                .id(character.id)
        }
    }

    /// The Mac sidebar's search field as the seat sees it (`SidebarSearchField.height` and `.radius`, which only the
    /// Mac compiles; `CompanionSeatTests` checks they agree).
    static let fieldHeight: CGFloat = 28
    static let fieldRadius: CGFloat = 7

    /// The host's shape (brief 100), in the sprite's own coordinates (its top-left at 0, 0): the "+" is a 76 × 50
    /// capsule (the iPhone's glass curves as a continuous one, the iPad's plain oval as a circular one; this is where
    /// both are, so a seat reaches the lower of the two); the Mac's field a continuous rounded rectangle 28 pt tall
    /// with a 7 pt radius, whose far end is out of the picture.
    static func surface(_ character: CompanionCharacter, spot: Spot) -> Path {
        let offset = offset(character, spot: spot)
        let spriteWidth: CGFloat = CGFloat(character.width) * CompanionCharacter.pointsPerPixel
        let left: CGFloat = -spriteWidth + offset.width
        switch spot {
        case .addButton:
            let size = FloatingAddButton.size
            let rect = CGRect(x: -size.width - left, y: -offset.height, width: size.width, height: size.height)
            let continuous = Capsule(style: .continuous).path(in: rect)
            return continuous.intersection(Capsule(style: .circular).path(in: rect))
        case .searchField:
            let width: CGFloat = 600
            let rect = CGRect(x: -width - left, y: -offset.height, width: width, height: fieldHeight)
            return RoundedRectangle(cornerRadius: fieldRadius, style: .continuous).path(in: rect)
        }
    }

    /// The sprite's offset from the host's top-trailing corner: its resting pose's rightmost pixel `spot.trailing`
    /// in from the edge (and the posture's own `inset` further), its seat row on the top edge.
    static func offset(_ character: CompanionCharacter, spot: Spot) -> CGSize {
        let p = CompanionCharacter.pointsPerPixel
        let posture = character.posture(spot.place)
        let rest = posture.awake.rest
        let clearColumns = character.width - 1 - character.rightmostColumn(rest)
        let inset: CGFloat = CGFloat(posture.inset) * p
        let clear: CGFloat = CGFloat(clearColumns) * p
        let x: CGFloat = clear - spot.trailing - inset
        let y: CGFloat = -CGFloat(character.seatRow) * p
        return CGSize(width: x, height: y)
    }
}

/// A companion on screen: registers with the director while it shows, and draws its pose on the clock's
/// timeline while an act plays (only while the app is active and motion is allowed); a still picture otherwise.
private struct CompanionLife: View {
    let character: CompanionCharacter
    let place: CompanionPlace
    let still: Bool
    let calm: Bool

    var body: some View {
        let director = CompanionDirector.shared
        let clock = director.clock(for: character)
        let stage = director.stages[character.id]
            ?? CompanionStage(since: .now, place: place, look: director.look(at: .now))
        let rest = clock.restPose(at: .now, stage: stage)
        let spot = CompanionPerch.Spot(place)
        Group {
            if !still, director.isAppActive, stage.act != nil {
                TimelineView(CompanionTimeline(clock: clock, stage: stage)) { context in
                    CompanionFigure(character: character, pose: clock.pose(at: context.date, stage: stage), spot: spot)
                }
            } else {
                CompanionFigure(character: character, pose: rest, spot: spot)
            }
        }
        .contentShape(TapArea(runs: character.drawn[rest.frame], width: character.width, seatRow: character.seatRow,
                              mirrored: rest.mirrored))
        .onTapGesture { director.tap(character.id) }
        .onAppear { director.appear(character.id, place: place, still: still, calm: calm) }
        .onDisappear { director.disappear(character.id) }
        .onChange(of: still) { _, new in director.setMotion(character.id, still: new, calm: calm) }
        .onChange(of: calm) { _, new in director.setMotion(character.id, still: still, calm: new) }
    }
}

extension CompanionPerch {
    /// Brief 100: how far the companion on the "+" stands above the button's top edge, at its tallest still (awake
    /// or asleep, in any weather), so the end of a list can be scrolled clear of it.
    static func clearance(_ character: CompanionCharacter) -> CGFloat {
        let posture = character.plus
        var tallest = 0
        for mode in [posture.awake, posture.asleep] {
            for still in mode.stills {
                guard let rows = character.rows(still) else { continue }
                guard let top = rows.firstIndex(where: { $0.contains { $0 != CompanionInk.clear } }) else { continue }
                tallest = max(tallest, character.seatRow - top)
            }
        }
        return CGFloat(tallest) * CompanionCharacter.pointsPerPixel
    }
}

extension View {
    /// The lists' bottom margin (brief 100): `base`, grown by what the companion on the "+" shows above it while
    /// companions are on, so the last row of every scrolling screen comes clear of the "+" and of the companion.
    func companionListMargin(_ base: CGFloat, besideThePlus: Bool) -> some View {
        modifier(CompanionListMargin(base: base, besideThePlus: besideThePlus))
    }
}

private struct CompanionListMargin: ViewModifier {
    let base: CGFloat
    let besideThePlus: Bool
    @AppStorage(Preferences.companions, store: AppGroup.defaults) private var enabled = true

    func body(content: Content) -> some View {
        // `CompanionCast.current` reads the theme, so a theme change brings the new companion's height.
        let extra: CGFloat = besideThePlus && enabled ? CompanionPerch.clearance(CompanionCast.current) : 0
        content.contentMargins(.bottom, base + extra, for: .automatic)
    }
}

/// A companion as it sits on its host: the sprite, and its seat under it.
struct CompanionFigure: View {
    let character: CompanionCharacter
    let pose: CompanionPose
    let spot: CompanionPerch.Spot
    var inks: CompanionInks? = nil

    var body: some View {
        CompanionSprite(character: character, pose: pose, inks: inks)
            .background(alignment: .topLeading) { CompanionSeat(character: character, pose: pose, spot: spot, inks: inks) }
    }
}

/// Brief 100, the seat: where the host curves away under a companion's base (the "+"'s shoulder, the field's corner)
/// the base is carried down to the host's edge in its own ink, so no background shows between them. What it adds is
/// tucked behind the rim: one sprite pixel below each base pixel that has nothing hanging under it, clipped to above
/// the host's shape (half a point into it, so the two edges meet without a seam). On the flat it is that half point;
/// a base more than a pixel above the curve is the drawing's to fix (`CompanionSeatTests`).
struct CompanionSeat: View {
    let character: CompanionCharacter
    let pose: CompanionPose
    let spot: CompanionPerch.Spot
    var inks: CompanionInks? = nil

    /// How far the clip sits into the host, so the seat's edge and the host's meet without a seam of background.
    static let overlap: CGFloat = 0.5

    /// The base pixels a seat goes under: on the edge row, with nothing hanging below them (x as drawn, mirrored or
    /// not).
    static func base(_ character: CompanionCharacter, pose: CompanionPose) -> [(x: Int, ink: CompanionInk)] {
        guard character.drawn.indices.contains(pose.frame) else { return [] }
        let runs = character.drawn[pose.frame]
        let edge = character.seatRow - 1
        var below = Set<Int>()
        for run in runs where run.y == edge + 1 { for x in run.x..<(run.x + run.length) { below.insert(x) } }
        var out: [(x: Int, ink: CompanionInk)] = []
        for run in runs where run.y == edge {
            for x in run.x..<(run.x + run.length) where !below.contains(x) {
                let drawnX: Int = pose.mirrored ? character.width - 1 - x : x
                out.append((drawnX, run.ink))
            }
        }
        return out
    }

    var body: some View {
        let inks = inks ?? CompanionInks(palette: Theme.palette)
        let p = CompanionCharacter.pointsPerPixel
        let base = Self.base(character, pose: pose)
        let host = CompanionPerch.surface(character, spot: spot).offsetBy(dx: 0, dy: Self.overlap)
        let top: CGFloat = CGFloat(character.seatRow) * p
        Canvas { context, _ in
            context.clip(to: host, options: .inverse)
            for pixel in base {
                let left: CGFloat = CGFloat(pixel.x) * p
                context.fill(Path(CGRect(x: left, y: top, width: p, height: p)), with: .color(inks[pixel.ink]))
            }
        }
        .frame(width: CGFloat(character.width) * p, height: CGFloat(character.height + 1) * p)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The companion's own pixels above the edge it sits on (a pixel's slack around them): a tap below the edge is the
/// field's or the "+"'s.
private struct TapArea: Shape {
    let runs: [CompanionCharacter.Run]
    let width: Int
    let seatRow: Int
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        CompanionCharacter.tapShape(runs: runs, width: width, mirrored: mirrored, belowRow: seatRow)
    }
}
