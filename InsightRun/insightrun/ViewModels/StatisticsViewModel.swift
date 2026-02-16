//
//  StatisticsViewModel.swift
//  InsightRun
//
//  ViewModel for statistics and performance metrics
//

import SwiftUI
import Combine
import HealthKit

// MARK: - Progression Data

struct ProgressionDataPoint: Identifiable {
    var id: UUID { workoutId }
    let workoutId: UUID
    let date: Date
    // Performance
    let averagePace: Double?
    let minPace: Double?
    let maxSpeed: Double?
    let averageCadence: Double?
    let strideLength: Double?
    let runningPower: Double?
    let vo2Max: Double?
    // Advanced
    let groundContactTime: Double?
    let verticalOscillation: Double?
    let walkingAsymmetry: Double?
    let doubleSupportPercentage: Double?
    let walkingSpeed: Double?
    let stairDescentSpeed: Double?
}

@MainActor
class StatisticsViewModel: ObservableObject {
    @Published var workouts: [WorkoutModel] = []
    @Published var isLoading = false
    @Published var selectedPeriod: TimePeriod = .thisMonth
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @Published var chartGranularity: ChartGranularity = .week

    // Progression
    @Published var progressionData: [ProgressionDataPoint] = []
    @Published var isLoadingProgression = false
    @Published var progressionLoadingProgress: Double = 0

    private let healthKitManager = HealthKitManager.shared
    private var progressionCache: [UUID: ProgressionDataPoint] = [:]
    private var progressionTask: Task<Void, Never>?

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
        if DemoMode.isEnabled {
            workouts = MockData.sampleWorkouts
            isLoading = false
            return
        }

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

