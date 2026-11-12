import SwiftUI

/// A theme's companion in miniature on its swatch (brief 86; George: "add a mini sprite of each creature on each
/// theme! … some could be poking out from behind their theme cards … some could be sitting on top"). The theme's own
/// companion (`CompanionCast`), in that theme's inks (`CompanionInks(palette:)`), still, at 1 point a sprite pixel
/// (half its size in the app), sitting its own way on the swatch (`seats`). It is hidden from VoiceOver and never
/// takes the tap that picks the theme. A theme whose companion isn't drawn yet (it would borrow Nod) shows none, so
/// the grid never has four Nods; Extras → Companions off hides them all.
enum ThemeCompanion {
    /// How a companion sits on its swatch.
    enum Placement: String, CaseIterable {
        /// On the swatch's inner card, legs over the card's top edge (its "+" pose).
        case onCard
        /// Lying along the swatch's top edge (its search-field pose).
        case alongTop
        /// Behind the swatch, only its head over the top edge, down to just under its eyes.
        case peeking
        /// Asleep on the accent dot (its "+" pose at night), what hangs down over the dot.
        case asleepOnDot
        /// On the swatch's top edge, legs over the edge (its "+" pose).
        case onTop
    }

    /// Where one companion sits.
    struct Seat: Equatable {
        var placement: Placement
        /// The sprite's centre across the swatch, 0 at its leading edge, 1 at its trailing edge. (Asleep on the dot,
        /// the dot decides.)
        var along: CGFloat
        var mirrored = false
    }

    /// Each companion's own way of sitting, by character id, in the grid's order (Slate, Graphite, Midnight, Moss;
    /// Nord, Tokyo Night, Mocha, Rosé), so neighbours differ. The second row's sit low (inside the swatch, or a peek):
    /// what rises there pushes the rows apart, and the iPhone's first screen has no room to spare.
    static let seats: [String: Seat] = [
        // Slate: Nod sits on the card, legs over its edge, its bobble clear of the accent dot.
        "nod": Seat(placement: .onCard, along: 0.27),
        // Graphite: Gargle peeks over the top as over a parapet, horns, eyes and wing tips.
        "gargle": Seat(placement: .peeking, along: 0.35),
        // Midnight: Quill lies along the top, its tail's inked tip up.
        "quill": Seat(placement: .alongTop, along: 0.62),
        // Moss: Tuck on the card with its pot, left of the accent dot.
        "tuck": Seat(placement: .onCard, along: 0.3),
        // Nord: Hush peeks over the top, ears and eyes, clear of the rounded corner.
        "hush": Seat(placement: .peeking, along: 0.4),
        // Tokyo Night: Glim on the card, its lantern hanging over the card's edge.
        "glim": Seat(placement: .onCard, along: 0.3),
        // Mocha: Phase asleep in the accent dot, sunk to its eyes, its point flopped over like a nightcap.
        "phase": Seat(placement: .asleepOnDot, along: 0.7),
        // Rosé: Button stands on the card's edge on its boots, left of the dot (round 22: 0.9.4's drawing, standing).
        "button": Seat(placement: .onCard, along: 0.3),
    ]

    /// For a companion not in `seats` (a new one until it is given its own): on the card, legs over its edge, left of
    /// the accent dot. Inside the swatch, so an untuned newcomer never adds height to the grid.
    static let defaultSeat = Seat(placement: .onCard, along: 0.3)

    static func seat(for character: CompanionCharacter) -> Seat { seat(forID: character.id) }

    static func seat(forID id: String) -> Seat { seats[id] ?? defaultSeat }

    /// The companion `palette`'s swatch shows: the theme's own. Nil when the theme only borrows one another theme
    /// owns (every theme without a companion of its own gets Nod: only Slate, Nod's theme, shows it). Launch
    /// arguments that force a companion (`-companion`) don't reach the swatches.
    static func character(for palette: ThemePalette, among palettes: [ThemePalette] = ThemePalette.all) -> CompanionCharacter? {
        let launch = CompanionLaunchOptions(arguments: [])
        let mine = CompanionCast.character(forTheme: palette.id, launch: launch)
        let owner = palettes.first { CompanionCast.character(forTheme: $0.id, launch: launch).id == mine.id }
        return owner?.id == palette.id ? mine : nil
    }

    // MARK: Geometry (pure; tests pin it)

