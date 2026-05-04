//
//  WidgetDataProvider.swift
//  InsightRun
//
//  Service that writes app data to the shared App Group container
//  for widget consumption. Call update methods after data changes.
//

import Foundation
import WidgetKit

@MainActor
class WidgetDataProvider {
    static let shared = WidgetDataProvider()

    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private var reloadTask: Task<Void, Never>?

    private init() {
        defaults = UserDefaults(suiteName: WidgetDataKeys.suiteName)
    }

    // MARK: - Readiness

    func updateReadiness(from recovery: RecoveryMetrics) {
        let statusKey: String
        switch recovery.recoveryStatus {
        case .excellent: statusKey = "excellent"
        case .good: statusKey = "good"
        case .fair: statusKey = "fair"
        case .poor: statusKey = "poor"
        }

        let data = WidgetReadinessData(
            score: recovery.recoveryScore,
            status: statusKey,
            date: recovery.date,
            hrvValue: recovery.hrvAverage,
            rhrValue: recovery.restingHeartRate
        )
        save(data, forKey: WidgetDataKeys.readiness)
        reloadWidgets()
    }

    // MARK: - Weekly Stats

    func updateWeeklyStats(workouts: [WorkoutModel]) {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) else { return }

        let thisWeekWorkouts = workouts.filter { $0.startDate >= weekStart }
        let totalDistance = thisWeekWorkouts.compactMap { $0.distance }.reduce(0, +)
        let totalDuration = thisWeekWorkouts.map { $0.duration }.reduce(0, +)
        let totalCalories = thisWeekWorkouts.compactMap { $0.totalEnergyBurned }.reduce(0, +)

        let paces = thisWeekWorkouts.compactMap { $0.averagePace }
        let avgPace = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)

        // Bucket distances by weekday (ordered by Calendar.firstWeekday)
        var dailyKm = Array(repeating: 0.0, count: 7)
        for workout in thisWeekWorkouts {
            guard let dist = workout.distance else { continue }
            let weekday = calendar.component(.weekday, from: workout.startDate)
            let idx = (weekday - calendar.firstWeekday + 7) % 7
            dailyKm[idx] += dist / 1000.0
        }

        let data = WidgetWeeklyStatsData(
            totalDistance: totalDistance,
            totalRuns: thisWeekWorkouts.count,
            averagePace: avgPace,
            totalDuration: totalDuration,
            totalCalories: totalCalories,
            weekStartDate: weekStart,
            dailyDistancesKm: dailyKm
        )
        save(data, forKey: WidgetDataKeys.weeklyStats)
        reloadWidgets()
    }

    // MARK: - Last Workout

    func updateLastWorkout(from workout: WorkoutModel) {
        let data = WidgetLastWorkoutData(
            date: workout.startDate,
            distance: workout.distance ?? 0,
            duration: workout.duration,
            averagePace: workout.averagePace,
            averageHeartRate: workout.averageHeartRate,
            calories: workout.totalEnergyBurned,
            elevationGain: workout.elevationGain
        )
        save(data, forKey: WidgetDataKeys.lastWorkout)
        reloadWidgets()
    }

    // MARK: - Health Vitals

    func updateHealthVitals(
        hrv: Double?,
        rhr: Double?,
        spo2: Double?,
        respRate: Double?,
        walkingHR: Double?,
        hrvSeries: [Double]? = nil,
        rhrSeries: [Double]? = nil,
        hrvDelta: Double? = nil,
        rhrDelta: Double? = nil
    ) {
        let data = WidgetHealthVitalsData(
            date: Date(),
            hrv: hrv,
            restingHeartRate: rhr,
            oxygenSaturation: spo2,
            respiratoryRate: respRate,
            walkingHeartRate: walkingHR,
            hrvSeries: hrvSeries,
            rhrSeries: rhrSeries,
            hrvDelta: hrvDelta,
            rhrDelta: rhrDelta
        )
        save(data, forKey: WidgetDataKeys.healthVitals)
        reloadWidgets()
    }

    // MARK: - Sleep

    func updateSleep(from sleep: SleepData) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let data = WidgetSleepQualityData(
            date: sleep.date,
            totalSleepHours: sleep.totalSleepDuration / 3600.0,
            sleepEfficiency: sleep.sleepEfficiency,
            qualityScore: sleep.qualityScore,
            deepSleepHours: sleep.deepSleepDuration.map { $0 / 3600.0 },
            remSleepHours: sleep.remSleepDuration.map { $0 / 3600.0 },
            sleepStartTime: formatter.string(from: sleep.sleepStart),
            sleepEndTime: formatter.string(from: sleep.sleepEnd)
        )
        save(data, forKey: WidgetDataKeys.sleepQuality)
        reloadWidgets()
    }

    // MARK: - Training Load

    func updateTrainingLoad(
        volumeChange: Double?,
        daysSinceLastWorkout: Int?,
        status: TrainingStatus,
        thisWeekDistance: Double,
        lastWeekDistance: Double
    ) {
        let statusKey: String
        switch status {
        case .normal: statusKey = "normal"
        case .overtraining: statusKey = "overtraining"
        case .inactive: statusKey = "inactive"
        }

        let data = WidgetTrainingLoadData(
            date: Date(),
            weeklyVolumeChange: volumeChange,
            daysSinceLastWorkout: daysSinceLastWorkout,
            status: statusKey,
            thisWeekDistance: thisWeekDistance,
            lastWeekDistance: lastWeekDistance
        )
        save(data, forKey: WidgetDataKeys.trainingLoad)
        reloadWidgets()
    }

    // MARK: - Refresh All

    /// Call this on app launch or after a background refresh to update all widget data
    func refreshAllWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Private

    private func save<T: Encodable>(_ data: T, forKey key: String) {
        do {
            let encoded = try encoder.encode(data)
            defaults?.set(encoded, forKey: key)
        } catch {
            print("❌ WidgetDataProvider: Failed to encode \(key): \(error)")
        }
    }

    private func reloadWidgets() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