        if selectedPeriod == .thisMonth && chartGranularity == .week {
            let now = Date()
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
                return data
            }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
                return data
            }

            // Group workouts by week using yearForWeekOfYear for correct year-boundary handling
            let grouped = Dictionary(grouping: filteredWorkouts) { workout in
                calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.startDate)
            }

            // Generate all weeks that overlap with the current month
            let weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startOfMonth)
            guard var currentWeekDate = calendar.date(from: weekStart) else { return data }

            while currentWeekDate < nextMonth {
                let weekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentWeekDate)
                let workoutsInWeek = grouped[weekComponents] ?? []

                let distance = workoutsInWeek.compactMap { $0.distance }.reduce(0, +)
                let paces = workoutsInWeek.compactMap { $0.averagePace }
                let avgPace = !paces.isEmpty ? paces.reduce(0, +) / Double(paces.count) : nil

                data.append(PeriodData(
                    date: currentWeekDate,
                    distance: distance,
                    workoutCount: workoutsInWeek.count,
                    averagePace: avgPace
                ))

                guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekDate) else { break }
                currentWeekDate = nextWeek
            }

            return data
        }

        let components: Calendar.Component = chartGranularity == .week ? .weekOfYear : .month
        let yearComponent: Calendar.Component = chartGranularity == .week ? .yearForWeekOfYear : .year

        // Group workouts by period
        let grouped = Dictionary(grouping: filteredWorkouts) { workout in
            calendar.dateComponents([yearComponent, components], from: workout.startDate)
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
            (range: "< 5:00", min: 0.0, max: 5.0, color: Color.irSuccess),
            (range: "5:00-6:00", min: 5.0, max: 6.0, color: Color.irPrimaryAccent),
            (range: "6:00-7:00", min: 6.0, max: 7.0, color: Color.irWarning),
            (range: "> 7:00", min: 7.0, max: 100.0, color: Color.irError)
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

    // MARK: - Progression Loading

    func loadProgressionMetrics() {
        progressionTask?.cancel()
        progressionTask = Task {
            isLoadingProgression = true
            progressionLoadingProgress = 0

            if DemoMode.isEnabled {
                progressionData = MockData.sampleProgressionData
                isLoadingProgression = false
                return
            }

            let workoutsToLoad = filteredWorkouts.sorted { $0.startDate < $1.startDate }
            guard !workoutsToLoad.isEmpty else {
                progressionData = []
                isLoadingProgression = false
                return
            }

            // Check cache first
            let uncached = workoutsToLoad.filter { progressionCache[$0.id] == nil }
            let totalToLoad = uncached.count

            if totalToLoad == 0 {
                progressionData = workoutsToLoad.compactMap { progressionCache[$0.id] }
                isLoadingProgression = false
                return
            }

            var loaded = 0

            // Process in batches of 8
            let batchSize = 8
            for batchStart in Swift.stride(from: 0, to: uncached.count, by: batchSize) {
                if Task.isCancelled { return }

                let batchEnd = min(batchStart + batchSize, uncached.count)
                let batch = Array(uncached[batchStart..<batchEnd])

                await withTaskGroup(of: ProgressionDataPoint.self) { group in
                    for workout in batch {
                        group.addTask {
                            await self.healthKitManager.fetchProgressionMetrics(for: workout)
                        }
                    }

                    for await result in group {
                        if Task.isCancelled { return }
                        self.progressionCache[result.workoutId] = result
                        loaded += 1
                        self.progressionLoadingProgress = Double(loaded) / Double(totalToLoad)
                    }
                }

                // Update progressionData incrementally
                if !Task.isCancelled {
                    progressionData = workoutsToLoad.compactMap { progressionCache[$0.id] }
                }
            }

            isLoadingProgression = false
        }
    }

    // MARK: - Progression Series

    struct MetricSeries: Identifiable {
        let id: String
        let name: String
        let icon: String
        let color: Color
        let unit: String
        let lowerIsBetter: Bool
        let metricInfoKey: String?
        let points: [(date: Date, value: Double)]

        var average: Double {
            guard !points.isEmpty else { return 0 }
            return points.map(\.value).reduce(0, +) / Double(points.count)
        }

        var trendPercentage: Double? {
            guard points.count >= 4 else { return nil }
            let mid = points.count / 2
            let firstHalf = points.prefix(mid).map(\.value)
            let secondHalf = points.suffix(mid).map(\.value)
            let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
            let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
            guard firstAvg > 0 else { return nil }
            return ((secondAvg - firstAvg) / firstAvg) * 100
        }
    }

    var performanceMetrics: [MetricSeries] {
        let data = progressionData
        var series: [MetricSeries] = []

        let bestPace = data.compactMap { p in p.minPace.map { (p.date, $0) } }
        if bestPace.count >= 2 {
            series.append(MetricSeries(
                id: "minPace", name: String(localized: "progression.metric.bestPace", defaultValue: "Best pace", comment: "Best pace metric"),
                icon: "hare.fill", color: .green, unit: String(localized: "progression.unit.minKm", defaultValue: "min/km", comment: "Pace unit"), lowerIsBetter: true, metricInfoKey: "metric.best_pace", points: bestPace
            ))
        }

        let maxSpd = data.compactMap { p in p.maxSpeed.map { (p.date, $0) } }
        if maxSpd.count >= 2 {
            series.append(MetricSeries(
                id: "maxSpeed", name: String(localized: "progression.metric.maxSpeed", defaultValue: "Max speed", comment: "Max speed metric"),
                icon: "bolt.fill", color: .yellow, unit: String(localized: "progression.unit.kmh", defaultValue: "km/h", comment: "Speed unit"), lowerIsBetter: false, metricInfoKey: "metric.max_speed", points: maxSpd
            ))
        }

        let cadence = data.compactMap { p in p.averageCadence.map { (p.date, $0) } }
        if cadence.count >= 2 {
            series.append(MetricSeries(
                id: "cadence", name: String(localized: "progression.metric.cadence", defaultValue: "Avg cadence", comment: "Cadence metric"),
                icon: "metronome.fill", color: .indigo, unit: String(localized: "progression.unit.spm", defaultValue: "spm", comment: "Steps per minute"), lowerIsBetter: false, metricInfoKey: "metric.avg_cadence", points: cadence
            ))
        }

        let stride = data.compactMap { p in p.strideLength.map { (p.date, $0) } }
        if stride.count >= 2 {
            series.append(MetricSeries(
                id: "stride", name: String(localized: "progression.metric.strideLength", defaultValue: "Stride length", comment: "Stride length metric"),
                icon: "figure.walk", color: .cyan, unit: String(localized: "progression.unit.m", defaultValue: "m", comment: "Meters unit"), lowerIsBetter: false, metricInfoKey: "metric.stride_length", points: stride
            ))
        }

        let power = data.compactMap { p in p.runningPower.map { (p.date, $0) } }
        if power.count >= 2 {
            series.append(MetricSeries(
                id: "power", name: String(localized: "progression.metric.power", defaultValue: "Power", comment: "Running power metric"),
                icon: "bolt.circle.fill", color: .orange, unit: "W", lowerIsBetter: false, metricInfoKey: "metric.running_power", points: power
            ))
        }

        let vo2 = data.compactMap { p in p.vo2Max.map { (p.date, $0) } }
        if vo2.count >= 2 {
            series.append(MetricSeries(
                id: "vo2max", name: "VO2 Max",
                icon: "lungs.fill", color: .red, unit: String(localized: "progression.unit.vo2", defaultValue: "ml/kg/min", comment: "VO2 Max unit"), lowerIsBetter: false, metricInfoKey: "metric.vo2_max", points: vo2
            ))
        }

        return series
    }

    var advancedMetrics: [MetricSeries] {
        let data = progressionData
        var series: [MetricSeries] = []

        let gct = data.compactMap { p in p.groundContactTime.map { (p.date, $0) } }
        if gct.count >= 2 {
            series.append(MetricSeries(
                id: "gct", name: String(localized: "progression.metric.groundContactTime", defaultValue: "Ground contact", comment: "Ground contact time metric"),
                icon: "timer", color: .indigo, unit: "ms", lowerIsBetter: true, metricInfoKey: "metric.ground_contact_time", points: gct
            ))
        }

        let vo = data.compactMap { p in p.verticalOscillation.map { (p.date, $0) } }
        if vo.count >= 2 {
            series.append(MetricSeries(
                id: "vertOsc", name: String(localized: "progression.metric.verticalOscillation", defaultValue: "Vertical osc.", comment: "Vertical oscillation metric"),
                icon: "arrow.up.and.down", color: .cyan, unit: "cm", lowerIsBetter: true, metricInfoKey: "metric.vertical_oscillation", points: vo
            ))
        }

        let asym = data.compactMap { p in p.walkingAsymmetry.map { (p.date, $0) } }
        if asym.count >= 2 {
            series.append(MetricSeries(
                id: "asymmetry", name: String(localized: "progression.metric.walkingAsymmetry", defaultValue: "Walking asymmetry", comment: "Walking asymmetry metric"),
                icon: "figure.walk.arrival", color: .orange, unit: "%", lowerIsBetter: true, metricInfoKey: "metric.walking_asymmetry", points: asym
            ))
        }

        let ds = data.compactMap { p in p.doubleSupportPercentage.map { (p.date, $0) } }
        if ds.count >= 2 {
            series.append(MetricSeries(
                id: "doubleSupport", name: String(localized: "progression.metric.doubleSupport", defaultValue: "Double support", comment: "Double support metric"),
                icon: "figure.2.arms.open", color: .blue, unit: "%", lowerIsBetter: false, metricInfoKey: "metric.double_support", points: ds
            ))
        }

        let ws = data.compactMap { p in p.walkingSpeed.map { (p.date, $0) } }
        if ws.count >= 2 {
            series.append(MetricSeries(
                id: "walkSpeed", name: String(localized: "progression.metric.walkingSpeed", defaultValue: "Walking speed", comment: "Walking speed metric"),
                icon: "figure.walk.circle", color: .cyan, unit: String(localized: "progression.unit.kmh", defaultValue: "km/h", comment: "Speed unit"), lowerIsBetter: false, metricInfoKey: "metric.walking_speed", points: ws
            ))
        }

        let sds = data.compactMap { p in p.stairDescentSpeed.map { (p.date, $0) } }
        if sds.count >= 2 {
            series.append(MetricSeries(
                id: "stairDescent", name: String(localized: "progression.metric.stairDescentSpeed", defaultValue: "Stair descent", comment: "Stair descent speed metric"),
                icon: "figure.stairs", color: .indigo, unit: String(localized: "progression.unit.kmh", defaultValue: "km/h", comment: "Speed unit"), lowerIsBetter: false, metricInfoKey: "metric.stair_descent_speed", points: sds
            ))
        }

        return series
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
        let testWorkouts: [WorkoutModel] = (1...45).map { day in
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
                sourceVersion: "1.0",
                metadata: nil,
                averageHeartRate: Double.random(in: 130...170),
                maxHeartRate: Double.random(in: 170...190),
                elevationGain: Double.random(in: 0...150),
                hasRoute: false
            )
        }
        self.workouts = testWorkouts
    }
}
