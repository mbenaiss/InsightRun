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
        XCUIDevice.shared.appearance = .dark

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

        // Wake the UI interruption monitor via status bar (always safe)
        let statusBar = app.statusBars.firstMatch
        if statusBar.exists {
            statusBar.tap()
        }
        sleep(1)
    }

    // MARK: - Navigation

    private func navigateAppPreview() {
        // === DASHBOARD (≈8s) ===
        sleep(3)

        // Open Readiness score detail (the marquee score)
        tapElement(identifier: "pulse-ring-hero")
        sleep(2)
        dismissSheet()

        // Scroll to show signals + weekly activity
        app.swipeUp()
        sleep(2)

        // === WORKOUTS (≈8s) ===
        app.tabBars.buttons.element(boundBy: 1).tap()
        sleep(3)

        // Open first workout detail
        tapElement(identifier: "workout-row-0")
        sleep(2)

        // Scroll through workout detail (map → metrics)
        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(1)

        // Go back to list
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // === STATISTICS (≈8s) ===
        app.tabBars.buttons.element(boundBy: 2).tap()
        sleep(3)

        // Scroll to reveal KPIs + charts
        app.swipeUp()
        sleep(2)

        // Switch to Progression tab
        if let tab = findProgressionTab() {
            if tab.isHittable {
                tab.tap()
            } else {
                tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            sleep(3)
        }

        // === GOALS (≈8s) ===
        app.tabBars.buttons.element(boundBy: 3).tap()
        sleep(3)

        // Tap the active goal row to open detail
        let firstGoalRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "10K")).firstMatch
        if firstGoalRow.waitForExistence(timeout: 2) {
            if firstGoalRow.isHittable {
                firstGoalRow.tap()
            } else {
                firstGoalRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            sleep(2)
            app.swipeUp()
            sleep(1)
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
        }

        // === BACK TO DASHBOARD — AI ASSISTANT (≈4s) ===
        app.tabBars.buttons.element(boundBy: 0).tap()
        sleep(1)
        tapElement(identifier: "floating-ai-button")
        sleep(2)
        dismissSheet()
    }

    /// Resolve the Progression segment in the custom Statistics tab control.
    /// Falls back across all supported localizations.
    private func findProgressionTab() -> XCUIElement? {
        for label in ["Progression", "Évolution", "Progresión", "Progressione", "Progressão", "進行"] {
            let btn = app.buttons[label]
            if btn.waitForExistence(timeout: 1) { return btn }
        }
        return nil
    }

    // MARK: - Helpers

    /// Tap an element by accessibility identifier. Falls back to coordinate tap
    /// when the element is not reported as hittable (e.g. SwiftUI cards inside
    /// a ScrollView whose isHittable check times out under XCUITest).
    private func tapElement(identifier: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        guard element.waitForExistence(timeout: 3) else { return }
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
