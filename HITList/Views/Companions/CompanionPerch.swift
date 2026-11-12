import SwiftUI

/// Where the companion lives, placed with one overlay line in the view that hosts it (briefs 76 and 79):
/// `.overlay(alignment: CompanionPerch.alignment(.searchField)) { CompanionPerch(.searchField) }`. One place per
/// platform, the same for every companion: the Mac sidebar's search field, at its right-hand middle; the "+" on
/// iPhone and iPad, at its top right (it goes with the "+" when a card opens and comes back with it). Which
/// companion is the theme's (`CompanionCast`).
///
/// On the iPhone Duo's outer display, where the tab island stands upright in the system's bar column and the "+" under
/// it has no room (brief 104, item 7), it sits on the crown of the island instead, with its "+" posture:
/// `CompanionPerch.island(pushed:)`, and only while the column leaves it room.
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
        /// The crown of the upright tab island on the iPhone Duo's outer display (brief 104, item 7): a dome, 66 pt
        /// across, the companion on it in its "+" posture.
        case island

        var place: CompanionPlace {
            switch self {
            case .searchField: .field
            case .addButton, .island: .plus
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
            case .island: 0
            }
        }

        /// How far its seat row sinks into the host's top, in points: on the island's dome the middle of the base
        /// settles a point into the crown, so the curve falls away from under it less at its sides.
        var sink: CGFloat { self == .island ? 1 : 0 }

        /// How many sprite pixels the seat may carry a base pixel down to the host's curve: one on the "+"'s
        /// shoulder and the field's corner; on the dome, which falls 3 pt 14 pt from the crown and 5 pt at 18, four.
        var seatDepth: Int { self == .island ? 4 : 1 }
    }

    let spot: Spot
    /// The clear room above its host, where only part of it may be free (the island under the system's items); nil:
    /// as much as it needs.
    var room: CGFloat? = nil
    @AppStorage(Preferences.companions, store: AppGroup.defaults) private var enabled = true
    @HITEffectsSetting private var effects

    init(_ spot: Spot, room: CGFloat? = nil) {
        self.spot = spot
        self.room = room
    }

    /// The companion on the crown of the Duo's upright island, given whether a screen is pushed (the system's Back
    /// stands in the column then) and the Debug stand-in for a call (`-duoStatusPad`, which moves the island up).
    static func island(pushed: Bool) -> CompanionPerch {
        let room: CGFloat = BarColumnBudget.clearRoom(pushed: pushed, call: false) - BarColumnDebug.statusPad
        return CompanionPerch(.island, room: room)
    }

    /// The air it keeps above itself on the island: it shows only where the room is its height and this much more.
    static let islandAir: CGFloat = 8

    /// Whether `character` has room on its host: always, but on the island only where the clear room above it holds
    /// its tallest still and `islandAir` (not on a pushed screen during a call, for one).
    static func fits(_ character: CompanionCharacter, room: CGFloat?) -> Bool {
        guard let room else { return true }
        return room >= clearance(character) + islandAir
    }

    /// The overlay alignment that goes with `spot`.
    static func alignment(_ spot: Spot) -> Alignment { spot == .island ? .top : .topTrailing }

    var body: some View {
        let character = CompanionCast.current
        if enabled, Self.fits(character, room: room) {
            CompanionLife(character: character, spot: spot, still: effects.reduceMotion,
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
        case .island:
            // The upright island, a continuous capsule 66 pt across, the sprite centred over it (`alignment`).
            let width: CGFloat = IslandMetrics.sideWidth
            let spriteLeft: CGFloat = (width - spriteWidth) / 2 + offset.width
            let rect = CGRect(x: -spriteLeft, y: -offset.height, width: width, height: IslandMetrics.sideHeight)
            return Capsule(style: .continuous).path(in: rect)
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
    /// in from the edge (and the posture's own `inset` further), its seat row on the top edge. On the island (aligned
    /// top centre) the middle of its resting pose's base is on the crown, and its seat row sinks `spot.sink` into it.
    static func offset(_ character: CompanionCharacter, spot: Spot) -> CGSize {
        let p = CompanionCharacter.pointsPerPixel
        let posture = character.posture(spot.place)
        let rest = posture.awake.rest
        if spot == .island {
            let span = baseSpan(character, frame: rest)
            let first: CGFloat = CGFloat(span.lowerBound)
            let last: CGFloat = CGFloat(span.upperBound + 1)
            let middle: CGFloat = (first + last) * p / 2
            let spriteWidth: CGFloat = CGFloat(character.width) * p
            let x: CGFloat = spriteWidth / 2 - middle
            let y: CGFloat = -CGFloat(character.seatRow) * p + spot.sink
            return CGSize(width: x, height: y)
        }
        let clearColumns = character.width - 1 - character.rightmostColumn(rest)
        let inset: CGFloat = CGFloat(posture.inset) * p
        let clear: CGFloat = CGFloat(clearColumns) * p
        let x: CGFloat = clear - spot.trailing - inset
        let y: CGFloat = -CGFloat(character.seatRow) * p
        return CGSize(width: x, height: y)
    }

    /// The columns its base spans in `frame`: the first and last pixel in front of the host on the edge row (or, for a
    /// frame with nothing there, on any row).
    static func baseSpan(_ character: CompanionCharacter, frame: String) -> ClosedRange<Int> {
        let rows = (character.rows(frame) ?? []).map(Array.init)
        let front = { (c: Character) in c != CompanionInk.clear && !CompanionInk.isBehind(c) }
        let edge = character.seatRow - 1
        var columns = rows.indices.contains(edge) ? rows[edge].indices.filter { front(rows[edge][$0]) } : []
        if columns.isEmpty { columns = (0..<character.width).filter { x in rows.contains { $0.indices.contains(x) && front($0[x]) } } }
        guard let first = columns.first, let last = columns.last else { return 0...(character.width - 1) }
        return first...last
    }
}

/// A companion on screen: registers with the director while it shows, and draws its pose on the clock's
/// timeline while an act plays (only while the app is active and motion is allowed); a still picture otherwise.
private struct CompanionLife: View {
    let character: CompanionCharacter
    let spot: CompanionPerch.Spot
    let still: Bool
    let calm: Bool

    var body: some View {
        let director = CompanionDirector.shared
        let clock = director.clock(for: character)
        let place = spot.place
        let stage = director.stages[character.id]
            ?? CompanionStage(since: .now, place: place, look: director.look(at: .now))
        let rest = clock.restPose(at: .now, stage: stage)
        Group {
            if !still, director.isAppActive, stage.act != nil {
                TimelineView(CompanionTimeline(clock: clock, stage: stage)) { context in
                    CompanionFigure(character: character, pose: clock.pose(at: context.date, stage: stage), spot: spot)
                }
            } else {
                CompanionFigure(character: character, pose: rest, spot: spot)
            }
        }
        .contentShape(TapArea(character: character, pose: rest, spot: spot))
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

/// A companion as it sits on its host: the sprite (what lies behind the host drawn only outside its shape, brief 104),
/// and its seat under it.
struct CompanionFigure: View {
    let character: CompanionCharacter
    let pose: CompanionPose
    let spot: CompanionPerch.Spot
    var inks: CompanionInks? = nil

    var body: some View {
        CompanionSprite(character: character, pose: pose, inks: inks, host: CompanionPerch.surface(character, spot: spot))
            .background(alignment: .topLeading) { CompanionSeat(character: character, pose: pose, spot: spot, inks: inks) }
    }
}

/// Brief 100, the seat: where the host curves away under a companion's base (the "+"'s shoulder, the field's corner)
/// the base is carried down to the host's edge in its own ink, so no background shows between them. What it adds is
/// tucked behind the rim: one sprite pixel below each base pixel that has nothing hanging under it, clipped to above
/// the host's shape (half a point into it, so the two edges meet without a seam). On the flat it is that half point;
/// a base more than a pixel above the curve is the drawing's to fix (`CompanionSeatTests`). On the Duo's island
/// (brief 104, item 7) the host is a dome falling away on both sides, so the seat carries a base pixel down as far as
/// `Spot.seatDepth` pixels, to the curve. A see-through character's
/// seat is as see-through as the pixel it goes under (`CompanionCharacter.opacity`), and a veil (Phase's hem, brief
/// 101) gets none: a ghost's hem floats, and a solid bit under its points showed where the "+" curves away.
struct CompanionSeat: View {
    let character: CompanionCharacter
    let pose: CompanionPose
    let spot: CompanionPerch.Spot
    var inks: CompanionInks? = nil

    /// How far the clip sits into the host, so the seat's edge and the host's meet without a seam of background.
    static let overlap: CGFloat = 0.5

    /// The base pixels a seat goes under: on the edge row, with nothing hanging below them in front of the host (x as
    /// drawn, mirrored or not). What lies behind the host (brief 104) is no base and hangs over nothing.
    static func base(_ character: CompanionCharacter, pose: CompanionPose) -> [(x: Int, ink: CompanionInk)] {
        seated(character, pose: pose, spot: .addButton).map { ($0.x, $0.ink) }
    }

    /// Where the seat goes in `spot`: under each base pixel (from the row under the edge row), and on the island's dome
    /// also under what hangs in front below the edge (an ear, a foot), from the row under its lowest pixel, so it
    /// rests on the curve too. `y` is the first sprite row the seat fills.
    static func seated(_ character: CompanionCharacter, pose: CompanionPose,
                       spot: CompanionPerch.Spot) -> [(x: Int, y: Int, ink: CompanionInk)] {
        let pixels = edgePixels(character, pose: pose)
        guard spot == .island, character.drawn.indices.contains(pose.frame) else { return pixels }
        let runs = character.drawn[pose.frame]
        let edge = character.seatRow - 1
        var lowest: [Int: (y: Int, ink: CompanionInk)] = [:]
        for run in runs where run.y > edge && !run.behind {
            for x in run.x..<(run.x + run.length) where (lowest[x]?.y ?? -1) < run.y { lowest[x] = (run.y, run.ink) }
        }
        // A ghost's hem too (brief 101 lets it float over the "+"): here it rests on the curve, as see-through as itself.
        var out = pixels
        for (x, pixel) in lowest {
            let drawnX: Int = pose.mirrored ? character.width - 1 - x : x
            out.append((drawnX, pixel.y + 1, pixel.ink))
        }
        return out
    }

    /// The edge row's base pixels with nothing in front hanging below them, as drawn, the seat starting a row lower.
    private static func edgePixels(_ character: CompanionCharacter, pose: CompanionPose) -> [(x: Int, y: Int, ink: CompanionInk)] {
        guard character.drawn.indices.contains(pose.frame) else { return [] }
        let runs = character.drawn[pose.frame]
        let edge = character.seatRow - 1
        var below = Set<Int>()
        for run in runs where run.y == edge + 1 && !run.behind {
            for x in run.x..<(run.x + run.length) { below.insert(x) }
        }
        var out: [(x: Int, y: Int, ink: CompanionInk)] = []
        for run in runs where run.y == edge && run.ink != .veil && !run.behind {
            for x in run.x..<(run.x + run.length) where !below.contains(x) {
                let drawnX: Int = pose.mirrored ? character.width - 1 - x : x
                out.append((drawnX, character.seatRow, run.ink))
            }
        }
        return out
    }

    var body: some View {
        let inks = inks ?? CompanionInks(palette: Theme.palette)
        let p = CompanionCharacter.pointsPerPixel
        let seated = Self.seated(character, pose: pose, spot: spot)
        let host = CompanionPerch.surface(character, spot: spot).offsetBy(dx: 0, dy: Self.overlap)
        let depth: Int = spot.seatDepth
        let tall: CGFloat = CGFloat(depth) * p
        let lowest: Int = seated.map(\.y).max() ?? character.seatRow
        let rows: Int = max(character.height, lowest + depth)
        let character = character
        Canvas { context, _ in
            context.clip(to: host, options: .inverse)
            for pixel in seated {
                let left: CGFloat = CGFloat(pixel.x) * p
                let top: CGFloat = CGFloat(pixel.y) * p
                let alpha: Double = character.opacity(pixel.ink)
                let color: Color = alpha < 1 ? inks[pixel.ink].opacity(alpha) : inks[pixel.ink]
                context.fill(Path(CGRect(x: left, y: top, width: p, height: tall)), with: .color(color))
            }
        }
        .frame(width: CGFloat(character.width) * p, height: CGFloat(rows) * p)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The companion's own pixels above the edge it sits on (a pixel's slack around them): a tap below the edge is the
/// field's or the "+"'s. On the island, whose dome its seat row sinks into, nothing inside the island's shape either:
/// the Inbox cell under it takes its taps.
private struct TapArea: Shape {
    let character: CompanionCharacter
    let pose: CompanionPose
    let spot: CompanionPerch.Spot

    func path(in rect: CGRect) -> Path { CompanionPerch.tapShape(character, pose: pose, spot: spot) }
}

extension CompanionPerch {
    /// What of a pose takes taps, in the sprite's coordinates (`TapArea`): its own pixels above the edge it sits on,
    /// with a pixel's slack; on the island, nothing inside the island's shape.
    static func tapShape(_ character: CompanionCharacter, pose: CompanionPose, spot: Spot) -> Path {
        let runs = character.drawn.indices.contains(pose.frame) ? character.drawn[pose.frame] : []
        let shape = CompanionCharacter.tapShape(runs: runs, width: character.width, mirrored: pose.mirrored,
                                                belowRow: character.seatRow)
        guard spot == .island else { return shape }
        return shape.subtracting(surface(character, spot: spot))
    }
}
