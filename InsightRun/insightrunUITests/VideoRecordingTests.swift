import XCTest

final class VideoRecordingTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
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
        // === DASHBOARD ===
        sleep(2)

        // Scroll down to show recovery metrics
        app.swipeUp()
        sleep(1)

        // Scroll back up for score buttons
        app.swipeDown()
        sleep(1)

        // Open Effort score detail sheet
        tapElement(identifier: "score-effort")
        sleep(2)
        dismissSheet()

        // Open Sleep score detail sheet
        tapElement(identifier: "score-sleep")
        sleep(2)
        dismissSheet()

        // Open Readiness score detail sheet
        tapElement(identifier: "score-readiness")
        sleep(2)
        dismissSheet()

        // Navigate to Weekly Summary
        let weeklySummaryLink = app.buttons.matching(identifier: "weekly-summary-link").firstMatch
        if weeklySummaryLink.waitForExistence(timeout: 3) && weeklySummaryLink.isHittable {
            weeklySummaryLink.tap()
            sleep(2)
            app.swipeUp()
            sleep(1)
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // Create Training Plan (do NOT swipe up - it triggers Export button)
        let trainingPlanButton = app.buttons.matching(identifier: "create-training-plan").firstMatch
        if trainingPlanButton.waitForExistence(timeout: 3) && trainingPlanButton.isHittable {
            trainingPlanButton.tap()
            sleep(3)
            dismissSheet()
        }

        // === WORKOUTS ===
        app.tabBars.buttons.element(boundBy: 1).tap()
        sleep(1)

        // Open first workout detail
        let firstWorkout = app.buttons.matching(identifier: "workout-row-0").firstMatch
        if firstWorkout.waitForExistence(timeout: 3) && firstWorkout.isHittable {
            firstWorkout.tap()
            sleep(2)

            // Scroll through ALL workout detail sections
            app.swipeUp()
            sleep(1)
            app.swipeUp()
            sleep(1)
            app.swipeUp()
            sleep(1)
            app.swipeUp()
            sleep(1)
            app.swipeUp()
            sleep(1)

            // Go back
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // === STATISTICS ===
        app.tabBars.buttons.element(boundBy: 2).tap()
        sleep(2)

        // Expand Personal Records
        let recordsToggle = app.buttons.matching(identifier: "personal-records-toggle").firstMatch
        if recordsToggle.waitForExistence(timeout: 3) && recordsToggle.isHittable {
            recordsToggle.tap()
            sleep(1)
            app.swipeUp()
            sleep(1)
        }

        // Statistics - Progression tab
        let progressionTab = app.buttons["Progression"]
        if progressionTab.waitForExistence(timeout: 2) {
            progressionTab.tap()
            sleep(2)
        }

        // === BACK TO DASHBOARD ===
        app.tabBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        // Scroll dashboard to show recovery section
        app.swipeUp()
        sleep(2)

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

    private func tapElement(identifier: String) {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        if button.waitForExistence(timeout: 2) && button.isHittable {
            button.tap()
        }
    }

    private func dismissSheet() {
        let closeButton = app.buttons["sheet-close"]
        if closeButton.waitForExistence(timeout: 2) && closeButton.isHittable {
            closeButton.tap()
            sleep(1)
            return
        }
        // Fallback: swipe down to dismiss
        app.swipeDown()
        sleep(1)
    }
}
