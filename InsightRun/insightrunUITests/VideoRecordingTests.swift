import XCTest

final class VideoRecordingTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Locale-specific tests

    func testAppPreviewEN() {
        launchApp(language: "en", locale: "en_US")
        navigateAppPreview()
    }

    func testAppPreviewFR() {
        launchApp(language: "fr", locale: "fr_FR")
        navigateAppPreview()
    }

    // MARK: - Launch

    private func launchApp(language: String, locale: String) {
        app.launchArguments = [
            "-DEMO_MODE",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        app.launch()

        addUIInterruptionMonitor(withDescription: "System Alert") { alert in
            let cancelButtons = ["Cancel", "Annuler", "Not Now", "Pas maintenant", "Don't Allow", "Ne pas autoriser"]
            for title in cancelButtons {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            if alert.buttons.count > 0 {
                alert.buttons.firstMatch.tap()
                return true
            }
            return false
        }

        // Dismiss any pending alerts
        app.tap()
        sleep(1)
    }

    // MARK: - Navigation

    private func navigateAppPreview() {
        // Dashboard - show recovery and readiness
        sleep(2)

        // Navigate to Workouts
        app.tabBars.buttons.element(boundBy: 1).tap()
        sleep(1)

        // Open first workout detail
        let firstWorkout = app.buttons.matching(identifier: "workout-row-0").firstMatch
        if firstWorkout.waitForExistence(timeout: 3) && firstWorkout.isHittable {
            firstWorkout.tap()
            sleep(2)

            // Scroll through workout detail to AI analysis
            app.swipeUp()
            sleep(1)
            app.swipeUp()
            sleep(1)

            // Go back
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // Navigate to Statistics - Overview
        app.tabBars.buttons.element(boundBy: 2).tap()
        sleep(2)

        // Statistics - Progression tab
        let progressionTab = app.buttons["Progression"]
        if progressionTab.waitForExistence(timeout: 2) {
            progressionTab.tap()
            sleep(2)
        }

        // Back to Dashboard
        app.tabBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        // Scroll dashboard to show recovery
        app.swipeUp()
        sleep(2)

        // Scroll back up for score buttons
        app.swipeDown()
        sleep(1)

        // Open Readiness score detail
        let readinessButton = app.buttons.matching(identifier: "score-readiness").firstMatch
        if readinessButton.waitForExistence(timeout: 2) && readinessButton.isHittable {
            readinessButton.tap()
            sleep(2)
            dismissSheet()
        }

        // Open AI Assistant
        let aiButton = app.buttons["floating-ai-button"]
        if aiButton.waitForExistence(timeout: 2) {
            aiButton.tap()
            sleep(2)
            dismissSheet()
        }

        sleep(1)
    }

    // MARK: - Helpers

    private func dismissSheet() {
        let closeButton = app.buttons["sheet-close"]
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.tap()
            sleep(1)
            return
        }
        app.swipeDown()
        sleep(1)
    }
}
