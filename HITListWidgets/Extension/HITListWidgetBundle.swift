import SwiftUI
import WidgetKit

/// HITList's widgets (brief 74). Each reads the snapshot the app writes (`WidgetSnapshotStore`) and asks
/// HITListCore's `WidgetContent` what to show at each moment of its timeline.
@main
struct HITListWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        UpcomingWidget()
        FlipboardWidget()
    }
}