    /// Where the sprite goes, in points from the swatch's top-left corner (not its selection ring's), on whole points
    /// so every sprite pixel is a crisp square.
    struct Layout: Equatable {
        /// The frame drawn.
        var frame: String
        var origin: CGPoint
        var mirrored: Bool
        /// Drawn behind the swatch, and only its rows above this one (peeking).
        var visibleRows: Int?
        /// How far its highest drawn pixel rises above the swatch's top edge (0 when it doesn't).
        var rise: CGFloat
    }

    static func layout(for character: CompanionCharacter, seat: Seat, side: CGFloat) -> Layout {
        let posture = character.posture(.plus)
        let frame: String
        switch seat.placement {
        case .alongTop: frame = character.posture(.field).awake.rest
        case .asleepOnDot: frame = posture.asleep.rest
        case .onCard, .peeking, .onTop: frame = posture.awake.rest
        }
        let rows = character.rows(frame) ?? []
        let first = CGFloat(firstOpaqueRow(rows) ?? 0)
        let width = CGFloat(character.width)
        let centre: CGFloat = side * seat.along
        var x: CGFloat = (centre - width / 2).rounded()
        var y: CGFloat
        var visibleRows: Int?
        switch seat.placement {
        case .onCard:
            y = ThemeSwatch.Metrics(side: side).cardTop - CGFloat(character.seatRow)
        case .alongTop:
            let last = CGFloat(lastOpaqueRow(rows) ?? character.height - 1)
            y = -(last + 1)
        case .peeking:
            // Down to one row under the eyes, so they aren't cut by the edge.
            let eyes = eyeRow(rows) ?? min(character.height - 2, Int(first) + 5)
            let shown = min(character.height, eyes + 2)
            visibleRows = shown
            y = -CGFloat(shown)
        case .asleepOnDot:
            let dot = ThemeSwatch.Metrics(side: side).dot
            x = (dot.midX - width / 2).rounded()
            y = dot.minY - CGFloat(character.seatRow)
        case .onTop:
            y = -CGFloat(character.seatRow)
        }
        // Keep it on the swatch across: no more than a pixel past either side.
        x = min(max(x, -1), side - width + 1)
        let rise = max(0, -(y + first))
        return Layout(frame: frame, origin: CGPoint(x: x, y: y), mirrored: seat.mirrored, visibleRows: visibleRows, rise: rise)
    }

    /// How far `palette`'s companion reaches above the swatch's selection ring (the top of its cell in the grid): the
    /// room its row of the grid keeps above the swatches. 0 for none.
    static func rise(for palette: ThemePalette, side: CGFloat, among palettes: [ThemePalette] = ThemePalette.all) -> CGFloat {
        guard let character = character(for: palette, among: palettes) else { return 0 }
        let rise = layout(for: character, seat: seat(for: character), side: side).rise
        return max(0, rise - ThemeSwatch.ringInset)
    }

    static func firstOpaqueRow(_ rows: [String]) -> Int? {
        rows.firstIndex { $0.contains { $0 != CompanionInk.clear } }
    }

    static func lastOpaqueRow(_ rows: [String]) -> Int? {
        rows.lastIndex { $0.contains { $0 != CompanionInk.clear } }
    }

    /// The last row of the first run of rows holding the eyes' ink (`CompanionInk.ink`): where a peek stops.
    static func eyeRow(_ rows: [String]) -> Int? {
        let eye = CompanionInk.ink.rawValue
        guard let start = rows.firstIndex(where: { $0.contains(eye) }) else { return nil }
        var end = start
        while end + 1 < rows.count, rows[end + 1].contains(eye) { end += 1 }
        return end
    }
}

/// The miniature itself, for `ThemeSwatch`: one still frame at 1 pt a pixel, in `palette`'s inks.
struct ThemeCompanionSprite: View {
    let character: CompanionCharacter
    let layout: ThemeCompanion.Layout
    let palette: ThemePalette

    /// Half the app's 2 pt a pixel (brief 86).
    static let pixel: CGFloat = 1

    var body: some View {
        let pose = CompanionPose(frame: character.drawnIndex(layout.frame), mirrored: layout.mirrored)
        CompanionSprite(character: character, pose: pose, inks: CompanionInks(palette: palette), pixel: Self.pixel)
            .mask(alignment: .top) {
                Rectangle().frame(height: CGFloat(layout.visibleRows ?? character.height) * Self.pixel)
            }
            .frame(width: CGFloat(character.width) * Self.pixel, height: CGFloat(character.height) * Self.pixel,
                   alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
