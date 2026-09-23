import Foundation
import HealthKit
import XCTest

@testable import insightrun

@MainActor
final class HealthDataPayloadTests: XCTestCase {
    private let backendTimestamp = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#
    private let watchBundle = "com.apple.health.6F1D2C3B-9A4E-4F70-8C1D-2B3A4C5D6E7F"

    private func parisCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        return calendar
    }

    func testPayloadDatesKeepTheLocalDayAndOffset() throws {
        let calendar = try parisCalendar()
        let night = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23)))
        XCTAssertEqual(night.ISO8601Format(), "2026-09-22T22:00:00Z")
        XCTAssertEqual(PayloadDate.day(night, timeZone: calendar.timeZone), "2026-09-23")
        XCTAssertEqual(PayloadDate.timestamp(night, timeZone: calendar.timeZone), "2026-09-23T00:00:00+02:00")
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(PayloadDate.timestamp(night, timeZone: newYork), "2026-09-22T18:00:00-04:00")
        XCTAssertEqual(ISO8601DateFormatter().date(from: PayloadDate.timestamp(night, timeZone: calendar.timeZone)), night)
    }

    func testRecoveryAndWorkoutPayloadsUseLocalDates() throws {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let posix = DateFormatter()
        posix.calendar = Calendar(identifier: .gregorian)
        posix.locale = Locale(identifier: "en_US_POSIX")
        posix.timeZone = .current
        posix.dateFormat = "yyyy-MM-dd"
        let recovery = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(RecoveryData(metrics: RecoveryMetrics(date: day, hrvAverage: 50))))
                as? [String: Any])
        XCTAssertEqual(recovery["date"] as? String, posix.string(from: day))

        let start = day.addingTimeInterval(7 * 3600)
        let run = WorkoutModel(
            id: UUID(), workoutType: .running, startDate: start, endDate: start.addingTimeInterval(1800),
            duration: 1800, distance: 5000, totalEnergyBurned: nil, sourceName: "Apple Watch", sourceVersion: nil,
            metadata: nil, averageHeartRate: nil, maxHeartRate: nil, elevationGain: nil, hasRoute: false)
        let workout = WorkoutAIService().convertToWorkoutData(workout: run, metrics: nil)
        XCTAssertEqual(workout.date, PayloadDate.timestamp(start))
        XCTAssertNotNil(workout.date.range(of: backendTimestamp, options: .regularExpression))
        XCTAssertEqual(ISO8601DateFormatter().date(from: workout.date), start)
    }

    func testRMSSDPayloadSendsLocalNightsAndOnlyASourceCategory() throws {
        let calendar = try parisCalendar()
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23)))
        let category = HealthInsightReader.sourceCategory(bundleIdentifier: watchBundle, productType: "Watch7,1")
        let observations = try (-7...0).flatMap { offset -> [RMSSDTrend.Observation] in
            let night = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: day))
            return (1...3).map {
                RMSSDTrend.Observation(
                    date: night.addingTimeInterval(Double($0) * 300), night: night, value: 60,
                    source: "\(watchBundle)/Watch7,1/11.0", category: category)
            }
        }
        let trend = try XCTUnwrap(RMSSDTrend.calculate(
            observations: observations, day: day, now: day.addingTimeInterval(8 * 3600), calendar: calendar))
        XCTAssertEqual(trend.currentNight?.date, "2026-09-23T00:00:00+02:00")
        XCTAssertEqual(trend.nights.first?.date, "2026-09-16T00:00:00+02:00")
        XCTAssertEqual(trend.latestSampleAt, "2026-09-23T00:15:00+02:00")
        XCTAssertEqual(trend.measuredAt, "2026-09-23T08:00:00+02:00")
        for date in trend.nights.map(\.date) + [trend.latestSampleAt, trend.measuredAt] {
            XCTAssertNotNil(date.range(of: backendTimestamp, options: .regularExpression), date)
        }
        XCTAssertEqual(trend.history(endingOn: day, calendar: calendar).count, 7)

        let payload = try JSONEncoder().encode(RecoveryData(metrics: RecoveryMetrics(date: day, hrvAverage: 50, rmssd: trend)))
        let json = String(decoding: payload, as: UTF8.self)
        XCTAssertTrue(json.contains(#""source":"Apple Watch""#))
        for identifier in ["com.apple.health", "6F1D2C3B", "Watch7", "11.0"] {
            XCTAssertFalse(json.contains(identifier), identifier)
        }
        let rmssd = try XCTUnwrap((JSONSerialization.jsonObject(with: payload) as? [String: Any])?["rmssd"] as? [String: Any])
        XCTAssertEqual(Set(rmssd.keys), [
            "metric", "context", "source", "sourceChanged", "latestSampleAt", "measuredAt", "currentNight",
            "baselineMedian", "baselineNights", "recentMedian", "recentNights", "nights",
        ])
    }

    func testSourceCategoriesHideDeviceIdentifiers() {
        XCTAssertEqual(HealthInsightReader.sourceCategory(bundleIdentifier: watchBundle, productType: "Watch7,1"), "Apple Watch")
        XCTAssertEqual(HealthInsightReader.sourceCategory(bundleIdentifier: watchBundle, productType: "iPhone17,2"), "iPhone")
        XCTAssertEqual(HealthInsightReader.sourceCategory(bundleIdentifier: "com.apple.Health", productType: "iPhone17,2"), "iPhone")
        XCTAssertEqual(HealthInsightReader.sourceCategory(bundleIdentifier: "com.strava.stravaride", productType: "iPhone17,2"), "Third-party app")
        XCTAssertEqual(HealthInsightReader.sourceCategory(bundleIdentifier: "com.apple.health", productType: nil), "Other Apple device")
    }

    func testAgeIsDerivedFromTheDateOfBirth() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12)))
        XCTAssertEqual(HealthKitManager.age(from: DateComponents(year: 1990, month: 9, day: 24), now: now, calendar: calendar), 35)
        XCTAssertEqual(HealthKitManager.age(from: DateComponents(year: 1990, month: 9, day: 23), now: now, calendar: calendar), 36)
        XCTAssertNil(HealthKitManager.age(from: nil, now: now, calendar: calendar))
        XCTAssertNil(HealthKitManager.age(from: DateComponents(year: 2030, month: 1, day: 1), now: now, calendar: calendar))
    }

    func testPermissionOutcomeNeverReportsGrantedWithoutReadableWorkouts() {
        XCTAssertEqual(HealthKitManager.permissionOutcome(workoutsFound: 3, error: nil), .dataFound)
        XCTAssertEqual(HealthKitManager.permissionOutcome(workoutsFound: 0, error: nil), .noData)
        XCTAssertEqual(HealthKitManager.permissionOutcome(workoutsFound: nil, error: URLError(.timedOut)), .error)
    }

    func testOnlyTheFirstPermissionRequestCarriesTimingAndWorkoutCount() {
        let first = HealthKitManager.permissionAnalyticsProperties(
            outcome: .noData, duration: 2.345, workoutsFound: 0, error: nil, isFirstRequest: true)
        XCTAssertEqual(first["outcome"] as? String, "no_data")
        XCTAssertEqual(first["duration_ms"] as? Int, 2345)
        XCTAssertEqual(first["sheet_likely_shown"] as? Bool, true)
        XCTAssertEqual(first["workouts_found"] as? Int, 0)
        XCTAssertNil(first["error_code"])

        let failure = HealthKitManager.permissionAnalyticsProperties(
            outcome: .error, duration: 0.04, workoutsFound: nil,
            error: HealthKitError.queryFailed(NSError(domain: HKErrorDomain, code: 5)), isFirstRequest: true)
        XCTAssertEqual(failure["outcome"] as? String, "error")
        XCTAssertEqual(failure["sheet_likely_shown"] as? Bool, false)
        XCTAssertEqual(failure["error_code"] as? Int, 5)
        XCTAssertNil(failure["workouts_found"])

        let later = HealthKitManager.permissionAnalyticsProperties(
            outcome: .dataFound, duration: 2, workoutsFound: 12, error: nil, isFirstRequest: false)
        XCTAssertEqual(later.keys.sorted(), ["outcome"])
        XCTAssertEqual(later["outcome"] as? String, "data_found")
    }

    func testSampleVerdictQuotesTheSampleWorkoutMeasurements() throws {
        let sample = MockData.activationWorkout
        let pace = Formatters.paceClock(try XCTUnwrap(sample.averagePace) * 60)
        let heartRate = Int(try XCTUnwrap(sample.averageHeartRate))
        XCTAssertEqual(pace, "4:48")
        XCTAssertTrue(MockData.sampleWorkoutAnalysis.contains("\(pace)/km"))
        XCTAssertTrue(MockData.sampleWorkoutAnalysis.contains("\(heartRate)"))
    }

    func testWorkoutStepCountHasItsOwnFrenchKey() throws {
        let french = try XCTUnwrap(Bundle.main.path(forResource: "fr", ofType: "lproj").flatMap(Bundle.init(path:)))
        let locale = Locale(identifier: "fr_FR")
        XCTAssertEqual(String(localized: "workout.steps.count", defaultValue: "\(4) steps", bundle: french, locale: locale), "4 étapes")
        XCTAssertEqual(String(localized: "workout.steps.count", defaultValue: "\(1) steps", bundle: french, locale: locale), "1 étape")
        XCTAssertEqual(String(localized: "steps", bundle: french, locale: locale), "pas")
    }
}
