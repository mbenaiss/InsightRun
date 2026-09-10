import HealthKit
import WorkoutKit
import XCTest

@testable import insightrun

@MainActor
final class WorkoutGenerationTests: XCTestCase {
    private func makeWorkout() throws -> AIGeneratedWorkout {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "open-intervals", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(WorkoutGenerationResponse.GeneratedWorkoutData.self, from: data)
        return AIGeneratedWorkout(from: response)
    }

    func testGeneratedWorkoutPreservesAllStepFields() throws {
        let workout = try makeWorkout()
        XCTAssertTrue(workout.isValid)
        XCTAssertEqual(workout.name, "Accélérations de 30 s")
        XCTAssertEqual(workout.steps.count, 4)
        XCTAssertEqual(workout.steps[0].goal.type, .open)
        XCTAssertEqual(workout.steps[0].targetHeartRateMax, 150)
        XCTAssertEqual(workout.steps[1].repetitions, 6)
        XCTAssertEqual(workout.steps[1].goal.value, 30)
        XCTAssertEqual(workout.steps[1].paceFormatted, "4:39–4:48/km")
        XCTAssertEqual(workout.steps[2].goal.value, 60)
        XCTAssertNil(workout.steps[2].targetPace)
        XCTAssertNil(workout.steps[2].targetHeartRateMax)
        XCTAssertNil(workout.steps[2].targetHeartRateZone)
        XCTAssertEqual(workout.steps[3].goal.type, .open)
        XCTAssertEqual(workout.calculatedTotalDistance, 5000)
        XCTAssertNil(workout.estimatedDurationFormatted)
    }

    func testExportPreservesOpenGoalsAndSixWorkRecoveryPairs() throws {
        let workout = try makeWorkout()
        let exported = try WorkoutKitManager.shared.createCustomWorkout(from: workout)
        XCTAssertEqual(exported.displayName, workout.name)
        XCTAssertEqual(exported.location, .outdoor)
        XCTAssertEqual(exported.warmup?.goal, .open)
        XCTAssertEqual(exported.cooldown?.goal, .open)
        XCTAssertEqual(exported.warmup?.displayName, workout.steps[0].instructions)
        XCTAssertEqual(exported.cooldown?.displayName, workout.steps[3].instructions)
        XCTAssertEqual(exported.blocks.count, 1)
        let block = try XCTUnwrap(exported.blocks.first)
        XCTAssertEqual(block.iterations, 6)
        XCTAssertEqual(block.steps.count, 2)
        XCTAssertEqual(block.steps[0].purpose, .work)
        XCTAssertEqual(block.steps[0].step.goal, .time(30, .seconds))
        XCTAssertEqual(block.steps[1].purpose, .recovery)
        XCTAssertEqual(block.steps[1].step.goal, .time(60, .seconds))
        XCTAssertNil(block.steps[1].step.alert)
        XCTAssertEqual(block.steps[1].step.displayName, workout.steps[2].instructions)

        let pace = try XCTUnwrap(block.steps[0].step.alert as? SpeedRangeAlert)
        XCTAssertEqual(pace.target.lowerBound.converted(to: .metersPerSecond).value, 1000.0 / 288, accuracy: 0.000001)
        XCTAssertEqual(pace.target.upperBound.converted(to: .metersPerSecond).value, 1000.0 / 279, accuracy: 0.000001)
        XCTAssertTrue(CustomWorkout.supportsAlert(pace, activity: .running, location: .outdoor))

        let heartRate = try XCTUnwrap(exported.warmup?.alert as? HeartRateRangeAlert)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        XCTAssertEqual(heartRate.targetQuantityLowerBound.doubleValue(for: bpm), 1)
        XCTAssertEqual(heartRate.targetQuantityUpperBound.doubleValue(for: bpm), 150)
        XCTAssertTrue(CustomWorkout.supportsAlert(heartRate, activity: .running, location: .outdoor))
    }

    func testDurationIncludesRepeatedRecoveryAndKeepsOpenEstimatesSeparate() throws {
        var workout = try makeWorkout()
        workout.estimatedDuration = 1800
        XCTAssertEqual(workout.calculatedEstimatedDuration, 1800)
        workout.steps = Array(workout.steps[1...2])
        XCTAssertEqual(workout.calculatedEstimatedDuration, 540)
    }

