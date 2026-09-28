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
