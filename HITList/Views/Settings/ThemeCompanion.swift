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
        /// Standing on the swatch's floor, inside the box: its feet on the square's bottom edge, just above its border
        /// line, in front of the card (its "+" pose; round 24, George: "have him sit at the bottom of his square box").
        /// What it draws below its seat row (Glim's lantern) hangs below the box.
        case onFloor
        /// Standing on the swatch's floor at its right end, as far over as its body clears the rounded corner (its
        /// continuous curve, inside the border line); what hangs below its seat row and the tail it hangs from (the two
        /// columns before it) go over the edge, off the corner (its "+" pose; round 25, George: "Glim in the bottom
        /// right, having his tail almost hanging over the 'Tokyo Night' text").
        case onFloorRight
        /// Asleep on the top edge at its right end, `past` points of it beyond the right edge, what hangs below its
        /// seat row (Quill's hindquarters) down past the corner, about to slide off (its "+" pose at night; round 25,
        /// George: "Quill asleep and almost falling/slumping off the top right corner").
        case overCorner
        /// In the air at the middle of the swatch's left edge, `past` points of it beyond the edge, mirrored to face into
        /// the box (its `fly` frame, its "+" pose until it has one; round 25, George: "flying in the middle left slightly
        /// extended outside of his box").
        case inAir
    }

    /// The frame a companion flies in (`inAir`), if it has one.
    static let flyFrame = "fly"

    /// The swatch's border line (`ThemeSwatch`'s separator stroke, inside the square): what one standing on the floor
    /// stands on.
    static let floorLine: CGFloat = 1

    /// Where one companion sits.
    struct Seat: Equatable {
        var placement: Placement
        /// The sprite's centre across the swatch, 0 at its leading edge, 1 at its trailing edge. (Asleep on the dot,
        /// the dot decides.)
        var along: CGFloat
        var mirrored = false
        /// How far its drawn pixels reach beyond the swatch's edge, in points: the right edge over the corner, the left
        /// in the air. (Elsewhere it stays on the swatch across.)
        var past: CGFloat = 0
    }

    /// Each companion's own way of sitting, by character id, in the grid's order (Slate, Graphite, Midnight, Moss;
    /// Nord, Tokyo Night, Mocha, Rosé), so neighbours differ, across a row and down a column (a different placement, or
    /// the same one at least `apart` points along). The second row's sit low (inside the swatch, or a peek): what rises
    /// there pushes the rows apart, and the iPhone's first screen has no room to spare. Round 25 (George, on 0.9.8) moved
    /// Flint, Quill, Tuck and Glim; Hush is the only one behind his box.
    static let seats: [String: Seat] = [
        // Slate: Nod sits on the card, legs over its edge, its bobble clear of the accent dot.
        "nod": Seat(placement: .onCard, along: 0.27),
        // Graphite: Flint in the air at the middle of the left edge, 5 pt of him outside the box, facing into it.
        "flint": Seat(placement: .inAir, along: 0, mirrored: true, past: 5),
        // Midnight: Quill asleep on the top edge at its right end, 7 pt of him past the corner, his hindquarters hanging
        // down the side.
        "quill": Seat(placement: .overCorner, along: 1, past: 7),
        // Moss: Tuck on the floor of his box, in the middle, his sprout under the accent dot (George: "center one of
        // them": Button keeps the place George saw him in).
        "tuck": Seat(placement: .onFloor, along: 0.5),
        // Nord: Hush peeks over the top, ears and eyes, clear of the rounded corner.
        "hush": Seat(placement: .peeking, along: 0.4),
        // Tokyo Night: Glim on the floor at the right, as far over as his body clears the rounded corner, his tail over
        // the edge and the lantern hanging off the corner toward "Tokyo Night", clear of it.
        "glim": Seat(placement: .onFloorRight, along: 1),
        // Mocha: Phase asleep over the accent dot, the sheet hovering low and slack a pixel above it (round 23).
        "phase": Seat(placement: .asleepOnDot, along: 0.7),
        // Rosé: Button stands on the floor of his box on his boots, under the card's edge and left of the dot, clear
        // of the rounded corner (round 24; George: "just have him sit at the bottom of his square box").
        "button": Seat(placement: .onFloor, along: 0.34),
    ]

    /// Two neighbours on the same placement sit at least this far apart along the swatch, in points at the iPhone's
    /// size (Tuck in the middle of his floor, Button at the left of his, one above the other).
    static let apart: CGFloat = 6

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
        case .asleepOnDot, .overCorner: frame = posture.asleep.rest
        case .inAir: frame = character.rows(flyFrame) == nil ? posture.awake.rest : flyFrame
        case .onCard, .peeking, .onTop, .onFloor, .onFloorRight: frame = posture.awake.rest
        }
        let rows = character.rows(frame) ?? []
        let first = CGFloat(firstOpaqueRow(rows) ?? 0)
        let drawn = drawnBox(rows, width: character.width, mirrored: seat.mirrored)
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
        case .onFloor:
            y = side - floorLine - CGFloat(character.seatRow)
        case .onFloorRight:
            y = side - floorLine - CGFloat(character.seatRow)
            x = rightmostFit(rows, character: character, side: side, y: y)
        case .overCorner:
            x = side + seat.past - CGFloat((drawn?.maxX ?? character.width - 1) + 1)
            y = -CGFloat(character.seatRow)
        case .inAir:
            let box = drawn ?? (minX: 0, maxX: character.width - 1, minY: 0, maxY: character.height - 1)
            x = -seat.past - CGFloat(box.minX)
            // Its drawn middle at the box's middle height, on a whole point.
            y = ((side - CGFloat(box.maxY - box.minY + 1)) / 2).rounded() - CGFloat(box.minY)
        }
        if seat.placement != .overCorner, seat.placement != .inAir, seat.placement != .onFloorRight {
            // Keep it on the swatch across: no more than a pixel past either side.
            x = min(max(x, -1), side - width + 1)
        }
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

    /// The body of one standing at the right (`onFloorRight`): its pixels above its seat row, less what hangs below the
    /// seat row's columns and the two before them (the tail a lantern hangs from).
    static func bodyPixels(_ rows: [String], seatRow: Int) -> [(x: Int, y: Int)] {
        var hanging = Int.max
        for row in rows.dropFirst(seatRow) {
            for (x, letter) in row.enumerated() where letter != CompanionInk.clear && !CompanionInk.isBehind(letter) {
                hanging = min(hanging, x)
            }
        }
        var out: [(x: Int, y: Int)] = []
        for (y, row) in rows.prefix(seatRow).enumerated() {
            for (x, letter) in row.enumerated() where letter != CompanionInk.clear && !CompanionInk.isBehind(letter) {
                if hanging == Int.max || x < hanging - 2 { out.append((x, y)) }
            }
        }
        return out
    }

    /// The swatch's rounded square inside its border line, as `ThemeSwatch` draws it (continuous corners).
    static func floorBox(side: CGFloat) -> Path {
        let inner = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: floorLine, dy: floorLine)
        return RoundedRectangle(cornerRadius: ThemeSwatch.Metrics(side: side).radius - floorLine, style: .continuous).path(in: inner)
    }

    /// Half an iPhone device pixel: the give where a pixel's corner meets the box's curve (or lies on its edge).
    static let cornerSlack: CGFloat = 1.0 / 6

    /// The largest whole-point x at which every pixel of the body (`bodyPixels`), its top at `y`, lies inside the box
    /// (`floorBox`), every corner of it (within `cornerSlack`); the leftmost place it can stand when none fits.
    static func rightmostFit(_ rows: [String], character: CompanionCharacter, side: CGFloat, y: CGFloat) -> CGFloat {
        let box = floorBox(side: side)
        let body = bodyPixels(rows, seatRow: character.seatRow)
        let near: CGFloat = cornerSlack, far: CGFloat = 1 - cornerSlack
        var x: CGFloat = side - CGFloat(character.width) + 1
        while x > floorLine {
            let fits = body.allSatisfy { pixel in
                let left: CGFloat = x + CGFloat(pixel.x), top: CGFloat = y + CGFloat(pixel.y)
                return [CGPoint(x: left + near, y: top + near), CGPoint(x: left + far, y: top + near),
                        CGPoint(x: left + near, y: top + far), CGPoint(x: left + far, y: top + far)].allSatisfy { box.contains($0) }
            }
            if fits { return x }
            x -= 1
        }
        return x
    }

    /// The square of points each pixel the swatch draws covers, from the swatch's top-left corner: mirrored as drawn, a
    /// peek only down to its visible rows, nothing behind the host. What the tests measure against the box, the accent
    /// dot, the ring and the names.
    static func drawnPixels(for character: CompanionCharacter, layout: Layout) -> [CGRect] {
        let rows = character.rows(layout.frame) ?? []
        var out: [CGRect] = []
        for (y, row) in rows.prefix(layout.visibleRows ?? rows.count).enumerated() {
            for (x, letter) in row.enumerated() where letter != CompanionInk.clear && !CompanionInk.isBehind(letter) {
                let column: Int = layout.mirrored ? character.width - 1 - x : x
                out.append(CGRect(x: layout.origin.x + CGFloat(column), y: layout.origin.y + CGFloat(y), width: 1, height: 1))
            }
        }
        return out
    }

    /// The columns and rows a frame draws on the swatch (not clear, not behind the host: with no host those aren't
    /// drawn), its columns as drawn when `mirrored`. Nil for a frame that draws nothing.
    static func drawnBox(_ rows: [String], width: Int, mirrored: Bool = false) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        var box: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
        for (y, row) in rows.enumerated() {
            for (x, letter) in row.enumerated() where letter != CompanionInk.clear && !CompanionInk.isBehind(letter) {
                let column = mirrored ? width - 1 - x : x
                if let b = box {
                    box = (min(b.minX, column), max(b.maxX, column), min(b.minY, y), max(b.maxY, y))
                } else {
                    box = (column, column, y, y)
                }
            }
        }
        return box
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
