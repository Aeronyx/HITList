import Foundation
import HITListCore

/// The app's road for `WidgetCompletionIntent` (brief 81), the one iPhone and iPad take (`LiveActivityIntent` runs the
/// intent here, launching the app in the background if it isn't running): the tap is written down first, as in the
/// extension, then handed to `WidgetCompletionCenter`, which applies it and keeps the app awake until the export that
/// carries it has finished (or the system's time runs out; the tap waits in the outbox then).
enum WidgetIntentRoad {
    /// Hosted tests write into a folder of their own: the test process is a Debug HITList in the real App Group, whose
    /// outbox George's app drains.
    @MainActor static var outboxOverride: WidgetOutbox?

    /// This store's own outbox in the App Group (a side store has its own).
    @MainActor static var outbox: WidgetOutbox? {
        if let outboxOverride { return outboxOverride }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        return WidgetOutbox(container: AppGroup.containerURL, suffix: ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"])
    }

    @MainActor
    static func deliver(_ request: WidgetRequest) async throws {
        try record(request, in: outbox)
        NotificationCenter.default.post(name: .widgetTapRecorded, object: nil, userInfo: ["request": request])
    }
}

extension Notification.Name {
    /// Posted on the main actor once `WidgetCompletionIntent` has written a tap into the outbox in this process.
    static let widgetTapRecorded = Notification.Name("HITList.widgetTapRecorded")
}
