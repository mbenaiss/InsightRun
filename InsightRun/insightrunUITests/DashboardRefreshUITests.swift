import XCTest

final class DashboardRefreshUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCardsKeepTheirValuesInDetailsAndShowReferenceDate() {
        let app = launchDemo()
        for id in ["pulse-ring-hero", "score-effort", "score-sleep"] {
            let card = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            if !card.isHittable { app.swipeUp() }
            card.tap()
            let hero = app.descendants(matching: .any)["detail-hero-value"].firstMatch
            XCTAssertTrue(hero.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["score-reference-date"].exists)
            if id == "pulse-ring-hero" { XCTAssertTrue(hero.label.contains("82")) }
            XCTAssertFalse(app.staticTexts["score-analysis-error"].exists)
            app.buttons["sheet-close"].tap()
            XCTAssertTrue(app.buttons["sheet-close"].waitForNonExistence(timeout: 5))
        }
    }

    func testCalendarSelectionRefreshesCardsAndMissingHistoricalReadinessStaysUnavailable() {
        let app = launchDemo()
        app.buttons["dashboard-calendar"].tap()
        XCTAssertTrue(app.buttons["recovery-calendar-close"].waitForExistence(timeout: 10))
        app.buttons["recovery-calendar-previous-month"].tap()
        app.buttons["dashboard-day-10"].tap()
        XCTAssertTrue(app.buttons["recovery-calendar-close"].waitForNonExistence(timeout: 10))
        let hero = app.buttons["pulse-ring-hero"]
        XCTAssertTrue(hero.waitForNonExistence(timeout: 20))
        XCTAssertTrue((app.buttons["dashboard-calendar"].value as? String)?.contains("10") == true)
        app.buttons["dashboard-calendar"].tap()
        app.buttons["Aujourd'hui"].tap()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        hero.tap()
        let detail = app.descendants(matching: .any)["detail-hero-value"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertTrue(detail.label.contains("82"))
    }

    func testMissingAndZeroDashboardMetricsAreHidden() {
        let app = launchDemo(language: "en", locale: "en_GB", additionalArguments: ["-MISSING_METRICS_UI_TEST"])
        XCTAssertFalse(app.buttons["score-effort"].exists)
        XCTAssertFalse(app.buttons["score-sleep"].exists)
        let hrv = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HRV at rest,")).firstMatch
        for _ in 0..<8 where !hrv.isHittable { app.swipeUp() }
        XCTAssertTrue(hrv.isHittable)
        XCTAssertTrue(hrv.label.contains("65"))
        for _ in 0..<3 { app.swipeUp() }
        for label in ["HRV · RMSSD,", "Resting HR,", "Respiratory rate,", "Oxygen saturation,", "Calories,", "Steps,"] {
            XCTAssertFalse(
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch.exists, label)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dashboard-Missing-Metrics"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAllSignalsAndWeeklySummaryOpenWithoutLosingDashboardState() {
        let app = launchDemo()
        for label in ["VFC au repos", "VFC · RMSSD", "FC repos", "Fréquence respiratoire", "Saturation en oxygène", "Charge cardiaque", "Calories", "Pas"] {
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            for _ in 0..<6 where !card.isHittable { app.swipeUp() }
            XCTAssertTrue(card.isHittable, label)
            card.tap()
            let value = app.descendants(matching: .any)["detail-hero-value"].firstMatch
            XCTAssertTrue(value.waitForExistence(timeout: 10), label)
            XCTAssertTrue(app.staticTexts["score-reference-date"].exists, label)
            XCTAssertFalse(app.staticTexts["score-analysis-error"].exists, label)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
            app.swipeUp()
            app.swipeUp()
            app.buttons["sheet-close"].tap()
            XCTAssertTrue(app.buttons["sheet-close"].waitForNonExistence(timeout: 5))
        }
        let calendarButton = app.buttons["dashboard-calendar"]
        for _ in 0..<8 where !calendarButton.isHittable { app.swipeDown() }
        calendarButton.tap()
        XCTAssertTrue(app.buttons["recovery-calendar-close"].waitForExistence(timeout: 5))
        let runDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        if !Calendar.current.isDate(runDate, equalTo: Date(), toGranularity: .month) {
            app.buttons["recovery-calendar-previous-month"].tap()
        }
        app.buttons["dashboard-day-\(Calendar.current.component(.day, from: runDate))"].tap()
        XCTAssertTrue(app.buttons["recovery-calendar-close"].waitForNonExistence(timeout: 5))
        let weekly = app.buttons["weekly-summary-link"]
        XCTAssertTrue(weekly.waitForExistence(timeout: 15))
        for _ in 0..<6 where !weekly.isHittable { app.swipeUp() }
        XCTAssertTrue(weekly.isHittable)
        weekly.tap()
        XCTAssertTrue(app.descendants(matching: .any)["weekly-summary-content"].firstMatch.waitForExistence(timeout: 15))
        app.swipeUp()
        app.swipeUp()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["dashboard-settings"].waitForExistence(timeout: 10))
    }

    func testRMSSDCardOpensLocalizedExplanationInEnglish() {
        let app = launchDemo(language: "en", locale: "en_GB")
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HRV · RMSSD")).firstMatch
        for _ in 0..<8 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.isHittable)
        let hrv = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HRV at rest")).firstMatch
        XCTAssertTrue(hrv.exists)
        XCTAssertEqual(card.frame.minY, hrv.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(card.frame.minX, hrv.frame.minX)
        XCTAssertTrue(card.label.contains("86"))
        XCTAssertTrue(card.label.contains("ms"))
        let grid = XCTAttachment(screenshot: app.screenshot())
        grid.name = "RMSSD-Signal-Grid-English"
        grid.lifetime = .keepAlways
        add(grid)
        card.tap()
        let hero = app.descendants(matching: .any)["detail-hero-value"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        XCTAssertTrue(hero.label.contains("86"))
        XCTAssertTrue(hero.label.contains("ms"))
        XCTAssertTrue(app.staticTexts["Your personal reference"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["7-Day History"].exists)
        let chart = app.descendants(matching: .any)["metric-history-chart"].firstMatch
        XCTAssertTrue(chart.exists)
        XCTAssertTrue(chart.label.contains("7"))
        XCTAssertTrue(app.staticTexts["score-reference-date"].exists)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "RMSSD-Explanation-English"
        detail.lifetime = .keepAlways
        add(detail)
        app.buttons["sheet-close"].tap()
        XCTAssertTrue(app.buttons["sheet-close"].waitForNonExistence(timeout: 5))
    }

    func testDailyStepsCardSharesTheMetricTemplateInEnglish() {
        let app = launchDemo(language: "en", locale: "en_GB")
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Steps,")).firstMatch
        for _ in 0..<8 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(card.label.contains("8,420"))
        XCTAssertTrue(card.label.contains("steps"))
        let calories = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Calories,")).firstMatch
        XCTAssertEqual(card.frame.minY, calories.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(card.frame.minX, calories.frame.minX)
        let grid = XCTAttachment(screenshot: app.screenshot())
        grid.name = "Daily-Steps-Signal-Grid-English"
        grid.lifetime = .keepAlways
        add(grid)
        card.tap()
        let value = app.descendants(matching: .any)["detail-hero-value"].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        XCTAssertTrue(value.label.contains("8,420"))
        XCTAssertTrue(value.label.contains("steps"))
        XCTAssertTrue(app.staticTexts["7-Day History"].exists)
        XCTAssertTrue(app.staticTexts["score-reference-date"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["metric-history-chart"].firstMatch.exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This is the number of steps")).firstMatch.exists)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Daily-Steps-Explanation-English"
        detail.lifetime = .keepAlways
        add(detail)
    }

    private func launchDemo(language: String = "fr", locale: String = "fr_FR", additionalArguments: [String] = [])
        -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchArguments =
            ["-DEMO_MODE", "-DASHBOARD_DIAGNOSTICS", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            + additionalArguments
        app.launch()
        XCTAssertTrue(app.buttons["pulse-ring-hero"].waitForExistence(timeout: 20))
        return app
    }
}
