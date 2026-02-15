//
//  ScoreAnalysisViewModelTests.swift
//  InsightRunTests
//

import XCTest
@testable import insightrun

@MainActor
final class ScoreAnalysisViewModelTests: XCTestCase {

    private static let testSuiteName = "com.insightrun.tests"
    private var sut: ScoreAnalysisViewModel!
    private var testDefaults: UserDefaults!
    private var testCache: DailyMetricsCache!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: Self.testSuiteName)!
        ScoreAnalysisViewModel.defaults = testDefaults
        testCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
        sut = ScoreAnalysisViewModel()
    }

    override func tearDown() {
        ScoreAnalysisViewModel.defaults = .standard
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        testDefaults = nil
        testCache = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Cache Key Tests

    func testCacheKeyContainsLanguageAndDate() {
        let key = sut.testCacheKey(for: "score_effort")
        let lang = Locale.current.language.languageCode?.identifier ?? "en"

        XCTAssertTrue(key.contains(lang), "Cache key should contain language code")
        XCTAssertTrue(key.hasPrefix("ai_analysis_score_effort_"), "Cache key should have correct prefix")
    }

    func testCacheKeyDifferentIdentifiersProduceDifferentKeys() {
        let key1 = sut.testCacheKey(for: "score_effort")
        let key2 = sut.testCacheKey(for: "score_sleep")

        XCTAssertNotEqual(key1, key2, "Different identifiers should produce different cache keys")
    }

    // MARK: - Cache Save/Retrieve Tests

    func testSaveAndRetrieveFromCache() {
        let identifier = "test_metric"
        let text = "This is a cached analysis"

        sut.testSaveAnalysis(text, for: identifier)
        let retrieved = sut.testCachedAnalysis(for: identifier)

        XCTAssertEqual(retrieved, text, "Retrieved analysis should match saved text")
    }

    func testCachedAnalysisReturnsNilWhenEmpty() {
        let result = sut.testCachedAnalysis(for: "nonexistent_identifier")
        XCTAssertNil(result, "Should return nil for non-cached identifier")
    }

    func testCleanOldCacheRemovesOldEntries() {
        let identifier = "test_clean"
        let oldKey = "ai_analysis_\(identifier)_en_2020-01-01"
        testDefaults.set("old", forKey: oldKey)

        sut.testSaveAnalysis("new", for: identifier)

        let oldValue = testDefaults.string(forKey: oldKey)
        XCTAssertNil(oldValue, "Old cache entries should be cleaned up")
    }

    // MARK: - Build Prompt Tests

    func testBuildPromptContainsScore() {
        let prompt = sut.testBuildPrompt(scoreType: .effort, score: 75)
        XCTAssertTrue(prompt.contains("75"), "Prompt should contain the score value")
    }

    func testBuildPromptContainsLanguage() {
        let prompt = sut.testBuildPrompt(scoreType: .effort, score: 50)
        let lang = Locale.current.englishLanguageName
        XCTAssertTrue(prompt.contains(lang), "Prompt should contain the language name")
    }

    func testBuildPromptEffortContainsKeywords() {
        let prompt = sut.testBuildPrompt(scoreType: .effort, score: 80)
        XCTAssertTrue(prompt.contains("effort"), "Effort prompt should mention effort")
    }

    func testBuildPromptSleepContainsKeywords() {
        let prompt = sut.testBuildPrompt(scoreType: .sleep, score: 85)
        XCTAssertTrue(prompt.lowercased().contains("sleep"), "Sleep prompt should mention sleep")
    }

    func testBuildPromptReadinessContainsKeywords() {
        let prompt = sut.testBuildPrompt(scoreType: .readiness, score: 70)
        XCTAssertTrue(prompt.lowercased().contains("readiness"), "Readiness prompt should mention readiness")
    }

    func testBuildPromptCardiacLoadContainsKeywords() {
        let prompt = sut.testBuildPrompt(scoreType: .cardiacLoad, score: 12)
        XCTAssertTrue(prompt.lowercased().contains("cardiac"), "Cardiac load prompt should mention cardiac")
    }

    func testBuildPromptCardiacLoadWithTrendData() {
        let points = (0..<7).map { day in
            TrendDataPoint(
                date: Calendar.current.date(byAdding: .day, value: -6 + day, to: Date())!,
                value: Double(10 + day)
            )
        }
        let prompt = sut.testBuildPrompt(scoreType: .cardiacLoad, score: 15, trendData: points)
        XCTAssertTrue(prompt.contains("trend"), "Cardiac load prompt with trend data should mention trend")
    }

    // MARK: - Build Metric Prompt Tests

    func testBuildMetricPromptHRV() {
        let prompt = sut.testBuildMetricPrompt(metricType: .hrv, value: 45.0, unit: "ms")
        XCTAssertTrue(prompt.contains("45.0"), "HRV prompt should contain the value")
        XCTAssertTrue(prompt.lowercased().contains("hrv"), "HRV prompt should mention HRV")
    }

    func testBuildMetricPromptRestingHeartRate() {
        let prompt = sut.testBuildMetricPrompt(metricType: .restingHeartRate, value: 62.0, unit: "bpm")
        XCTAssertTrue(prompt.contains("62.0"), "RHR prompt should contain the value")
        XCTAssertTrue(prompt.lowercased().contains("resting heart rate"), "RHR prompt should mention resting heart rate")
    }

    func testBuildMetricPromptRespiratoryRate() {
        let prompt = sut.testBuildMetricPrompt(metricType: .respiratoryRate, value: 14.5, unit: "rpm")
        XCTAssertTrue(prompt.contains("14.5"), "Respiratory rate prompt should contain the value")
        XCTAssertTrue(prompt.lowercased().contains("respiratory"), "Respiratory prompt should mention respiratory")
    }

    func testBuildMetricPromptOxygenSaturation() {
        let prompt = sut.testBuildMetricPrompt(metricType: .oxygenSaturation, value: 98.0, unit: "%")
        XCTAssertTrue(prompt.contains("98.0"), "SpO2 prompt should contain the value")
        XCTAssertTrue(prompt.lowercased().contains("oxygen"), "SpO2 prompt should mention oxygen")
    }

    // MARK: - Format Trend Summary Tests

    func testFormatTrendSummaryWithData() {
        let points = (0..<3).map { day in
            TrendDataPoint(
                date: Calendar.current.date(byAdding: .day, value: -2 + day, to: Date())!,
                value: Double(10 + day)
            )
        }
        let result = sut.testFormatTrendSummary(points)
        XCTAssertNotNil(result, "Should return formatted summary for non-empty data")
        XCTAssertTrue(result!.contains("Day"), "Summary should contain day labels")
    }

    func testFormatTrendSummaryEmpty() {
        let result = sut.testFormatTrendSummary([])
        XCTAssertNil(result, "Should return nil for empty data")
    }

    func testFormatTrendSummaryNil() {
        let result = sut.testFormatTrendSummary(nil)
        XCTAssertNil(result, "Should return nil for nil data")
    }

    // MARK: - Effort Score Computation Tests

    func testEffortScoreAllGoalsMet() {
        let activity = DailyActivityData(
            steps: 10_000,
            activeCalories: 400,
            exerciseMinutes: 30,
            activeCaloriesGoal: 400,
            exerciseMinutesGoal: 30
        )
        let score = MetricTrendDataService.testComputeEffortScore(activity: activity)
        XCTAssertEqual(score, 100, "Score should be 100 when all goals are met")
    }

    func testEffortScoreZeroActivity() {
        let activity = DailyActivityData(
            steps: 0,
            activeCalories: 0,
            exerciseMinutes: 0,
            activeCaloriesGoal: 400,
            exerciseMinutesGoal: 30
        )
        let score = MetricTrendDataService.testComputeEffortScore(activity: activity)
        XCTAssertEqual(score, 0, "Score should be 0 with no activity")
    }

    func testEffortScorePartialActivity() {
        let activity = DailyActivityData(
            steps: 5_000,
            activeCalories: 200,
            exerciseMinutes: 15,
            activeCaloriesGoal: 400,
            exerciseMinutesGoal: 30
        )
        let score = MetricTrendDataService.testComputeEffortScore(activity: activity)
        XCTAssertEqual(score, 50, "Score should be 50 at half of all goals")
    }

    func testEffortScoreCappedAt100() {
        let activity = DailyActivityData(
            steps: 20_000,
            activeCalories: 800,
            exerciseMinutes: 60,
            activeCaloriesGoal: 400,
            exerciseMinutesGoal: 30
        )
        let score = MetricTrendDataService.testComputeEffortScore(activity: activity)
        XCTAssertEqual(score, 100, "Score should be capped at 100 even when exceeding goals")
    }

    func testEffortScoreUsesDefaultGoalsWhenNil() {
        let activity = DailyActivityData(
            steps: 10_000,
            activeCalories: 400,
            exerciseMinutes: 30,
            activeCaloriesGoal: nil,
            exerciseMinutesGoal: nil
        )
        let score = MetricTrendDataService.testComputeEffortScore(activity: activity)
        XCTAssertEqual(score, 100, "Score should use default goals (400 cal, 30 min) when nil")
    }

    func testEffortScoreWeighting() {
        // Steps only: 10000/10000 * 0.30 = 30%
        let stepsOnly = DailyActivityData(
            steps: 10_000,
            activeCalories: 0,
            exerciseMinutes: 0,
            activeCaloriesGoal: 400,
            exerciseMinutesGoal: 30
        )
        let score = MetricTrendDataService.testComputeEffortScore(activity: stepsOnly)
        XCTAssertEqual(score, 30, "Steps alone at goal should give 30% (weight 0.30)")
    }

    // MARK: - Historical Readiness Cache Tests

    func testCacheReadinessSavesHistoricalScore() {
        testCache.cacheReadiness(score: 82, status: "good", recommendation: "Go run", workoutType: "moderate")

        let score = testCache.getHistoricalReadinessScore(for: Date())
        XCTAssertEqual(score, 82, "Historical readiness score should be saved when caching readiness")
    }

    func testGetHistoricalReadinessScoreReturnsNilForMissingDate() {
        let pastDate = Calendar.current.date(byAdding: .year, value: -5, to: Date())!
        let score = testCache.getHistoricalReadinessScore(for: pastDate)
        XCTAssertNil(score, "Should return nil for dates with no stored score")
    }

    func testGetHistoricalReadinessScoreReturnsZeroWhenExplicitlyStored() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let key = "readiness_score_\(formatter.string(from: Date()))"
        testDefaults.set(0, forKey: key)

        let score = testCache.getHistoricalReadinessScore(for: Date())
        XCTAssertEqual(score, 0, "Should return 0 when explicitly stored")
    }
}

