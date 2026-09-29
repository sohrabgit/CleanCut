import XCTest

/// A slow, deliberate walk through the app for the README demo GIF.
/// Runs only when recording: `make demo` (sets CLEANCUT_DEMO=1).
///
/// It starts with guided capture on the replay camera, so the demo needs no
/// bundled photos and looks the same on every machine: the coach walks
/// through each tip, the shot turns ready, and the photo goes to the editor.
final class DemoRecordingTests: XCTestCase {
    @MainActor
    func testDemoFlow() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANCUT_DEMO"] == "1", "Only runs when recording the demo")
        let app = XCUIApplication()
        app.launchArguments += ["-resetState", "-hasSeenSelectHint", "YES", "-captureReplay", "-hideLocalSamples"]
        app.launch()
        pause(1.5)

        // Guided capture: the replay timeline plays every tip, then a good shot.
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.staticTexts["Looks great, take the photo"].waitForExistence(timeout: 30))
        pause(1.8)
        app.buttons["shutter"].tap()

        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 20))
        pause(2.2) // scan → lift

        app.buttons["Studio background"].tap()
        pause(1.2)
        app.buttons["Sand background"].tap()
        pause(1.2)
        app.buttons["White background"].tap()
        pause(0.8)

        app.buttons["Shadow"].tap()
        pause(0.6)
        for style in ["Contact", "Natural"] {
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
