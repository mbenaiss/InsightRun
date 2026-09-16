//
//  StatisticsViewModel.swift
//  InsightRun
//
//  ViewModel for statistics and performance metrics
//

import Combine
import HealthKit
import SwiftUI

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
    @Published var workouts: [WorkoutModel] = [] { didSet { invalidateSnapshot() } }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: TimePeriod = .thisMonth { didSet { invalidateSnapshot() } }
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date()) {
        didSet { invalidateSnapshot() }
    }
    @Published var chartGranularity: ChartGranularity = .week { didSet { invalidateSnapshot() } }

    // Progression
    @Published var progressionData: [ProgressionDataPoint] = [] {
        didSet {
            performanceCache = nil
            advancedCache = nil
        }
    }
    @Published var isLoadingProgression = false
    @Published var progressionLoadingProgress: Double = 0

    private let fetchWorkouts: () async throws -> [WorkoutModel]
    private let usesDemoProgression: Bool
    private let fetchProgression: (WorkoutModel) async -> ProgressionDataPoint
    private let now: () -> Date
    private let calendar: Calendar
    private var snapshotCache: StatisticsSnapshot?
    private var paceCache: [PaceDistribution]?
    private var distanceCache: [DistanceDistribution]?
    private var performanceCache: [MetricSeries]?
    private var advancedCache: [MetricSeries]?
    private var progressionCache: [UUID: ProgressionDataPoint] = [:]
    private var progressionTask: Task<Void, Never>?
    private var progressionRequestID = UUID()
    private var progressionWorkerID = UUID()
    private var progressionSelection: [UUID] = []
    private var loadTask: Task<[WorkoutModel], Error>?
    private var lastLoadedAt: Date?
    @Published private(set) var dataRevision = 0

    init(
        now: @escaping () -> Date = Date.init, calendar: Calendar = .current,
        fetchWorkouts: @escaping () async throws -> [WorkoutModel] = {
            try await HealthKitManager.shared.fetchRunningWorkouts(includeEffortScores: false)
        },
        fetchProgression: ((WorkoutModel) async -> ProgressionDataPoint)? = nil
    ) {
        self.now = now
        self.calendar = calendar
        self.fetchWorkouts = fetchWorkouts
        self.fetchProgression = fetchProgression ?? { await HealthKitManager.shared.fetchProgressionMetrics(for: $0) }
        self.usesDemoProgression = fetchProgression == nil && DemoMode.isEnabled
        selectedYear = calendar.component(.year, from: now())
    }

    private func invalidateSnapshot() {
        snapshotCache = nil
        paceCache = nil
        distanceCache = nil
    }

    var snapshot: StatisticsSnapshot {
        if let snapshotCache { return snapshotCache }
        let value = StatisticsSnapshot(
            workouts: workouts, period: selectedPeriod, year: selectedYear,
            granularity: chartGranularity, now: now(), calendar: calendar)
        snapshotCache = value
        return value
    }

    enum TimePeriod: Equatable, CaseIterable {
        case thisWeek
        case thisMonth
        case sixMonths
        case oneYear
        case allTime
        case specificYear

        var localizedTitle: String {
            switch self {
            case .thisWeek:
                return String(
                    localized: "statistics.period.thisWeek", defaultValue: "Week", comment: "This week period filter")
            case .thisMonth:
                return String(
                    localized: "statistics.period.thisMonth", defaultValue: "This month",
                    comment: "This month period filter")
            case .sixMonths:
                return String(
                    localized: "statistics.period.6months", defaultValue: "6 months", comment: "6 months period filter")
            case .oneYear:
                return String(
                    localized: "statistics.period.1year", defaultValue: "1 year", comment: "1 year period filter")
            case .allTime:
                return String(
                    localized: "statistics.period.all", defaultValue: "All", comment: "All-time period filter")
            case .specificYear:
                return String(
                    localized: "statistics.period.year", defaultValue: "Year", comment: "Specific year period filter")
            }
        }

        static var allCases: [TimePeriod] {
            [.thisWeek, .thisMonth, .sixMonths, .oneYear, .allTime, .specificYear]
        }
    }

    enum ChartGranularity: String, CaseIterable {
        case week
        case month

        var localizedTitle: String {
            switch self {
            case .week:
                return String(
                    localized: "statistics.granularity.week", defaultValue: "Week", comment: "Week chart granularity")
            case .month:
                return String(
                    localized: "statistics.granularity.month", defaultValue: "Month", comment: "Month chart granularity"
                )
            }
        }
    }

    // MARK: - Data Structures for Charts

    struct PeriodData: Identifiable {
        var id: Date { date }
        let date: Date
        let distance: Double  // in meters
        let duration: TimeInterval
        let workoutCount: Int
        let averagePace: Double?
    }

    struct PaceDistribution: Identifiable {
        var id: String { range }
        let range: String
        let zoneLabel: String
        let count: Int
        let percentage: Double
        let color: Color

        init(range: String, count: Int, percentage: Double, color: Color, zoneLabel: String = "") {
            self.range = range
            self.zoneLabel = zoneLabel
            self.count = count
            self.percentage = percentage
            self.color = color
        }
    }

    struct DistanceDistribution: Identifiable {
        var id: String { category }
        let category: String
        let count: Int
        let percentage: Double
        let totalKm: Double
        let isMarathon: Bool

        init(category: String, count: Int, percentage: Double, totalKm: Double = 0, isMarathon: Bool = false) {
            self.category = category
            self.count = count
            self.percentage = percentage
            self.totalKm = totalKm
            self.isMarathon = isMarathon
        }
    }

    func loadWorkouts(force: Bool = false) async {
        invalidateSnapshot()
        if let loadTask {
            _ = try? await loadTask.value
            return
        }
        if !force, let lastLoadedAt, now().timeIntervalSince(lastLoadedAt) < 60 { return }
        isLoading = workouts.isEmpty
        errorMessage = nil
        let task = Task { try await fetchWorkouts() }
        loadTask = task
        defer {
            loadTask = nil
            isLoading = false
        }
        do {
            let fresh = try await task.value
            cancelProgressionLoading()
            let updatedByID = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            let previous = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            progressionCache = progressionCache.filter { id, _ in
                guard let old = previous[id], let updated = updatedByID[id] else { return false }
                return old.startDate == updated.startDate && old.duration == updated.duration
                    && old.distance == updated.distance
            }
            workouts = fresh
            lastLoadedAt = now()
            dataRevision += 1
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        cancelProgressionLoading()
        progressionCache.removeAll()
        await loadWorkouts(force: true)
    }

    var filteredWorkouts: [WorkoutModel] { snapshot.workouts }
    var periodDistanceData: [PeriodData] { snapshot.buckets }
    var sparklineWorkouts: [Double] { snapshot.buckets.map { Double($0.workoutCount) } }
    var sparklineDistance: [Double] { snapshot.buckets.map { $0.distance / 1000 } }
    var sparklineDuration: [Double] { snapshot.buckets.map { $0.duration / 3600 } }
    var sparklinePace: [Double] { snapshot.buckets.compactMap(\.averagePace) }
    var totalWorkouts: Int { snapshot.totals.count }
    var totalDistance: Double { snapshot.totals.distance }
    var totalDuration: TimeInterval { snapshot.totals.duration }
    var averagePace: Double? { snapshot.totals.averagePace }
    var availableYears: [Int] { snapshot.availableYears }
    var longestRun: WorkoutModel? { snapshot.longestRun }
    var longestDuration: WorkoutModel? { snapshot.longestDuration }
    var best5K: WorkoutModel? { snapshot.distanceRecords[0] }
    var best10K: WorkoutModel? { snapshot.distanceRecords[1] }
    var bestHalfMarathon: WorkoutModel? { snapshot.distanceRecords[2] }
    var bestMarathon: WorkoutModel? { snapshot.distanceRecords[3] }

    var periodTitle: String {
        selectedPeriod == .specificYear ? String(selectedYear) : selectedPeriod.localizedTitle
    }

    var comparisonLabel: String? {
        guard let interval = snapshot.previousInterval else { return nil }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.calendar = calendar
        let end =
            calendar.isDate(interval.end, inSameDayAs: calendar.startOfDay(for: interval.end))
                && interval.end == calendar.startOfDay(for: interval.end)
            ? interval.end.addingTimeInterval(-1) : interval.end
        return formatter.string(from: interval.start, to: max(interval.start, end))
    }

    var monthlyWorkouts: (current: [WorkoutModel], previous: [WorkoutModel]) {
        let intervals = StatisticsSnapshot.ranges(
            period: .thisMonth, year: selectedYear, now: now(), first: nil, calendar: calendar)
        let current = workouts.filter {
            $0.startDate >= intervals.current.start && $0.startDate < intervals.current.end
        }
        let previous =
            intervals.previous.map { interval in
                workouts.filter { $0.startDate >= interval.start && $0.startDate < interval.end }
            } ?? []
        return (current, previous)
    }

    // MARK: - Header Subtitle (editorial)

    /// Editorial header subtitle: "{Period name} · {N} séances · {Total km}".
    /// Falls back to the selected period's localized title when there is no data.
    var headerSubtitle: String {
        let count = totalWorkouts
        let kmText = formatDistance(totalDistance)
        let periodName: String = {
            switch selectedPeriod {
            case .thisWeek:
                return String(
                    localized: "statistics.header.thisWeek", defaultValue: "This week",
                    comment: "Header subtitle period: this week")
            case .thisMonth:
                let f = DateFormatter()
                f.locale = Locale.current
                f.dateFormat = "LLLL yyyy"
                return f.string(from: now()).capitalized
            case .sixMonths:
                return String(
                    localized: "statistics.header.6months", defaultValue: "Last 6 months",
                    comment: "Header subtitle period: last 6 months")
            case .oneYear:
                return String(
                    localized: "statistics.header.1year", defaultValue: "Last 12 months",
                    comment: "Header subtitle period: last 12 months")
            case .allTime:
                return String(
                    localized: "statistics.header.all", defaultValue: "All time",
                    comment: "Header subtitle period: all time")
            case .specificYear:
                return "\(selectedYear)"
            }
        }()

        let sessions = String(
            format: String(
                localized: "statistics.header.sessionsCount", defaultValue: "%lld sessions",
                comment: "Header subtitle: number of sessions"), count)
        return "\(periodName) · \(sessions) · \(kmText)"
    }

    var paceDistributionData: [PaceDistribution] {
        if let paceCache { return paceCache }
        let paces = filteredWorkouts.compactMap { $0.averagePace }.filter { $0.isFinite && $0 > 0 }
        guard !paces.isEmpty else { return [] }

        let total = Double(paces.count)

        struct Zone {
            let range: String
            let label: String
            let min: Double
            let max: Double
            let color: Color
        }

        let unitScale = Formatters.distanceValue(km: 1)
        func clock(_ minutes: Double) -> String { Formatters.paceClock(minutes * 60 / unitScale) }
        let zones: [Zone] = [
            Zone(range: "< \(clock(5))", label: "", min: 0, max: 5, color: .irWarning),
            Zone(range: "\(clock(5))–\(clock(6))", label: "", min: 5, max: 6, color: .irSuccess),
            Zone(range: "\(clock(6))–\(clock(7))", label: "", min: 6, max: 7, color: .irPrimaryAccent),
            Zone(range: "≥ \(clock(7))", label: "", min: 7, max: .infinity, color: .irTextSecondary),
        ]

        let result = zones.map { zone in
            let count = paces.filter { $0 >= zone.min && $0 < zone.max }.count
            let percentage = (Double(count) / total) * 100
            return PaceDistribution(
                range: zone.range,
                count: count,
                percentage: percentage,
                color: zone.color,
                zoneLabel: zone.label
            )
        }
        paceCache = result
        return result
    }

    var distanceDistributionData: [DistanceDistribution] {
        if let distanceCache { return distanceCache }
        let measured = filteredWorkouts.filter { ($0.distance ?? 0).isFinite && ($0.distance ?? 0) > 0 }
        guard !measured.isEmpty else { return [] }
        let total = Double(measured.count)

        struct Bucket {
            let label: String
            let min: Double
            let max: Double
            let isMarathon: Bool
        }

        func label(_ km: Double) -> String {
            Formatters.decimal(
                Formatters.distanceValue(km: km), fractionDigits: UnitPreference.current.usesImperial ? 1 : 0)
        }
        let unit = Formatters.distanceUnitLabel()
        let buckets: [Bucket] = [
            Bucket(label: "< \(label(5)) \(unit)", min: 0, max: 5000, isMarathon: false),
            Bucket(label: "\(label(5))–\(label(10)) \(unit)", min: 5000, max: 10000, isMarathon: false),
            Bucket(label: "\(label(10))–\(label(15)) \(unit)", min: 10000, max: 15000, isMarathon: false),
            Bucket(label: "\(label(15))–\(label(20)) \(unit)", min: 15000, max: 20000, isMarathon: false),
            Bucket(label: "≥ \(label(20)) \(unit)", min: 20000, max: .infinity, isMarathon: false),
        ]

        let result = buckets.map { bucket in
            let matched = measured.filter { workout in
                guard let distance = workout.distance else { return false }
                return distance >= bucket.min && distance < bucket.max
            }
            let count = matched.count
            let percentage = (Double(count) / total) * 100
            let totalKm = matched.compactMap { $0.distance }.reduce(0, +) / 1000.0
            return DistanceDistribution(
                category: bucket.label,
                count: count,
                percentage: percentage,
                totalKm: totalKm,
                isMarathon: bucket.isMarathon
            )
        }
        distanceCache = result
        return result
    }

    // MARK: - Progression Loading

    func cancelProgressionLoading() {
        progressionRequestID = UUID()
        progressionTask?.cancel()
        isLoadingProgression = false
    }

    func loadProgressionMetrics() {
        let selected = filteredWorkouts.sorted { $0.startDate < $1.startDate }
        let ids = selected.map(\.id)
        if isLoadingProgression && progressionSelection == ids { return }
        let previousTask = progressionTask
        cancelProgressionLoading()
        progressionSelection = ids
        progressionData = selected.map { progressionCache[$0.id] ?? Self.baseProgression(for: $0) }
        progressionLoadingProgress = 0
        if usesDemoProgression {
            let demo = Dictionary(uniqueKeysWithValues: MockData.sampleProgressionData.map { ($0.workoutId, $0) })
            progressionData = selected.map { demo[$0.id] ?? Self.baseProgression(for: $0) }
            return
        }
        let uncached = selected.reversed().filter { progressionCache[$0.id] == nil }
        guard !uncached.isEmpty else { return }
        let requestID = progressionRequestID
        isLoadingProgression = true
        progressionWorkerID = requestID
        progressionTask = Task {
            defer {
                if progressionRequestID == requestID { isLoadingProgression = false }
                if progressionWorkerID == requestID { progressionTask = nil }
            }
            await previousTask?.value
            var loaded = 0
            for start in stride(from: 0, to: uncached.count, by: 4) {
                guard !Task.isCancelled, progressionRequestID == requestID else { return }
                let batch = Array(uncached[start..<min(start + 4, uncached.count)])
                await withTaskGroup(of: ProgressionDataPoint.self) { group in
                    for workout in batch {
                        group.addTask { await self.fetchProgression(workout) }
                    }
                    for await result in group {
                        guard !Task.isCancelled, self.progressionRequestID == requestID else {
                            group.cancelAll()
                            return
                        }
                        self.progressionCache[result.workoutId] = result
                        loaded += 1
                    }
                }
                guard !Task.isCancelled, progressionRequestID == requestID else { return }
                progressionLoadingProgress = Double(loaded) / Double(uncached.count)
                progressionData = selected.map { progressionCache[$0.id] ?? Self.baseProgression(for: $0) }
            }
        }
    }

    static func baseProgression(for workout: WorkoutModel) -> ProgressionDataPoint {
        ProgressionDataPoint(
            workoutId: workout.id, date: workout.startDate, averagePace: workout.averagePace,
            minPace: nil, maxSpeed: nil, averageCadence: nil, strideLength: nil, runningPower: nil,
            vo2Max: nil, groundContactTime: nil, verticalOscillation: nil, walkingAsymmetry: nil,
            doubleSupportPercentage: nil, walkingSpeed: nil, stairDescentSpeed: nil)
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
        var aggregateAverage: Double? = nil

        var chartPoints: [(date: Date, value: Double)] {
            guard points.count > 160 else { return points }
            let size = Int(ceil(Double(points.count) / 40))
            var indices = Set<Int>()
            for start in stride(from: 0, to: points.count, by: size) {
                let end = min(start + size, points.count)
                let range = start..<end
                indices.insert(start)
                indices.insert(end - 1)
                if let low = range.min(by: { points[$0].value < points[$1].value }) { indices.insert(low) }
                if let high = range.max(by: { points[$0].value < points[$1].value }) { indices.insert(high) }
            }
            return indices.sorted().map { points[$0] }
        }

        var average: Double {
            if let aggregateAverage { return aggregateAverage }
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
        if let performanceCache { return performanceCache }
        let data = progressionData
        var series: [MetricSeries] = []
        let averagePace = data.compactMap { point in
            point.averagePace.flatMap { value in value.isFinite && value > 0 ? (point.date, value) : nil }
        }
        if averagePace.count >= 2 {
            series.append(
                MetricSeries(
                    id: "averagePace",
                    name: String(localized: "statistics.kpi.avgPace", defaultValue: "Avg pace"),
                    icon: "figure.run", color: .irPrimaryAccent, unit: "min\(Formatters.paceUnitSuffix())",
                    lowerIsBetter: true, metricInfoKey: nil, points: averagePace,
                    aggregateAverage: snapshot.totals.averagePace))
        }
        let vo2 = data.compactMap { p in p.vo2Max.map { (p.date, $0) } }
        if vo2.count >= 2 {
            series.append(
                MetricSeries(
                    id: "vo2max", name: "VO2 Max",
                    icon: "lungs.fill", color: .red,
                    unit: String(localized: "progression.unit.vo2", defaultValue: "ml/kg/min", comment: "VO2 Max unit"),
                    lowerIsBetter: false, metricInfoKey: "metric.vo2_max", points: vo2
                ))
        }

        let cadence = data.compactMap { p in p.averageCadence.map { (p.date, $0) } }
        if cadence.count >= 2 {
            series.append(
                MetricSeries(
                    id: "cadence",
                    name: String(
                        localized: "progression.metric.cadence", defaultValue: "Avg cadence", comment: "Cadence metric"),
                    icon: "metronome.fill", color: .indigo,
                    unit: String(localized: "progression.unit.spm", defaultValue: "spm", comment: "Steps per minute"),
                    lowerIsBetter: false, metricInfoKey: "metric.avg_cadence", points: cadence
                ))
        }

        let stride = data.compactMap { p in p.strideLength.map { (p.date, $0) } }
        if stride.count >= 2 {
            series.append(
                MetricSeries(
                    id: "stride",
                    name: String(
                        localized: "progression.metric.strideLength", defaultValue: "Stride length",
                        comment: "Stride length metric"),
                    icon: "figure.walk", color: .cyan,
                    unit: String(localized: "progression.unit.m", defaultValue: "m", comment: "Meters unit"),
                    lowerIsBetter: false, metricInfoKey: "metric.stride_length", points: stride
                ))
        }

        let power = data.compactMap { p in p.runningPower.map { (p.date, $0) } }
        if power.count >= 2 {
            series.append(
                MetricSeries(
                    id: "power",
                    name: String(
                        localized: "progression.metric.power", defaultValue: "Power", comment: "Running power metric"),
                    icon: "bolt.circle.fill", color: .orange, unit: "W", lowerIsBetter: false,
                    metricInfoKey: "metric.running_power", points: power
                ))
        }

        performanceCache = series
        return series
    }

    var advancedMetrics: [MetricSeries] {
        if let advancedCache { return advancedCache }
        let data = progressionData
        var series: [MetricSeries] = []

        let gct = data.compactMap { p in p.groundContactTime.map { (p.date, $0) } }
        if gct.count >= 2 {
            series.append(
                MetricSeries(
                    id: "gct",
                    name: String(
                        localized: "progression.metric.groundContactTime", defaultValue: "Ground contact",
                        comment: "Ground contact time metric"),
                    icon: "timer", color: .indigo, unit: "ms", lowerIsBetter: true,
                    metricInfoKey: "metric.ground_contact_time", points: gct
                ))
        }

        let vo = data.compactMap { p in p.verticalOscillation.map { (p.date, $0) } }
        if vo.count >= 2 {
            series.append(
                MetricSeries(
                    id: "vertOsc",
                    name: String(
                        localized: "progression.metric.verticalOscillation", defaultValue: "Vertical osc.",
                        comment: "Vertical oscillation metric"),
                    icon: "arrow.up.and.down", color: .cyan, unit: "cm", lowerIsBetter: true,
                    metricInfoKey: "metric.vertical_oscillation", points: vo
                ))
        }

        advancedCache = series
        return series
    }

    // MARK: - Formatting

    func formatDistance(_ distance: Double) -> String {
        Formatters.distance(km: distance / 1000.0, fractionDigits: 1)
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
        Formatters.paceFromMinutesPerKm(pace)
    }

    func formatConsistencyRate(_ rate: Double) -> String {
        Formatters.percent(min(rate, 100))
    }

    func formatPercentageChange(_ change: Double) -> String {
        Formatters.percent(change, signed: true)
    }

    func formatFrequency(_ frequency: Double) -> String {
        Formatters.decimal(frequency, fractionDigits: 1)
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
            let distance = Double.random(in: 3000...15000)  // 3-15 km
            let pace = Double.random(in: 5.5...7.5)  // 5:30-7:30 min/km
            let duration = (distance / 1000.0) * pace * 60  // Convert to seconds

            return WorkoutModel(
                id: UUID(),
                workoutType: .running,
                startDate: startDate,
                endDate: calendar.date(byAdding: .second, value: Int(duration), to: startDate) ?? startDate,
                duration: duration,
                distance: distance,
                totalEnergyBurned: distance / 1000 * Double.random(in: 50...80),  // 50-80 kcal per km
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
