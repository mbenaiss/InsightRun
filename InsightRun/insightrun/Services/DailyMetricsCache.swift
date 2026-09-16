//
//  DailyMetricsCache.swift
//  InsightRun
//
//  UserDefaults cache for daily readiness metrics.
//  Preserve the daily score while its recovery inputs stay unchanged.
//

import Foundation

final class DailyMetricsCache {
    // Swift 6.3 can miscompile inferred isolated destruction of the UserDefaults reference.
    nonisolated deinit {}

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
        let inputSignature: String?
        let recoverySignature: String?
        let coachingSource: String?
    }

    // MARK: - Readiness

    /// Returns today's cached readiness only if the inputs (effort + cardiac load) still match.
    /// Used to skip the backend call entirely when nothing relevant has changed.
    func getCachedReadiness(effortScore: Int, cardiacLoadScore: Int?, inputSignature: String? = nil, now: Date = Date()) -> CachedReadiness? {
        guard let data = defaults.data(forKey: readinessKey),
              let cached = try? JSONDecoder().decode(CachedReadiness.self, from: data),
              Calendar.current.isDateInToday(cached.cacheDate),
              now.timeIntervalSince(cached.cacheDate) >= 0,
              now.timeIntervalSince(cached.cacheDate) < (cached.coachingSource == "fallback" ? 300 : 3600) else {
            return nil
        }
        if let inputSignature {
            guard cached.inputSignature == inputSignature else { return nil }
        } else {
            guard cached.effortScore == effortScore, cached.cardiacLoadScore == cardiacLoadScore else { return nil }
        }
        return cached
    }

    /// Returns the morning score for today regardless of effort/cardiac changes.
    /// Activity can refresh coaching without changing the score; new recovery data can recompute it.
    func getCachedScoreForToday(recoverySignature: String? = nil) -> (score: Int, status: String)? {
        guard let data = defaults.data(forKey: readinessKey),
              let cached = try? JSONDecoder().decode(CachedReadiness.self, from: data),
              Calendar.current.isDateInToday(cached.cacheDate),
              recoverySignature == nil || cached.recoverySignature == recoverySignature else {
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
        cardiacLoadScore: Int? = nil,
        inputSignature: String? = nil,
        recoverySignature: String? = nil,
        coachingSource: String? = nil,
        date: Date = Date()
    ) {
        let now = Calendar.current.isDateInToday(date) ? Date() : date
        let cached = CachedReadiness(
            cacheDate: now,
            score: score,
            status: status,
            recommendation: recommendation,
            summary: summary,
            suggestedWorkoutType: workoutType,
            effortScore: effortScore,
            cardiacLoadScore: cardiacLoadScore,
            inputSignature: inputSignature,
            recoverySignature: recoverySignature,
            coachingSource: coachingSource
        )
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: readinessKey)
            defaults.set(data, forKey: historyKey(for: now))
        }
        saveHistoricalReadinessScore(score, for: now)
    }

    private func historyKey(for date: Date) -> String {
        "\(readinessKey)_\(Self.dateFormatter.string(from: date))"
    }

    func getReadiness(for date: Date) -> CachedReadiness? {
        let key = Calendar.current.isDateInToday(date) ? readinessKey : historyKey(for: date)
        guard let data = defaults.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedReadiness.self, from: data),
              Calendar.current.isDate(cached.cacheDate, inSameDayAs: date) else { return nil }
        return cached
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
