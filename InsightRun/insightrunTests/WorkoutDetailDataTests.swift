import HealthKit
import SwiftData
import XCTest
@testable import insightrun

@MainActor
final class WorkoutDetailDataTests: XCTestCase {
    private func workout(source: String = "Apple Watch", indoor: Bool = false) -> WorkoutModel {
        WorkoutModel(id: UUID(), workoutType: .running,
                     startDate: Date(timeIntervalSince1970: 1_700_000_000),
                     endDate: Date(timeIntervalSince1970: 1_700_007_200),
                     duration: 7200, distance: 20_000, totalEnergyBurned: nil,
                     sourceName: source, sourceVersion: nil, metadata: ["strava_id": "42"],
                     averageHeartRate: 140, maxHeartRate: 165, elevationGain: nil, hasRoute: false,
                     isIndoor: indoor, effortScore: 6, effortIsEstimated: false)
    }

    private func splits(_ count: Int = 20) -> [Split] {
        (1...count).map { km in
            Split(kilometer: km, distance: 1000, time: km <= 10 ? 300 : 420,
                  pace: km <= 10 ? 5 : 7, averageHeartRate: nil, averagePower: nil,
                  elevationGain: nil, elevationLoss: nil)
        }
    }

    private func strava(_ splitsJSON: String = "null") throws -> StravaDetailedActivity {
        let json = """
        {"id":42,"name":"Run","distance":20000,"moving_time":7200,"elapsed_time":7200,
         "total_elevation_gain":12,"type":"Run","start_date":"2026-09-16T08:00:00Z",
         "splits_metric":\(splitsJSON)}
        """
        return try JSONDecoder().decode(StravaDetailedActivity.self, from: Data(json.utf8))
    }

