import XCTest

final class ActivationFlowUITests: XCTestCase {
    func testRecordedZonesAndWorkoutFeedback() {
        let app = XCUIApplication()
        app.launchArguments = ["-DEMO_MODE", "-WORKOUT_ANALYSIS_UI_TEST", "-TRAINING_INSIGHTS_UI_TEST", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["workout-analysis-consent"].waitForExistence(timeout: 15))
        let temperature = app.descendants(matching: .any)["workout-weather-temperature"].firstMatch
        XCTAssertTrue(temperature.isHittable)
        XCTAssertTrue(temperature.label.contains("19,5 °C"))
        XCTAssertTrue(app.descendants(matching: .any)["workout-weather-humidity"].firstMatch.label.contains("62"))
        let recordedEffort = app.descendants(matching: .any)["workout-recorded-effort"].firstMatch
        XCTAssertTrue(recordedEffort.isHittable)
        XCTAssertTrue(recordedEffort.label.contains("Estimation Apple"))
        XCTAssertTrue(recordedEffort.label.contains("7/10"))
        let title = app.staticTexts["workout-title"]
        XCTAssertLessThan(temperature.frame.maxY, title.frame.minY)
        XCTAssertLessThan(recordedEffort.frame.maxY, title.frame.minY)
        let startTime = app.descendants(matching: .any)["workout-start-time"].firstMatch
        XCTAssertTrue(startTime.isHittable)
        XCTAssertTrue(startTime.label.contains("10:00"))
        XCTAssertFalse(startTime.label.contains("2026"))
        let duration = app.descendants(matching: .any)["workout-header-duration"].firstMatch
        XCTAssertTrue(duration.isHittable)
        XCTAssertTrue(duration.label.contains("30:00"))
        XCTAssertLessThan(startTime.frame.maxY, title.frame.minY)
        XCTAssertLessThan(duration.frame.maxY, title.frame.minY)
        XCTAssertEqual(startTime.frame.minY, duration.frame.minY, accuracy: 2)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2026'")).count, 1)
        let coach = app.staticTexts["workout-section-coach"]
        let timeline = app.staticTexts["workout-section-timeline"]
        let effort = app.staticTexts["workout-section-effort"]
        let information = app.staticTexts["workout-section-information"]
        XCTAssertLessThan(app.buttons["workout-metric.distance"].frame.maxY, coach.frame.minY)
        XCTAssertLessThan(coach.frame.minY, timeline.frame.minY)
        XCTAssertLessThan(timeline.frame.minY, effort.frame.minY)
        XCTAssertLessThan(effort.frame.minY, information.frame.minY)
        attachScreenshot(of: app, named: "Workout-Weather-Effort-French")
        let feedback = app.buttons["workout-feedback"]
        for _ in 0..<5 where !feedback.isHittable { app.swipeUp() }
        XCTAssertTrue(feedback.isHittable)
        feedback.tap()
        XCTAssertTrue(app.staticTexts["Effort ressenti"].waitForExistence(timeout: 5))
        app.staticTexts["Effort ressenti"].tap()
        app.buttons["8/10"].tap()
        attachScreenshot(of: app, named: "Workout-Feedback-French")
        app.buttons["Enregistrer"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-perceived-effort"].firstMatch.label.contains("8/10"))
        XCTAssertTrue(recordedEffort.label.contains("7/10"))
        feedback.tap()
        XCTAssertTrue(app.staticTexts["8/10"].waitForExistence(timeout: 5))
        app.buttons["Enregistrer"].tap()
        for _ in 0..<10 where !app.staticTexts["Zones automatiques Apple"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Zones automatiques Apple"].exists)
        XCTAssertTrue(app.staticTexts["Z3"].exists)
        attachScreenshot(of: app, named: "Recorded-Zones-French")
    }

    func testEmptyWorkoutMetricsLeaveNoEmptyCardsOrFields() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DEMO_MODE", "-WORKOUT_ANALYSIS_UI_TEST", "-EMPTY_WORKOUT_UI_TEST",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_GB",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["workout-analysis-consent"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["workout-title"].exists)
        for id in [
            "workout-main-metrics", "workout-metric.distance", "workout-metric.duration",
            "workout-metric.avg_hr", "workout-metric.avg_pace", "workout-header-duration",
            "workout-weather-temperature", "workout-weather-humidity", "workout-charts",
            "workout-section-timeline", "workout-section-effort",
        ] {
            XCTAssertFalse(app.descendants(matching: .any)[id].firstMatch.exists, id)
        }
        XCTAssertTrue(app.buttons["workout-feedback"].exists)
        attachScreenshot(of: app, named: "Workout-Empty-Metrics-English")
    }

    func testPartialWorkoutKeepsOnlyAvailableMetricsAndCharts() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DEMO_MODE", "-WORKOUT_ANALYSIS_UI_TEST", "-MISSING_METRICS_UI_TEST",
            "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["workout-analysis-consent"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["workout-metric.distance"].exists)
        XCTAssertTrue(app.buttons["workout-metric.duration"].exists)
        XCTAssertTrue(app.buttons["workout-metric.avg_pace"].exists)
        XCTAssertFalse(app.buttons["workout-metric.avg_hr"].exists)
        XCTAssertFalse(app.staticTexts["workout-section-effort"].exists)
        let chart = app.descendants(matching: .any)["workout-charts"].firstMatch
        for _ in 0..<6 where !chart.isHittable { app.swipeUp() }
        XCTAssertTrue(chart.exists)
        XCTAssertFalse(app.staticTexts["bpm"].exists)
        XCTAssertFalse(app.staticTexts["—"].exists)
        attachScreenshot(of: app, named: "Workout-Partial-Metrics-French")
    }

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
        XCTAssertTrue(app.descendants(matching: .any)["workout-analysis-result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Sur ce 10 km à 4:47/km")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Prochaine action"].exists)
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
        XCTAssertFalse(app.descendants(matching: .any)["workout-weather-temperature"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout-weather-humidity"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout-recorded-effort"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout-perceived-effort"].exists)
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
        for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
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
        for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
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
        let paragraph = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Cette séance de 5 kilomètres en 30 minutes")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(paragraph.label.contains("Pour ta prochaine séance"), file: file, line: line)
        XCTAssertFalse(app.staticTexts["Constats"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["Interprétation"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["Prochaine action"].exists, file: file, line: line)
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension ActivationFlowUITests {
    func testObjectiveWizardRequiresTrainingDaysAndKeepsManualLevel() {
        let app = XCUIApplication()
        app.launchArguments = ["-DEMO_MODE", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard-settings"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Objectifs"].tap()
        app.buttons["goals-add"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("QA Objectif jours\n")
        app.buttons["Suivant"].tap()
        app.swipeUp()
        app.buttons["Avancé"].tap()
        for day in ["lun.", "mer.", "ven.", "sam."] { app.buttons[day].tap() }
        XCTAssertFalse(app.buttons["Suivant"].isEnabled)
        attachScreenshot(of: app, named: "Goals-No-Training-Days")
        for day in ["mar.", "jeu.", "dim."] { app.buttons[day].tap() }
        XCTAssertTrue(app.buttons["Suivant"].isEnabled)
        app.buttons["Suivant"].tap()
        XCTAssertTrue(app.staticTexts["Avancé"].exists)
        attachScreenshot(of: app, named: "Goals-Manual-Profile-Summary")
        app.buttons["Créer l'objectif"].tap()
        let created = app.staticTexts["QA Objectif jours"].firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 10))
        created.tap()
        app.buttons["Options de l'objectif"].tap()
        app.buttons["Supprimer l'objectif"].tap()
        app.buttons["Supprimer"].tap()
        XCTAssertTrue(app.buttons["goals-add"].waitForExistence(timeout: 10))
        XCTAssertFalse(created.exists)
    }
}
