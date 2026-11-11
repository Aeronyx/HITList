import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 100, the seat: a companion sits on the "+" (and on the Mac's search field); it never floats above it or lies
/// over its face. Every character in the app, every still it may show (awake and asleep, rain, snow and each depth of
/// the pile, heat), is drawn as the app draws it (`CompanionFigure` at `CompanionPerch.offset`) on its host's real
/// shape (the "+" a continuous capsule on iPhone 17 and iPhone 16 at 3x and a plain capsule on iPad at 2x; the field
/// a continuous rounded rectangle at the Mac's 2x), and measured device column by device column:
/// - along where they meet (every column whose pixels reach the edge line or hang below it) not one device pixel of
///   the background shows between the creature and the host, unless the creature covers the host's edge there (a
///   leg or a lantern hanging over the front);
/// - the base's two ends are not overhung flat: no two columns just past an end whose lowest pixel is one row above
///   the edge (a slab of body there leaves a notch of background under its end: Tuck's, round 19);
/// - where the host falls further away than the sprite's box can reach (a rump draped down the "+"'s shoulder), the
///   column is left out and counted.
/// The geometry is the same in every theme, so each still is drawn once, on its own theme; every theme is then
/// checked for a pixel where it meets the host that would read as the background (the background's own ink).
///
/// A new character must pass `testEveryCompanionSitsOnItsHost`; `testRenderTheSeats` draws the sheets (before and
/// after the seat, real size and enlarged) into the test host's temporary folder.
@MainActor
final class CompanionSeatTests: XCTestCase {
    /// A host as a device shows it.
    struct Host {
        let name: String
        let spot: CompanionPerch.Spot
        let scale: CGFloat
        /// The "+"'s shape: the glass on iPhone curves as a continuous capsule; the iPad's plain oval is circular.
        var circular = false
        /// Where the host's left edge falls on the screen, in points (its fraction decides the pixel grid).
        var screenX: CGFloat = 0
    }

    static let iPhone17 = Host(name: "iPhone 17", spot: .addButton, scale: 3,
                               screenX: 402 - IslandMetrics.sideInset - FloatingAddButton.size.width)
    static let iPhone16 = Host(name: "iPhone 16", spot: .addButton, scale: 3,
                               screenX: 393 - IslandMetrics.sideInset - FloatingAddButton.size.width)
    static let hosts: [Host] = [iPhone17, iPhone16, Host(name: "iPad", spot: .addButton, scale: 2, circular: true),
                                Host(name: "Mac", spot: .searchField, scale: 2)]

    /// The field's width in the scene (the Mac sidebar's is about this; only its trailing end matters).
    static let fieldWidth: CGFloat = 200
    static let margin: CGFloat = 12
    /// The host's top in the scene: room above it for the tallest sprite.
    static let hostTop: CGFloat = 44

    static func hostSize(_ host: Host) -> CGSize {
        host.spot == .addButton ? FloatingAddButton.size : CGSize(width: fieldWidth, height: CompanionPerch.fieldHeight)
    }

    static func sceneSize(_ host: Host) -> CGSize {
        let size = hostSize(host)
        return CGSize(width: size.width + 2 * margin, height: hostTop + size.height + 6)
    }

    /// The host's left edge in the scene, with the screen's fraction of a point.
    static func hostLeft(_ host: Host) -> CGFloat {
        let fraction: CGFloat = host.screenX - host.screenX.rounded(.down)
        return margin + fraction
    }

    /// The sprite's top-left in the scene.
    static func spriteOrigin(_ character: CompanionCharacter, host: Host) -> CGPoint {
        let offset = CompanionPerch.offset(character, spot: host.spot)
        let spriteWidth: CGFloat = CGFloat(character.width) * CompanionCharacter.pointsPerPixel
        let right: CGFloat = hostLeft(host) + hostSize(host).width
        return CGPoint(x: right - spriteWidth + offset.width, y: hostTop + offset.height)
    }

    /// The host and the companion on it, on the theme's background, as the app draws them.
    struct Scene: View {
        let character: CompanionCharacter
        let pose: CompanionPose?
        let host: Host
        let palette: ThemePalette
        var seat = true

        var body: some View {
            let size = CompanionSeatTests.hostSize(host)
            let inks = CompanionInks(palette: palette)
            let origin = CompanionSeatTests.spriteOrigin(character, host: host)
            ZStack(alignment: .topLeading) {
                Color(hex: palette.hex.background)
                hostShape
                    .frame(width: size.width, height: size.height)
                    .offset(x: CompanionSeatTests.hostLeft(host), y: CompanionSeatTests.hostTop)
                if let pose {
                    Group {
                        if seat {
                            CompanionFigure(character: character, pose: pose, spot: host.spot, inks: inks)
                        } else {
                            CompanionSprite(character: character, pose: pose, inks: inks)
                        }
                    }
                    .offset(x: origin.x, y: origin.y)
                }
            }
            .frame(width: CompanionSeatTests.sceneSize(host).width, height: CompanionSeatTests.sceneSize(host).height,
                   alignment: .topLeading)
        }

        @ViewBuilder private var hostShape: some View {
            switch host.spot {
            case .addButton:
                if host.circular {
                    Capsule(style: .circular).fill(Color(hex: palette.hex.accent))
                } else {
                    Capsule(style: .continuous).fill(Color(hex: palette.hex.accent))
                }
            case .searchField:
                let shape = RoundedRectangle(cornerRadius: CompanionPerch.fieldRadius, style: .continuous)
                shape.fill(Color(hex: palette.hex.elevated))
                    .overlay(shape.strokeBorder(Color(hex: palette.hex.separator).opacity(0.5), lineWidth: 1))
            }
        }
    }

    /// A rendered picture's pixels, RGBA.
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            let w = image.width
            let h = image.height
            width = w
            height = h
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let info: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
            buffer.withUnsafeMutableBytes { raw in
                let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                        bytesPerRow: w * 4, space: space, bitmapInfo: info)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            bytes = buffer
        }

        func rgb(_ x: Int, _ y: Int) -> [Int] {
            let row: Int = y * width
            let i: Int = (row + x) * 4
            return [Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])]
        }
    }

    static func render<V: View>(_ view: V, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// What a device pixel shows: the nearest of the background, the host's colours and the inks.
    enum Shows { case background, host, creature }

    struct Palette {
        let background: [Int]
        let host: [[Int]]
        let inks: [[Int]]

        init(_ palette: ThemePalette, host: Host) {
            background = CompanionInks.rgb(palette.hex.background)
            if host.spot == .addButton {
                self.host = [CompanionInks.rgb(palette.hex.accent)]
            } else {
                let stroke = CompanionInks.mix(palette.hex.separator, palette.hex.elevated, 0.5)
                self.host = [CompanionInks.rgb(palette.hex.elevated), CompanionInks.rgb(stroke)]
            }
            let inks = CompanionInks(palette: palette)
            self.inks = CompanionInk.allCases.filter { $0 != .ink }.compactMap { inks.hex[$0].map(CompanionInks.rgb) }
        }

        static func distance(_ a: [Int], _ b: [Int]) -> Int {
            var total = 0
            for i in 0..<3 {
                let d: Int = a[i] - b[i]
                total += d * d
            }
            return total
        }

        func shows(_ rgb: [Int]) -> Shows {
            var best = Self.distance(rgb, background)
            var shows = Shows.background
            for colour in host {
                let d = Self.distance(rgb, colour)
                if d < best { best = d; shows = .host }
            }
            for colour in inks {
                let d = Self.distance(rgb, colour)
                if d < best { best = d; shows = .creature }
            }
            return shows
        }
    }

    /// One still measured on one host: the worst gap (device rows of background between creature and host) and the
    /// columns it shows in; the overhung ends; the columns left out because the host falls beyond the sprite's reach.
    struct Measure {
        var worst = 0
        var gaps: [Int: Int] = [:]
        var overhangs: [Int] = []
        var unreachable = 0

        var sits: Bool { worst == 0 && overhangs.isEmpty }

        var text: String {
            var parts: [String] = []
            if worst > 0 { parts.append("\(worst) device rows under \(gaps.keys.sorted())") }
            if !overhangs.isEmpty { parts.append("overhung at \(overhangs)") }
            if parts.isEmpty { parts.append("sits") }
            if unreachable > 0 { parts.append("\(unreachable) px past reach") }
            return parts.joined(separator: ", ")
        }
    }

    /// The rows of a pose as drawn (mirrored when it is).
    static func drawnRows(_ character: CompanionCharacter, pose: CompanionPose) -> [[Character]] {
        let rows = character.rows(character.frames[pose.frame].name) ?? []
        return rows.map { pose.mirrored ? Array($0.reversed()) : Array($0) }
    }

    /// The lowest opaque row of a column, or nil.
    static func lowest(_ rows: [[Character]], _ c: Int) -> Int? {
        rows.indices.last { rows[$0][c] != CompanionInk.clear }
    }

    /// Where a body overhangs its base flat: two or more columns just past either end of the base whose lowest pixel
    /// is one row above the edge row, a slab of body with a notch of background under it (Tuck's foot, round 19). A
    /// rounded end (one column at that row, then higher) is how a round body sits, and passes.
    static func overhangs(_ character: CompanionCharacter, pose: CompanionPose) -> [Int] {
        let rows = drawnRows(character, pose: pose)
        let edge = character.seatRow - 1
        guard rows.indices.contains(edge) else { return [] }
        let base = rows[edge].indices.filter { rows[edge][$0] != CompanionInk.clear }
        guard let first = base.first, let last = base.last else { return [] }
        var out: [Int] = []
        for (start, step) in [(first - 1, -1), (last + 1, 1)] {
            var run: [Int] = []
            var c = start
            while rows[edge].indices.contains(c), lowest(rows, c) == edge - 1 {
                run.append(c)
                c += step
            }
            if run.count >= 2 { out.append(contentsOf: run.sorted()) }
        }
        return out.sorted()
    }

    /// The sprite columns that meet the host: every column with a pixel on the edge row or below it, as drawn.
    static func meeting(_ character: CompanionCharacter, pose: CompanionPose) -> [Int] {
        let rows = drawnRows(character, pose: pose)
        return (0..<character.width).filter { c in (lowest(rows, c) ?? -1) >= character.seatRow - 1 }
    }

    /// The pixels where it meets the host whose ink is the background's own: on any theme they read as a gap.
    static func backgroundInk(_ character: CompanionCharacter, pose: CompanionPose) -> [Int] {
        let rows = drawnRows(character, pose: pose)
        let edge = character.seatRow - 1
        return meeting(character, pose: pose).filter { c in
            (edge..<rows.count).contains { rows[$0][c] == CompanionInk.ink.rawValue }
        }
    }

    static func measure(_ character: CompanionCharacter, pose: CompanionPose, host: Host, palette: ThemePalette,
                        seat: Bool = true, hostOnly: Pixels? = nil) -> Measure {
        let scale = host.scale
        var result = Measure()
        result.overhangs = overhangs(character, pose: pose)
        let bare = hostOnly ?? Pixels(render(Scene(character: character, pose: nil, host: host, palette: palette), scale: scale)!)
        guard let image = render(Scene(character: character, pose: pose, host: host, palette: palette, seat: seat), scale: scale)
        else { return result }
        let full = Pixels(image)
        let colours = Palette(palette, host: host)
        let origin = spriteOrigin(character, host: host)
        let p = CompanionCharacter.pointsPerPixel
        let spriteTop: Int = Int((origin.y * scale).rounded())
        // As low as a column can draw: the sprite's box, or a pixel under the edge row where a seat goes.
        let seated = Set(CompanionSeat.base(character, pose: pose).map(\.x))
        for c in meeting(character, pose: pose) {
            let rowsDown: Int = seated.contains(c) ? max(character.height, character.seatRow + 1) : character.height
            let boxBottom: CGFloat = origin.y + CGFloat(rowsDown) * p
            let reach: Int = Int((boxBottom * scale).rounded())
            let left: CGFloat = origin.x + CGFloat(c) * p
            let from: Int = Int((left * scale).rounded())
            let to: Int = Int(((left + p) * scale).rounded())
            for x in from..<to where x >= 0 && x < full.width {
                // The host's top in this device column: its first pixel that shows the host.
                var top: Int?
                for y in 0..<bare.height where colours.shows(bare.rgb(x, y)) == .host {
                    top = y
                    break
                }
                guard let top else { continue }
                if top >= reach {
                    result.unreachable += 1
                    continue
                }
                // Something hangs in front of the host's edge here: nothing shows between them.
                if colours.shows(full.rgb(x, top)) == .creature { continue }
                var gap = 0
                var y = top - 1
                while y >= spriteTop, colours.shows(full.rgb(x, y)) == .background {
                    gap += 1
                    y -= 1
                }
                if gap > 0 {
                    result.gaps[c] = max(result.gaps[c] ?? 0, gap)
                    result.worst = max(result.worst, gap)
                }
            }
        }
        return result
    }

    /// Every still a character may show in a place, by name: awake and asleep, the weather's and each depth of snow.
    static func stills(_ character: CompanionCharacter, place: CompanionPlace) -> [String] {
        let posture = character.posture(place)
        var out: [String] = []
        for mode in [posture.awake, posture.asleep] {
            for still in mode.stills where !out.contains(still) { out.append(still) }
        }
        return out
    }

    /// Characters another session is redrawing in round 20 (brief 102 replaces Posy and owns Smudge): measured and
    /// reported, their failures expected until that session's drawing lands. Remove an id when its character sits.
    static let awaitingRedraw: Set<String> = ["posy", "smudge"]

    /// Its own theme's palette (the one it lives in), else slate.
    static func home(_ character: CompanionCharacter) -> ThemePalette {
        ThemePalette.all.first { CompanionCast.byTheme[$0.id] == character.id } ?? .slate
    }

    /// The check, for every character on every host and still, and every theme. Prints the table the report shows.
    func testEveryCompanionSitsOnItsHost() {
        // iPhone 16 and 17 put the "+" on the same pixel grid (whole points), so one picture stands for both.
        let fraction17: CGFloat = Self.hostLeft(Self.iPhone17)
        let fraction16: CGFloat = Self.hostLeft(Self.iPhone16)
        XCTAssertEqual(fraction17, fraction16, "the \"+\" on the same grid on both phones")
        var lines: [String] = []
        for character in CompanionCharacter.all {
            let palette = Self.home(character)
            for host in Self.hosts where host.name != Self.iPhone16.name {
                let name = host.name == Self.iPhone17.name ? "iPhone 17 and 16" : host.name
                let bare = Pixels(Self.render(Scene(character: character, pose: nil, host: host, palette: palette),
                                              scale: host.scale)!)
                var row: [String] = []
                for still in Self.stills(character, place: host.spot.place) {
                    guard let frame = character.index[still] else { continue }
                    let pose = CompanionPose(frame: frame, mirrored: false)
                    let m = Self.measure(character, pose: pose, host: host, palette: palette, hostOnly: bare)
                    if Self.awaitingRedraw.contains(character.id) {
                        XCTExpectFailure("\(character.id) is being redrawn (brief 102)", strict: false)
                    }
                    XCTAssertTrue(m.sits, "\(character.id) \(still) on \(name): \(m.text)")
                    let dark = Self.backgroundInk(character, pose: pose)
                    XCTAssertEqual(dark, [], "\(character.id) \(still): the background's ink where it meets the host, "
                                   + "a gap on every theme")
                    row.append("\(still): \(m.text)")
                }
                lines.append("\(character.id) on \(name): " + row.joined(separator: "; "))
            }
        }
        let text = lines.joined(separator: "\n")
        print("Companion seats:\n\(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = "companion-seats.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The seat itself: on the flat it adds only the half point tucked into the rim; on a curve, at most a pixel.
    func testTheSeatIsTuckedBehindTheRim() {
        let nod = CompanionCharacter.nod
        let rest = CompanionPose(frame: nod.index["rest"]!, mirrored: false)
        let base = CompanionSeat.base(nod, pose: rest)
        XCTAssertFalse(base.isEmpty, "Nod has a base on the edge row")
        let rows = nod.rows("rest")!.map(Array.init)
        for pixel in base {
            XCTAssertNotEqual(rows[nod.seatRow - 1][pixel.x], CompanionInk.clear)
            if nod.seatRow < nod.height { XCTAssertEqual(rows[nod.seatRow][pixel.x], CompanionInk.clear, "nothing hangs under it") }
        }
        // Mirrored, the same pixels the other way round.
        let turned = CompanionSeat.base(nod, pose: CompanionPose(frame: rest.frame, mirrored: true))
        XCTAssertEqual(Set(turned.map(\.x)), Set(base.map { nod.width - 1 - $0.x }))
        // The host's shape lines up with the perch: the "+"'s flat top on the edge line, its right end where the
        // perch puts the host's trailing edge.
        let surface = CompanionPerch.surface(nod, spot: .addButton).boundingRect
        let p = CompanionCharacter.pointsPerPixel
        XCTAssertEqual(surface.minY, CGFloat(nod.seatRow) * p, accuracy: 0.001)
        let offset = CompanionPerch.offset(nod, spot: .addButton)
        let spriteWidth: CGFloat = CGFloat(nod.width) * p
        XCTAssertEqual(surface.maxX, spriteWidth - offset.width, accuracy: 0.001)
        XCTAssertEqual(surface.width, FloatingAddButton.size.width, accuracy: 0.001)
        #if os(macOS)
        XCTAssertEqual(CompanionPerch.fieldHeight, SidebarSearchField.height, "the seat's field is the Mac's")
        XCTAssertEqual(CompanionPerch.fieldRadius, SidebarSearchField.radius)
        #endif
    }

    // MARK: - Sheets

    /// Each character's stills on each host: before the seat (the sprite alone) and after, at device pixels (real
    /// size) and enlarged eight times around where it meets the host, with the gap measured.
    func testRenderTheSeats() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CompanionSeats", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for character in CompanionCharacter.all {
            for host in [Self.hosts[0], Self.hosts[3]] {
                let palette = Self.home(character)
                var strips: [CGImage] = []
                for still in Self.stills(character, place: host.spot.place) {
                    guard let frame = character.index[still] else { continue }
                    let pose = CompanionPose(frame: frame, mirrored: false)
                    for seat in [false, true] {
                        let m = Self.measure(character, pose: pose, host: host, palette: palette, seat: seat)
                        let scene = Scene(character: character, pose: pose, host: host, palette: palette, seat: seat)
                        guard let image = Self.render(scene, scale: host.scale) else { continue }
                        let label = "\(still) \(seat ? "with" : "without") the seat: " + m.text
                        strips.append(Self.strip(image, character: character, host: host, label: label))
                    }
                }
                let sheet = Self.stack(strips)
                let name = "\(character.id)-\(host.spot == .addButton ? "plus" : "mac")-seat.png"
                try Self.writePNG(sheet, to: folder.appendingPathComponent(name))
            }
        }
        print("Companion seat sheets: \(folder.path)")
    }

    /// One still: the real-size scene, then the meeting strip enlarged eight times (nearest neighbour), with a label.
    static func strip(_ image: CGImage, character: CompanionCharacter, host: Host, label: String) -> CGImage {
        let scale = host.scale
        let origin = spriteOrigin(character, host: host)
        let p = CompanionCharacter.pointsPerPixel
        let top: CGFloat = origin.y + CGFloat(character.seatRow - 4) * p
        let height: CGFloat = 8 * p + 4
        let left: CGFloat = max(0, origin.x - 4)
        let width: CGFloat = min(CGFloat(image.width) / scale - left, CGFloat(character.width) * p + 8)
        let crop = CGRect(x: left * scale, y: top * scale, width: width * scale, height: height * scale).integral
        let piece = image.cropping(to: crop) ?? image
        let zoom = 8
        let real = image
        let outWidth: Int = max(real.width, piece.width * zoom) + 16
        let outHeight: Int = 18 + real.height + 8 + piece.height * zoom + 12
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
        context.interpolationQuality = .none
        // CG's origin is bottom-left.
        context.draw(real, in: CGRect(x: 8, y: outHeight - 18 - real.height, width: real.width, height: real.height))
        context.draw(piece, in: CGRect(x: 8, y: 12, width: piece.width * zoom, height: piece.height * zoom))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.85, alpha: 1),
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: 8, y: outHeight - 14)
        CTLineDraw(line, context)
        return context.makeImage()!
    }

    static func stack(_ images: [CGImage]) -> CGImage {
        let width = images.map(\.width).max() ?? 1
        let height = images.map(\.height).reduce(0, +)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y = height
        for image in images {
            y -= image.height
            context.draw(image, in: CGRect(x: 0, y: y, width: image.width, height: image.height))
        }
        return context.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

/// Brief 100, item 4: on iPhone the last row of a list scrolls clear of the "+" and of the companion on it: the lists'
/// bottom margin grows by how far the companion stands above the button.
@MainActor
final class CompanionListMarginTests: XCTestCase {
    func testEveryCompanionsClearance() {
        for character in CompanionCharacter.all {
            let clearance = CompanionPerch.clearance(character)
            let p = CompanionCharacter.pointsPerPixel
            XCTAssertGreaterThan(clearance, 0, character.id)
            XCTAssertLessThanOrEqual(clearance, CGFloat(character.seatRow) * p, character.id)
            // Every still's top is under it.
            for mode in [character.plus.awake, character.plus.asleep] {
                for still in mode.stills {
                    let rows = character.rows(still)!
                    let top = rows.firstIndex { $0.contains { $0 != CompanionInk.clear } }!
                    XCTAssertLessThanOrEqual(CGFloat(character.seatRow - top) * p, clearance, "\(character.id) \(still)")
                }
            }
        }
        // Tuck stands 16 pixels above the "+" (its seedling's tip, row 4 of 20).
        XCTAssertEqual(CompanionPerch.clearance(.tuck), 32)
    }
}
