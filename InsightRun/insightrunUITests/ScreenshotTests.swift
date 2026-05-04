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
        dismissAlertsSafely()
        captureAllScreenshots(prefix: "Light")
    }

    // MARK: - Dark Mode

    func testDarkModeScreenshots() {
        XCUIDevice.shared.appearance = .dark
        sleep(1)
        dismissAlertsSafely()
        captureAllScreenshots(prefix: "Dark")
    }

    /// Wake the UI interruption monitor without tapping interactive elements.
    /// Tapping the Dashboard center or its edges hits the PulseRingHero / score
    /// cards (full-width), so we tap the status bar which is never interactive.
    private func dismissAlertsSafely() {
        let statusBar = app.statusBars.firstMatch
        if statusBar.exists {
            statusBar.tap()
        }
        sleep(1)
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
            forceTap(row)
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

        // 10 - Statistics Progression (tap second tab in custom segmented control)
        let progressionTab = findProgressionTab()
        if let tab = progressionTab {
            forceTap(tab)
            sleep(2)
            snapshot("\(prefix)-10-Progression")
        }

        // 13 - Goals tab (active 10K plan)
        app.tabBars.buttons.element(boundBy: 3).tap()
        sleep(2)
        snapshot("\(prefix)-13-Goals")

        // 14 - Goal Detail (tap the active goal row)
        let goalRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "10K")).firstMatch
        if goalRow.waitForExistence(timeout: 2) {
            forceTap(goalRow)
            sleep(2)
            snapshot("\(prefix)-14-GoalDetail")
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
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

        // 07 - Readiness Score Detail Sheet (tap pulse-ring-hero)
        forceTapAndCapture(identifier: "pulse-ring-hero", snapshotName: "\(prefix)-07-ReadinessDetail")

        // 11 - Sleep Score Detail Sheet
        forceTapAndCapture(identifier: "score-sleep", snapshotName: "\(prefix)-11-SleepDetail")

        // 12 - Effort Score Detail Sheet
        forceTapAndCapture(identifier: "score-effort", snapshotName: "\(prefix)-12-EffortDetail")

        // 09 - Training Plan sheet (from Coach card)
        forceTapAndCapture(identifier: "create-training-plan", snapshotName: "\(prefix)-09-TrainingPlan")

        // 08 - AI Assistant (tap floating button)
        forceTapAndCapture(identifier: "floating-ai-button", snapshotName: "\(prefix)-08-AIAssistant")
    }

    /// Force-tap by computing element center coordinate.
    /// XCUITest's regular `tap()` checks isHittable which fails for SwiftUI cards
    /// inside a ScrollView even when they are visible.
    private func forceTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Locate the Progression segment in the custom Statistics tab control.
    /// Falls back to localized label, then to the second button in the segment.
    private func findProgressionTab() -> XCUIElement? {
        for label in ["Progression", "Évolution", "Progresión", "Progressione", "Progressão", "進行"] {
            let btn = app.buttons[label]
            if btn.waitForExistence(timeout: 1) { return btn }
        }
        // Fallback: the segmented control has 2 buttons; the second is Progression
        let candidates = app.buttons.matching(NSPredicate(format: "label != %@ AND label != %@", "", " "))
        if candidates.count >= 2 {
            return candidates.element(boundBy: 1)
        }
        return nil
    }

    /// Force-tap an element by its center coordinate (bypasses XCUITest isHittable check)
    /// then take a snapshot and dismiss the resulting sheet.
    private func forceTapAndCapture(identifier: String, snapshotName: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        guard element.waitForExistence(timeout: 3) else { return }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(2)
        snapshot(snapshotName)
        dismissSheet()
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

    /// Try multiple strategies to find the first workout row.
    /// Does NOT filter by isHittable — XCUITest reports SwiftUI cards in
    /// ScrollView as not-hittable even when visible. The caller must use
    /// `forceTap` (coordinate-based) to actually tap.
    private func findWorkoutRow() -> XCUIElement? {
        // Strategy 1: accessibility identifier as button
        let button = app.buttons.matching(identifier: "workout-row-0").firstMatch
        if button.waitForExistence(timeout: 5) { return button }

        // Strategy 2: any element type
        let any = app.descendants(matching: .any).matching(identifier: "workout-row-0").firstMatch
        if any.waitForExistence(timeout: 3) { return any }

        // Strategy 3: any button inside the workout-list scroll view
        let list = app.scrollViews["workout-list"]
        if list.waitForExistence(timeout: 3) {
            let firstButton = list.buttons.firstMatch
            if firstButton.waitForExistence(timeout: 2) { return firstButton }
        }

        // Strategy 4: any element with workout-row prefix
        let workoutRowAny = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'workout-row'")).firstMatch
        if workoutRowAny.waitForExistence(timeout: 2) { return workoutRowAny }

        return nil
    }
}
