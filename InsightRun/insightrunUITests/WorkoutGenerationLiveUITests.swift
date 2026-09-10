import XCTest

final class WorkoutGenerationLiveUITests: XCTestCase {
    func testLiveGenerationAndExport() throws {
        let backendURL = ProcessInfo.processInfo.environment["INSIGHTRUN_BACKEND_URL"] ?? ""
        try XCTSkipUnless(backendURL.hasPrefix("http://127.0.0.1:"), "Live tests require a local backend")
        let destination = ProcessInfo.processInfo.environment["INSIGHTRUN_EXPORT_DESTINATION"] ?? "outdoor"
        XCTAssertTrue(["outdoor", "treadmill"].contains(destination))
        continueAfterFailure = false

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Refuser"].exists { springboard.buttons["Refuser"].tap() }
        let app = XCUIApplication()
        app.launchArguments = ["-WORKOUT_GENERATION_UI_TEST", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launchEnvironment["INSIGHTRUN_BACKEND_URL"] = backendURL
        app.launch()

        let prompt = app.descendants(matching: .any)["workout-prompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 20))
        prompt.tap()
        prompt.typeText(
            "Bloc 1 — Échauffement : Ouvert (temps libre), environ 1,5–2 km en trottinant, allure très facile (<150 bpm). Bloc 2 — Boucle ×6 : effort 0:30 à 4:39–4:48/km ; récupération 1:00, objectif Aucun (ou FC <150), trot, pas marche. Bloc 3 — Retour au calme : Ouvert (temps libre), le reste jusqu’à boucler les 5 km, allure facile."
        )
        let generate = app.buttons["generate-workout"]
        if !generate.isHittable { app.swipeUp() }
        generate.tap()

        let consent = app.buttons["ai-consent-allow"]
        if consent.waitForExistence(timeout: 5) { consent.tap() }

        let title = app.staticTexts["generated-workout-name"]
        let generated = title.waitForExistence(timeout: 100)
        attach(app, name: "Generated workout")
        XCTAssertTrue(generated, app.debugDescription)
        let workoutName = title.label
        XCTAssertFalse(title.label.contains("20"))
        XCTAssertTrue(app.staticTexts["× 6"].exists)
        XCTAssertTrue(app.staticTexts["0:30"].exists)
        XCTAssertTrue(app.staticTexts["1:00"].exists)
        XCTAssertTrue(app.staticTexts["4:39–4:48/km"].exists)
        XCTAssertTrue(app.staticTexts["≤ 150 bpm"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Libre")).count, 2)

        let export = app.buttons["export-workout"]
        for _ in 0..<5 where !export.isHittable { app.swipeUp() }
        attach(app, name: "Workout steps before export")
        XCTAssertTrue(export.isHittable)
        export.tap()
        let destinationChoice = app.buttons["export-destination-\(destination)"].firstMatch
        XCTAssertTrue(destinationChoice.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-destination-outdoor"].firstMatch.exists)
        XCTAssertTrue(app.buttons["export-destination-treadmill"].firstMatch.exists)
        attach(app, name: "Fitness export destination")
        destinationChoice.tap()

        if springboard.buttons["Autoriser"].waitForExistence(timeout: 10) {
            springboard.buttons["Autoriser"].tap()
        }
        XCTAssertTrue(app.staticTexts["workout-export-success"].waitForExistence(timeout: 30), app.debugDescription)
        attach(app, name: "Fitness export success")

        let fitness = XCUIApplication(bundleIdentifier: "com.apple.Fitness")
        fitness.launch()
        if springboard.buttons["Refuser"].waitForExistence(timeout: 5) {
            springboard.buttons["Refuser"].tap()
        }
        fitness.tabBars.buttons["Workout"].tap()
        if fitness.buttons["Continue"].waitForExistence(timeout: 5) {
            fitness.buttons["Continue"].tap()
        }
        let provider = fitness.staticTexts["Insight Run"]
        XCTAssertTrue(provider.waitForExistence(timeout: 15), fitness.debugDescription)
        attach(fitness, name: "Fitness after export")
        let schedule = try XCTUnwrap(
            fitness.buttons.matching(identifier: "View Schedule").allElementsBoundByIndex
                .filter { $0.frame.minY > provider.frame.maxY }
                .min { $0.frame.minY < $1.frame.minY })
        schedule.tap()
        attach(fitness, name: "Fitness workout schedule")
        let activity = destination == "treadmill" ? "Indoor Run" : "Outdoor Run"
        let importedWorkout = fitness.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", workoutName, activity)).firstMatch
        for _ in 0..<5 where !importedWorkout.isHittable { fitness.swipeUp() }
        XCTAssertTrue(importedWorkout.exists, fitness.debugDescription)
        importedWorkout.tap()
        XCTAssertTrue(fitness.staticTexts["00:30"].waitForExistence(timeout: 5))
        attach(fitness, name: "Fitness imported workout details")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name) accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