// MARK: - MetricTrendDataService Tests

@MainActor
final class MetricTrendDataServiceTests: XCTestCase {

    private static let testSuiteName = "com.insightrun.trendtests"
    private var service: MetricTrendDataService!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: Self.testSuiteName)!
        service = MetricTrendDataService.createForTesting()
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        testDefaults = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Cache Tests

    func testCacheStartsEmpty() {
        XCTAssertEqual(service.testCacheCount, 0, "Cache should start empty")
    }

    func testSetCacheStoresData() {
        let points = [TrendDataPoint(date: Date(), value: 42.0)]
        service.testSetCache(key: "test_key", data: points, timestamp: Date())

        XCTAssertEqual(service.testCacheCount, 1, "Cache should have one entry")
        let cached = service.testGetCachedData(key: "test_key")
        XCTAssertEqual(cached?.count, 1, "Cached data should have one point")
        XCTAssertEqual(cached?.first?.value, 42.0, "Cached value should match")
    }

    func testGetCachedDataReturnsNilForMissingKey() {
        let result = service.testGetCachedData(key: "nonexistent")
        XCTAssertNil(result, "Should return nil for missing cache key")
    }

    func testInvalidateCacheClearsAllEntries() {
        service.testSetCache(key: "key1", data: [TrendDataPoint(date: Date(), value: 1)], timestamp: Date())
        service.testSetCache(key: "key2", data: [TrendDataPoint(date: Date(), value: 2)], timestamp: Date())
        XCTAssertEqual(service.testCacheCount, 2)

        service.invalidateCache()

        XCTAssertEqual(service.testCacheCount, 0, "Cache should be empty after invalidation")
        XCTAssertNil(service.testGetCachedData(key: "key1"), "key1 should be cleared")
        XCTAssertNil(service.testGetCachedData(key: "key2"), "key2 should be cleared")
    }

    func testMultipleCacheKeysIndependent() {
        let points1 = [TrendDataPoint(date: Date(), value: 10)]
        let points2 = [TrendDataPoint(date: Date(), value: 20)]

        service.testSetCache(key: "effort_7", data: points1, timestamp: Date())
        service.testSetCache(key: "sleep_7", data: points2, timestamp: Date())

        XCTAssertEqual(service.testGetCachedData(key: "effort_7")?.first?.value, 10)
        XCTAssertEqual(service.testGetCachedData(key: "sleep_7")?.first?.value, 20)
    }

    // MARK: - Readiness Trend Tests

    func testReadinessTrendReturnsPointsFromCache() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -6 + dayOffset, to: today) else { continue }
            let testCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let key = "readiness_score_\(formatter.string(from: date))"
            testDefaults.set(70 + dayOffset, forKey: key)
        }

        let metricsCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
        let points = await service.readinessTrend(days: 7, metricsCache: metricsCache)

        XCTAssertEqual(points.count, 7, "Should return 7 days of readiness data")
        XCTAssertEqual(Int(points.first!.value), 70, "First day should have score 70")
        XCTAssertEqual(Int(points.last!.value), 76, "Last day should have score 76")
    }

    func testReadinessTrendReturnsEmptyWhenNoData() async {
        let metricsCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
        let points = await service.readinessTrend(days: 7, metricsCache: metricsCache)

        XCTAssertTrue(points.isEmpty, "Should return empty when no historical scores exist")
    }

    func testReadinessTrendCachesNonEmptyResult() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let key = "readiness_score_\(formatter.string(from: Date()))"
        testDefaults.set(85, forKey: key)

        let metricsCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
        _ = await service.readinessTrend(days: 7, metricsCache: metricsCache)

        XCTAssertEqual(service.testCacheCount, 1, "Non-empty result should be cached")
        XCTAssertNotNil(service.testGetCachedData(key: "readiness_7"), "Cache key should be readiness_7")
    }

    func testEmptyResultIsNotCached() async {
        let metricsCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
        _ = await service.readinessTrend(days: 7, metricsCache: metricsCache)

        XCTAssertEqual(service.testCacheCount, 0, "Empty result should not be cached")
    }

    // MARK: - Cache Expiration Tests

    func testExpiredCacheIsCleanedOnAccess() async {
        let oldTimestamp = Date().addingTimeInterval(-7200) // 2 hours ago
        service.testSetCache(key: "old_key", data: [TrendDataPoint(date: Date(), value: 1)], timestamp: oldTimestamp)
        XCTAssertEqual(service.testCacheCount, 1)

        let metricsCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
        _ = await service.readinessTrend(days: 7, metricsCache: metricsCache)

        XCTAssertNil(service.testGetCachedData(key: "old_key"), "Expired entry should be cleaned")
    }

    func testFreshCacheIsNotCleaned() async {
        let freshTimestamp = Date().addingTimeInterval(-1800) // 30 min ago
        service.testSetCache(key: "fresh_key", data: [TrendDataPoint(date: Date(), value: 99)], timestamp: freshTimestamp)

        let metricsCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
        _ = await service.readinessTrend(days: 7, metricsCache: metricsCache)

        XCTAssertNotNil(service.testGetCachedData(key: "fresh_key"), "Fresh entry should not be cleaned")
        XCTAssertEqual(service.testGetCachedData(key: "fresh_key")?.first?.value, 99)
    }

    func testMixedCacheOnlyExpiresOld() async {
        let oldTimestamp = Date().addingTimeInterval(-7200)
        let freshTimestamp = Date().addingTimeInterval(-600)

        service.testSetCache(key: "old", data: [TrendDataPoint(date: Date(), value: 1)], timestamp: oldTimestamp)
        service.testSetCache(key: "fresh", data: [TrendDataPoint(date: Date(), value: 2)], timestamp: freshTimestamp)
        XCTAssertEqual(service.testCacheCount, 2)

        let metricsCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
        _ = await service.readinessTrend(days: 7, metricsCache: metricsCache)

        XCTAssertNil(service.testGetCachedData(key: "old"), "Expired entry should be removed")
        XCTAssertNotNil(service.testGetCachedData(key: "fresh"), "Fresh entry should be kept")
    }
}

