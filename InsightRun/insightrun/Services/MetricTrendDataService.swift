//
//  MetricTrendDataService.swift
//  InsightRun
//

import Foundation
import HealthKit

@MainActor
final class MetricTrendDataService {
    static let shared = MetricTrendDataService()

    private var cache: [String: (data: [TrendDataPoint], timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 3600

    private init() {}

    func metricTrend(for metricType: MetricType, days: Int = 7) async -> [TrendDataPoint] {
        let cacheKey = "metric_\(metricType)_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let hkManager = HealthKitManager.shared
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit

        switch metricType {
        case .hrv:
            identifier = .heartRateVariabilitySDNN
            unit = HKUnit.secondUnit(with: .milli)
        case .restingHeartRate:
            identifier = .restingHeartRate
            unit = HKUnit.count().unitDivided(by: .minute())
        case .respiratoryRate:
            identifier = .respiratoryRate
            unit = HKUnit.count().unitDivided(by: .minute())
        case .oxygenSaturation:
            identifier = .oxygenSaturation
            unit = .percent()
        default:
            return []
        }

        let data = await hkManager.fetchDailyTrendData(for: identifier, days: days, unit: unit)
        if !data.isEmpty {
            cache[cacheKey] = (data, Date())
        }
        return data
    }

    func effortTrend(days: Int = 7) async -> [TrendDataPoint] {
        let cacheKey = "effort_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let hkManager = HealthKitManager.shared

        let dates: [Date] = (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: -(days - 1) + offset, to: today)
        }

        let activities = await withTaskGroup(of: (Date, DailyActivityData).self) { group in
            for date in dates {
                group.addTask { (date, await hkManager.fetchDailyActivityData(for: date)) }
            }
            var results: [(Date, DailyActivityData)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }

        let tls = TrainingLoadService.shared
        let points: [TrendDataPoint] = activities.map { date, activity in
            TrendDataPoint(date: date, value: Double(Self.computeEffortScore(activity: activity)))
        }

        // Keep TrainingLoadService in sync with today's effort
        if let todayActivity = activities.last {
            await tls.analyzeDailyEffort(for: todayActivity.0)
        }

        cache[cacheKey] = (points, Date())
        return points
    }

    func sleepTrend(days: Int = 7) async -> [TrendDataPoint] {
        let cacheKey = "sleep_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        let sleepHistory = await HealthKitManager.shared.fetchSleepHistory(start: start, end: Date())

        let points = sleepHistory.map { sleep in
            TrendDataPoint(date: sleep.date, value: Double(sleep.qualityScore))
        }

        if !points.isEmpty {
            cache[cacheKey] = (points, Date())
        }
        return points
    }

    func readinessTrend(days: Int = 7) async -> [TrendDataPoint] {
        let cacheKey = "readiness_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let metricsCache = DailyMetricsCache.shared

        var points: [TrendDataPoint] = []
        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if let score = metricsCache.getHistoricalReadinessScore(for: date) {
                points.append(TrendDataPoint(date: date, value: Double(score)))
            }
        }

        if !points.isEmpty {
            cache[cacheKey] = (points, Date())
        }
        return points
    }

    func invalidateCache() {
        cache.removeAll()
    }

    private static func computeEffortScore(activity: DailyActivityData) -> Int {
        let caloriesTarget = activity.activeCaloriesGoal ?? 400
        let exerciseTarget = activity.exerciseMinutesGoal ?? 30
        let stepsScore = min(activity.steps / 10_000, 1.0)
        let caloriesScore = min(activity.activeCalories / caloriesTarget, 1.0)
        let exerciseScore = min(activity.exerciseMinutes / exerciseTarget, 1.0)
        let composite = stepsScore * 0.30 + caloriesScore * 0.35 + exerciseScore * 0.35
        return min(100, Int((composite * 100).rounded()))
    }

    #if DEBUG
    static func testComputeEffortScore(activity: DailyActivityData) -> Int {
        computeEffortScore(activity: activity)
    }

    static func createForTesting() -> MetricTrendDataService {
        MetricTrendDataService()
    }

    var testCacheCount: Int { cache.count }

    func testSetCache(key: String, data: [TrendDataPoint], timestamp: Date) {
        cache[key] = (data, timestamp)
    }

    func testGetCachedData(key: String) -> [TrendDataPoint]? {
        cache[key]?.data
    }

    func readinessTrend(days: Int = 7, metricsCache: DailyMetricsCache) async -> [TrendDataPoint] {
        let cacheKey = "readiness_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var points: [TrendDataPoint] = []
        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if let score = metricsCache.getHistoricalReadinessScore(for: date) {
                points.append(TrendDataPoint(date: date, value: Double(score)))
            }
        }

        if !points.isEmpty {
            cache[cacheKey] = (points, Date())
        }
        return points
    }
    #endif
}