    func testTreadmillExportPreservesStepsAndAlerts() throws {
        let workout = try makeWorkout()
        let outdoor = try WorkoutKitManager.shared.createCustomWorkout(from: workout, destination: .outdoor)
        let treadmill = try WorkoutKitManager.shared.createCustomWorkout(from: workout, destination: .treadmill)
        XCTAssertEqual(treadmill.activity, .running)
        XCTAssertEqual(treadmill.location, .indoor)
        XCTAssertEqual(treadmill.displayName, outdoor.displayName)
        XCTAssertEqual(treadmill.warmup, outdoor.warmup)
        XCTAssertEqual(treadmill.blocks, outdoor.blocks)
        XCTAssertEqual(treadmill.cooldown, outdoor.cooldown)
        let pace = try XCTUnwrap(treadmill.blocks.first?.steps.first?.step.alert)
        XCTAssertTrue(CustomWorkout.supportsAlert(pace, activity: .running, location: .indoor))
    }

    func testRunningDestinationDoesNotChangeCyclingExport() throws {
        let running = try makeWorkout()
        let workout = AIGeneratedWorkout(name: running.name, description: running.description, sport: .cycling, steps: running.steps)
        let exported = try WorkoutKitManager.shared.createCustomWorkout(from: workout, destination: .treadmill)
        XCTAssertEqual(exported.activity, .cycling)
        XCTAssertEqual(exported.location, .outdoor)
    }

    func testEditedPaceReplacesOriginalRangeAtExport() throws {
        var workout = try makeWorkout()
        workout.steps[1].setTargetPace("5:00")
        XCTAssertNil(workout.steps[1].targetPaceMin)
        XCTAssertNil(workout.steps[1].targetPaceMax)
        XCTAssertEqual(workout.steps[1].repetitions, 6)

        let exported = try WorkoutKitManager.shared.createCustomWorkout(from: workout)
        let alert = try XCTUnwrap(exported.blocks[0].steps[0].step.alert as? SpeedThresholdAlert)
        XCTAssertEqual(alert.target.converted(to: .metersPerSecond).value, 1000.0 / 300, accuracy: 0.000001)
    }

    func testInvalidHeartRateCeilingIsRejectedBeforeExport() throws {
        for limit in [-1, 0, 1, 301] {
            var workout = try makeWorkout()
            workout.steps[0].targetHeartRateMax = limit
            XCTAssertFalse(workout.isValid)
            XCTAssertThrowsError(try WorkoutKitManager.shared.createCustomWorkout(from: workout))
        }
    }

    func testExplicitPaceEditReplacesHeartRateAlert() throws {
        var workout = try makeWorkout()
        workout.steps[0].setTargetPace("6:00")
        XCTAssertNil(workout.steps[0].targetHeartRateMax)
        let exported = try WorkoutKitManager.shared.createCustomWorkout(from: workout)
        XCTAssertNotNil(exported.warmup?.alert as? SpeedThresholdAlert)
    }

    func testWorkoutRoundTripPreservesNewAndExistingTargets() throws {
        let workout = try makeWorkout()
        let data = try JSONEncoder().encode(workout)
        XCTAssertEqual(try JSONDecoder().decode(AIGeneratedWorkout.self, from: data), workout)
    }

    func testLegacyResponsesStillDecodeWithoutHeartRateCeiling() throws {
        let data = Data(
            """
            {
              "name": "Easy run", "description": "Easy", "sport": "running",
              "steps": [{ "type": "work", "goal": { "type": "open" }, "targetHeartRateZone": 2 }]
            }
            """.utf8)
        let response = try JSONDecoder().decode(WorkoutGenerationResponse.GeneratedWorkoutData.self, from: data)
        let workout = AIGeneratedWorkout(from: response)
        XCTAssertNil(workout.steps[0].targetHeartRateMax)
        XCTAssertEqual(workout.steps[0].targetHeartRateZone, 2)
        XCTAssertEqual(workout.steps[0].goal.value, 0)
        let exported = try WorkoutKitManager.shared.createCustomWorkout(from: workout)
        XCTAssertEqual((exported.blocks[0].steps[0].step.alert as? HeartRateZoneAlert)?.zone, 2)
    }
}
