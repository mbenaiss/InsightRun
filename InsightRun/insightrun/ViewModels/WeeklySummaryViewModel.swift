//
//  WeeklySummaryViewModel.swift
//  InsightRun
//
//  ViewModel for weekly summary screen aggregating running, sleep, and recovery data.
//

import Combine
import Foundation

@MainActor
class WeeklySummaryViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Running
    @Published var runCount = 0
    @Published var totalDistance: Double = 0 // meters
    @Published var totalDuration: TimeInterval = 0
    @Published var totalCalories: Double = 0
    @Published var totalElevation: Double = 0
    @Published var averageHeartRate: Double?
    @Published var averagePace: Double? // min/km

    // Sleep
    @Published var averageSleepDuration: TimeInterval = 0
    @Published var averageSleepEfficiency: Double = 0
    @Published var averageQualityScore: Int = 0
    @Published var averageDeepPercent: Double = 0
    @Published var averageCorePercent: Double = 0
    @Published var averageRemPercent: Double = 0

    // Recovery
    @Published var averageRecoveryScore: Int = 0
    @Published var averageHRV: Double?
    @Published var averageRestingHR: Double?
    @Published var averageSpO2: Double?

    // Comparison vs previous week
    @Published var distanceChange: Double? // percentage
    @Published var durationChange: Double? // percentage
    @Published var recoveryScoreChange: Int? // absolute

    // Week dates
    @Published var weekStart: Date = .now
    @Published var weekEnd: Date = .now

    private let healthKitManager = HealthKitManager.shared
    private let calendar = Calendar.current

    var formattedWeekRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let start = formatter.string(from: weekStart)
        let end = formatter.string(from: weekEnd)
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: weekEnd)
        return "\(start) - \(end) \(year)"
    }

    var formattedTotalDistance: String {
        let km = totalDistance / 1000.0
        let unit = String(localized: "km", comment: "Unit abbreviation for kilometers")
        return String(format: "%.1f \(unit)", km)
    }

    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) / 60 % 60
        let h = String(localized: "h", comment: "Unit abbreviation for hours in duration")
        let m = String(localized: "m", comment: "Unit abbreviation for minutes in duration")
        if hours > 0 {
            return String(format: "%d\(h) %02d\(m)", hours, minutes)
        }
        return String(format: "%d\(m)", minutes)
    }

    var formattedAveragePace: String {
        guard let pace = averagePace, pace.isFinite else { return "--" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        let unit = String(localized: "/km", comment: "Pace unit per kilometer")
        return String(format: "%d'%02d\"\(unit)", minutes, seconds)
    }

    var formattedAverageSleep: String {
        let hours = Int(averageSleepDuration) / 3600
        let minutes = Int(averageSleepDuration) / 60 % 60
        return String(format: "%dh%02d", hours, minutes)
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        let now = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        weekStart = startOfWeek
        weekEnd = now

        let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek)!

        do {
            // Fetch current week running workouts
            let workouts = try await healthKitManager.fetchRunningWorkouts(from: startOfWeek, to: now)
            aggregateRunning(workouts)

            // Fetch previous week for comparison
            let prevWorkouts = try await healthKitManager.fetchRunningWorkouts(from: prevWeekStart, to: startOfWeek)
            computeRunningComparison(previous: prevWorkouts)

            // Fetch sleep data for each day
            await loadSleepData(from: startOfWeek, to: now)

            // Fetch recovery metrics for each day
            await loadRecoveryData(from: startOfWeek, to: now, prevStart: prevWeekStart, prevEnd: startOfWeek)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func aggregateRunning(_ workouts: [WorkoutModel]) {
        runCount = workouts.count
        totalDistance = workouts.compactMap(\.distance).reduce(0, +)
        totalDuration = workouts.map(\.duration).reduce(0, +)
        totalCalories = workouts.compactMap(\.totalEnergyBurned).reduce(0, +)
        totalElevation = workouts.compactMap(\.elevationGain).reduce(0, +)

        let heartRates = workouts.compactMap(\.averageHeartRate)
        averageHeartRate = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count)

        if totalDistance > 0, totalDuration > 0 {
            averagePace = (totalDuration / 60.0) / (totalDistance / 1000.0)
        }
    }

    private func computeRunningComparison(previous: [WorkoutModel]) {
        let prevDistance = previous.compactMap(\.distance).reduce(0, +)
        let prevDuration = previous.map(\.duration).reduce(0, +)

        if prevDistance > 0 {
            distanceChange = ((totalDistance - prevDistance) / prevDistance) * 100
        }
        if prevDuration > 0 {
            durationChange = ((totalDuration - prevDuration) / prevDuration) * 100
        }
    }

    private func loadSleepData(from start: Date, to end: Date) async {
        let sleepHistory = await healthKitManager.fetchSleepHistory(start: start, end: end)
        guard !sleepHistory.isEmpty else { return }

        let count = Double(sleepHistory.count)
        averageSleepDuration = sleepHistory.map(\.totalSleepDuration).reduce(0, +) / count
        averageSleepEfficiency = sleepHistory.map(\.sleepEfficiency).reduce(0, +) / count
        averageQualityScore = Int(sleepHistory.map { Double($0.qualityScore) }.reduce(0, +) / count)

        let withStages = sleepHistory.filter { $0.deepSleepDuration != nil && $0.totalSleepDuration > 0 }
        if !withStages.isEmpty {
            let stageCount = Double(withStages.count)
            averageDeepPercent = withStages.map { ($0.deepSleepDuration! / $0.totalSleepDuration) * 100 }.reduce(0, +) / stageCount
            averageCorePercent = withStages.compactMap { s in
                s.coreSleepDuration.map { ($0 / s.totalSleepDuration) * 100 }
            }.reduce(0, +) / stageCount
            averageRemPercent = withStages.compactMap { s in
                s.remSleepDuration.map { ($0 / s.totalSleepDuration) * 100 }
            }.reduce(0, +) / stageCount
        }
    }

    private func loadRecoveryData(from start: Date, to end: Date, prevStart: Date, prevEnd: Date) async {
        var scores: [Int] = []
        var hrvValues: [Double] = []
        var rhrValues: [Double] = []
        var spo2Values: [Double] = []

        var currentDate = start
        while currentDate < end {
            if let metrics = try? await healthKitManager.fetchRecoveryMetrics(for: currentDate) {
                scores.append(metrics.recoveryScore)
                if let hrv = metrics.hrvAverage { hrvValues.append(hrv) }
                if let rhr = metrics.restingHeartRate { rhrValues.append(rhr) }
                if let spo2 = metrics.oxygenSaturation { spo2Values.append(spo2) }
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        if !scores.isEmpty {
            averageRecoveryScore = scores.reduce(0, +) / scores.count
        }
        averageHRV = hrvValues.isEmpty ? nil : hrvValues.reduce(0, +) / Double(hrvValues.count)
        averageRestingHR = rhrValues.isEmpty ? nil : rhrValues.reduce(0, +) / Double(rhrValues.count)
        averageSpO2 = spo2Values.isEmpty ? nil : spo2Values.reduce(0, +) / Double(spo2Values.count)

        // Previous week recovery for comparison
        var prevScores: [Int] = []
        var prevDate = prevStart
        while prevDate < prevEnd {
            if let metrics = try? await healthKitManager.fetchRecoveryMetrics(for: prevDate) {
                prevScores.append(metrics.recoveryScore)
            }
            prevDate = calendar.date(byAdding: .day, value: 1, to: prevDate)!
        }

        if !scores.isEmpty, !prevScores.isEmpty {
            let prevAvg = prevScores.reduce(0, +) / prevScores.count
            recoveryScoreChange = averageRecoveryScore - prevAvg
        }
    }
}
