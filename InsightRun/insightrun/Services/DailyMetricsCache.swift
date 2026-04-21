//
//  DailyMetricsCache.swift
//  InsightRun
//
//  UserDefaults cache for daily readiness metrics.
//  Readiness is computed once per day then frozen (keyed on effort + cardiac load).
//

import Foundation

final class DailyMetricsCache {
    static let shared = DailyMetricsCache()

    private(set) var defaults: UserDefaults
    private let readinessKeyPrefix = "com.insightrun.dailyReadinessCache"

    private init() {
        self.defaults = .standard
    }

    #if DEBUG
    static func createForTesting(defaults: UserDefaults) -> DailyMetricsCache {
        let cache = DailyMetricsCache()
        cache.defaults = defaults
        return cache
    }
    #endif

    private var readinessKey: String {
        return "\(readinessKeyPrefix)_\(AppLanguage.current)"
    }

    // MARK: - Cached Models

    struct CachedReadiness: Codable {
        let cacheDate: Date
        let score: Int
        let status: String
        let recommendation: String
        let suggestedWorkoutType: String
        let effortScore: Int?
        let cardiacLoadScore: Int?
    }

    // MARK: - Readiness

    /// Returns today's cached readiness only if the inputs (effort + cardiac load) still match.
    /// A score mismatch invalidates the cache so a new workout or effort change triggers a re-fetch.
    func getCachedReadiness(effortScore: Int, cardiacLoadScore: Int?) -> CachedReadiness? {
        guard let data = defaults.data(forKey: readinessKey),
              let cached = try? JSONDecoder().decode(CachedReadiness.self, from: data),
              Calendar.current.isDateInToday(cached.cacheDate),
              cached.effortScore == effortScore,
              cached.cardiacLoadScore == cardiacLoadScore else {
            return nil
        }
        return cached
    }

    func cacheReadiness(
        score: Int,
        status: String,
        recommendation: String,
        workoutType: String,
        effortScore: Int = 0,
        cardiacLoadScore: Int? = nil
    ) {
        let now = Date()
        let cached = CachedReadiness(
            cacheDate: now,
            score: score,
            status: status,
            recommendation: recommendation,
            suggestedWorkoutType: workoutType,
            effortScore: effortScore,
            cardiacLoadScore: cardiacLoadScore
        )
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: readinessKey)
        }
        saveHistoricalReadinessScore(score, for: now)
    }

    // MARK: - Historical Readiness

    private static let historicalReadinessPrefix = "readiness_score_"
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func saveHistoricalReadinessScore(_ score: Int, for date: Date) {
        let key = Self.historicalReadinessPrefix + Self.dateFormatter.string(from: date)
        defaults.set(score, forKey: key)
    }

    func getHistoricalReadinessScore(for date: Date) -> Int? {
        let key = Self.historicalReadinessPrefix + Self.dateFormatter.string(from: date)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }
}
