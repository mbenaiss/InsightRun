//
//  ScoreAnalysisViewModelTests.swift
//  InsightRunTests
//

import XCTest
@testable import insightrun

@MainActor
final class ScoreAnalysisViewModelTests: XCTestCase {

    private var sut: ScoreAnalysisViewModel!

    override func setUp() {
        super.setUp()
        sut = ScoreAnalysisViewModel()
        clearTestCache()
    }

    override func tearDown() {
        clearTestCache()
        sut = nil
        super.tearDown()
    }

    private func clearTestCache() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("ai_analysis_") {
            defaults.removeObject(forKey: key)
        }
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
        UserDefaults.standard.set("old", forKey: oldKey)

        sut.testSaveAnalysis("new", for: identifier)

        let oldValue = UserDefaults.standard.string(forKey: oldKey)
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
}