    func testLongRunPayloadIncludesFinalSplitsInMetricUnits() async throws {
        let run = workout()
        let metrics = WorkoutMetrics(workout: run, splits: splits())
        let data = WorkoutAIService().convertToWorkoutData(workout: run, metrics: metrics)
        XCTAssertEqual(data.splits?.count, 20)
        XCTAssertEqual(data.splits?.first?.pace, "5:00")
        XCTAssertEqual(data.splits?.last?.pace, "7:00")
        XCTAssertEqual(data.splits?.last?.kilometer, 20)
        XCTAssertEqual(data.splits?.last?.distanceMeters, 1000)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any]
        XCTAssertEqual((encoded?["splits"] as? [[String: Any]])?.count, 20)
    }

    func testAppleHealthDetailsNeverRequestStravaEvenWithLegacyMetadata() async throws {
        for value in ["null", "[]"] {
            let run = workout()
            let detail = try strava(value)
            let original = WorkoutMetrics(workout: run, averageHeartRate: 140, minPace: 5, splits: splits())
            var stravaCalls = 0
            let model = WorkoutDetailViewModel(workout: run, fetchMetrics: { _ in original }, fetchStravaActivity: { _ in
                stravaCalls += 1
                return detail
            })
            await model.loadMetrics()
            XCTAssertEqual(model.metrics?.splits?.count, 20)
            XCTAssertEqual(model.metrics?.splits?.last?.kilometer, 20)
            XCTAssertEqual(model.metrics?.minPace, 5)
            XCTAssertNil(model.metrics?.totalElevationAscent)
            XCTAssertEqual(stravaCalls, 0)
            XCTAssertFalse(model.isLoading)
            XCTAssertFalse(model.isLoadingDetails)
        }
    }

    func testMissingStravaSpeedUsesDistanceAndTimeWithoutZeroPace() async throws {
        let run = workout(source: "Strava")
        let detail = try strava("""
        [{"split":1,"distance":1000,"elapsed_time":300,"moving_time":300},
         {"split":2,"distance":0,"elapsed_time":0,"moving_time":0}]
        """)
        let model = WorkoutDetailViewModel(workout: run, fetchMetrics: { WorkoutMetrics(workout: $0, averageHeartRate: 140) }, fetchStravaActivity: { _ in detail })
        await model.loadMetrics()
        XCTAssertEqual(model.metrics?.splits?.count, 1)
        XCTAssertEqual(model.metrics?.splits?.first?.pace, 5)
        XCTAssertEqual(model.metrics?.minPace, 5)
    }

    func testUnavailableStravaDoesNotAffectAppleHealthWorkout() async {
        let run = workout()
        let original = WorkoutMetrics(workout: run, averageHeartRate: 140, splits: splits())
        let model = WorkoutDetailViewModel(workout: run, fetchMetrics: { _ in original }, fetchStravaActivity: { _ in throw URLError(.timedOut) })
        await model.loadMetrics()
        XCTAssertEqual(model.metrics?.splits?.count, 20)
        XCTAssertEqual(model.metrics?.averageHeartRate, 140)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isLoadingDetails)
    }

    func testCancelledHealthReadDoesNotStartStravaOrPublishIncompleteMetrics() async {
        var stravaCalls = 0
        let model = WorkoutDetailViewModel(workout: workout(), fetchMetrics: { _ in throw CancellationError() }, fetchStravaActivity: { _ in
            stravaCalls += 1
            return try self.strava()
        })
        await model.loadMetrics()
        XCTAssertEqual(stravaCalls, 0)
        XCTAssertNil(model.metrics)
        XCTAssertFalse(model.isLoading)
    }
    func testMatchingStravaRunCannotOverrideAppleHealthWorkout() async throws {
        let run = workout(indoor: true)
        let date = ISO8601DateFormatter().string(from: run.startDate)
        let strava = StravaActivity(id: 42, name: "Outdoor Strava copy", distance: 20_100,
                                   movingTime: 7000, elapsedTime: 7200, totalElevationGain: 100,
                                   type: "Run", startDate: date, startDateLocal: date,
                                   averageSpeed: 4, maxSpeed: 6, averageHeartrate: 149,
                                   maxHeartrate: 180, calories: 200, trainer: false)
        let result = UnifiedWorkoutViewModel().mergeWorkouts(healthKit: [run], strava: [strava])
        XCTAssertEqual(result.count, 1)
        let unified = try XCTUnwrap(result.first)
        XCTAssertEqual(unified.source, .healthKit)
        XCTAssertNil(unified.stravaActivity)
        let model = unified.toWorkoutModel()
        XCTAssertTrue(model.isIndoor)
        XCTAssertEqual(model.distance, run.distance)
        XCTAssertEqual(model.averageHeartRate, 140)
        XCTAssertEqual(model.effortScore, 6)
        XCTAssertEqual(model.averagePace, run.averagePace)
    }

    func testCacheRoundTripAndUpdatesKeepIndoorEffortAndOriginalSource() async throws {
        let container = try ModelContainer(for: CachedUnifiedWorkout.self, CachedStravaActivity.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cache = UnifiedWorkoutCache(modelContext: container.mainContext)
        let run = workout(indoor: true)
        try cache.saveWorkouts([UnifiedWorkout(from: run)])
        let restored = try XCTUnwrap(cache.fetchAllWorkouts().first?.toWorkoutModel())
        XCTAssertEqual(restored.id, run.id)
        XCTAssertTrue(restored.isIndoor)
        XCTAssertEqual(restored.effortScore, 6)
        XCTAssertFalse(restored.effortIsEstimated)
        XCTAssertEqual(restored.sourceName, "Apple Watch")
        var updated = run
        updated.effortScore = 7
        try cache.saveWorkouts([UnifiedWorkout(from: updated)])
        let freshContext = ModelContext(container)
        let saved = try XCTUnwrap(UnifiedWorkoutCache(modelContext: freshContext).fetchAllWorkouts().first?.toWorkoutModel())
        XCTAssertEqual(saved.effortScore, 7)
        XCTAssertTrue(saved.isIndoor)
    }


    func testAppleKilometerEventsAreNotMixedWithMileEvents() async throws {
        let start = Date(timeIntervalSince1970: 0)
        let eventTimes: [(Double, Double)] = [(0, 391.472), (0, 638.871), (391.472, 801.229),
                                                   (638.871, 1223.919), (801.229, 1212.982), (1212.982, 1223.919)]
        let events = eventTimes.map { lower, upper in
            HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: start.addingTimeInterval(lower), end: start.addingTimeInterval(upper)), metadata: nil)
        }
        let intervals = try XCTUnwrap(WorkoutSplitBoundaries.kilometers(events: Array(events.reversed()), distance: 3021.036, start: start, end: start.addingTimeInterval(1225.532)))
        XCTAssertEqual(intervals.map { Int($0.duration.rounded()) }, [391, 410, 412, 11])
        XCTAssertNil(WorkoutSplitBoundaries.kilometers(events: Array(events.prefix(2)), distance: 3021.036, start: start, end: start.addingTimeInterval(1225.532)))
        XCTAssertNil(WorkoutSplitBoundaries.kilometers(events: events, distance: 10000, start: start, end: start.addingTimeInterval(1225.532)))
        let split = Split(kilometer: 2, distance: 1000, time: intervals[1].duration,
                          pace: intervals[1].duration / 60, averageHeartRate: nil, averagePower: nil,
                          elevationGain: nil, elevationLoss: nil)
        XCTAssertEqual(split.timeFormatted, "6:50")
    }
    private func comparisonWorkout(distance: Double = 5000, duration: Double = 1800, daysAgo: Double = 0, indoor: Bool = true) -> WorkoutModel {
        let start = Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86400)
        return WorkoutModel(id: UUID(), workoutType: .running, startDate: start,
                            endDate: start.addingTimeInterval(duration), duration: duration,
                            distance: distance, totalEnergyBurned: 300,
                            sourceName: "Apple Watch", sourceVersion: nil, metadata: nil,
                            averageHeartRate: 150, maxHeartRate: 170, elevationGain: 0,
                            hasRoute: false, isIndoor: indoor)
    }

    func testSimilarWorkoutsRespectChronologyEnvironmentAndDistance() {
        let current = comparisonWorkout()
        let earlier = comparisonWorkout(daysAgo: 1)
        let oldest = comparisonWorkout(daysAgo: 5)
        let candidates = [current, comparisonWorkout(daysAgo: -1), comparisonWorkout(daysAgo: 2, indoor: false),
                          comparisonWorkout(distance: 10_000, daysAgo: 3), oldest, earlier]
        XCTAssertEqual(SimilarWorkoutFinder.findSimilar(to: current, from: candidates).map(\.id), [earlier.id, oldest.id])
        XCTAssertTrue(SimilarWorkoutFinder.findSimilar(to: current, from: candidates, limit: -1).isEmpty)
        XCTAssertTrue(SimilarWorkoutFinder.findSimilar(to: comparisonWorkout(distance: 0), from: candidates).isEmpty)
    }

    func testComparisonDoesNotTreatVolumeDifferencesAsProgress() async {
        let current = comparisonWorkout(distance: 4000, duration: 1200)
        let previous = comparisonWorkout(daysAgo: 2)
        let model = WorkoutComparisonViewModel(referenceWorkout: current, similarWorkouts: [previous])
        let deltas = model.comparisons[0].deltas
        XCTAssertEqual(deltas.first?.direction, .improved)
        XCTAssertTrue(deltas.dropFirst().allSatisfy { $0.direction == .neutral })
        let expectedPaceDelta = Formatters.paceClock(60 / (UnitPreference.current.usesImperial ? Formatters.kmToMiles : 1))
        XCTAssertEqual(deltas.first?.deltaText, "-\(expectedPaceDelta) \(Formatters.paceUnitSuffix())")
    }

    func testComparisonAnalysisCacheChangesWhenPeersChange() async {
        let current = comparisonWorkout()
        let earlier = comparisonWorkout(daysAgo: 2)
        let initial = WorkoutComparisonViewModel(referenceWorkout: current, similarWorkouts: [earlier])
        let repeated = WorkoutComparisonViewModel(referenceWorkout: current, similarWorkouts: [earlier])
        let changed = WorkoutComparisonViewModel(referenceWorkout: current, similarWorkouts: [comparisonWorkout(daysAgo: 3)])
        XCTAssertEqual(initial.analysisCacheKey, repeated.analysisCacheKey)
        XCTAssertNotEqual(initial.analysisCacheKey, changed.analysisCacheKey)
    }

    func testKilometerDurationsIncludeRoundedPartialSegment() {
        let times: [Double] = [391.472, 409.757, 411.752, 10.937]
        let durations = times.enumerated().map { index, time in
            Split(kilometer: index + 1, distance: index == 3 ? 21 : 1000, time: time, pace: time / 60,
                  averageHeartRate: nil, averagePower: nil, elevationGain: nil, elevationLoss: nil).timeFormatted
        }
        XCTAssertEqual(durations, ["6:31", "6:50", "6:52", "0:11"])
    }

    func testWeeklyVolumeIncludesTheSameTimeOfDayAndDoesNotInventGrowthFromZero() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        calendar.firstWeekday = 2
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-14T18:00:00Z"))
        let ranges = try XCTUnwrap(TrainingLoadService.weeklyComparisonRanges(through: date, calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: ranges.previous.end), 20)
        XCTAssertEqual(calendar.component(.day, from: ranges.previous.end), 7)
        XCTAssertEqual(ranges.current.duration, ranges.previous.duration)
        XCTAssertEqual(TrainingLoadService.volumeChange(current: 10000, previous: 10000), 0)
        XCTAssertNil(TrainingLoadService.volumeChange(current: 10000, previous: 0))
        XCTAssertEqual(TrainingLoadService.volumeChange(current: 0, previous: 10000), -100)
    }

    func testAnalysisPayloadRoundsMeasurementsLikeTheMetricCards() {
        let run = workout()
        let metrics = WorkoutMetrics(workout: run, averageHeartRate: 149.8, averageCadence: 64.7)
        let payload = WorkoutAIService().convertToWorkoutData(workout: run, metrics: metrics)
        XCTAssertEqual(payload.heartRate?.avg, 150)
        XCTAssertEqual(payload.cadence, 65)
    }

}