// MARK: - DailyMetricsCache Historical Score Tests

@MainActor
final class DailyMetricsCacheHistoricalTests: XCTestCase {

    private static let testSuiteName = "com.insightrun.cachescoretest"
    private var testDefaults: UserDefaults!
    private var testCache: DailyMetricsCache!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: Self.testSuiteName)!
        testCache = DailyMetricsCache.createForTesting(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        testDefaults = nil
        testCache = nil
        super.tearDown()
    }

    func testZeroScoreIsReturnedWhenExplicitlyStored() {
        testCache.cacheReadiness(score: 0, status: "rest", recommendation: "Take a break", workoutType: "none")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let key = "readiness_score_\(formatter.string(from: Date()))"

        XCTAssertNotNil(testDefaults.object(forKey: key), "Key should exist in UserDefaults")
        let score = testCache.getHistoricalReadinessScore(for: Date())
        XCTAssertEqual(score, 0, "Score of 0 should be returned when explicitly stored")
    }

    func testMissingKeyReturnsNil() {
        let farFuture = Calendar.current.date(byAdding: .year, value: 10, to: Date())!
        let score = testCache.getHistoricalReadinessScore(for: farFuture)
        XCTAssertNil(score, "Missing key should return nil")
    }

    func testMultipleDaysStoreIndependently() {
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        testDefaults.set(80, forKey: "readiness_score_\(formatter.string(from: today))")
        testDefaults.set(65, forKey: "readiness_score_\(formatter.string(from: yesterday))")

        XCTAssertEqual(testCache.getHistoricalReadinessScore(for: today), 80)
        XCTAssertEqual(testCache.getHistoricalReadinessScore(for: yesterday), 65)
    }
}
