import XCTest

final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-DEMO_MODE"]
        setupSnapshot(app)
        app.launch()

        // Dismiss any system alerts (Apple ID login, notifications, etc.)
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

    // MARK: - Light Mode

    func testLightModeScreenshots() {
        XCUIDevice.shared.appearance = .light
        sleep(1)
        app.tap()
        sleep(1)
        captureAllScreenshots(prefix: "Light")
    }

    // MARK: - Dark Mode

    func testDarkModeScreenshots() {
        XCUIDevice.shared.appearance = .dark
        sleep(1)
        app.tap()
        sleep(1)
        captureAllScreenshots(prefix: "Dark")
    }

    // MARK: - Screenshot Capture

    private func captureAllScreenshots(prefix: String) {
        // 01 - Dashboard (recovery score, readiness)
        sleep(3)
        snapshot("\(prefix)-01-Dashboard")

        // === WORKOUT SCREENSHOTS FIRST (before any sheets that break accessibility tree) ===

        // 02 - Workout List
        app.tabBars.buttons.element(boundBy: 1).tap()
        sleep(3)
        snapshot("\(prefix)-02-WorkoutList")

        // 03 - Workout Detail (map + metrics + AI analysis)
        let workoutRow = findWorkoutRow()
        if let row = workoutRow {
            row.tap()
            sleep(3)
            snapshot("\(prefix)-03-WorkoutDetail")

            // 04 - AI Analysis (scroll down to find it)
            app.swipeUp()
            sleep(1)
            snapshot("\(prefix)-04-AIAnalysis")

            // Go back to workout list
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // 05 - Statistics Overview
        app.tabBars.buttons.element(boundBy: 2).tap()
        sleep(2)
        snapshot("\(prefix)-05-Statistics")

        // 10 - Statistics Progression (tap Progression tab)
        let progressionTab = app.buttons["Progression"]
        if progressionTab.waitForExistence(timeout: 3) {
            progressionTab.tap()
            sleep(2)
            snapshot("\(prefix)-10-Progression")
        }

        // === BACK TO DASHBOARD FOR SCORE SHEETS ===

        // 06 - Recovery Dashboard (scroll down on dashboard)
        app.tabBars.buttons.element(boundBy: 0).tap()
        sleep(2)
        app.swipeUp()
        sleep(1)
        snapshot("\(prefix)-06-Recovery")

        // Scroll back up for the score buttons
        app.swipeDown()
        sleep(1)

        // 07 - Readiness Score Detail Sheet
        let readinessButton = findHittableElement(identifier: "score-readiness", elementType: .button)
        if let btn = readinessButton {
            btn.tap()
            sleep(2)
            snapshot("\(prefix)-07-ReadinessDetail")
            dismissSheet()
        }

        // 11 - Sleep Score Detail Sheet
        let sleepButton = findHittableElement(identifier: "score-sleep", elementType: .button)
        if let btn = sleepButton {
            btn.tap()
            sleep(2)
            snapshot("\(prefix)-11-SleepDetail")
            dismissSheet()
        }

        // 12 - Effort Score Detail Sheet
        let effortButton = findHittableElement(identifier: "score-effort", elementType: .button)
        if let btn = effortButton {
            btn.tap()
            sleep(2)
            snapshot("\(prefix)-12-EffortDetail")
            dismissSheet()
        }

        // 08 - AI Assistant (tap floating button)
        let aiButton = app.buttons["floating-ai-button"]
        if aiButton.waitForExistence(timeout: 3) {
            aiButton.tap()
            sleep(2)
            snapshot("\(prefix)-08-AIAssistant")
            dismissSheet()
        }
    }

    // MARK: - Sheet Dismissal

    /// Dismiss the currently presented sheet using close button or swipe
    private func dismissSheet() {
        // Try the sheet-close accessibility identifier first
        let closeButton = app.buttons["sheet-close"]
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.tap()
            sleep(1)
            return
        }

        // Try xmark button
        let xmark = app.buttons.matching(NSPredicate(format: "label CONTAINS 'xmark' OR label CONTAINS 'close' OR label CONTAINS 'Close' OR label CONTAINS 'Fermer'")).firstMatch
        if xmark.exists {
            xmark.tap()
            sleep(1)
            return
        }

        // Fallback: swipe down
        app.swipeDown()
        sleep(1)
    }

    // MARK: - Element Finding

    /// Find a hittable element by identifier, handling duplicates from TabView pages
    private func findHittableElement(identifier: String, elementType: XCUIElement.ElementType = .any) -> XCUIElement? {
        let query = elementType == .button
            ? app.buttons.matching(identifier: identifier)
            : app.descendants(matching: elementType).matching(identifier: identifier)

        // Wait for at least one match
        let first = query.firstMatch
        guard first.waitForExistence(timeout: 3) else { return nil }

        // If only one match, return it
        if query.count == 1 { return first }

        // Multiple matches (e.g. TabView pages) - find the hittable one
        for i in 0..<query.count {
            let element = query.element(boundBy: i)
            if element.isHittable { return element }
        }

        // Fallback: return first match anyway
        return first
    }

    /// Try multiple strategies to find the first workout row
    private func findWorkoutRow() -> XCUIElement? {
        // Strategy 1: accessibility identifier as button
        let button = app.buttons.matching(identifier: "workout-row-0").firstMatch
        if button.waitForExistence(timeout: 5) && button.isHittable {
            return button
        }

        // Strategy 2: accessibility identifier as any element type
        let any = app.descendants(matching: .any).matching(identifier: "workout-row-0").firstMatch
        if any.waitForExistence(timeout: 3) && any.isHittable {
            return any
        }

        // Strategy 3: find any button inside the workout-list scroll view
        let list = app.scrollViews["workout-list"]
        if list.waitForExistence(timeout: 3) {
            let firstButton = list.buttons.firstMatch
            if firstButton.waitForExistence(timeout: 2) && firstButton.isHittable {
                return firstButton
            }
        }

        // Strategy 4: find any element with workout-row prefix
        let workoutRowAny = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'workout-row'")).firstMatch
        if workoutRowAny.waitForExistence(timeout: 2) && workoutRowAny.isHittable {
            return workoutRowAny
        }

        return nil
    }
}
