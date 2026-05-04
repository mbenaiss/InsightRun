//
//  NoSleepModeTests.swift
//  InsightRunTests
//
//  Covers the freezing + freshness logic introduced for users without sleep tracking.
//

import XCTest
@testable import insightrun

@MainActor
final class FreshnessScoreFromTSBTests: XCTestCase {

    func testNeutralTSBReturnsBaseline() {
        XCTAssertEqual(TrainingLoadService.freshnessScoreFromTSB(0), 55)
    }

    func testPositiveTSBIncreasesFreshness() {
        // TSB +30 → 55 + 30*1.5 = 100 (clamped)
        XCTAssertEqual(TrainingLoadService.freshnessScoreFromTSB(30), 100)
        XCTAssertEqual(TrainingLoadService.freshnessScoreFromTSB(10), 70)
    }

    func testNegativeTSBDecreasesFreshness() {
        // TSB -20 → 55 - 30 = 25; TSB -30 → 55 - 45 = 10
        XCTAssertEqual(TrainingLoadService.freshnessScoreFromTSB(-20), 25)
        XCTAssertEqual(TrainingLoadService.freshnessScoreFromTSB(-30), 10)
    }

    func testExtremeValuesAreClampedTo0And100() {
        XCTAssertEqual(TrainingLoadService.freshnessScoreFromTSB(500), 100)
        XCTAssertEqual(TrainingLoadService.freshnessScoreFromTSB(-500), 0)
    }
}

@MainActor
final class DailyMetricsCacheFrozenScoreTests: XCTestCase {

    private static let testSuiteName = "com.insightrun.tests.dailyMetricsCache"
    private var testDefaults: UserDefaults!
    private var sut: DailyMetricsCache!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: Self.testSuiteName)!
        sut = DailyMetricsCache.createForTesting(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        testDefaults = nil
        sut = nil
        super.tearDown()
    }

    func testGetCachedScoreForTodayReturnsNilWhenEmpty() {
        XCTAssertNil(sut.getCachedScoreForToday())
    }

    func testGetCachedScoreForTodayReturnsScoreRegardlessOfEffortChange() {
        sut.cacheReadiness(
            score: 78,
            status: "good",
            recommendation: "Solid recovery, run easy.",
            summary: "Run easy",
            workoutType: "moderate",
            effortScore: 30,
            cardiacLoadScore: 12
        )

        // Effort/cardiac mismatch invalidates getCachedReadiness
        XCTAssertNil(sut.getCachedReadiness(effortScore: 60, cardiacLoadScore: 15))
        // …but the frozen score is still available for the day
        let frozen = sut.getCachedScoreForToday()
        XCTAssertEqual(frozen?.score, 78)
        XCTAssertEqual(frozen?.status, "good")
    }
}
