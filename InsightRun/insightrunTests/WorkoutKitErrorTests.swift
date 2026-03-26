//
//  WorkoutKitErrorTests.swift
//  InsightRunTests
//

import XCTest
@testable import insightrun

final class WorkoutKitErrorTests: XCTestCase {

    // MARK: - Error Description Tests

    func testAuthorizationDeniedHasDescription() {
        let error = WorkoutKitError.authorizationDenied
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testAuthorizationDeniedMentionsFitnessApp() {
        let error = WorkoutKitError.authorizationDenied
        let desc = error.errorDescription!.lowercased()
        XCTAssertTrue(
            desc.contains("fitness") || desc.contains("forme"),
            "Authorization denied message should mention the Fitness app"
        )
    }

    func testAuthorizationDeniedDoesNotMentionHealthSettings() {
        let error = WorkoutKitError.authorizationDenied
        let desc = error.errorDescription!
        XCTAssertFalse(
            desc.contains("Settings > Health > Data Access"),
            "Authorization denied should not reference Health Data Access settings path"
        )
    }

    func testInvalidWorkoutHasDescription() {
        let error = WorkoutKitError.invalidWorkout
        XCTAssertNotNil(error.errorDescription)
    }

    func testWorkoutKitNotAvailableHasDescription() {
        let error = WorkoutKitError.workoutKitNotAvailable
        XCTAssertNotNil(error.errorDescription)
    }

    func testExportFailedIncludesUnderlyingError() {
        let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "test failure"])
        let error = WorkoutKitError.exportFailed(underlying)
        XCTAssertTrue(error.errorDescription!.contains("test failure"))
    }

    func testUnsupportedSportTypeHasDescription() {
        let error = WorkoutKitError.unsupportedSportType
        XCTAssertNotNil(error.errorDescription)
    }

    func testTooManyStepsHasDescription() {
        let error = WorkoutKitError.tooManySteps
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("50"))
    }

}
