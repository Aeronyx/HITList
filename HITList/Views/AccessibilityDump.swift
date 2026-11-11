#if DEBUG && os(iOS)
import OSLog
import UIKit

/// Debug only (brief 94): what VoiceOver can reach, written to the log, for checking without VoiceOver. Launch with
/// `-dumpAccessibility YES`; every 4 s the key window's accessibility tree is walked as VoiceOver walks it (an element
/// is a stop and its children are not; hidden elements and hidden views are skipped; a modal view hides its siblings)
/// and each stop is logged under the "accessibility" category, one line each: label | value | traits | frame.
/// Read it with `xcrun simctl spawn <udid> log show --last 2m --info --predicate 'category == "accessibility"'`.
@MainActor
enum AccessibilityDump {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "accessibility")
    private static var task: Task<Void, Never>?

    static func startIfRequested() {
        guard UserDefaults.standard.bool(forKey: "dumpAccessibility"), task == nil else { return }
        task = Task { @MainActor in
            var pass = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                pass += 1
                guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .flatMap(\.windows).first(where: \.isKeyWindow) else { continue }
                var stops: [String] = []
                walk(window, into: &stops, depth: 0)
                log.info("pass \(pass, privacy: .public): \(stops.count, privacy: .public) stops")
                for (index, stop) in stops.enumerated() {
                    log.info("pass \(pass, privacy: .public) #\(index, privacy: .public) \(stop, privacy: .public)")
                }
            }
        }
    }

    private static func walk(_ object: NSObject, into stops: inout [String], depth: Int) {
        guard depth < 60 else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        if object.accessibilityElementsHidden { return }
        if object.isAccessibilityElement {
            let frame = object.accessibilityFrame.integral
            stops.append("\(object.accessibilityLabel ?? "") | \(object.accessibilityValue ?? "") | "
                         + "\(object.accessibilityTraits.rawValue) | \(Int(frame.minX)),\(Int(frame.minY)) "
                         + "\(Int(frame.width))x\(Int(frame.height))")
            return
        }
        var children: [NSObject] = []
        if let elements = object.accessibilityElements as? [NSObject] {
            children = elements
        } else if object.accessibilityElementCount() != NSNotFound, object.accessibilityElementCount() > 0 {
            for index in 0..<object.accessibilityElementCount() {
                if let child = object.accessibilityElement(at: index) as? NSObject { children.append(child) }
            }
        } else if let view = object as? UIView {
            children = view.subviews
        }
        if let modal = children.last(where: { $0.accessibilityViewIsModal }) { children = [modal] }
        for child in children { walk(child, into: &stops, depth: depth + 1) }
    }
}
#endif
