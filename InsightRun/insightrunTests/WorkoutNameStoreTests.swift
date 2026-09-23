import HealthKit
import XCTest

@testable import insightrun

@MainActor
final class WorkoutNameStoreTests: XCTestCase {
  private func withStore(_ operation: (WorkoutNameStore, UserDefaults) throws -> Void) throws {
    let suite = "WorkoutNameStoreTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try operation(WorkoutNameStore(defaults: defaults), defaults)
  }

  func testTrimmedNameSurvivesRelaunchAndEmptySyncWithoutChangingSource() async throws {
    try withStore { store, defaults in
      let run = workout()
      store.rename(run, to: "  Sortie longue à Bruxelles \n")
      store.reconcile([])
      XCTAssertEqual(store.name(for: run), "Sortie longue à Bruxelles")
      XCTAssertEqual(
        WorkoutNameStore(defaults: defaults).name(for: run), "Sortie longue à Bruxelles")
      XCTAssertEqual(run.raceDisplayName, "Morning Run")
      XCTAssertEqual(run.distance, 10_000)
    }
  }

  func testEmptyNamesDoNotReplaceAnExistingName() async throws {
    try withStore { store, _ in
      let run = workout()
      store.rename(run, to: " \n ")
      XCTAssertNil(store.name(for: run))
      store.rename(run, to: "Footing")
      store.rename(run, to: "\t\n")
      XCTAssertEqual(store.name(for: run), "Footing")
    }
  }

  func testSuuntoCacheKeepsAStableWorkoutUUIDAndName() async throws {
    try withStore { store, defaults in
      let cached = CachedUnifiedWorkout(from: UnifiedWorkout(from: workout()))
      cached.source = WorkoutSource.suunto.rawValue
      cached.id = "suunto-1700000000.0"
      cached.healthKitWorkoutId = nil
      cached.originalWorkoutData = nil
      let first = cached.toUnifiedWorkout().toWorkoutModel()
      store.rename(first, to: "Sortie Suunto")
      let reloaded = cached.toUnifiedWorkout().toWorkoutModel()
      XCTAssertEqual(first.id, reloaded.id)
      XCTAssertEqual(WorkoutNameStore(defaults: defaults).name(for: reloaded), "Sortie Suunto")
    }
  }

