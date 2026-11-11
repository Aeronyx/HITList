import Foundation
import HITListCore

/// The widget extension's road for `WidgetCompletionIntent` (brief 81), the one the Mac takes: the extension writes the
/// tap down and nudges the app, and never completes anything itself (it never opens the store). The app applies it
/// when the nudge arrives, or the next time it runs.
enum WidgetIntentRoad {
    /// The outbox beside the snapshot this extension reads (`WidgetSnapshotStore`).
    static var outbox: WidgetOutbox? {
        WidgetOutbox(container: AppGroup.containerURL, suffix: WidgetSnapshotStore.suffix)
    }

    @MainActor
    static func deliver(_ request: WidgetRequest) async throws {
        try record(request, in: outbox)
        WidgetOutboxBell.ring(suffix: WidgetSnapshotStore.suffix)
    }
}
