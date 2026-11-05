import SwiftUI

/// Extras → Squeaky hinge (brief 50): on by default, shown only on a device whose hinge has reported (the iPhone
/// Duo), so no one else sees a switch that does nothing. `DelightSettingsSection` lists it with one line.
struct HingeCreakSettingsRow: View {
    @AppStorage(HingeCreak.key, store: AppGroup.defaults) private var squeaky = true

    static func isShown(hasHinge: Bool) -> Bool { hasHinge }

    var body: some View {
        if Self.isShown(hasHinge: HingeCreak.shared.hasHinge) {
            Toggle(isOn: $squeaky) {
                HITMenuRowLabel("Squeaky hinge", subtitle: "Creaks as you open and close the phone",
                                systemImage: "door.left.hand.open")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
        }
    }
}
