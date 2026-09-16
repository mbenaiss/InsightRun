import HealthKit
import XCTest
@testable import insightrun

@MainActor
final class WorkoutDetailDataTests: XCTestCase {
    private func workout() -> WorkoutModel {
        WorkoutModel(id: UUID(), workoutType: .running,
                     startDate: Date(timeIntervalSince1970: 1_700_000_000),
                     endDate: Date(timeIntervalSince1970: 1_700_007_200),
                     duration: 7200, distance: 20_000, totalEnergyBurned: nil,
                     sourceName: "Apple Watch", sourceVersion: nil, metadata: ["strava_id": "42"],
                     averageHeartRate: 140, maxHeartRate: 165, elevationGain: nil, hasRoute: false)
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

    func testMissingOrEmptyStravaSplitsPreserveHealthKitData() async throws {
        for value in ["null", "[]"] {
            let run = workout()
            let detail = try strava(value)
            let original = WorkoutMetrics(workout: run, averageHeartRate: 140, minPace: 5, splits: splits())
            let model = WorkoutDetailViewModel(workout: run, fetchMetrics: { _ in original }, fetchStravaActivity: { _ in detail })
            await model.loadMetrics()
            XCTAssertEqual(model.metrics?.splits?.count, 20)
            XCTAssertEqual(model.metrics?.splits?.last?.kilometer, 20)
            XCTAssertEqual(model.metrics?.minPace, 5)
            XCTAssertEqual(model.metrics?.totalElevationAscent, 12)
            XCTAssertFalse(model.isLoading)
            XCTAssertFalse(model.isLoadingDetails)
        }
    }

    func testMissingStravaSpeedUsesDistanceAndTimeWithoutZeroPace() async throws {
        let run = workout()
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

    func testStravaFailureKeepsTheLoadedWorkoutUsable() async {
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
}
