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
    @Published var selectedPeriod: TimePeriod = .thisMonth
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @Published var chartGranularity: ChartGranularity = .month

    private let healthKitManager = HealthKitManager.shared

    enum TimePeriod: Equatable, CaseIterable {
        case thisMonth
        case sixMonths
        case oneYear
        case specificYear

        var localizedTitle: String {
            switch self {
            case .thisMonth:
                return String(localized: "statistics.period.thisMonth", defaultValue: "This month", comment: "This month period filter")
            case .sixMonths:
                return String(localized: "statistics.period.6months", defaultValue: "6 months", comment: "6 months period filter")
            case .oneYear:
                return String(localized: "statistics.period.1year", defaultValue: "1 year", comment: "1 year period filter")
            case .specificYear:
                return String(localized: "statistics.period.year", defaultValue: "Year", comment: "Specific year period filter")
            }
        }

        var days: Int? {
            switch self {
            case .thisMonth: return nil
            case .sixMonths: return 180
            case .oneYear: return 365
            case .specificYear: return nil
            }
        }

        static var allCases: [TimePeriod] {
            [.thisMonth, .sixMonths, .oneYear, .specificYear]
        }
    }

    enum ChartGranularity: String, CaseIterable {
        case week
        case month

        var localizedTitle: String {
            switch self {
            case .week:
                return String(localized: "statistics.granularity.week", defaultValue: "Week", comment: "Week chart granularity")
            case .month:
                return String(localized: "statistics.granularity.month", defaultValue: "Month", comment: "Month chart granularity")
            }
        }
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
        let calendar = Calendar.current

        switch selectedPeriod {
        case .thisMonth:
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else {
                return workouts
            }
            return workouts.filter { $0.startDate >= startOfMonth }

        case .sixMonths, .oneYear:
            guard let days = selectedPeriod.days else { return workouts }
            let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return workouts.filter { $0.startDate >= cutoffDate }

        case .specificYear:
            guard let startOfYear = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) else {
                return workouts
            }
            guard let endOfYear = calendar.date(from: DateComponents(year: selectedYear, month: 12, day: 31)) else {
                return workouts
            }
            return workouts.filter { $0.startDate >= startOfYear && $0.startDate <= endOfYear }
        }
    }

    // MARK: - Available Years

    var availableYears: [Int] {
        guard !workouts.isEmpty else { return [Calendar.current.component(.year, from: Date())] }

        let years = Set(workouts.map { Calendar.current.component(.year, from: $0.startDate) })
        return years.sorted(by: >)
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

        // This month values
        let thisMonthWorkouts: Int
        let thisMonthDistance: Double
        let thisMonthDuration: TimeInterval
        let thisMonthAvgPace: Double?

        // Last month values
        let lastMonthWorkouts: Int
        let lastMonthDistance: Double
        let lastMonthDuration: TimeInterval
        let lastMonthAvgPace: Double?

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
            guard let previousDate = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                break
            }
            currentDate = previousDate
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
            return MonthlyChange(
                distanceChange: 0, workoutsChange: 0, paceChange: nil, durationChange: 0,
                thisMonthWorkouts: 0, thisMonthDistance: 0, thisMonthDuration: 0, thisMonthAvgPace: nil,
                lastMonthWorkouts: 0, lastMonthDistance: 0, lastMonthDuration: 0, lastMonthAvgPace: nil
            )
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
            durationChange: durationChange,
            thisMonthWorkouts: thisMonthWorkouts.count,
            thisMonthDistance: thisMonthDistance,
            thisMonthDuration: thisMonthDuration,
            thisMonthAvgPace: thisMonthAvgPace,
            lastMonthWorkouts: lastMonthWorkouts.count,
            lastMonthDistance: lastMonthDistance,
            lastMonthDuration: lastMonthDuration,
            lastMonthAvgPace: lastMonthAvgPace
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

        data = data.sorted { $0.date < $1.date }

        // When displaying this month with week granularity, filter to only include weeks within the current month
        if selectedPeriod == .thisMonth && chartGranularity == .week {
            let now = Date()
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
                return data
            }
            guard let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
                return data
            }
            data = data.filter { $0.date >= startOfMonth && $0.date <= endOfMonth }
        }

        return data
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

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
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
            (nameKey: "statistics.distance.short", min: 0.0, max: 5000.0),
            (nameKey: "statistics.distance.medium", min: 5000.0, max: 10000.0),
            (nameKey: "statistics.distance.long", min: 10000.0, max: 15000.0),
            (nameKey: "statistics.distance.veryLong", min: 15000.0, max: Double.infinity)
        ]

        var distribution: [DistanceDistribution] = []

        for category in categories {
            let count = filteredWorkouts.filter { workout in
                guard let distance = workout.distance else { return false }
                return distance >= category.min && distance < category.max
            }.count

            let percentage = (Double(count) / total) * 100

            if count > 0 {
                let localizedName: String
                switch category.nameKey {
                case "statistics.distance.short":
                    localizedName = String(localized: "statistics.distance.short", defaultValue: "Short (< 5 km)", comment: "Short distance category")
                case "statistics.distance.medium":
                    localizedName = String(localized: "statistics.distance.medium", defaultValue: "Medium (5-10 km)", comment: "Medium distance category")
                case "statistics.distance.long":
                    localizedName = String(localized: "statistics.distance.long", defaultValue: "Long (10-15 km)", comment: "Long distance category")
                case "statistics.distance.veryLong":
                    localizedName = String(localized: "statistics.distance.veryLong", defaultValue: "Very long (> 15 km)", comment: "Very long distance category")
                default:
                    localizedName = ""
                }

                distribution.append(DistanceDistribution(
                    category: localizedName,
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

    // MARK: - Test Data

    @MainActor
    static func createWithTestData() -> StatisticsViewModel {
        let viewModel = StatisticsViewModel()
        viewModel.loadTestData()
        return viewModel
    }

    func loadTestData() {
        let testWorkouts = (1...45).map { day -> WorkoutModel in
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: -day, to: Date()) ?? Date()
            let distance = Double.random(in: 3000...15000) // 3-15 km
            let pace = Double.random(in: 5.5...7.5) // 5:30-7:30 min/km
            let duration = (distance / 1000.0) * pace * 60 // Convert to seconds

            return WorkoutModel(
                id: UUID(),
                workoutType: .running,
                startDate: startDate,
                endDate: calendar.date(byAdding: .second, value: Int(duration), to: startDate) ?? startDate,
                duration: duration,
                distance: distance,
                totalEnergyBurned: distance / 1000 * Double.random(in: 50...80), // 50-80 kcal per km
                sourceName: "Apple Health",
                sourceVersion: "1.0"
            )
        }
        self.workouts = testWorkouts
    }
}
