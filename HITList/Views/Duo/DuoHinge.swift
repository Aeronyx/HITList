import SwiftUI

/// The iPhone Duo's hinge as the layouts see it (brief 50): closed, partly open or open flat. Apple's guidance
/// is to prefer this over the raw angle for layout; the creak uses the angle (`HingeCreak`).
enum HingeStatus: Equatable {
    case closed, partiallyOpen, fullyOpen
}

extension View {
    /// Calls `action` with the hinge's status when it changes (iOS 27.1's `onHingeChange`): nil where the view's
    /// hierarchy gets no hinge updates (every device without one). Does nothing before iOS 27.1, on the Mac, and
    /// when built with an older SDK (the CI runner).
    func onHingeStatusChange(_ action: @escaping (HingeStatus?) -> Void) -> some View {
        modifier(HingeStatusWatch(action: action))
    }
}

private struct HingeStatusWatch: ViewModifier {
    let action: (HingeStatus?) -> Void

    func body(content: Content) -> some View {
        #if compiler(>=6.4) && os(iOS)
        if #available(iOS 27.1, *) {
            content.onHingeChange { old, new in
                let status = new.hinge.flatMap { HingeStatus($0.status) }
                if old.hinge.flatMap({ HingeStatus($0.status) }) != status { action(status) }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if compiler(>=6.4) && os(iOS)
@available(iOS 27.1, *)
extension HingeStatus {
    init?(_ status: DeviceHinge.Status) {
        switch status {
        case .closed: self = .closed
        case .partiallyOpen: self = .partiallyOpen
        case .fullyOpen: self = .fullyOpen
        default: return nil
        }
    }
}
#endif
