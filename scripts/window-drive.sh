#!/bin/zsh
# window-drive.sh <pid> <action> [args] [<action> [args] ...]
#
# Clicks, hovers and types in ONE window of a session's own Debug HITList (or the Simulator app), using the
# Accessibility access George granted Claude (2026-11-05). Coordinates are points from the window's top-left
# corner, the same frame as a `window-shot.sh` capture divided by its scale (captures are 2x: halve the pixels).
#
# Actions:
#   click X Y          left click at window point (X, Y)
#   dclick X Y         double click
#   move X Y           move the pointer there (hover tests) and wait 0.3 s
#   type "text"        type the text
#   key NAME           return, delete, escape, tab, left, right, up, down, space, cmd+z, cmd+shift+z, cmd+n,
#                      cmd+comma, cmd+return
#   wait SECONDS       pause
#   shot FILE.png      capture the window (as window-shot.sh)
#
# Safety, all enforced here: the target must be a HITList built under a build.noindex folder (never
# /Applications/HITList.app) or the Simulator; the target is brought to the front and every event is refused
# unless it is still frontmost (George may be using the Mac); clicks must land inside the window; the app that
# was in front before is brought back at the end.
#
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/window-drive.sh 12345 click 84 172 wait 1 shot build.noindex/a.png
set -euo pipefail
(( $# >= 2 )) || { echo "usage: window-drive.sh <pid> <action> [args] ..." >&2; exit 2; }
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
driver=$(mktemp -t windowdrive).swift
trap 'rm -f "$driver"' EXIT
cat > "$driver" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("window-drive: \(message)\n".data(using: .utf8)!)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let pid = Int32(args.removeFirst()) else { fail("first argument must be a pid") }
guard let target = NSRunningApplication(processIdentifier: pid) else { fail("no process \(pid)") }
let path = target.executableURL?.path ?? ""
let isDebugHITList = path.contains("/build.noindex/") && path.hasSuffix("/HITList")
let isSimulator = target.bundleIdentifier == "com.apple.iphonesimulator"
guard isDebugHITList || isSimulator else { fail("refusing: \(path) is neither a Debug HITList under build.noindex nor the Simulator") }
guard AXIsProcessTrusted() else { fail("Accessibility access is not granted to this process") }

func windowBounds() -> CGRect {
    let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = all.compactMap { w -> CGRect? in
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
              let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) else { return nil }
        return r
    }
    guard let best = mine.max(by: { $0.width * $0.height < $1.width * $1.height }) else { fail("no on-screen window for pid \(pid)") }
    return best
}

let previous = NSWorkspace.shared.frontmostApplication
func frontmostIsTarget() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
target.activate()
for _ in 0..<40 where !frontmostIsTarget() { usleep(50_000) }
guard frontmostIsTarget() else { fail("could not bring pid \(pid) to the front") }
usleep(150_000)

func guardFront() { if !frontmostIsTarget() { fail("another app came to the front; stopping so nothing lands in it") } }
func point(_ x: Double, _ y: Double) -> CGPoint {
    let b = windowBounds()
    guard x >= 0, y >= 0, x <= b.width, y <= b.height else { fail("(\(x), \(y)) is outside the \(Int(b.width))x\(Int(b.height)) window") }
    return CGPoint(x: b.minX + x, y: b.minY + y)
}
func mouse(_ type: CGEventType, _ p: CGPoint, clicks: Int64 = 1) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.post(tap: .cghidEventTap)
}
let keyCodes: [String: CGKeyCode] = ["return": 36, "delete": 51, "escape": 53, "tab": 48, "space": 49,
                                     "left": 123, "right": 124, "down": 125, "up": 126, "z": 6, "n": 45, "comma": 43]
func key(_ spec: String) {
    var flags: CGEventFlags = []
    var parts = spec.lowercased().split(separator: "+").map(String.init)
    let name = parts.removeLast()
    for m in parts {
        switch m {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "alt": flags.insert(.maskAlternate)
        case "ctrl": flags.insert(.maskControl)
        default: fail("unknown modifier \(m)")
        }
    }
    guard let code = keyCodes[name] else { fail("unknown key \(name)") }
    guardFront()
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}
func type(_ text: String) {
    for scalar in text.unicodeScalars {
        guardFront()
        var units = Array(String(scalar).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            e.post(tap: .cghidEventTap)
        }
        usleep(25_000)
    }
}
func shot(_ file: String) {
    let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = all.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    func area(_ w: [String: Any]) -> CGFloat {
        guard let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) else { return 0 }
        return r.width * r.height
    }
    guard let best = mine.max(by: { area($0) < area($1) }), let n = best[kCGWindowNumber as String] as? Int else { fail("no window to capture") }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", String(n), file]
    try? p.run(); p.waitUntilExit()
    print(file)
}

func number(_ s: String) -> Double { guard let v = Double(s) else { fail("\(s) is not a number") }; return v }
while !args.isEmpty {
    let action = args.removeFirst()
    func next() -> String { guard !args.isEmpty else { fail("\(action) needs an argument") }; return args.removeFirst() }
    switch action {
    case "click", "dclick":
        let p = point(number(next()), number(next()))
        guardFront()
        mouse(.mouseMoved, p); usleep(60_000)
        let clicks: Int64 = action == "dclick" ? 2 : 1
        for c in 1...clicks { mouse(.leftMouseDown, p, clicks: c); usleep(40_000); mouse(.leftMouseUp, p, clicks: c); usleep(60_000) }
    case "move":
        let p = point(number(next()), number(next()))
        guardFront(); mouse(.mouseMoved, p); usleep(300_000)
    case "type": type(next())
    case "key": key(next())
    case "wait": usleep(UInt32(number(next()) * 1_000_000))
    case "shot": shot(next())
    default: fail("unknown action \(action)")
    }
}
if let previous, previous.processIdentifier != pid { previous.activate() }
SWIFT
swift "$driver" "$@"
