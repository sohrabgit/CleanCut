import XCTest

/// A slow, deliberate walk through the app for the README demo GIF.
/// Runs only when recording: `make demo` (sets CLEANCUT_DEMO=1).
final class DemoRecordingTests: XCTestCase {
    @MainActor
    func testDemoFlow() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANCUT_DEMO"] == "1", "Only runs when recording the demo")
        let app = XCUIApplication()
        app.launchArguments += ["-resetState", "-hasSeenSelectHint", "YES"]
        app.launch()
        pause(1.5)

        // Prefer a sample whose name says it's the hero shot, else the first one.
        let samples = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sample:'"))
        let hero = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'hero'")).firstMatch
        (hero.exists ? hero : samples.firstMatch).tap()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 20))
        pause(2.0) // scan → lift

        app.buttons["Select"].tap()
        pause(1.8)
        app.buttons["Background"].tap()
        pause(0.8)
        app.buttons["Studio background"].tap()
        pause(1.2)
        app.buttons["Sand background"].tap()
        pause(1.2)
        app.buttons["White background"].tap()
        pause(0.8)

        app.buttons["Shadow"].tap()
        pause(0.6)
        for style in ["Soft", "Contact", "Natural"] {
            app.buttons[style].tap()
            pause(1.1)
        }

        for format in ["Vinted", "Amazon", "Depop"] {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", format)).firstMatch.tap()
            pause(1.2)
        }

        app.buttons["Export"].tap()
        pause(2.5)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
