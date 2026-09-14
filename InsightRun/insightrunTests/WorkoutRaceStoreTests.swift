import HealthKit
import XCTest
@testable import insightrun

@MainActor
final class WorkoutRaceStoreTests: XCTestCase {
    private func withStore(_ operation: (WorkoutRaceStore, UserDefaults) throws -> Void) throws {
        let suite = "WorkoutRaceStoreTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try operation(WorkoutRaceStore(defaults: defaults), defaults)
    }

    private func workout(id: UUID = UUID(), date: Date = Date(), stravaID: String? = nil) -> WorkoutModel {
        var metadata: [String: Any] = ["display_name": "Official 10K"]
        if let stravaID { metadata["strava_id"] = stravaID }
        return WorkoutModel(
            id: id, workoutType: .running, startDate: date, endDate: date.addingTimeInterval(3000),
            duration: 3000, distance: 10000, totalEnergyBurned: nil, sourceName: "Test",
            sourceVersion: nil, metadata: metadata, averageHeartRate: nil, maxHeartRate: nil,
            elevationGain: nil, hasRoute: false
        )
    }

    func testMarkingAndUnmarkingSurviveRelaunch() async throws {
        try withStore { store, defaults in
            let run = workout(stravaID: "42")
            store.setOfficialRace(true, for: run)
            store.setOfficialRace(true, for: run)
            let reopened = WorkoutRaceStore(defaults: defaults)
            XCTAssertEqual(reopened.races.count, 1)
            XCTAssertTrue(reopened.isOfficialRace(run))
            XCTAssertTrue(reopened.isOfficialRace(workoutID: "STRAVA-42"))
            XCTAssertTrue(reopened.isOfficialRace(workoutID: run.id.uuidString))
            reopened.setOfficialRace(false, for: run)
            XCTAssertTrue(WorkoutRaceStore(defaults: defaults).races.isEmpty)
        }
    }

    func testSourceMergeKeepsLabelAcrossHealthKitAndStravaIDs() async throws {
        try withStore { store, defaults in
            let healthKit = workout()
            let merged = workout(id: healthKit.id, stravaID: "42")
            let stravaOnly = workout(stravaID: "42")
            store.setOfficialRace(true, for: healthKit)
            store.reconcile([merged])
            let reopened = WorkoutRaceStore(defaults: defaults)
            XCTAssertTrue(reopened.isOfficialRace(stravaOnly))
            reopened.setOfficialRace(false, for: stravaOnly)
            XCTAssertFalse(reopened.isOfficialRace(healthKit))
            XCTAssertTrue(reopened.races.isEmpty)
        }
    }

    func testMergingTwoLabeledSourcesDoesNotDuplicateTheRace() async throws {
        try withStore { store, _ in
            let healthKit = workout()
            let stravaOnly = workout(stravaID: "42")
            store.setOfficialRace(true, for: healthKit)
            store.setOfficialRace(true, for: stravaOnly)
            XCTAssertEqual(store.races.count, 2)
            store.reconcile([workout(id: healthKit.id, stravaID: "42")])
            XCTAssertEqual(store.races.count, 1)
            XCTAssertTrue(store.isOfficialRace(healthKit))
            XCTAssertTrue(store.isOfficialRace(stravaOnly))
        }
    }

    func testFilterIncludesEveryMonthAndDoesNotLabelAnotherRunOnSameDate() async throws {
        try withStore { store, _ in
            let today = workout()
            let older = workout(date: Date().addingTimeInterval(-90 * 86400))
            let another = workout(date: today.startDate)
            store.setOfficialRace(true, for: today)
            store.setOfficialRace(true, for: older)
            store.reconcile([another])
            XCTAssertEqual(store.officialRaces(from: [today, another, older]).map(\.id), [today.id, older.id])
            XCTAssertFalse(store.isOfficialRace(another))
            store.reconcile([])
            XCTAssertEqual(store.races.count, 2)
        }
    }

    func testPlanWeeksIncludeRacesOnRestDaysAndRespectDSTBoundaries() async throws {
        try withStore { store, _ in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
            let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
            let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
            let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: start))
            let weeks = (1...2).map { number in
                TrainingWeek(weekNumber: number, phase: .base, days: [TrainingDay(dayOfWeek: .sunday)])
            }
            let plan = TrainingPlan(name: "Plan", goal: "10K", level: .beginner, weeks: weeks, startDate: start)
            let sunday = workout(date: nextWeek.addingTimeInterval(-60))
            let monday = workout(date: nextWeek)
            for run in [workout(date: start.addingTimeInterval(-1)), sunday, monday, workout(date: end)] {
                store.setOfficialRace(true, for: run)
            }
            XCTAssertEqual(store.races(in: plan, weekIndex: 0, calendar: calendar).map(\.date), [sunday.startDate])
            XCTAssertEqual(store.races(in: plan, weekIndex: 1, calendar: calendar).map(\.date), [monday.startDate])
            XCTAssertTrue(store.races(in: plan, weekIndex: -1, calendar: calendar).isEmpty)
            XCTAssertTrue(store.races(in: plan, weekIndex: 2, calendar: calendar).isEmpty)
            XCTAssertFalse(plan.weeks[0].days[0].isCompleted)
            XCTAssertNil(plan.weeks[0].days[0].completedWorkoutId)
        }
    }
}
