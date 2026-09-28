import XCTest

/// End-to-end smoke test of the core flow on a bundled sample: open → lift →
/// switch tools and formats → export sheet. Screenshots are attached to the
/// test result (see `make screenshots`).
final class EditorFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEditASampleAndOpenExport() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetState"]
        app.launch()
        snapshot(app, "01-home")

        let sample = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sample:'")).firstMatch
        try XCTSkipUnless(sample.waitForExistence(timeout: 5), "No bundled samples in this build")
        sample.tap()

        let export = app.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 20), "Editor should finish processing")
        sleep(1) // let the lift animation settle
        snapshot(app, "02-editor-background")

        app.buttons["Shadow"].tap()
        snapshot(app, "03-editor-shadow")

        let canvas = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Studio preview'")).firstMatch
        XCTAssertTrue(canvas.exists)
        canvas.pinch(withScale: 2.5, velocity: 2)
        snapshot(app, "03b-editor-zoomed")
        canvas.doubleTap()

        app.buttons["Select"].tap()
        snapshot(app, "04-editor-select")

        app.buttons["Edges"].tap()
        chip(app, "Vinted").tap()
        snapshot(app, "05-editor-edges-vinted")

        chip(app, "Amazon").tap()
        app.buttons["Background"].tap()
        snapshot(app, "06-editor-amazon-locked")

        export.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save")).firstMatch.waitForExistence(timeout: 5))
        sleep(2) // thumbnails
        snapshot(app, "07-export-sheet")
    }

    /// Regression: opening the editor straight after the Photos picker closed
    /// laid it out edge to edge, so the top bar sat under the status bar and the
    /// tool tabs under the home indicator, where taps didn't reach them.
    /// Needs a photo in the Simulator's library (`xcrun simctl addmedia`).
    @MainActor
    func testEditorFromPhotoLibraryStaysInsideTheSafeArea() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetState"]
        app.launch()

        app.buttons["Choose from Photos"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        try XCTSkipUnless(photo.waitForExistence(timeout: 10), "No photos in the Simulator's library")
        // The picker runs out of process, so its cells report as not hittable.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let export = app.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 30), "Editor should finish processing")
        sleep(1)
        snapshot(app, "09-editor-from-library")

        let window = app.windows.firstMatch.frame
        let close = app.buttons["Close"].frame
        let edges = app.buttons["Edges"].frame
        XCTAssertGreaterThanOrEqual(close.minY, window.minY + 44, "Top bar is under the status bar")
        XCTAssertLessThanOrEqual(edges.maxY, window.maxY - 20, "Tool tabs are under the home indicator")

        app.buttons["Select"].tap()
        sleep(1)
        // Library photos go through U²-Netp in the Simulator: check its objects.
        snapshot(app, "10-select-from-library")

        app.buttons["Edges"].tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Clean edges'")).firstMatch.waitForExistence(timeout: 2))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Choose from Photos"].waitForExistence(timeout: 5), "Close should dismiss the editor")
    }

    /// Regression: tapping Save to Photos crashed the app. The Photos change
    /// block inherited the view's `MainActor` isolation, and Photos runs it on
    /// its own queue, so Swift's runtime isolation check trapped.
    @MainActor
    func testSaveToPhotosFromTheExportSheet() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetState"]
        app.launch()

        let sample = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sample:'")).firstMatch
        try XCTSkipUnless(sample.waitForExistence(timeout: 5), "No bundled samples in this build")
        sample.tap()

        let export = app.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 20), "Editor should finish processing")
        export.tap()

        let save = app.buttons["Save to Photos"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // The add-only permission prompt belongs to SpringBoard, not the app.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Allow'")).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        XCTAssertTrue(app.staticTexts["Saved to Photos"].waitForExistence(timeout: 20), "Save should finish without crashing")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testBatchEmptyState() {
        let app = XCUIApplication()
        app.launchArguments += ["-resetState"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Batch edit'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Choose Photos"].waitForExistence(timeout: 5))
        snapshot(app, "08-batch-empty")
    }

    /// Chips combine their title and subtitle ("Vinted, 4:5") into one label.
    @MainActor
    private func chip(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        usleep(500_000) // let panel transitions finish
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
