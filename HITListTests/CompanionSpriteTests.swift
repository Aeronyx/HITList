import XCTest
import SwiftUI
@testable import HITList

/// Brief 76: every companion is good data (sizes, inks, loops that close, a flourish that starts and ends on the
/// rest frame), is drawn crisp (only its own colours, no smoothing), reads on all eight themes, and the contact
/// sheets of every frame (8x, and the rest frame on each theme) are rendered from the shipped data.
@MainActor
final class CompanionSpriteTests: XCTestCase {
    func testEveryCompanionIsGoodData() {
        XCTAssertEqual(CompanionCharacter.all.map(\.id), ["nod"])
        for character in CompanionCharacter.all {
            XCTAssertEqual(character.problems, [], character.id)
            XCTAssertLessThanOrEqual(character.width, 20)
            XCTAssertLessThanOrEqual(character.height, 20)
            XCTAssertEqual(character.frames.first?.name, "rest")
            XCTAssertEqual(CompanionCharacter.named(character.id)?.id, character.id)
        }
    }

    func testTheirFlourishesLastAboutTwoAndAHalfSeconds() {
        for character in CompanionCharacter.all {
            XCTAssertGreaterThanOrEqual(character.flourishDuration, 2.0, character.id)
            XCTAssertLessThanOrEqual(character.flourishDuration, 2.7, character.id)
            XCTAssertEqual(character.idleFPS, 5, character.id)
            XCTAssertEqual(character.flourishFPS, 9, character.id)
        }
    }

    func testNodSitsBackDownWhereItWas() {
        XCTAssertFalse(CompanionCharacter.nod.flourishTurns, "Nod sits back down exactly where it was")
        XCTAssertEqual(CompanionCharacter.nod.footing, .seat(row: 17))
    }

    func testNodBlinksNowAndThen() {
        let clock = CompanionClock(character: .nod, seed: 11)
        let anchor = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let picks = (1..<1_200).map { clock.loop(forCycle: $0, anchor: anchor).name }
        let blinks = Double(picks.filter { $0.hasSuffix("Blink") }.count) / Double(picks.count)
        // Four cycles in eleven have a blink: about one every twelve seconds.
        XCTAssertEqual(blinks, 4.0 / 11.0, accuracy: 0.05)
    }

    func testTheChecksCatchBadData() {
        let bad = CompanionCharacter(
            id: "bad", width: 3, height: 2, footing: .floor,
            frames: [.init(name: "rest", rows: ["mmm", "mxm"]), .init(name: "two", rows: ["mm", "mmm"])],
            idleFPS: 12, idle: [.init(name: "a", weight: 1, ticks: CompanionCharacter.ticks(("two", 2)))],
            flourishFPS: 9, flourish: CompanionCharacter.ticks(("rest", 3), ("gone", 1)), flourishTurns: false)
        let problems = bad.problems.joined(separator: "\n")
        for expected in ["unknown ink x", "2 wide, not 3", "doesn't start on rest", "no frame gone",
                         "doesn't end on rest", "not 4…6", "not 12…24", "colours"] {
            XCTAssertTrue(problems.contains(expected), "missing: \(expected)\n\(problems)")
        }
    }

    func testEachLoopClosesWithoutAPop() {
        // The seam (last tick back to the first) changes no more pixels than the loops' own steps do.
        for character in CompanionCharacter.all {
            var largestStep = 0
            for loop in character.idle {
                for (a, b) in zip(loop.ticks, loop.ticks.dropFirst()) {
                    largestStep = max(largestStep, character.difference(character.frameIndex(a), character.frameIndex(b)))
                }
            }
            for loop in character.idle {
                let seam = character.difference(character.frameIndex(loop.ticks.last!), character.restFrame)
                XCTAssertLessThanOrEqual(seam, largestStep, "\(character.id).\(loop.name)")
            }
            // The flourish's last tick is the rest frame itself (turned round for Quill): nothing pops after it.
            XCTAssertEqual(character.difference(character.frameIndex(character.flourish.last!), character.restFrame,
                                                mirrored: false), 0)
        }
    }

    func testTheIdleMovesAPixelOrSoAtATime() {
        // Idle steps are one-pixel shifts (a breath, a leg, an ear): every changed pixel's new ink sits next to it in
        // the frame before, and its old ink next to it in the frame after. A blink or a twitch may change up to three
        // pixels in place.
        for character in CompanionCharacter.all {
            for loop in character.idle {
                for (a, b) in zip(loop.ticks, loop.ticks.dropFirst() + [loop.ticks[0]]) where a != b {
                    let jumps = unexplainedChanges(character.frames[character.frameIndex(a)].rows,
                                                   character.frames[character.frameIndex(b)].rows)
                    XCTAssertLessThanOrEqual(jumps, 3, "\(character.id).\(loop.name) \(a.frame) → \(b.frame)")
                }
            }
        }
    }

