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

    private var activityCache: [Date: (data: DailyActivityData, timestamp: Date)] = [:]
    private var activityHistoryCache: [String: (data: [(Date, DailyActivityData)], timestamp: Date)] = [:]
    private var activityHistoryTasks: [String: Task<[(Date, DailyActivityData)], Never>] = [:]
    private var recoveryCache: [Date: (metrics: RecoveryMetrics, timestamp: Date)] = [:]
    private let recoveryRequests = ConcurrentRequestCoalescer<Date, RecoveryMetrics>()
    private var seededActivity: (date: Date, data: DailyActivityData)?
    private var cacheGeneration = UUID()
    private let recoveryLoader: (Date) async throws -> RecoveryMetrics
    private let activityLoader: (Date) async -> DailyActivityData

    init(recoveryLoader: @escaping (Date) async throws -> RecoveryMetrics = {
        try await HealthKitManager.shared.fetchRecoveryMetrics(for: $0)
    }, activityLoader: @escaping (Date) async -> DailyActivityData = {
        await HealthKitManager.shared.fetchDailyActivityData(for: $0)
    }) {
        self.recoveryLoader = recoveryLoader
        self.activityLoader = activityLoader
    }

    private func activityHistory(days: Int, endingOn date: Date) async -> [(Date, DailyActivityData)] {
        let calendar = Calendar.current
        let now = Date()
        let key = cacheKey("activity", days: days, date: date)
        let generation = cacheGeneration
        if let cached = activityHistoryCache[key],
           now.timeIntervalSince(cached.timestamp) < cacheDuration,
           calendar.isDate(cached.timestamp, inSameDayAs: now) {
            return cached.data
        }
        if let task = activityHistoryTasks[key] { return await task.value }

        let today = calendar.startOfDay(for: date)
        let task = Task<[(Date, DailyActivityData)], Never> { @MainActor in
            var result: [(Date, DailyActivityData)] = []
            // Share a sequential read across charts to avoid saturating HealthKit.
            for offset in 0..<max(0, days) {
                guard let date = calendar.date(byAdding: .day, value: -(days - 1) + offset, to: today) else { continue }
                guard !Task.isCancelled else { return [] }
                if let seeded = self.seededActivity, calendar.isDate(seeded.date, inSameDayAs: date) {
                    result.append((date, seeded.data))
                } else if let cached = self.activityCache[date], Date().timeIntervalSince(cached.timestamp) < self.cacheDuration {
                    result.append((date, cached.data))
                } else {
                    let activity = await self.activityLoader(date)
                    guard !Task.isCancelled, generation == self.cacheGeneration else { return [] }
                    if activity.steps > 0 || activity.totalCalories > 0 || activity.exerciseMinutes > 0 {
                        self.activityCache[date] = (activity, Date())
                    }
                    result.append((date, activity))
                }
            }
            return result
        }
        activityHistoryTasks[key] = task
        let data = await task.value
        guard generation == cacheGeneration, !Task.isCancelled else { return [] }
        activityHistoryTasks[key] = nil
        if data.contains(where: { $0.1.steps > 0 || $0.1.totalCalories > 0 || $0.1.exerciseMinutes > 0 }) {
            activityHistoryCache[key] = (data, now)
        }
        return data
    }

    private func cleanExpiredCache() {
        activityCache = activityCache.filter { Date().timeIntervalSince($0.value.timestamp) < cacheDuration }
        recoveryCache = recoveryCache.filter { Date().timeIntervalSince($0.value.timestamp) < cacheDuration }
        cache = cache.filter { _, entry in
            Date().timeIntervalSince(entry.timestamp) < cacheDuration
                && Calendar.current.isDateInToday(entry.timestamp)
        }
        caloriesBreakdownCache = caloriesBreakdownCache.filter { _, entry in
            Date().timeIntervalSince(entry.timestamp) < cacheDuration
                && Calendar.current.isDateInToday(entry.timestamp)
        }
        activityHistoryCache = activityHistoryCache.filter { _, entry in
            Date().timeIntervalSince(entry.timestamp) < cacheDuration
                && Calendar.current.isDateInToday(entry.timestamp)
        }
    }

    func metricTrend(for metricType: MetricType, days: Int = 7, endingOn date: Date = Date()) async -> [TrendDataPoint] {
        guard days > 0 else { return [] }
        let generation = cacheGeneration
        cleanExpiredCache()
        let cacheKey = cacheKey("metric_\(metricType)", days: days, date: date)
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let metrics = await recoveryHistory(days: days, endingOn: date)
        let data = metrics.compactMap { metrics -> TrendDataPoint? in
            let value: Double?
            switch metricType {
            case .hrv: value = metrics.hrvAverage
            case .restingHeartRate: value = metrics.restingHeartRate
            case .respiratoryRate: value = metrics.respiratoryRate
            case .oxygenSaturation: value = metrics.oxygenSaturation
            default: value = nil
            }
            return value.map { TrendDataPoint(date: metrics.date, value: $0) }
        }
        guard generation == cacheGeneration, !Task.isCancelled else { return [] }
        if !data.isEmpty {
            cache[cacheKey] = (data, Date())
        }
        return data
    }

    func effortTrend(days: Int = 7, endingOn date: Date = Date()) async -> [TrendDataPoint] {
        guard days > 0 else { return [] }
        let generation = cacheGeneration
        cleanExpiredCache()
        let cacheKey = cacheKey("effort", days: days, date: date)
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let activities = await activityHistory(days: days, endingOn: date)

        let points: [TrendDataPoint] = activities.map { date, activity in
            TrendDataPoint(date: date, value: Double(Self.computeEffortScore(activity: activity)))
        }

        guard generation == cacheGeneration, !Task.isCancelled else { return [] }
        if activities.contains(where: { $0.1.steps > 0 || $0.1.totalCalories > 0 || $0.1.exerciseMinutes > 0 }) {
            cache[cacheKey] = (points, Date())
        }
        return points
    }

    func caloriesTotalTrend(days: Int = 7, endingOn date: Date = Date()) async -> [TrendDataPoint] {
        guard days > 0 else { return [] }
        let generation = cacheGeneration
        cleanExpiredCache()
        let cacheKey = cacheKey("calories_total", days: days, date: date)
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let activities = await activityHistory(days: days, endingOn: date)
        let points = activities.compactMap { date, activity in
            activity.totalCalories > 0 ? TrendDataPoint(date: date, value: activity.totalCalories) : nil
        }

        guard generation == cacheGeneration, !Task.isCancelled else { return [] }
        if !points.isEmpty {
            cache[cacheKey] = (points, Date())
        }
        return points
    }

    /// Daily active vs. resting calories for the last `days` days.
    func caloriesBreakdownTrend(days: Int = 7, endingOn date: Date = Date()) async -> [CaloriesBreakdownPoint] {
        guard days > 0 else { return [] }
        let generation = cacheGeneration
        cleanExpiredCache()
        let cacheKey = cacheKey("calories_breakdown", days: days, date: date)
        if let cached = caloriesBreakdownCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let activities = await activityHistory(days: days, endingOn: date)
        let points = activities.compactMap { date, activity -> CaloriesBreakdownPoint? in
            guard activity.totalCalories > 0 else { return nil }
            return CaloriesBreakdownPoint(date: date, active: activity.activeCalories, resting: activity.basalCalories)
        }

        guard generation == cacheGeneration, !Task.isCancelled else { return [] }
        if !points.isEmpty {
            caloriesBreakdownCache[cacheKey] = (points, Date())
        }
        return points
    }

    func sleepTrend(days: Int = 7, endingOn date: Date = Date()) async -> [TrendDataPoint] {
        guard days > 0 else { return [] }
        let generation = cacheGeneration
        cleanExpiredCache()
        let cacheKey = cacheKey("sleep", days: days, date: date)
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let metrics = await recoveryHistory(days: days, endingOn: date)
        let points = metrics.compactMap { metrics in
            metrics.sleepData.map { TrendDataPoint(date: metrics.date, value: Double($0.qualityScore)) }
        }

        guard generation == cacheGeneration, !Task.isCancelled else { return [] }
        if !points.isEmpty {
            cache[cacheKey] = (points, Date())
        }
        return points
    }

    func readinessTrend(days: Int = 7, metricsCache: DailyMetricsCache? = nil, endingOn date: Date = Date()) async -> [TrendDataPoint] {
        cleanExpiredCache()
        guard days > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let cache = metricsCache ?? DailyMetricsCache.shared

        var points: [TrendDataPoint] = []
        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if let score = cache.getHistoricalReadinessScore(for: date) {
                points.append(TrendDataPoint(date: date, value: Double(score)))
            }
        }

        return points
    }

    private func recoveryHistory(days: Int, endingOn date: Date) async -> [RecoveryMetrics] {
        let generation = cacheGeneration
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: date)
        var result: [RecoveryMetrics] = []
        for offset in 0..<days {
            guard !Task.isCancelled, generation == cacheGeneration,
                  let day = calendar.date(byAdding: .day, value: offset - days + 1, to: endDay) else { return [] }
            if let metrics = try? await recoveryMetrics(for: day) {
                guard !Task.isCancelled, generation == cacheGeneration else { return [] }
                result.append(metrics)
            }
        }
        return result
    }

    func recoveryMetrics(for date: Date) async throws -> RecoveryMetrics {
        try Task.checkCancellation()
        let day = Calendar.current.startOfDay(for: date)
        let generation = cacheGeneration
        if let entry = recoveryCache[day], Date().timeIntervalSince(entry.timestamp) < cacheDuration {
            return entry.metrics
        }
        let metrics = try await recoveryRequests.value(for: day) { try await self.recoveryLoader(day) }
        try Task.checkCancellation()
        guard generation == cacheGeneration else { throw CancellationError() }
        recoveryCache[day] = (metrics, Date())
        return metrics
    }

    func seedRecovery(_ metrics: RecoveryMetrics, for date: Date) {
        recoveryCache[Calendar.current.startOfDay(for: date)] = (metrics, Date())
    }

    private func cacheKey(_ kind: String, days: Int, date: Date) -> String {
        "\(kind)_\(days)_\(Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate)"
    }

    func seedActivity(_ activity: DailyActivityData, for date: Date) {
        seededActivity = (date, activity)
    }

    func invalidateCache(keepingHistoricalData: Bool = false) {
        if keepingHistoricalData {
            let today = Calendar.current.startOfDay(for: Date())
            recoveryCache.removeValue(forKey: today)
            activityCache.removeValue(forKey: today)
        } else {
            recoveryCache.removeAll()
            activityCache.removeAll()
        }
        seededActivity = nil
        cacheGeneration = UUID()
        activityHistoryTasks.values.forEach { $0.cancel() }
        activityHistoryTasks.removeAll()
        activityHistoryCache.removeAll()
        cache.removeAll()
        caloriesBreakdownCache.removeAll()
    }

    static func computeEffortScore(activity: DailyActivityData) -> Int {
        let caloriesTarget = activity.activeCaloriesGoal.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Constants.defaultActiveCaloriesGoal
        let exerciseTarget = activity.exerciseMinutesGoal.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Constants.defaultExerciseMinutesGoal
        func progress(_ value: Double, target: Double) -> Double {
            value.isFinite ? min(max(0, value / target), 1) : 0
        }
        let stepsScore = progress(activity.steps, target: Constants.defaultStepsGoal)
        let caloriesScore = progress(activity.activeCalories, target: caloriesTarget)
        let exerciseScore = progress(activity.exerciseMinutes, target: exerciseTarget)
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
