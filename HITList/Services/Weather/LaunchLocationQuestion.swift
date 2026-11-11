import Foundation

/// Whether HITList asks for the location now, by itself (brief 83): once, at the first launch, shortly after the first
/// screen is showing and the app is in front, so the companion keeps local time and dresses for the weather. Pure, so
/// every case is a test; `CompanionWeather` gathers the situation and does what this says.
///
/// - Never in a test host, a UI test, a screenshot run (`-seedDemoData`, `-seedDemoSky`, `-seedDemoWeatherAccess`) or
///   a Debug build, unless that Debug build was launched with `-askLocationAtLaunch YES` (a session's own simulator).
/// - Never with Companions off (nobody needs the sky), with Weather switched off, or once it has asked (or the switch
///   has). A permission already answered without the flag is taken as the answer (`.answered`), with no prompt.
/// - Not yet while the app is behind another, still launching, or something covers the first screen (a sheet, a
///   popover tip, a card, the keyboard): it waits and looks again.
enum LaunchLocationQuestion {
    /// The launch argument that lets a Debug build ask by itself.
    static let argument = "-askLocationAtLaunch"
    /// Runs that never ask, whatever the build: screenshots, demos and the UI tests that use them.
    static let quietArguments = ["-seedDemoData", "-seedDemoSky", "-seedDemoWeatherAccess"]

    enum Build: Equatable {
        case debug, release

        static var current: Build {
            #if DEBUG
            .debug
            #else
            .release
            #endif
        }
    }

    enum Decision: Equatable {
        /// Ask now.
        case ask
        /// Not yet: look again in a moment (the app is behind, or something covers the first screen).
        case later
        /// Not in this run.
        case never
        /// Nothing to ask: the permission is already answered (the asked flag was lost with the defaults, say), so
        /// it is taken as the answer.
        case answered
    }

    /// What a run is, fixed at launch: the build, its arguments, whether it hosts the unit tests.
    struct Run: Equatable {
        var build: Build
        var arguments: [String]
        var isTestHost: Bool

        static var current: Run {
            Run(build: .current, arguments: CommandLine.arguments, isTestHost: LaunchLocationQuestion.isTestHost)
        }
    }

    struct Situation: Equatable {
        var build: Build
        var arguments: [String]
        /// The app is the host of the unit tests.
        var isTestHost: Bool
        /// Settings → Extras → Companions.
        var companionsOn: Bool
        /// Settings → Extras → Weather (on unless someone switched it off).
        var weatherOn: Bool
        /// The system's question may already have been shown (by the switch in 0.9.2, or by this at a launch).
        var asked: Bool
        /// The app is in front, its first screen up and settled.
        var isInFront: Bool
        /// Nothing over the first screen: no sheet, popover, alert, card or keyboard.
        var isScreenClear: Bool
    }

    /// The decision. `access` reads the permission (no prompt) and is called only once everything else says yes,
    /// so a run that never asks never touches Core Location.
    static func decide(_ situation: Situation, access: () -> WeatherAccess) -> Decision {
        if situation.isTestHost { return .never }
        if quietArguments.contains(where: situation.arguments.contains) { return .never }
        if situation.build == .debug && !optedIn(situation.arguments) { return .never }
        guard situation.companionsOn, situation.weatherOn, !situation.asked else { return .never }
        guard situation.isInFront, situation.isScreenClear else { return .later }
        guard access() == .notDetermined else { return .answered }
        return .ask
    }

    /// `-askLocationAtLaunch YES` (or `true`, `1`).
    static func optedIn(_ arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: argument) else { return false }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return false }
        return ["YES", "yes", "true", "1"].contains(arguments[next])
    }

    /// The app hosts the unit tests (they never reach `CompanionWeather.start()`, and this says so again).
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
