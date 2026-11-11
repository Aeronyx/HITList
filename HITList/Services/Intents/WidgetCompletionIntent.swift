import AppIntents
import Foundation
import OSLog
import WidgetKit
import HITListCore

/// A row's check on the Today or Upcoming widget, or a red switch's pill on the Flipboard widget (brief 81). Compiled
/// into the app and the widget extension (project.yml), so `Button(intent:)` can name it in the extension and the
/// system can run it in either process; `WidgetIntentRoad` is each process's own road.
///
/// It first writes the tap down in the outbox (`WidgetOutbox`, durable), then reloads the widgets, which draw the row
/// checked. The app does the completing, never the extension:
/// - **iPhone and iPad**: `LiveActivityIntent` (below) is the protocol App Intents gives for an intent that must run in
///   the app's process from a widget or a control: the system launches the app in the background if it isn't
///   running, without opening it, and runs `perform()` there. The app records the tap and applies it at once.
/// - **The Mac**: `LiveActivityIntent` is unavailable on macOS, and macOS 26 has no other way to ask for the app's
///   process, so the system runs the intent in the widget extension. The extension records the tap and rings
///   `WidgetOutboxBell`; the app, which keeps running with its window closed, applies it at once. If the app isn't
///   running, the tap waits in the outbox and the app applies it the next time it starts (the widget says "Open
///   HITList to finish"). macOS 27 adds `allowedExecutionTargets`; it is pinned to the extension there so a newer Mac
///   behaves as the one that was tested (the app would otherwise be launched with its window).
///
/// Each process logs which one ran it (subsystem com.trammells.hitlist, category widgets, "widget tap … recorded by").
struct WidgetCompletionIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete from a Widget"
    static let description = IntentDescription("Checks off a task, or flips a switch, from a HITList widget.")
    /// Only the widgets' buttons run it: not offered in Shortcuts or Spotlight (Siri's is `CompleteTaskIntent`).
    static let isDiscoverable = false

    #if os(macOS)
    @available(macOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { [.widgetKitExtension] }
    #endif

    @Parameter(title: "Task")
    var taskID: String

    /// `WidgetRequest.Action`'s raw value.
    @Parameter(title: "Action")
    var action: String

    /// The due date the widget showed, as seconds since the reference date ("" for none): a number survives the trip
    /// between processes exactly, where a date parameter may be rounded.
    @Parameter(title: "Due")
    var seenDue: String

    @Parameter(title: "Timed")
    var seenHasTime: Bool

    /// The widget's kind ("today", "upcoming", "flipboard"), for the sync log.
    @Parameter(title: "Widget")
    var widget: String

    init() {}

    init(task: WidgetSnapshot.Task, action: WidgetRequest.Action, widget: String) {
        self.taskID = task.id.uuidString
        self.action = action.rawValue
        self.seenDue = task.due.map { String($0.timeIntervalSinceReferenceDate) } ?? ""
        self.seenHasTime = task.hasTime
        self.widget = widget
    }

    /// The request this tap makes, asked at `now`; nil when its parameters don't name a task.
    func request(at now: Date, id: UUID = UUID()) -> WidgetRequest? {
        guard let task = UUID(uuidString: taskID), let action = WidgetRequest.Action(rawValue: action) else { return nil }
        let due = Double(seenDue).map { Date(timeIntervalSinceReferenceDate: $0) }
        return WidgetRequest(id: id, taskID: task, action: action, askedAt: now, seenDue: due, seenHasTime: seenHasTime,
                             widget: widget, recordedBy: WidgetIntentRoad.processDescription)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let request = request(at: Date()) else { throw WidgetIntentFailure.notATask }
        try await WidgetIntentRoad.deliver(request)
        return .result()
    }
}

#if os(iOS)
/// Runs `perform()` in the app's process (see above). The app starts no Live Activity.
extension WidgetCompletionIntent: LiveActivityIntent {}
#endif

enum WidgetIntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case notATask
    case notWritten(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notATask: "That isn't a task HITList knows."
        case .notWritten(let reason): "HITList couldn't save the tap: \(reason)"
        }
    }
}

/// What both roads share: writing the tap down, then the widgets' reload, and the line that says which process did it.
extension WidgetIntentRoad {
    static let log = Logger(subsystem: "com.trammells.hitlist", category: "widgets")

    /// "HITListWidgets 812 com.trammells.hitlist.widgets": the process that ran the intent.
    static var processDescription: String {
        let info = ProcessInfo.processInfo
        return "\(info.processName) \(info.processIdentifier) \(Bundle.main.bundleIdentifier ?? "?")"
    }

    /// Writes `request` into `outbox` before anything else; throws (and the widget draws nothing checked) when it can't.
    static func record(_ request: WidgetRequest, in outbox: WidgetOutbox?) throws {
        guard let outbox else { throw WidgetIntentFailure.notWritten("no App Group") }
        do {
            let wrote = try outbox.record(request)
            log.notice("widget tap \(request.id.uuidString, privacy: .public) (\(request.action.rawValue, privacy: .public) \(request.taskID.uuidString, privacy: .public) from \(request.widget, privacy: .public)) recorded by \(processDescription, privacy: .public)\(wrote ? "" : ", already there", privacy: .public) in \(outbox.folder.lastPathComponent, privacy: .public)")
        } catch {
            log.error("widget tap not recorded by \(processDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw WidgetIntentFailure.notWritten(error.localizedDescription)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// A Darwin notification from the widget extension to a running app: "a tap is in the outbox". It carries nothing (the
/// outbox is the message), may be missed (a suspended iPhone app doesn't get it) and is only a nudge: the app also
/// reads the outbox at launch, on activation, after an import and from the background refresh.
enum WidgetOutboxBell {
    /// Prefixed with the App Group, the namespace a sandboxed app and its extension share; a side store has its own.
    static func name(suffix: String?) -> String {
        "\(AppGroup.id).widget-outbox" + (suffix.map { $0.isEmpty ? "" : ".\($0)" } ?? "")
    }

    static func ring(suffix: String?) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name(suffix: suffix) as CFString), nil, nil, true)
    }
}
