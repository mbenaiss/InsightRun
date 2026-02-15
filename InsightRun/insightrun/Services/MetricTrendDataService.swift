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
        cache[cacheKey] = (data, Date())
        return data
    }

    func effortTrend(days: Int = 7) async -> [TrendDataPoint] {
        let cacheKey = "effort_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var points: [TrendDataPoint] = []

        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            await TrainingLoadService.shared.analyzeDailyEffort(for: date)
            let score = TrainingLoadService.shared.dailyEffortScore
            points.append(TrendDataPoint(date: date, value: Double(score)))
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

        cache[cacheKey] = (points, Date())
        return points
    }

    func readinessTrend(days: Int = 7) async -> [TrendDataPoint] {
        let cacheKey = "readiness_\(days)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var points: [TrendDataPoint] = []
        for dayOffset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let key = "readiness_score_\(formatter.string(from: date))"
            let score = UserDefaults.standard.integer(forKey: key)
            if score > 0 {
                points.append(TrendDataPoint(date: date, value: Double(score)))
            }
        }

        cache[cacheKey] = (points, Date())
        return points
    }

    func invalidateCache() {
        cache.removeAll()
    }
}