    private func unexplainedChanges(_ a: [String], _ b: [String]) -> Int {
        let a = a.map(Array.init), b = b.map(Array.init)
        func near(_ grid: [[Character]], _ x: Int, _ y: Int, _ c: Character) -> Bool {
            for dy in -1...1 { for dx in -1...1 {
                let yy = y + dy, xx = x + dx
                if grid.indices.contains(yy), grid[yy].indices.contains(xx), grid[yy][xx] == c { return true }
            } }
            return false
        }
        var count = 0
        for y in a.indices { for x in a[y].indices where a[y][x] != b[y][x] {
            if !(near(a, x, y, b[y][x]) && near(b, x, y, a[y][x])) { count += 1 }
        } }
        return count
    }

    func testFewColoursFromTheTheme() {
        XCTAssertEqual(CompanionCharacter.nod.inks, [.ink, .dark, .mid, .light, .warm, .glow])
        let slate = CompanionInks(palette: .slate)
        XCTAssertEqual(slate.hex[.ink], ThemePalette.slate.hex.background)
        XCTAssertEqual(slate.hex[.mid], ThemePalette.slate.hex.secondaryText)
        XCTAssertEqual(slate.hex[.light], ThemePalette.slate.hex.text)
        XCTAssertEqual(slate.hex[.accent], ThemePalette.slate.hex.accent)
        XCTAssertEqual(slate.hex[.warm], ThemePalette.slate.hex.bolt)
        XCTAssertEqual(CompanionInks.mix("#000000", "#FFFFFF", 0.5), "#808080")
    }

    func testEveryInkReadsOnEveryTheme() {
        // Each tone stands apart from the window and the field it sits on, on all eight palettes.
        for palette in ThemePalette.all {
            let inks = CompanionInks(palette: palette)
            for ground in [palette.hex.background, palette.hex.surface, palette.hex.elevated] {
                for ink in [CompanionInk.mid, .light, .accent, .warm] {
                    XCTAssertGreaterThan(contrast(inks.hex[ink]!, ground), 2.5, "\(palette.id) \(ink) on \(ground)")
                }
                XCTAssertGreaterThan(contrast(inks.hex[.dark]!, ground), 1.5, "\(palette.id) dark on \(ground)")
            }
            // The body's tones step apart from each other.
            XCTAssertGreaterThan(contrast(inks.hex[.light]!, inks.hex[.mid]!), 1.4, palette.id)
            XCTAssertGreaterThan(contrast(inks.hex[.mid]!, inks.hex[.dark]!), 1.8, palette.id)
            XCTAssertGreaterThan(contrast(inks.hex[.light]!, inks.hex[.ink]!), 7, palette.id)
        }
    }

    func testDrawnCrispWithOnlyItsOwnColours() throws {
        // At 3x, every device pixel is exactly a sprite ink or clear: nothing blurred or half-shifted.
        for character in CompanionCharacter.all {
            let inks = CompanionInks(palette: .slate)
            let allowed = Set(character.inks.map { CompanionInks.rgb(inks.hex[$0]!) })
            for frame in [character.restFrame, character.frameIndex(character.flourish[character.flourish.count / 2])] {
                let pixels = try render(CompanionSprite(character: character, pose: .init(frame: frame, mirrored: false), inks: inks), scale: 3)
                XCTAssertEqual(pixels.width, character.width * 6)
                var stray = 0
                for (rgb, alpha) in pixels.colors where alpha > 0 {
                    if alpha != 255 || !allowed.contains(where: { close($0, rgb) }) { stray += 1 }
                }
                XCTAssertEqual(stray, 0, "\(character.id): pixels that are no ink of its own (blurred or half-covered)")
                // And each 6×6 block is one colour: the pixels are squares on the device grid.
                let rows = character.frames[frame].rows.map(Array.init)
                for y in 0..<character.height {
                    for x in 0..<character.width {
                        let c = rows[y][x]
                        let px = pixels.at(x * 6 + 3, y * 6 + 3)
                        if c == CompanionInk.clear { XCTAssertEqual(px.alpha, 0) } else {
                            XCTAssertTrue(close(px.rgb, CompanionInks.rgb(inks.hex[CompanionInk(rawValue: c)!]!)), "\(character.id) \(x),\(y)")
                        }
                    }
                }
            }
        }
    }

