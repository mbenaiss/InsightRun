import XCTest

final class ActivationFlowUITests: XCTestCase {
    func testLatestRunOpensDetailAndAnalysis() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DEMO_MODE",
            "-AppleLanguages", "(fr)",
            "-AppleLocale", "fr_FR"
        ]
        app.launch()

        let activationButton = app.buttons["dashboard-activation-primary"]
        XCTAssertTrue(activationButton.waitForExistence(timeout: 10))
        activationButton.tap()

        let detail = app.descendants(matching: .any)["workout-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))

        let analysis = app.descendants(matching: .any)["workout-ai-analysis"]
        XCTAssertTrue(analysis.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Prochaine action"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Activation-Workout-Analysis"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
