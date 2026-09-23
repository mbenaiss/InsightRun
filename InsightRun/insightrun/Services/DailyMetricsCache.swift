//
//  DailyMetricsCache.swift
//  InsightRun
//
//  UserDefaults cache for daily readiness metrics.
//  One frozen score per calendar day; the coaching text is cached per language.
//

import Foundation

final class DailyMetricsCache {
    // Swift 6.3 can miscompile inferred isolated destruction of the UserDefaults reference.
    nonisolated deinit {}

    static let shared = DailyMetricsCache()

    private(set) var defaults: UserDefaults
    private var language = AppLanguage.current
    private let readinessKeyPrefix = "com.insightrun.dailyReadinessCache"
    private let frozenScoreKey = "com.insightrun.dailyReadinessScore"

    private init() {
        self.defaults = .standard
    }

    #if DEBUG
    static func createForTesting(defaults: UserDefaults, language: String = AppLanguage.current) -> DailyMetricsCache {
        let cache = DailyMetricsCache()
        cache.defaults = defaults
        cache.language = language
        return cache
    }
    #endif

    private var readinessKey: String {
        return "\(readinessKeyPrefix)_\(language)"
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
        let coachingSource: String?
    }

    private struct FrozenScore: Codable {
        let date: Date
        let score: Int
        let status: String
        let nightSignature: String?
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

    /// Today's score, shared by every language and replaced only after late night data.
    func getCachedScoreForToday(nightSignature: String? = nil) -> (score: Int, status: String)? {
        if let data = defaults.data(forKey: frozenScoreKey),
           let frozen = try? JSONDecoder().decode(FrozenScore.self, from: data),
           Calendar.current.isDateInToday(frozen.date) {
            guard nightSignature == nil || frozen.nightSignature == nightSignature else { return nil }
            return (frozen.score, frozen.status)
        }
        // Keeps a score cached before this key existed frozen for the rest of that day.
        return getReadiness(for: Date()).map { ($0.score, $0.status) }
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
        nightSignature: String? = nil,
        coachingSource: String? = nil,
        date: Date = Date()
    ) {
        let isToday = Calendar.current.isDateInToday(date)
        let now = isToday ? Date() : date
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
            coachingSource: coachingSource
        )
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: readinessKey)
            defaults.set(data, forKey: historyKey(for: now))
        }
        if isToday, let data = try? JSONEncoder().encode(
            FrozenScore(date: now, score: score, status: status, nightSignature: nightSignature)
        ) {
            defaults.set(data, forKey: frozenScoreKey)
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
