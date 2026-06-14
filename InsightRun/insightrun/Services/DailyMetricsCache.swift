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
        /// Short coaching TL;DR. Optional for backward compatibility with cache entries
        /// written by older app versions that didn't yet split summary/detail.
        let summary: String?
        let suggestedWorkoutType: String
        let effortScore: Int?
        let cardiacLoadScore: Int?
    }

    // MARK: - Readiness

    /// Returns today's cached readiness only if the inputs (effort + cardiac load) still match.
    /// Used to skip the backend call entirely when nothing relevant has changed.
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

    /// Returns the morning score for today regardless of effort/cardiac changes.
    /// The readiness score is computed once per calendar day and frozen — only the
    /// AI coaching text is allowed to refresh as inputs evolve during the day.
    func getCachedScoreForToday() -> (score: Int, status: String)? {
        guard let data = defaults.data(forKey: readinessKey),
              let cached = try? JSONDecoder().decode(CachedReadiness.self, from: data),
              Calendar.current.isDateInToday(cached.cacheDate) else {
            return nil
        }
        return (cached.score, cached.status)
    }

    func cacheReadiness(
        score: Int,
        status: String,
        recommendation: String,
        summary: String? = nil,
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
            summary: summary,
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
        // Fixed-format key: pin to POSIX locale so the key never shifts with the
        // user's locale/calendar (e.g. Persian/Buddhist), keeping cache lookups stable.
        f.locale = Locale(identifier: "en_US_POSIX")
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
