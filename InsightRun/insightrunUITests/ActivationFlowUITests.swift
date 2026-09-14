import XCTest

final class ActivationFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLatestRunOpensDetailAndAnalysis() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DEMO_MODE",
            "-RESET_ACTIVATION_UI_TEST",
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
        XCTAssertTrue(app.descendants(matching: .any)["analysis-confidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Prochaine action"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["post-analysis-notification"].exists)

        attachScreenshot(of: app, named: "Activation-Workout-Analysis")

        app.tabBars.buttons["Tableau de bord"].tap()
        XCTAssertTrue(activationButton.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ouvrez votre dernière course et obtenez une recommandation concrète."].exists)
        attachScreenshot(of: app, named: "Dashboard-After-Workout-Consultation")

        app.terminate()
        app.launchArguments.removeAll { $0 == "-RESET_ACTIVATION_UI_TEST" }
        app.launch()
        XCTAssertTrue(app.buttons["dashboard-settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(activationButton.exists)
    }

    func testRealWorkoutConsentIsVisibleAndAcceptShowsAnalysis() {
        let app = launchAnalysisScenario()
        let consentButton = app.buttons["workout-analysis-consent"]
        XCTAssertTrue(consentButton.waitForExistence(timeout: 10))
        XCTAssertTrue(consentButton.isHittable)
        XCTAssertFalse(app.buttons["ai-consent-allow"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout-analysis-result"].exists)
        attachScreenshot(of: app, named: "Real-Workout-Consent-Required")

        consentButton.tap()
        let allowButton = app.buttons["ai-consent-allow"]
        XCTAssertTrue(allowButton.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Real-Workout-Consent-Sheet")
        allowButton.tap()

        assertAnalysisIsDisplayed(in: app)
        attachScreenshot(of: app, named: "Real-Workout-Analysis-After-Consent")
    }

    func testDecliningConsentKeepsAnalysisLockedAndAllowsReopening() {
        let app = launchAnalysisScenario()
        let consentButton = app.buttons["workout-analysis-consent"]
        XCTAssertTrue(consentButton.waitForExistence(timeout: 10))
        consentButton.tap()

        let declineButton = app.buttons["ai-consent-decline"]
        XCTAssertTrue(declineButton.waitForExistence(timeout: 5))
        declineButton.tap()
        XCTAssertTrue(declineButton.waitForNonExistence(timeout: 5))
        XCTAssertTrue(consentButton.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["workout-analysis-result"].exists)
        XCTAssertFalse(app.staticTexts["Prochaine action"].exists)
        attachScreenshot(of: app, named: "Real-Workout-Consent-Declined")

        consentButton.tap()
        let allowButton = app.buttons["ai-consent-allow"]
        XCTAssertTrue(allowButton.waitForExistence(timeout: 5))
        allowButton.tap()

        assertAnalysisIsDisplayed(in: app)
        attachScreenshot(of: app, named: "Real-Workout-Consent-Reopened-And-Accepted")
    }

    func testAnalysisErrorCanBeRetriedAfterConsent() {
        let app = launchAnalysisScenario(failsFirstRequest: true)
        let consentButton = app.buttons["workout-analysis-consent"]
        XCTAssertTrue(consentButton.waitForExistence(timeout: 10))
        consentButton.tap()

        let allowButton = app.buttons["ai-consent-allow"]
        XCTAssertTrue(allowButton.waitForExistence(timeout: 5))
        allowButton.tap()

        let retryButton = app.buttons["workout-analysis-retry"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["workout-analysis-result"].exists)
        attachScreenshot(of: app, named: "Real-Workout-Analysis-Error")
        retryButton.tap()

        assertAnalysisIsDisplayed(in: app)
        XCTAssertFalse(retryButton.exists)
        attachScreenshot(of: app, named: "Real-Workout-Analysis-Retry-Succeeded")
    }

    private func launchAnalysisScenario(failsFirstRequest: Bool = false, showsRacePlan: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DEMO_MODE",
            "-WORKOUT_ANALYSIS_UI_TEST",
            "-AppleLanguages", "(fr)",
            "-AppleLocale", "fr_FR"
        ]
        if failsFirstRequest {
            app.launchArguments.append("-WORKOUT_ANALYSIS_UI_ERROR")
        }
        if showsRacePlan {
            app.launchArguments.append("-WORKOUT_RACE_UI_TEST")
        }
        app.launch()
        return app
    }

    func testOfficialRaceLabelCanBeAddedAndRemovedFromWorkoutDetail() {
        let app = launchAnalysisScenario()
        let toggle = app.switches["workout-official-race-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        attachScreenshot(of: app, named: "Official-Race-Enabled")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(app.buttons["workout-analysis-consent"].exists)
    }

    func testCompletedOfficialRaceAppearsInPlanAndDisappearsWhenUnmarked() {
        let app = launchAnalysisScenario(showsRacePlan: true)
        let toggle = app.switches["workout-official-race-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["test-official-race-plan"].tap()
        XCTAssertTrue(app.staticTexts["Courses officielles réalisées"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Course du matin"].exists)
        attachScreenshot(of: app, named: "Official-Race-In-Training-Plan")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["test-official-race-plan"].tap()
        XCTAssertFalse(app.staticTexts["Courses officielles réalisées"].exists)
        XCTAssertFalse(app.staticTexts["Course du matin"].exists)
    }

    private func assertAnalysisIsDisplayed(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let result = app.descendants(matching: .any)["workout-analysis-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(app.staticTexts["Prochaine action"].waitForExistence(timeout: 5), file: file, line: line)
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