    func testMirroringFlipsThePixels() throws {
        let character = CompanionCharacter.nod
        let inks = CompanionInks(palette: .slate)
        let plain = try render(CompanionSprite(character: character, pose: .init(frame: 0, mirrored: false), inks: inks), scale: 1)
        let flipped = try render(CompanionSprite(character: character, pose: .init(frame: 0, mirrored: true), inks: inks), scale: 1)
        let w = character.width * 2
        for y in stride(from: 1, to: character.height * 2, by: 2) {
            for x in stride(from: 1, to: w, by: 2) {
                XCTAssertEqual(plain.at(x, y).alpha, flipped.at(w - 1 - x, y).alpha, "\(x),\(y)")
            }
        }
    }

    func testTheTapAreaIsTheCompanionAboveItsSeat() {
        let nod = CompanionCharacter.nod
        guard case .seat(let seat) = nod.footing else { return XCTFail("Nod sits") }
        let shape = nod.tapShape(mirrored: false, belowRow: seat)
        // Its face takes a tap; its dangling feet, which hang over the field, don't.
        XCTAssertTrue(shape.contains(CGPoint(x: 9 * 2 + 1, y: 11 * 2 + 1)))
        XCTAssertFalse(shape.contains(CGPoint(x: 6 * 2 + 1, y: 19 * 2 + 1)))
        XCTAssertFalse(shape.contains(CGPoint(x: 1, y: 1)), "the empty corner above its cap")
    }

    // MARK: - Contact sheets

    /// Every frame of every companion at 8x on the slate background, and each one's rest frame on all eight themes,
    /// written to the test host's temporary folder (the path is printed) and attached to the result bundle.
    func testRenderTheContactSheets() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CompanionSheets", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for character in CompanionCharacter.all {
            let frames = Self.sheet(character, palette: .slate, frames: Array(character.frames.indices), scale: 4)
            try write(frames, scale: 2, to: folder.appendingPathComponent("\(character.id)-frames-8x.png"))
            let themes = VStack(alignment: .leading, spacing: 12) {
                ForEach(ThemePalette.all) { palette in
                    HStack(spacing: 16) {
                        Text(palette.name).font(.system(size: 11)).foregroundStyle(Color(hex: palette.hex.secondaryText))
                            .frame(width: 80, alignment: .leading)
                        ForEach([0, character.frameIndex(character.flourish[character.flourish.count / 2])], id: \.self) { f in
                            CompanionSprite(character: character, pose: .init(frame: f, mirrored: false), inks: CompanionInks(palette: palette),
                                            pixel: 4)
                        }
                        CompanionSprite(character: character, pose: .init(frame: 0, mirrored: false), inks: CompanionInks(palette: palette))
                    }
                    .padding(8)
                    .background(Color(hex: palette.hex.background))
                }
            }
            .padding(12)
            .background(Color.black)
            try write(themes, scale: 2, to: folder.appendingPathComponent("\(character.id)-themes.png"))
        }
        print("Companion sheets: \(folder.path)")
    }

    private static func sheet(_ character: CompanionCharacter, palette: ThemePalette, frames: [Int], scale: CGFloat) -> some View {
        let columns = 6
        let rows = stride(from: 0, to: frames.count, by: columns).map { Array(frames[$0..<min($0 + columns, frames.count)]) }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rows[r], id: \.self) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(f) \(character.frames[f].name)").font(.system(size: 9)).foregroundStyle(Color(hex: palette.hex.secondaryText))
                            CompanionSprite(character: character, pose: .init(frame: f, mirrored: false), inks: CompanionInks(palette: palette),
                                            pixel: scale)
                                .border(Color(hex: palette.hex.separator).opacity(0.6), width: 0.5)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(hex: palette.hex.background))
    }

    // MARK: - Helpers

    private func write<V: View>(_ view: V, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        attachment.name = url.lastPathComponent
        add(attachment)
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func at(_ x: Int, _ y: Int) -> (rgb: [Int], alpha: Int) {
            let i = (y * width + x) * 4
            return ([Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])], Int(bytes[i + 3]))
        }

        var colors: [([Int], Int)] {
            stride(from: 0, to: bytes.count, by: 4).map { ([Int(bytes[$0]), Int(bytes[$0 + 1]), Int(bytes[$0 + 2])], Int(bytes[$0 + 3])) }
        }
    }

    private func render<V: View>(_ view: V, scale: CGFloat) throws -> Pixels {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, bytes: bytes)
    }

    /// The same colour, give or take the colour space's rounding.
    private func close(_ a: [Int], _ b: [Int]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) <= 2 } }

    private func luminance(_ hex: String) -> Double {
        let c = CompanionInks.rgb(hex).map { v -> Double in
            let s = Double(v) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
