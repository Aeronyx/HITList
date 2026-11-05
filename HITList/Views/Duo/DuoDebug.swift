import SwiftUI

/// Debug-only launch arguments for looking at the Duo's layouts where the hardware isn't to hand (brief 50):
/// the simulator's fold is Device Hub's pose buttons, which a session can't press.
///
/// - `-duoVerticalBar trailing` (or `leading`): any iPhone lays its tab island out as on the Duo's outer display.
/// - `-duoStandIn YES`: an iPad counts as a phone, so an iPad mini (744 × 1133 pt) stands in for the inner
///   display (669 × 951 pt): the Duo shell, its columns, Upcoming's board, Flipboard's even grid.
/// - `-duoCrease 360`: a 24 pt crease from top to bottom centred at that x, as the system reports the fold
///   while the device is partly open (an active `division` region), where the system reports none.
enum DuoDebug {
    static var standIn: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "duoStandIn")
        #else
        false
        #endif
    }

    static var verticalBarEdge: HorizontalEdge? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "duoVerticalBar") {
        case "trailing": return .trailing
        case "leading": return .leading
        default: return nil
        }
        #else
        return nil
        #endif
    }

    static func crease(in size: CGSize) -> CGRect? {
        #if DEBUG
        let x = UserDefaults.standard.double(forKey: "duoCrease")
        guard x > 0, x < size.width else { return nil }
        return CGRect(x: x - 12, y: 0, width: 24, height: size.height)
        #else
        return nil
        #endif
    }
}
