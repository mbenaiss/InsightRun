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
    @Published var selectedPeriod: TimePeriod = .thirtyDays
    @Published var chartGranularity: ChartGranularity = .month

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

    enum ChartGranularity: String, CaseIterable {
        case week = "Semaine"
        case month = "Mois"
    }

    // MARK: - Data Structures for Charts

    struct PeriodData: Identifiable {
        let id = UUID()
        let date: Date
        let distance: Double // in meters
        let workoutCount: Int
        let averagePace: Double?
    }

    struct ActivityDay: Identifiable {
        let id = UUID()
        let date: Date
        let hasActivity: Bool
        let distance: Double
        let intensity: ActivityIntensity
    }

    enum ActivityIntensity: Int {
        case none = 0
        case light = 1
        case moderate = 2
        case high = 3
        case veryHigh = 4

        var color: Color {
            switch self {
            case .none: return Color.gray.opacity(0.1)
            case .light: return Color.green.opacity(0.3)
            case .moderate: return Color.green.opacity(0.5)
            case .high: return Color.green.opacity(0.7)
            case .veryHigh: return Color.green.opacity(0.9)
            }
        }
    }

    struct PaceDistribution: Identifiable {
        let id = UUID()
        let range: String
        let count: Int
        let percentage: Double
        let color: Color
    }

    struct DistanceDistribution: Identifiable {
        let id = UUID()
        let category: String
        let count: Int
        let percentage: Double
    }

    struct YearlyComparison {
        let thisYearDistance: Double
        let lastYearDistance: Double
        let thisYearWorkouts: Int
        let lastYearWorkouts: Int
        let thisYearAvgPace: Double?
        let lastYearAvgPace: Double?

        var distanceChange: Double {
            guard lastYearDistance > 0 else { return 0 }
            return ((thisYearDistance - lastYearDistance) / lastYearDistance) * 100
        }

        var workoutsChange: Double {
            guard lastYearWorkouts > 0 else { return 0 }
            return Double((thisYearWorkouts - lastYearWorkouts)) / Double(lastYearWorkouts) * 100
        }

        var paceChange: Double? {
            guard let thisPace = thisYearAvgPace, let lastPace = lastYearAvgPace else { return nil }
            return thisPace - lastPace
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

    // MARK: - Chart Data Methods

    var periodDistanceData: [PeriodData] {
        let calendar = Calendar.current
        var data: [PeriodData] = []

        let components: Calendar.Component = chartGranularity == .week ? .weekOfYear : .month

        // Group workouts by period
        let grouped = Dictionary(grouping: filteredWorkouts) { workout in
            calendar.dateComponents([.year, components], from: workout.startDate)
        }

        // Create data points for each period
        for (dateComponents, workouts) in grouped {
            guard let date = calendar.date(from: dateComponents) else { continue }

            let distance = workouts.compactMap { $0.distance }.reduce(0, +)
            let paces = workouts.compactMap { $0.averagePace }
            let avgPace = !paces.isEmpty ? paces.reduce(0, +) / Double(paces.count) : nil

            data.append(PeriodData(
                date: date,
                distance: distance,
                workoutCount: workouts.count,
                averagePace: avgPace
            ))
        }

        return data.sorted { $0.date < $1.date }
    }

    var activityHeatMapData: [ActivityDay] {
        let calendar = Calendar.current
        var data: [ActivityDay] = []

        // Get last 12 months
        guard let startDate = calendar.date(byAdding: .month, value: -12, to: Date()) else { return [] }
        let endDate = Date()

        // Create dictionary of workout dates with their distances
        let workoutsByDate = Dictionary(grouping: workouts.filter { $0.startDate >= startDate }) { workout in
            calendar.startOfDay(for: workout.startDate)
        }

        // Iterate through all days
        var currentDate = startDate
        while currentDate <= endDate {
            let dayStart = calendar.startOfDay(for: currentDate)
            let dayWorkouts = workoutsByDate[dayStart] ?? []
            let totalDistance = dayWorkouts.compactMap { $0.distance }.reduce(0, +)

            let intensity = getActivityIntensity(distance: totalDistance)

            data.append(ActivityDay(
                date: dayStart,
                hasActivity: !dayWorkouts.isEmpty,
                distance: totalDistance,
                intensity: intensity
            ))

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return data
    }

    private func getActivityIntensity(distance: Double) -> ActivityIntensity {
        if distance == 0 { return .none }
        let km = distance / 1000.0
        if km < 3 { return .light }
        if km < 6 { return .moderate }
        if km < 10 { return .high }
        return .veryHigh
    }

    var paceDistributionData: [PaceDistribution] {
        let paces = filteredWorkouts.compactMap { $0.averagePace }
        guard !paces.isEmpty else { return [] }

        let total = Double(paces.count)

        // Define pace zones (min/km)
        let zones = [
            (range: "< 5:00", min: 0.0, max: 5.0, color: Color.green),
            (range: "5:00-6:00", min: 5.0, max: 6.0, color: Color.yellow),
            (range: "6:00-7:00", min: 6.0, max: 7.0, color: Color.orange),
            (range: "> 7:00", min: 7.0, max: 100.0, color: Color.red)
        ]

        var distribution: [PaceDistribution] = []

        for zone in zones {
            let count = paces.filter { $0 >= zone.min && $0 < zone.max }.count
            let percentage = (Double(count) / total) * 100

            distribution.append(PaceDistribution(
                range: zone.range,
                count: count,
                percentage: percentage,
                color: zone.color
            ))
        }

        return distribution.filter { $0.count > 0 }
    }

    var distanceDistributionData: [DistanceDistribution] {
        guard !filteredWorkouts.isEmpty else { return [] }

        let total = Double(filteredWorkouts.count)

        // Define distance categories
        let categories = [
            (name: "Courte (< 5 km)", min: 0.0, max: 5000.0),
            (name: "Moyenne (5-10 km)", min: 5000.0, max: 10000.0),
            (name: "Longue (10-15 km)", min: 10000.0, max: 15000.0),
            (name: "Très longue (> 15 km)", min: 15000.0, max: Double.infinity)
        ]

        var distribution: [DistanceDistribution] = []

        for category in categories {
            let count = filteredWorkouts.filter { workout in
                guard let distance = workout.distance else { return false }
                return distance >= category.min && distance < category.max
            }.count

            let percentage = (Double(count) / total) * 100

            if count > 0 {
                distribution.append(DistanceDistribution(
                    category: category.name,
                    count: count,
                    percentage: percentage
                ))
            }
        }

        return distribution
    }

    var yearlyComparisonData: YearlyComparison {
        let calendar = Calendar.current
        let now = Date()

        guard let startOfThisYear = calendar.date(from: calendar.dateComponents([.year], from: now)),
              let startOfLastYear = calendar.date(byAdding: .year, value: -1, to: startOfThisYear),
              let endOfLastYear = calendar.date(byAdding: .day, value: -1, to: startOfThisYear) else {
            return YearlyComparison(
                thisYearDistance: 0,
                lastYearDistance: 0,
                thisYearWorkouts: 0,
                lastYearWorkouts: 0,
                thisYearAvgPace: nil,
                lastYearAvgPace: nil
            )
        }

        let thisYearWorkouts = workouts.filter { $0.startDate >= startOfThisYear }
        let lastYearWorkouts = workouts.filter { $0.startDate >= startOfLastYear && $0.startDate <= endOfLastYear }

        let thisYearDistance = thisYearWorkouts.compactMap { $0.distance }.reduce(0, +)
        let lastYearDistance = lastYearWorkouts.compactMap { $0.distance }.reduce(0, +)

        let thisYearPaces = thisYearWorkouts.compactMap { $0.averagePace }
        let lastYearPaces = lastYearWorkouts.compactMap { $0.averagePace }

        let thisYearAvgPace = !thisYearPaces.isEmpty ? thisYearPaces.reduce(0, +) / Double(thisYearPaces.count) : nil
        let lastYearAvgPace = !lastYearPaces.isEmpty ? lastYearPaces.reduce(0, +) / Double(lastYearPaces.count) : nil

        return YearlyComparison(
            thisYearDistance: thisYearDistance,
            lastYearDistance: lastYearDistance,
            thisYearWorkouts: thisYearWorkouts.count,
            lastYearWorkouts: lastYearWorkouts.count,
            thisYearAvgPace: thisYearAvgPace,
            lastYearAvgPace: lastYearAvgPace
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
