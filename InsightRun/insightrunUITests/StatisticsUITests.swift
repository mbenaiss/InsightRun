import XCTest

@MainActor
final class StatisticsUITests: XCTestCase {
    func testStatisticsRemainsInteractiveAfterScrollingRecords() {
        continueAfterFailure = false
        executionTimeAllowance = 90
        let app = XCUIApplication()
        app.launchArguments = [
            "-DEMO_MODE", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR", "-selectedTheme", "dark",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard-settings"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Statistiques"].tap()
        XCTAssertTrue(app.staticTexts["statistics-kpi-sessions"].waitForExistence(timeout: 10))
        app.buttons["statistics-period-allTime"].tap()
        app.buttons["statistics-period-thisMonth"].tap()
        for page in 1...3 {
            app.swipeUp()
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Statistics-Scroll-\(page)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertFalse(app.staticTexts["Meilleure allure"].exists)
        }
        for _ in 0..<6 { app.swipeDown() }
        app.buttons["statistics-tab-progression"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["statistics-metric-averagePace"].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Tableau de bord"].tap()
        app.tabBars.buttons["Statistiques"].tap()
        app.buttons["statistics-tab-overview"].tap()
        XCTAssertTrue(app.staticTexts["statistics-kpi-sessions"].waitForExistence(timeout: 10))
    }
}
