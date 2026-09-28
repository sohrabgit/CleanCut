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

        assertEditorIsInsideTheSafeArea(app)

        app.buttons["Select"].tap()
        sleep(1)
        // Library photos go through U²-Netp in the Simulator: check its objects.
        snapshot(app, "10-select-from-library")

        app.buttons["Edges"].tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Clean edges'")).firstMatch.waitForExistence(timeout: 2))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Choose from Photos"].waitForExistence(timeout: 5), "Close should dismiss the editor")
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

    /// Guided capture with the replay camera: a staged problem shows its tip,
    /// a good shot turns ready, and the shutter opens the editor, inside the
    /// safe area (the capture cover has to be gone first).
    @MainActor
    func testGuidedCaptureOpensTheEditor() throws {
        let blurry = XCUIApplication()
        blurry.launchArguments += ["-resetState", "-captureReplay", "blurry"]
        blurry.launch()
        blurry.buttons["Take Photo"].tap()
        XCTAssertTrue(blurry.staticTexts["Hold still, the photo is blurry"].waitForExistence(timeout: 15))
        snapshot(blurry, "10-capture-blurry")

        let app = XCUIApplication()
        app.launchArguments += ["-resetState", "-captureReplay", "good"]
        app.launch()
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.staticTexts["Looks great, take the photo"].waitForExistence(timeout: 15))
        snapshot(app, "11-capture-ready")

        app.buttons["shutter"].tap()
        let export = app.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 30), "Editor should open with the captured photo")
        sleep(1)
        snapshot(app, "12-editor-from-capture")

        assertEditorIsInsideTheSafeArea(app)
    }

    /// The editor's top bar clears the status bar (44 pt on iPhone, 24 on iPad)
    /// and its tool tabs clear the home indicator.
    @MainActor
    private func assertEditorIsInsideTheSafeArea(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let statusBar: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 24 : 44
        XCTAssertGreaterThanOrEqual(app.buttons["Close"].frame.minY, window.minY + statusBar, "Top bar is under the status bar", file: file, line: line)
        XCTAssertLessThanOrEqual(app.buttons["Edges"].frame.maxY, window.maxY - 20, "Tool tabs are under the home indicator", file: file, line: line)
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
