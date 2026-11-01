import SwiftUI

/// Settings → Appearance. A placeholder until the themes session fills it in: theme swatches and the
/// "Reduce effects" switch belong here (keys in `Preferences`).
struct AppearanceSettingsSection: View {
    var body: some View {
        HITGroup("Appearance", footer: "HITList is dark only. Colour themes arrive in a later build.") {
            HITMenuRow("Theme", systemImage: "paintpalette", value: "Slate")
        }
    }
}
