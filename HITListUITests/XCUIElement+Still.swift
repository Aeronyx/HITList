import XCTest

extension XCUIElement {
    /// Waits until the element has stopped moving: its frame the same over three looks a quarter of a second apart,
    /// or `timeout`. On a simulator made fresh, the software keyboard slides away and back while XCUITest types (its
    /// keys arrive as a hardware keyboard's), and the card above it travels with it; a tap aimed during that lands
    /// where the control was. Round 34: `testTheEditorsDateRowAndQuickAddTitle` and
    /// `QuickAddChipRowUITests.testRowScrollsInsteadOfWrapping` failed that way on every simulator made that evening
    /// (the recordings show the card mid-flight at the tap) and on none before.
    func waitUntilStill(timeout: TimeInterval = 6) {
        var last = frame
        var same = 0
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let now = frame
            if now == last {
                same += 1
                if same >= 3 { return }
            } else {
                same = 0
                last = now
            }
        }
    }
}
