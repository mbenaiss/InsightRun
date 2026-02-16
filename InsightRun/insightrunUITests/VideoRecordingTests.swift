import XCTest

final class VideoRecordingTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-DEMO_MODE"]
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
    }

    func testAppPreviewNavigation() {
        // Dismiss any pending alerts
        app.tap()
        sleep(1)

        // Dashboard - show recovery and readiness
        sleep(3)

        // Navigate to Workouts
        app.tabBars.buttons.element(boundBy: 1).tap()
        sleep(2)

        // Open first workout detail
        let firstWorkout = app.buttons.matching(identifier: "workout-row-0").firstMatch
        if firstWorkout.waitForExistence(timeout: 5) && firstWorkout.isHittable {
            firstWorkout.tap()
            sleep(2)

            // Scroll through workout detail
            app.swipeUp()
            sleep(2)
            app.swipeUp()
            sleep(1)

            // Go back
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // Navigate to Statistics
        app.tabBars.buttons.element(boundBy: 2).tap()
        sleep(3)

        // Back to Dashboard
        app.tabBars.buttons.element(boundBy: 0).tap()
        sleep(2)

        // Scroll dashboard to show recovery
        app.swipeUp()
        sleep(3)

        // Return to dashboard
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        sleep(2)
    }
}
