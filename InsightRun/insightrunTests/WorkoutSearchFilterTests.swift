import HealthKit
import SwiftData
import XCTest

@testable import insightrun

@MainActor
final class WorkoutSearchFilterTests: XCTestCase {
  func testDistanceFiltersRespectTheirInclusiveMargins() async {
    let ranges: [(WorkoutDistanceFilter, Double, Double)] = [
      (.fiveKilometers, 4_800, 5_200), (.tenKilometers, 9_800, 10_200),
      (.halfMarathon, 19_000, 22_097.5), (.marathon, 41_195, 43_195),
    ]
    for (filter, lowerBound, upperBound) in ranges {
      for distance in [lowerBound, (lowerBound + upperBound) / 2, upperBound] {
        XCTAssertTrue(filter.matches(distance), "\(filter): \(distance)")
      }
      for distance in [lowerBound - 0.01, upperBound + 0.01, 0, -1, .nan, .infinity] {
        XCTAssertFalse(filter.matches(distance), "\(filter): \(distance)")
      }
      XCTAssertFalse(filter.matches(nil))
    }
    XCTAssertTrue(WorkoutDistanceFilter.all.matches(nil))
    XCTAssertTrue(WorkoutDistanceFilter.all.matches(0))
  }

  func testHalfMarathonSearchIncludesTwentyKilometersAndHalfMarathonsWithOneKilometerMargin() async
  {
    let twentyK = workout(distance: 20_120)
    let half = workout(distance: 21_150)
    let betweenTargets = workout(distance: 20_500)
    let outsideMargin = workout(distance: 22_100)
    let results = WorkoutSearchFilter(distance: .halfMarathon).apply(
      to: [twentyK, half, betweenTargets, outsideMargin])
    XCTAssertEqual(results.map(\.id), [twentyK.id, half.id, betweenTargets.id])
  }

  func testSearchCombinesTextAndDistanceAcrossDatesAndOfficialRaces() async throws {
    let suite = "WorkoutSearchFilterTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = WorkoutRaceStore(defaults: defaults)
    let recent = workout(distance: 10_009)
    let old = workout(distance: 9_800, date: Date(timeIntervalSince1970: 1_700_000_000))
    let fiveK = workout(distance: 5_021)
    let all = [recent, old, fiveK]
    let distance = WorkoutSearchFilter(distance: .tenKilometers)
    XCTAssertEqual(distance.apply(to: all).map(\.id), [recent.id, old.id])
    XCTAssertEqual(
      WorkoutSearchFilter(query: "  sTrAvA ", distance: .tenKilometers).apply(to: all).map(\.id),
      [recent.id, old.id])
    XCTAssertEqual(
      WorkoutSearchFilter(query: "2023", distance: .tenKilometers).apply(to: all).map(\.id),
      [old.id])
    XCTAssertTrue(
      WorkoutSearchFilter(query: "no match", distance: .tenKilometers).apply(to: all).isEmpty)
    store.setOfficialRace(true, for: old)
    store.setOfficialRace(true, for: fiveK)
    XCTAssertEqual(distance.apply(to: store.officialRaces(from: all)).map(\.id), [old.id])
    XCTAssertEqual(WorkoutSearchFilter().apply(to: all).count, 3)
  }

  func testNonRunningStravaActivitiesCannotMergeWithARun() async {
    let run = workout(distance: 0)
    let strength = activity(id: 1, type: "WeightTraining", distance: 0, date: run.startDate)
    let free = activity(id: 2, type: "Workout", distance: 0, date: run.startDate)
    let merged = UnifiedWorkoutViewModel().mergeWorkouts(
      healthKit: [run], strava: [strength, free])
    XCTAssertEqual(merged.count, 1)
    XCTAssertEqual(merged.first?.healthKitWorkout?.id, run.id)
    XCTAssertNil(merged.first?.stravaActivity)
    XCTAssertEqual(UnifiedWorkout(from: strength).toWorkoutModel().workoutType, .other)
  }