  func testImportedWorkoutKeepsTheSameUUIDFreshAndFromCache() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let parsed = ParsedSuuntoWorkout(
      startDate: start, endDate: start.addingTimeInterval(3_000), duration: 3_000,
      distance: 10_000, calories: 600, elevationGain: 40, elevationLoss: 40,
      averageHeartRate: 150, maxHeartRate: 172, averageSpeed: 3.3, maxSpeed: 4.2,
      averageGroundContactTime: nil, averageVerticalOscillation: nil, averageStrideLength: nil,
      averageCadence: nil, averagePower: nil, vo2Max: nil, epoc: nil, trainingEffect: nil,
      routeCoordinates: [], hasRoute: false, heartRateSamples: [], cadenceSamples: [],
      powerSamples: [], altitudeSamples: [], splits: [], deviceName: "Suunto Race",
      activityType: "Running", feeling: nil, notes: nil)
    let imported = UnifiedWorkout(from: SuuntoActivity(from: parsed))
    let first = imported.toWorkoutModel()
    let reimported = UnifiedWorkout(from: SuuntoActivity(from: parsed)).toWorkoutModel()
    let restored = CachedUnifiedWorkout(from: imported).toUnifiedWorkout().toWorkoutModel()
    XCTAssertEqual(first.id, reimported.id)
    XCTAssertEqual(first.id, restored.id)
    let otherSource = UnifiedWorkout.stableWorkoutID(
      source: WorkoutSource.strava.rawValue, sourceID: imported.id)
    XCTAssertNotEqual(first.id, otherSource)
    let healthKitID = UUID()
    let parsedID = UnifiedWorkout.stableWorkoutID(
      source: WorkoutSource.healthKit.rawValue, sourceID: healthKitID.uuidString)
    XCTAssertEqual(parsedID, healthKitID)
  }

  func testMergedAliasesKeepNameThroughSourceChangesAndCanBeResetFromEitherSource() async throws {
    try withStore { store, defaults in
      let healthKit = workout()
      let merged = workout(id: healthKit.id, stravaID: "42", sourceTitle: "New Strava title")
      let strava = workout(stravaID: "42")
      store.rename(healthKit, to: "Ma course")
      store.reconcile([merged])
      let reopened = WorkoutNameStore(defaults: defaults)
      XCTAssertEqual(reopened.name(for: strava), "Ma course")
      XCTAssertEqual(reopened.name(for: merged), "Ma course")
      XCTAssertNil(reopened.name(for: workout()))
      reopened.resetName(for: strava)
      XCTAssertNil(WorkoutNameStore(defaults: defaults).name(for: healthKit))
      XCTAssertEqual(merged.raceDisplayName, "New Strava title")
    }
  }

  func testMergingTwoNamedSourcesKeepsTheMostRecentUserName() async throws {
    try withStore { _, defaults in
      let healthKit = workout()
      let strava = workout(stravaID: "42")
      let saved = [
        WorkoutNameOverride(
          id: UUID(), identifiers: healthKit.raceIdentifiers, name: "Older name",
          updatedAt: Date(timeIntervalSince1970: 100)),
        WorkoutNameOverride(
          id: UUID(), identifiers: strava.raceIdentifiers, name: "Latest name",
          updatedAt: Date(timeIntervalSince1970: 200)),
      ]
      defaults.set(try JSONEncoder().encode(saved), forKey: "workoutNames.v1")
      let store = WorkoutNameStore(defaults: defaults)
      store.reconcile([workout(id: healthKit.id, stravaID: "42")])
      XCTAssertEqual(store.overrides.count, 1)
      XCTAssertEqual(store.name(for: healthKit), "Latest name")
      XCTAssertEqual(store.name(for: strava), "Latest name")
    }
  }

  func testOfficialRaceInPlanResolvesRenamedWorkoutWithoutChangingItsRaceFlag() async throws {
    try withStore { store, defaults in
      let run = workout(stravaID: "42")
      let races = WorkoutRaceStore(defaults: defaults)
      races.setOfficialRace(true, for: run)
      let plan = TrainingPlan(
        name: "Plan", goal: "10K", level: .beginner,
        weeks: [TrainingWeek(weekNumber: 1, phase: .base, days: [])], startDate: run.startDate)
      store.rename(run, to: "Les 10 km de Bruxelles")
      let race = try XCTUnwrap(races.races(in: plan, weekIndex: 0).first)
      XCTAssertEqual(store.name(for: race.identifiers), "Les 10 km de Bruxelles")
      XCTAssertTrue(races.isOfficialRace(run))
      store.resetName(for: run)
      XCTAssertNil(store.name(for: race.identifiers))
      XCTAssertEqual(race.name, "Morning Run")
      XCTAssertTrue(races.isOfficialRace(run))
    }
  }

  func testSearchFindsTheCustomNameAndCombinesItWithDistance() async throws {
    try withStore { store, _ in
      let tenK = workout()
      let fiveK = workout(distance: 5_000)
      store.rename(tenK, to: "Bruxelles")
      store.rename(fiveK, to: "Bruxelles")
      let filter = WorkoutSearchFilter(query: "  bRuXeLLeS ", distance: .tenKilometers)
      XCTAssertEqual(filter.apply(to: [tenK, fiveK], names: store).map(\.id), [tenK.id])
      store.resetName(for: tenK)
      XCTAssertTrue(filter.apply(to: [tenK, fiveK], names: store).isEmpty)
    }
  }

  private func workout(
    id: UUID = UUID(), stravaID: String? = nil, sourceTitle: String = "Morning Run",
    distance: Double = 10_000
  ) -> WorkoutModel {
    var metadata: [String: Any] = ["display_name": sourceTitle]
    if let stravaID { metadata["strava_id"] = stravaID }
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    return WorkoutModel(
      id: id, workoutType: .running, startDate: date, endDate: date.addingTimeInterval(3_000),
      duration: 3_000, distance: distance, totalEnergyBurned: nil, sourceName: "Test",
      sourceVersion: nil, metadata: metadata, averageHeartRate: nil, maxHeartRate: nil,
      elevationGain: nil, hasRoute: false
    )
  }
}
