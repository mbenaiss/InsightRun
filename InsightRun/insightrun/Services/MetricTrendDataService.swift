//
//  MetricTrendDataService.swift
//  InsightRun
//

import Foundation
import HealthKit

@MainActor
final class MetricTrendDataService {
    static let shared = MetricTrendDataService()

    private enum Constants {
        static let cacheDurationSeconds: TimeInterval = 3600
        static let defaultActiveCaloriesGoal: Double = 400
        static let defaultExerciseMinutesGoal: Double = 30
        static let defaultStepsGoal: Double = 10_000
        static let stepsWeight: Double = 0.30
        static let caloriesWeight: Double = 0.35
        static let exerciseWeight: Double = 0.35
        static let maxScore: Int = 100
    }

    private var cache: [String: (data: [TrendDataPoint], timestamp: Date)] = [:]
    private var caloriesBreakdownCache: [String: (data: [CaloriesBreakdownPoint], timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = Constants.cacheDurationSeconds

    private var activityHistoryCache: [Int: (data: [(Date, DailyActivityData)], timestamp: Date)] = [:]
    private var activityHistoryTasks: [Int: Task<[(Date, DailyActivityData)], Never>] = [:]
    private let activityLoader: (Date) async -> DailyActivityData

    init(activityLoader: @escaping (Date) async -> DailyActivityData = {
        await HealthKitManager.shared.fetchDailyActivityData(for: $0)
    }) {
        self.activityLoader = activityLoader
    }

    private func activityHistory(days: Int) async -> [(Date, DailyActivityData)] {
        let calendar = Calendar.current
        let now = Date()
        if let cached = activityHistoryCache[days],
           now.timeIntervalSince(cached.timestamp) < cacheDuration,
           calendar.isDate(cached.timestamp, inSameDayAs: now) {
            return cached.data
        }
        if let task = activityHistoryTasks[days] { return await task.value }

        let today = calendar.startOfDay(for: now)
        let task = Task { @MainActor in
            var result: [(Date, DailyActivityData)] = []
            // Share a sequential read across charts to avoid saturating HealthKit.
            for offset in 0..<max(0, days) {
                guard let date = calendar.date(byAdding: .day, value: -(days - 1) + offset, to: today) else { continue }
                result.append((date, await self.activityLoader(date)))
            }
            return result
        }
        activityHistoryTasks[days] = task
        let data = await task.value
        activityHistoryTasks[days] = nil
        if data.contains(where: { $0.1.steps > 0 || $0.1.totalCalories > 0 || $0.1.exerciseMinutes > 0 }) {
            activityHistoryCache[days] = (data, now)
        }
        return data
    }

    private func cleanExpiredCache() {
        cache = cache.filter { _, entry in
            Date().timeIntervalSince(entry.timestamp) < cacheDuration
        }
        caloriesBreakdownCache = caloriesBreakdownCache.filter { _, entry in
            Date().timeIntervalSince(entry.timestamp) < cacheDuration
        }
        activityHistoryCache = activityHistoryCache.filter { _, entry in
            Date().timeIntervalSince(entry.timestamp) < cacheDuration
        }
    }

    func metricTrend(for metricType: MetricType, days: Int = 7) async -> [TrendDataPoint] {
        cleanExpiredCache()
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
        cleanExpiredCache()
        let cacheKey = "effort_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let activities = await activityHistory(days: days)

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

    func caloriesTotalTrend(days: Int = 7) async -> [TrendDataPoint] {
        cleanExpiredCache()
        let cacheKey = "calories_total_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let activities = await activityHistory(days: days)
        let points = activities.compactMap { date, activity in
            activity.totalCalories > 0 ? TrendDataPoint(date: date, value: activity.totalCalories) : nil
        }

        if !points.isEmpty {
            cache[cacheKey] = (points, Date())
        }
        return points
    }

    /// Daily active vs. resting calories for the last `days` days.
    func caloriesBreakdownTrend(days: Int = 7) async -> [CaloriesBreakdownPoint] {
        cleanExpiredCache()
        let cacheKey = "calories_breakdown_\(days)"
        if let cached = caloriesBreakdownCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let activities = await activityHistory(days: days)
        let points = activities.compactMap { date, activity -> CaloriesBreakdownPoint? in
            guard activity.totalCalories > 0 else { return nil }
            return CaloriesBreakdownPoint(date: date, active: activity.activeCalories, resting: activity.basalCalories)
        }

        if !points.isEmpty {
            caloriesBreakdownCache[cacheKey] = (points, Date())
        }
        return points
    }

    func sleepTrend(days: Int = 7) async -> [TrendDataPoint] {
        cleanExpiredCache()
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

    func readinessTrend(days: Int = 7, metricsCache: DailyMetricsCache? = nil) async -> [TrendDataPoint] {
        cleanExpiredCache()
        let cacheKey = "readiness_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cache = metricsCache ?? DailyMetricsCache.shared

        var points: [TrendDataPoint] = []
        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if let score = cache.getHistoricalReadinessScore(for: date) {
                points.append(TrendDataPoint(date: date, value: Double(score)))
            }
        }

        if !points.isEmpty {
            self.cache[cacheKey] = (points, Date())
        }
        return points
    }

    func invalidateCache() {
        cache.removeAll()
        caloriesBreakdownCache.removeAll()
    }

    private static func computeEffortScore(activity: DailyActivityData) -> Int {
        let caloriesTarget = activity.activeCaloriesGoal ?? Constants.defaultActiveCaloriesGoal
        let exerciseTarget = activity.exerciseMinutesGoal ?? Constants.defaultExerciseMinutesGoal
        let stepsScore = min(activity.steps / Constants.defaultStepsGoal, 1.0)
        let caloriesScore = min(activity.activeCalories / caloriesTarget, 1.0)
        let exerciseScore = min(activity.exerciseMinutes / exerciseTarget, 1.0)
        let composite = stepsScore * Constants.stepsWeight + caloriesScore * Constants.caloriesWeight + exerciseScore * Constants.exerciseWeight
        return min(Constants.maxScore, Int((composite * Double(Constants.maxScore)).rounded()))
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
    #endif
}
