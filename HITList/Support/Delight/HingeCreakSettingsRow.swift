import SwiftUI

/// Extras → Creaky hinge (briefs 50, 55): on by default, shown only on a device whose hinge has reported (the iPhone
/// Duo), so no one else sees a switch that does nothing. `DelightSettingsSection` lists it with one line. The key is
/// still `delight.squeakyHinge`, so whoever switched it off in 0.7.0's earlier builds keeps it off.
struct HingeCreakSettingsRow: View {
    @AppStorage(HingeCreak.key, store: AppGroup.defaults) private var creaky = true

    static let title = "Creaky hinge"

    static func isShown(hasHinge: Bool) -> Bool { hasHinge }

    var body: some View {
        if Self.isShown(hasHinge: HingeCreak.shared.hasHinge) {
            Toggle(isOn: $creaky) {
                HITMenuRowLabel(Self.title, subtitle: "A quiet wooden creak as you open and close the phone",
                                systemImage: "door.left.hand.open")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
        }
    }
}
