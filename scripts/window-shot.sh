#!/bin/zsh
# window-shot.sh <pid> <out.png>
#
# Captures the largest on-screen window of process <pid> into <out.png>, and nothing else: never the whole
# screen, which shows George's own windows. For sessions that run a Debug Mac HITList (with its own store,
# HITLIST_STORE_SUFFIX=<name>, and `-disableCloudKit YES` as a launch argument so sync stays off for that
# process only) and need to see it. George granted Claude screen recording on 2026-11-05; without it the
# capture comes back as wallpaper only.
#
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/window-shot.sh 12345 build.noindex/shot.png
set -euo pipefail
pid=${1:?usage: window-shot.sh <pid> <out.png>}
out=${2:?usage: window-shot.sh <pid> <out.png>}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

finder=$(mktemp -t windowshot).swift
trap 'rm -f "$finder"' EXIT
cat > "$finder" <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1]) ?? -1
let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = all.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
func area(_ w: [String: Any]) -> CGFloat {
    guard let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) else { return 0 }
    return r.width * r.height
}
guard let best = mine.max(by: { area($0) < area($1) }), let n = best[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write("no on-screen window for pid \(pid)\n".data(using: .utf8)!)
    exit(1)
}
print(n)
SWIFT
id=$(swift "$finder" "$pid")
screencapture -x -o -l "$id" "$out"
echo "$out"
