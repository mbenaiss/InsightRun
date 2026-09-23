import XCTest

@testable import insightrun

@MainActor
final class ReadinessWidgetDataTests: XCTestCase {
    func testScoreBandsUseTheAppAndBackendThresholds() {
        XCTAssertEqual(ReadinessScoreBand(score: 100), .excellent)
        XCTAssertEqual(ReadinessScoreBand(score: 67), .excellent)
        XCTAssertEqual(ReadinessScoreBand(score: 66), .good)
        XCTAssertEqual(ReadinessScoreBand(score: 50), .good)
        XCTAssertEqual(ReadinessScoreBand(score: 49), .fair)
        XCTAssertEqual(ReadinessScoreBand(score: 33), .fair)
        XCTAssertEqual(ReadinessScoreBand(score: 32), .poor)
        XCTAssertEqual(ReadinessScoreBand(score: 0), .poor)
    }

    func testScoreBandsAgreeWithTheAppRecoveryStatus() {
        for hrv in stride(from: 20.0, through: 100.0, by: 1.0) {
            let metrics = RecoveryMetrics(date: Date(), hrvAverage: hrv)
            let expected: ReadinessScoreBand = switch metrics.recoveryStatus {
            case .excellent: .excellent
            case .good: .good
            case .fair: .fair
            case .poor: .poor
            }
            XCTAssertEqual(ReadinessScoreBand(score: metrics.recoveryScore), expected, "score \(metrics.recoveryScore)")
        }
    }

    func testWidgetStoresTheDisplayedScoreAndItsDay() throws {
        let suite = "readiness-widget-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = WidgetDataProvider.createForTesting(defaults: defaults)
        func stored() throws -> WidgetReadinessData {
            try JSONDecoder().decode(WidgetReadinessData.self, from: XCTUnwrap(defaults.data(forKey: WidgetDataKeys.readiness)))
        }

        let recovery = RecoveryMetrics(date: Calendar.current.startOfDay(for: Date()), restingHeartRate: 52, hrvAverage: 64)
        provider.updateReadiness(score: 58, status: .good, recovery: recovery)
        XCTAssertEqual(try stored().score, 58)
        XCTAssertEqual(try stored().status, "good")
        XCTAssertEqual(try stored().hrvValue, 64)
        XCTAssertEqual(try stored().rhrValue, 52)
        XCTAssertTrue(Calendar.current.isDateInToday(try stored().date))

        provider.updateReadiness(score: 71, status: .unknown, recovery: nil)
        XCTAssertEqual(try stored().status, "excellent")
        XCTAssertNil(try stored().hrvValue)
    }
}