  func testRunningTypesIncludingZeroDistanceSurviveWhileOtherSportsAreExcluded() async {
    let types = [
      "Run", "TrailRun", "VirtualRun", "Workout", "WeightTraining", "Ride", "Walk", "Unknown",
    ]
    let activities = types.enumerated().map { index, type in
      activity(id: Int64(index), type: type, distance: 0)
    }
    let merged = UnifiedWorkoutViewModel().mergeWorkouts(healthKit: [], strava: activities)
    XCTAssertEqual(
      merged.compactMap { $0.stravaActivity?.type }, ["Run", "TrailRun", "VirtualRun"])
    XCTAssertTrue(merged.allSatisfy { $0.toWorkoutModel().workoutType == .running })
  }

  func testLegacyCacheRecoversOriginalTypesWithoutInventingRuns() async throws {
    let container = try ModelContainer(
      for: CachedUnifiedWorkout.self, CachedStravaActivity.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    for (index, type) in ["Run", "WeightTraining", "Workout", "VirtualRun"].enumerated() {
      let original = activity(id: Int64(index), type: type)
      context.insert(CachedStravaActivity(from: original))
      let legacy = CachedUnifiedWorkout(from: UnifiedWorkout(from: original))
      legacy.stravaActivityType = nil
      context.insert(legacy)
    }
    let unknown = CachedUnifiedWorkout(from: UnifiedWorkout(from: activity(id: 99, type: "Run")))
    unknown.stravaActivityType = nil
    context.insert(unknown)
    try context.save()

    let cache = UnifiedWorkoutCache(modelContext: context)
    XCTAssertEqual(
      Set(try cache.fetchAllWorkouts().compactMap { $0.stravaActivity?.type }),
      ["Run", "VirtualRun"])
    let reopened = ModelContext(container)
    XCTAssertEqual(try UnifiedWorkoutCache(modelContext: reopened).fetchAllWorkouts().count, 2)
    XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<CachedStravaActivity>()), 4)
    let entries = try reopened.fetch(FetchDescriptor<CachedUnifiedWorkout>())
    XCTAssertEqual(entries.first { $0.stravaActivityId == 1 }?.stravaActivityType, "WeightTraining")
    XCTAssertNil(entries.first { $0.stravaActivityId == 99 }?.stravaActivityType)
  }

  func testCachedTypeIsPreservedOnInsertAndUpdatedWhenStravaSportChanges() async throws {
    let container = try ModelContainer(
      for: CachedUnifiedWorkout.self, CachedStravaActivity.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let cache = UnifiedWorkoutCache(modelContext: context)
    try cache.saveWorkouts([UnifiedWorkout(from: activity(id: 42, type: "TrailRun"))])
    XCTAssertEqual(try cache.fetchAllWorkouts().first?.stravaActivity?.type, "TrailRun")
    try cache.saveWorkouts([UnifiedWorkout(from: activity(id: 42, type: "WeightTraining"))])
    XCTAssertTrue(try cache.fetchAllWorkouts().isEmpty)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<CachedUnifiedWorkout>()).first?.stravaActivityType,
      "WeightTraining")
  }

  private func activity(id: Int64, type: String, distance: Double = 5_000, date: Date = Date())
    -> StravaActivity
  {
    let start = ISO8601DateFormatter().string(from: date)
    return StravaActivity(
      id: id, name: "Test \(type)", distance: distance, movingTime: 1_800,
      elapsedTime: 1_800, totalElevationGain: 0, type: type,
      startDate: start, startDateLocal: start, averageSpeed: nil,
      maxSpeed: nil, averageHeartrate: nil, maxHeartrate: nil, calories: nil, trainer: nil
    )
  }

  private func workout(distance: Double, date: Date = Date()) -> WorkoutModel {
    WorkoutModel(
      id: UUID(), workoutType: .running, startDate: date, endDate: date.addingTimeInterval(1_800),
      duration: 1_800, distance: distance, totalEnergyBurned: nil, sourceName: "Strava",
      sourceVersion: nil, metadata: nil, averageHeartRate: nil, maxHeartRate: nil,
      elevationGain: nil, hasRoute: false
    )
  }
}
