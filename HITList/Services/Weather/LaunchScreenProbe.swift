import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// What is on screen, for the location question at the first launch (brief 83): whether the app is in front and
/// whether anything covers its first screen. Reads UIKit and AppKit only; changes nothing.
@MainActor
enum LaunchScreenProbe {
    /// The app is the active one, with a window showing.
    static func isInFront() -> Bool {
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { return false }
        return activeScene() != nil
        #else
        return NSApp.isActive && (NSApp.keyWindow ?? NSApp.mainWindow)?.isVisible == true
        #endif
    }

    /// Nothing over the first screen: no sheet, popover (a tip's included), alert, What's New card, keyboard (the
    /// iPhone's quick-add card rides it) or Mac sheet, modal or child window.
    static func isScreenClear() -> Bool {
        #if os(iOS)
        guard let scene = activeScene() else { return false }
        for window in scene.windows where !window.isHidden {
            if window.rootViewController?.presentedViewController != nil { return false }
        }
        if KeyboardObserver.shared.height > 0 { return false }
        return true
        #else
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        if NSApp.modalWindow != nil || window.attachedSheet != nil { return false }
        if let children = window.childWindows, children.contains(where: \.isVisible) { return false }
        return true
        #endif
    }

    #if os(iOS)
    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
    #endif
}
