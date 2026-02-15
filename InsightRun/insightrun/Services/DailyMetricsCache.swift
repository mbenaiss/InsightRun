//
//  DailyMetricsCache.swift
//  InsightRun
//
//  UserDefaults cache for daily sleep and readiness metrics.
//  Sleep and readiness are computed once per day then frozen.
//

import Foundation

final class DailyMetricsCache {
    static let shared = DailyMetricsCache()

    private(set) var defaults: UserDefaults
    private let sleepKey = "com.insightrun.dailySleepCache"
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
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return "\(readinessKeyPrefix)_\(lang)"
    }

    // MARK: - Cached Models

    struct CachedSleepData: Codable {
        let cacheDate: Date
        let qualityScore: Int
        let totalSleepDuration: TimeInterval
        let timeInBed: TimeInterval
        let sleepStart: Date
        let sleepEnd: Date
        let deepSleepDuration: TimeInterval?
        let coreSleepDuration: TimeInterval?
        let remSleepDuration: TimeInterval?
        let awakeDuration: TimeInterval?
        let napDuration: TimeInterval?
    }

    struct CachedReadiness: Codable {
        let cacheDate: Date
        let score: Int
        let status: String
        let recommendation: String
        let suggestedWorkoutType: String
    }

    // MARK: - Sleep

    func getCachedSleepData() -> CachedSleepData? {
        guard let data = defaults.data(forKey: sleepKey),
              let cached = try? JSONDecoder().decode(CachedSleepData.self, from: data),
              Calendar.current.isDateInToday(cached.cacheDate) else {
            return nil
        }
        return cached
    }

    func cacheSleepData(_ sleep: SleepData) {
        let cached = CachedSleepData(
            cacheDate: Date(),
            qualityScore: sleep.qualityScore,
            totalSleepDuration: sleep.totalSleepDuration,
            timeInBed: sleep.timeInBed,
            sleepStart: sleep.sleepStart,
            sleepEnd: sleep.sleepEnd,
            deepSleepDuration: sleep.deepSleepDuration,
            coreSleepDuration: sleep.coreSleepDuration,
            remSleepDuration: sleep.remSleepDuration,
            awakeDuration: sleep.awakeDuration,
            napDuration: sleep.napDuration
        )
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: sleepKey)
        }
    }

    // MARK: - Readiness

    func getCachedReadiness() -> CachedReadiness? {
        guard let data = defaults.data(forKey: readinessKey),
              let cached = try? JSONDecoder().decode(CachedReadiness.self, from: data),
              Calendar.current.isDateInToday(cached.cacheDate) else {
            return nil
        }
        return cached
    }

    func cacheReadiness(score: Int, status: String, recommendation: String, workoutType: String) {
        let now = Date()
        let cached = CachedReadiness(
            cacheDate: now,
            score: score,
            status: status,
            recommendation: recommendation,
            suggestedWorkoutType: workoutType
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
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    // MARK: - Conversion

    func toSleepData(_ cached: CachedSleepData) -> SleepData {
        SleepData(
            date: cached.cacheDate,
            sleepStart: cached.sleepStart,
            sleepEnd: cached.sleepEnd,
            totalSleepDuration: cached.totalSleepDuration,
            timeInBed: cached.timeInBed,
            deepSleepDuration: cached.deepSleepDuration,
            coreSleepDuration: cached.coreSleepDuration,
            remSleepDuration: cached.remSleepDuration,
            awakeDuration: cached.awakeDuration,
            napDuration: cached.napDuration
        )
    }
}
