//
//  StatisticsViewModel.swift
//  InsightRun
//
//  ViewModel for statistics and performance metrics
//

import SwiftUI
import Combine
import HealthKit

@MainActor
class StatisticsViewModel: ObservableObject {
    @Published var workouts: [WorkoutModel] = []
    @Published var isLoading = false
    @Published var selectedPeriod: TimePeriod = .allTime

    private let healthKitManager = HealthKitManager.shared

    enum TimePeriod: String, CaseIterable {
        case thirtyDays = "30j"
        case ninetyDays = "90j"
        case sixMonths = "6 mois"
        case oneYear = "1 an"
        case allTime = "Tout"

        var days: Int? {
            switch self {
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .sixMonths: return 180
            case .oneYear: return 365
            case .allTime: return nil
            }
        }
    }

    // MARK: - Data Loading

    func loadWorkouts() async {
        isLoading = true

        do {
            workouts = try await healthKitManager.fetchRunningWorkouts()
        } catch {
            print("Error loading workouts: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func refresh() async {
        await loadWorkouts()
    }

    // MARK: - Filtered Workouts

    var filteredWorkouts: [WorkoutModel] {
        guard let days = selectedPeriod.days else { return workouts }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return workouts.filter { $0.startDate >= cutoffDate }
    }

    // MARK: - Overview Metrics

    var totalWorkouts: Int {
        filteredWorkouts.count
    }

    var totalDistance: Double {
        filteredWorkouts.compactMap { $0.distance }.reduce(0, +)
    }

    var totalDuration: TimeInterval {
        filteredWorkouts.map { $0.duration }.reduce(0, +)
    }

    var currentStreak: Int {
        calculateStreak()
    }

    var longestStreak: Int {
        calculateLongestStreak()
    }

    var consistencyRate: Double {
        calculateConsistencyRate()
    }

    var averagePace: Double? {
        let paces = filteredWorkouts.compactMap { $0.averagePace }
        guard !paces.isEmpty else { return nil }

        // Weighted average by distance
        let totalDistance = filteredWorkouts.compactMap { $0.distance }.reduce(0, +)
        guard totalDistance > 0 else { return nil }

        let weightedSum = zip(filteredWorkouts, paces).reduce(0.0) { sum, pair in
            let (workout, pace) = pair
            let distance = workout.distance ?? 0
            return sum + (pace * distance)
        }

        return weightedSum / totalDistance
    }

    // MARK: - Performance Metrics

    var averageDistance: Double {
        guard !filteredWorkouts.isEmpty else { return 0 }
        return totalDistance / Double(filteredWorkouts.count)
    }

    var averageDuration: TimeInterval {
        guard !filteredWorkouts.isEmpty else { return 0 }
        return totalDuration / Double(filteredWorkouts.count)
    }

    var weeklyFrequency: Double {
        guard !filteredWorkouts.isEmpty else { return 0 }

        let sortedWorkouts = filteredWorkouts.sorted { $0.startDate < $1.startDate }
        guard let firstDate = sortedWorkouts.first?.startDate,
              let lastDate = sortedWorkouts.last?.startDate else { return 0 }

        let weeks = Calendar.current.dateComponents([.weekOfYear], from: firstDate, to: lastDate).weekOfYear ?? 0
        guard weeks > 0 else { return Double(filteredWorkouts.count) }

        return Double(filteredWorkouts.count) / Double(weeks)
    }

    // MARK: - Personal Records

    var longestRun: WorkoutModel? {
        workouts.max(by: { ($0.distance ?? 0) < ($1.distance ?? 0) })
    }

    var fastestRun: WorkoutModel? {
        workouts.min(by: { ($0.averagePace ?? Double.infinity) < ($1.averagePace ?? Double.infinity) })
    }

    var longestDuration: WorkoutModel? {
        workouts.max(by: { $0.duration < $1.duration })
    }

    var best5K: WorkoutModel? {
        findBestTime(forDistance: 5000, tolerance: 250)
    }

    var best10K: WorkoutModel? {
        findBestTime(forDistance: 10000, tolerance: 500)
    }

    var bestHalfMarathon: WorkoutModel? {
        findBestTime(forDistance: 21097.5, tolerance: 1000)
    }

    var bestMarathon: WorkoutModel? {
        findBestTime(forDistance: 42195, tolerance: 1000)
    }

    // MARK: - Change Metrics

    var monthlyChange: MonthlyChange {
        calculateMonthlyChange()
    }

    struct MonthlyChange {
        let distanceChange: Double
        let workoutsChange: Int
        let paceChange: Double?
        let durationChange: TimeInterval

        var distancePercentage: Double {
            guard distanceChange != 0 else { return 0 }
            return distanceChange * 100
        }

        var workoutsPercentage: Double {
            guard workoutsChange != 0 else { return 0 }
            return Double(workoutsChange) * 100
        }
    }

    // MARK: - Helper Methods

    private func calculateStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let workoutDates = Set(workouts.map { calendar.startOfDay(for: $0.startDate) })

        var streak = 0
        var currentDate = today

        while workoutDates.contains(currentDate) {
            streak += 1
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }

        return streak
    }

    private func calculateLongestStreak() -> Int {
        let calendar = Calendar.current
        let workoutDates = Set(workouts.map { calendar.startOfDay(for: $0.startDate) }).sorted()

        guard !workoutDates.isEmpty else { return 0 }

        var maxStreak = 1
        var currentStreak = 1

        for i in 1..<workoutDates.count {
            let previousDate = workoutDates[i - 1]
            let currentDate = workoutDates[i]

            let daysDiff = calendar.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0

            if daysDiff == 1 {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 1
            }
        }

        return maxStreak
    }

    private func calculateConsistencyRate() -> Double {
        guard let days = selectedPeriod.days, days > 0 else {
            // For all time, calculate based on actual date range
            guard !workouts.isEmpty else { return 0 }
            let sortedWorkouts = workouts.sorted { $0.startDate < $1.startDate }
            guard let firstDate = sortedWorkouts.first?.startDate else { return 0 }

            let totalDays = Calendar.current.dateComponents([.day], from: firstDate, to: Date()).day ?? 1
            let workoutDays = Set(workouts.map { Calendar.current.startOfDay(for: $0.startDate) }).count

            return Double(workoutDays) / Double(totalDays) * 100
        }

        let workoutDays = Set(filteredWorkouts.map { Calendar.current.startOfDay(for: $0.startDate) }).count
        return Double(workoutDays) / Double(days) * 100
    }

    private func findBestTime(forDistance targetDistance: Double, tolerance: Double) -> WorkoutModel? {
        let candidates = workouts.filter { workout in
            guard let distance = workout.distance else { return false }
            return abs(distance - targetDistance) <= tolerance
        }

        return candidates.min { $0.duration < $1.duration }
    }

    private func calculateMonthlyChange() -> MonthlyChange {
        let calendar = Calendar.current
        let now = Date()

        guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) else {
            return MonthlyChange(distanceChange: 0, workoutsChange: 0, paceChange: nil, durationChange: 0)
        }

        let thisMonthWorkouts = workouts.filter { $0.startDate >= startOfThisMonth }
        let lastMonthWorkouts = workouts.filter { $0.startDate >= startOfLastMonth && $0.startDate < startOfThisMonth }

        let thisMonthDistance = thisMonthWorkouts.compactMap { $0.distance }.reduce(0, +)
        let lastMonthDistance = lastMonthWorkouts.compactMap { $0.distance }.reduce(0, +)

        let thisMonthDuration = thisMonthWorkouts.map { $0.duration }.reduce(0, +)
        let lastMonthDuration = lastMonthWorkouts.map { $0.duration }.reduce(0, +)

        let distanceChange = lastMonthDistance > 0 ? (thisMonthDistance - lastMonthDistance) / lastMonthDistance : 0
        let workoutsChange = lastMonthWorkouts.count > 0 ?
            Int((Double(thisMonthWorkouts.count - lastMonthWorkouts.count) / Double(lastMonthWorkouts.count)) * 100) : 0
        let durationChange = thisMonthDuration - lastMonthDuration

        // Calculate pace change
        let thisMonthPaces = thisMonthWorkouts.compactMap { $0.averagePace }
        let lastMonthPaces = lastMonthWorkouts.compactMap { $0.averagePace }

        let thisMonthAvgPace = thisMonthPaces.isEmpty ? nil : thisMonthPaces.reduce(0, +) / Double(thisMonthPaces.count)
        let lastMonthAvgPace = lastMonthPaces.isEmpty ? nil : lastMonthPaces.reduce(0, +) / Double(lastMonthPaces.count)

        let paceChange: Double?
        if let thisAvg = thisMonthAvgPace, let lastAvg = lastMonthAvgPace {
            paceChange = thisAvg - lastAvg
        } else {
            paceChange = nil
        }

        return MonthlyChange(
            distanceChange: distanceChange,
            workoutsChange: workoutsChange,
            paceChange: paceChange,
            durationChange: durationChange
        )
    }

    // MARK: - Formatting

    func formatDistance(_ distance: Double) -> String {
        let km = distance / 1000.0
        return String(format: "%.1f km", km)
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60

        if hours > 0 {
            return String(format: "%dh %02dmin", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }

    func formatPace(_ pace: Double) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    func formatConsistencyRate(_ rate: Double) -> String {
        return String(format: "%.0f%%", min(rate, 100))
    }

    func formatPercentageChange(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return String(format: "%@%.0f%%", sign, change)
    }

    func formatFrequency(_ frequency: Double) -> String {
        return String(format: "%.1f", frequency)
    }
}
