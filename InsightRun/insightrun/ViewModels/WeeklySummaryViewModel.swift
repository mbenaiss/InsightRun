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
    @Published var longestRunDistance: Double = 0 // meters
    @Published var bestPace: Double? // min/km
    @Published var maxHeartRate: Double?

    /// WHO-adjusted active minutes: vigorous intensity (pace < 6:00/km) counts double
    /// Source: WHO Guidelines on Physical Activity (2020) - 150 min moderate OR 75 min vigorous
    @Published var whoAdjustedMinutes: Double = 0

    /// Distance run on each day of the current week (Mon → Sun, kilometers).
    /// Always 7 entries, 0 for days without a recorded run.
    @Published var dailyRunDistancesKm: [Double] = Array(repeating: 0, count: 7)

    /// Index (0–6) of today inside `dailyRunDistancesKm`, ordered by `Calendar.firstWeekday`.
    @Published var todayIndexInWeek: Int = 0

    // Sleep
    @Published var averageSleepDuration: TimeInterval = 0
    @Published var averageSleepEfficiency: Double = 0
    @Published var averageQualityScore: Int = 0
    @Published var averageDeepPercent: Double = 0
    @Published var averageCorePercent: Double = 0
    @Published var averageRemPercent: Double = 0

    // Recovery
    @Published var averageRecoveryScore: Int?
    @Published var averageHRV: Double?
    @Published var averageRestingHR: Double?
    @Published var averageSpO2: Double?
    @Published var averageRespRate: Double?

    // Daily series (for sparklines, week-long)
    @Published var dailyHRV: [Double] = []
    @Published var dailyRestingHR: [Double] = []
    @Published var dailySpO2: [Double] = []
    @Published var dailyRespRate: [Double] = []

    // Per-metric deltas vs previous week (absolute units)
    @Published var hrvDelta: Double?
    @Published var restingHRDelta: Double?
    @Published var spo2Delta: Double?
    @Published var respRateDelta: Double?

    // Previous-week averages (for strikethrough comparison)
    @Published var prevTotalDistance: Double = 0
    @Published var prevTotalDuration: TimeInterval = 0
    @Published var prevAverageRecoveryScore: Int?
    @Published var prevAverageSleepDuration: TimeInterval = 0
    @Published var prevAverageHRV: Double?

    // Comparison vs previous week
    @Published var distanceChange: Double? // percentage
    @Published var durationChange: Double? // percentage
    @Published var recoveryScoreChange: Int? // absolute
    @Published var sleepDurationChange: TimeInterval? // absolute seconds

    // Coaching (LLM-driven)
    @Published var coachingTLDR: String = ""
    @Published var coachingHighlight: String?
    @Published var coachingDetail: String = ""
    @Published var isCoachingLoading: Bool = false
    @Published var coachingTimestamp: Date?

    // Week dates
    @Published var weekStart: Date = .now
    @Published var weekEnd: Date = .now

    private let loadWorkouts: @MainActor (Date, Date) async throws -> [WorkoutModel]
    private let loadRecovery: @MainActor (Date) async throws -> RecoveryMetrics
    private let loadInsight: @MainActor (WeeklyCoachingService.Snapshot) async throws -> WeeklyCoachingInsight?
    private let calendar = Calendar.current
    // The dashboard card only needs running totals; details and coaching belong to the recap screen.
    private var runningLoadedAt: Date?
    private var detailsLoadedAt: Date?
    private var loadTask: Task<Void, Never>?
    private(set) var selectedDate = Calendar.current.startOfDay(for: Date())

    init(
        loadWorkouts: @escaping @MainActor (Date, Date) async throws -> [WorkoutModel] = {
            try await HealthKitManager.shared.fetchRunningWorkouts(from: $0, to: $1)
        },
        loadRecovery: @escaping @MainActor (Date) async throws -> RecoveryMetrics = {
            try await MetricTrendDataService.shared.recoveryMetrics(for: $0)
        },
        loadInsight: @escaping @MainActor (WeeklyCoachingService.Snapshot) async throws -> WeeklyCoachingInsight? = {
            try await WeeklyCoachingService.shared.insight(for: $0)
        }
    ) {
        self.loadWorkouts = loadWorkouts
        self.loadRecovery = loadRecovery
        self.loadInsight = loadInsight
    }

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
        Formatters.distance(km: totalDistance / 1000.0, fractionDigits: 1)
    }

    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) / 60 % 60
        let h = String(localized: "h", comment: "Unit abbreviation for hours in duration")
        let m = String(localized: "m", comment: "Unit abbreviation for minutes in duration")
        if hours > 0 {
            return "\(hours)\(h) \(String(format: "%02d", minutes))\(m)"
        }
        return "\(minutes)\(m)"
    }

    var formattedAveragePace: String {
        guard let pace = averagePace, pace.isFinite else { return "--" }
        return Formatters.paceFromMinutesPerKm(pace)
    }

    var formattedLongestRun: String {
        Formatters.distance(km: longestRunDistance / 1000.0, fractionDigits: 1)
    }

    var formattedBestPace: String {
        guard let pace = bestPace, pace.isFinite else { return "--" }
        return Formatters.paceFromMinutesPerKm(pace)
    }

    var formattedAverageSleep: String {
        let hours = Int(averageSleepDuration) / 3600
        let minutes = Int(averageSleepDuration) / 60 % 60
        return String(format: "%dh%02d", hours, minutes)
    }

    func load(for date: Date? = nil, forceCoachingRefresh: Bool = false, minimumRefreshInterval: TimeInterval = 0, includeCoaching: Bool = true, includeDetails: Bool = true) async {
        if let loadTask { await loadTask.value }
        guard !Task.isCancelled else { return }
        let targetDate = Calendar.current.startOfDay(for: date ?? selectedDate)
        let task = Task { await self.performLoad(for: targetDate, forceCoachingRefresh: forceCoachingRefresh,
                                               minimumRefreshInterval: minimumRefreshInterval,
                                               includeCoaching: includeCoaching, includeDetails: includeDetails) }
        loadTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        loadTask = nil
    }

    private func performLoad(for date: Date, forceCoachingRefresh: Bool, minimumRefreshInterval: TimeInterval, includeCoaching: Bool, includeDetails: Bool) async {
        if selectedDate != date {
            runningLoadedAt = nil
            detailsLoadedAt = nil
            resetDetails()
            resetCoaching()
        }
        selectedDate = date
        let reuseRunning = isRecent(runningLoadedAt, within: minimumRefreshInterval)
        let reuseDetails = reuseRunning && !forceCoachingRefresh && isRecent(detailsLoadedAt, within: minimumRefreshInterval)
        if reuseRunning, !includeDetails || reuseDetails {
            return
        }
        #if DEBUG
        DashboardDiagnostics.record(includeDetails ? "weekly.details" : "weekly.card", date: date)
        #endif
        isLoading = includeDetails || runningLoadedAt == nil
        defer { isLoading = false }
        errorMessage = nil

        let now = min(Date(), calendar.date(byAdding: .day, value: 1, to: date)!.addingTimeInterval(-0.001))
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        weekStart = startOfWeek
        weekEnd = now

        let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek)!

        do {
            // Fetch current week running workouts
            if !reuseRunning {
                let workouts = try await loadWorkouts(startOfWeek, now)
                try Task.checkCancellation()
                aggregateRunning(workouts)
                runningLoadedAt = Date()
                // Comparisons derive from the running totals, so the recap reloads them on its next load.
                detailsLoadedAt = nil
            }
            guard includeDetails else { return }
            resetDetails()

            // Fetch previous week for comparison
            let comparisonEnd = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
            let prevWorkouts = try await loadWorkouts(prevWeekStart, comparisonEnd)
            try Task.checkCancellation()
            computeRunningComparison(previous: prevWorkouts)

            // Fetch recovery metrics for each day
            await loadRecoveryData(from: startOfWeek, to: now, prevStart: prevWeekStart, prevEnd: comparisonEnd)
            try Task.checkCancellation()
            detailsLoadedAt = Date()
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isLoading = false

        if includeCoaching && !Task.isCancelled { await loadCoaching(forceRefresh: forceCoachingRefresh) }
    }

    private func resetDetails() {
        averageSleepDuration = 0
        averageSleepEfficiency = 0
        averageQualityScore = 0
        averageDeepPercent = 0
        averageCorePercent = 0
        averageRemPercent = 0
        prevAverageSleepDuration = 0
        averageRecoveryScore = nil
        prevAverageRecoveryScore = nil
        averageHRV = nil
        averageRestingHR = nil
        averageSpO2 = nil
        averageRespRate = nil
        prevAverageHRV = nil
        hrvDelta = nil
        restingHRDelta = nil
        spo2Delta = nil
        respRateDelta = nil
        distanceChange = nil
        durationChange = nil
        recoveryScoreChange = nil
        sleepDurationChange = nil
        dailyHRV = []
        dailyRestingHR = []
        dailySpO2 = []
        dailyRespRate = []
    }

    private func resetCoaching() {
        coachingTimestamp = nil
        coachingTLDR = ""
        coachingDetail = ""
        coachingHighlight = nil
    }

    private func isRecent(_ loadedAt: Date?, within interval: TimeInterval) -> Bool {
        guard let loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) < interval && calendar.isDateInToday(loadedAt)
    }

    // MARK: - Coaching

    func loadCoachingIfNeeded() async {
        guard detailsLoadedAt != nil, !isCoachingLoading, coachingTimestamp == nil else { return }
        await loadCoaching(forceRefresh: false)
    }

    private func loadCoaching(forceRefresh: Bool) async {
        guard !isCoachingLoading else { return }
        let language = AppLanguage.current
        if forceRefresh {
            WeeklyCoachingService.shared.invalidateCache(weekStart: weekStart, language: language)
        }

        isCoachingLoading = true
        defer { isCoachingLoading = false }

        let snapshot = WeeklyCoachingService.Snapshot(
            weekStart: weekStart,
            weekEnd: weekEnd,
            language: language,
            runCount: runCount,
            totalDistanceKm: totalDistance / 1000.0,
            totalDurationMin: Int(totalDuration / 60),
            averagePaceMinPerKm: averagePace,
            prevTotalDistanceKm: prevTotalDistance / 1000.0,
            prevTotalDurationMin: Int(prevTotalDuration / 60),
            averageRecoveryScore: averageRecoveryScore,
            recoveryScoreChange: recoveryScoreChange,
            averageHRV: averageHRV,
            hrvDelta: hrvDelta,
            averageRestingHR: averageRestingHR,
            restingHRDelta: restingHRDelta,
            averageSleepHours: averageSleepDuration > 0 ? averageSleepDuration / 3600.0 : nil,
            sleepDurationChangeMinutes: sleepDurationChange.map { Int($0 / 60) },
            averageSleepEfficiency: averageSleepEfficiency > 0 ? averageSleepEfficiency : nil
        )

        do {
            if let insight = try await loadInsight(snapshot) {
                coachingTLDR = insight.tldr
                coachingHighlight = insight.highlight
                coachingDetail = insight.detail
                coachingTimestamp = Date()
            } else {
                // No consent yet — keep the local fallback so the card still appears.
                applyLocalCoachingFallback()
            }
        } catch {
            applyLocalCoachingFallback()
        }
    }

    private func applyLocalCoachingFallback() {
        coachingTLDR = coachingInsight ?? String(
            localized: "recovery.insufficient_data",
            defaultValue: "Not enough health data to assess your recovery yet."
        )
        coachingHighlight = nil
        coachingDetail = ""
        coachingTimestamp = Date()
    }

    /// Reasons rendered as chips in the expanded coach card. Always derived locally
    /// from the deltas so the figures stay consistent with what the user sees.
    var coachingReasons: [String] {
        var reasons: [String] = []
        if let recDelta = recoveryScoreChange {
            let label = String(localized: "Recovery", comment: "Coaching chip: recovery")
            reasons.append("\(label) \(formatSignedInt(recDelta))")
        }
        if let hrv = hrvDelta {
            let label = String(localized: "HRV", comment: "Coaching chip: HRV")
            reasons.append("\(label) \(formatSignedInt(Int(hrv.rounded())))")
        }
        if let rhr = restingHRDelta {
            let label = String(localized: "Resting HR", comment: "Coaching chip: resting HR")
            reasons.append("\(label) \(formatSignedInt(Int(rhr.rounded())))")
        }
        if let sleepDelta = sleepDurationChange {
            let mins = Int(sleepDelta / 60)
            let label = String(localized: "Sleep", comment: "Coaching chip: sleep")
            let unit = String(localized: "min", comment: "Unit abbreviation for minutes")
            reasons.append("\(label) \(formatSignedInt(mins)) \(unit)")
        }
        if let dist = distanceChange {
            let label = String(localized: "Weekly volume", comment: "Coaching chip: weekly running volume")
            reasons.append("\(label) \(Formatters.percent(dist, signed: true))")
        }
        return reasons
    }

    private func formatSignedInt(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    private func aggregateRunning(_ workouts: [WorkoutModel]) {
        runCount = workouts.count
        totalDistance = workouts.compactMap(\.distance).reduce(0, +)
        totalDuration = workouts.map(\.duration).reduce(0, +)
        totalCalories = workouts.compactMap(\.totalEnergyBurned).reduce(0, +)
        totalElevation = workouts.compactMap(\.elevationGain).reduce(0, +)

        let heartRates = workouts.compactMap(\.averageHeartRate)
        averageHeartRate = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count)

        let maxHRs = workouts.compactMap(\.maxHeartRate)
        maxHeartRate = maxHRs.max()

        longestRunDistance = workouts.compactMap(\.distance).max() ?? 0

        let paces: [Double] = workouts.compactMap { w in
            guard let dist = w.distance, dist > 0 else { return nil }
            let pace = (w.duration / 60.0) / (dist / 1000.0)
            return pace.isFinite ? pace : nil
        }
        bestPace = paces.min()

        averagePace = Formatters.averagePaceValue(totalDurationSeconds: totalDuration, totalDistanceKm: totalDistance / 1000.0)
            .map { $0 / 60.0 }

        // WHO-adjusted minutes: vigorous intensity counts double
        // WHO (2020): 150 min moderate-intensity OR 75 min vigorous-intensity per week
        // Vigorous threshold: pace < 6:00/km (Garmin/Polar convention)
        whoAdjustedMinutes = workouts.reduce(0.0) { total, workout in
            let minutes = workout.duration / 60.0
            guard let dist = workout.distance, dist > 0 else { return total + minutes }
            let paceMinPerKm = (workout.duration / 60.0) / (dist / 1000.0)
            let isVigorous = paceMinPerKm.isFinite && paceMinPerKm < 6.0
            return total + (isVigorous ? minutes * 2.0 : minutes)
        }

        let bucketed = bucketRunsByDayOfWeek(workouts)
        dailyRunDistancesKm = bucketed
        todayIndexInWeek = dayIndexInWeek(for: selectedDate)
    }

    /// Returns 7 distances (km) ordered Mon→Sun (or per `calendar.firstWeekday`),
    /// summing all running workouts that started on each weekday.
    private func bucketRunsByDayOfWeek(_ workouts: [WorkoutModel]) -> [Double] {
        var buckets = Array(repeating: 0.0, count: 7)
        for workout in workouts {
            guard let distance = workout.distance else { continue }
            let idx = dayIndexInWeek(for: workout.startDate)
            buckets[idx] += distance / 1000.0
        }
        return buckets
    }

    private func dayIndexInWeek(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        // weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday.
        // Map so position 0 corresponds to `calendar.firstWeekday`.
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func computeRunningComparison(previous: [WorkoutModel]) {
        let prevDistance = previous.compactMap(\.distance).reduce(0, +)
        let prevDuration = previous.map(\.duration).reduce(0, +)
        prevTotalDistance = prevDistance
        prevTotalDuration = prevDuration

        if prevDistance > 0 {
            distanceChange = ((totalDistance - prevDistance) / prevDistance) * 100
        }
        if prevDuration > 0 {
            durationChange = ((totalDuration - prevDuration) / prevDuration) * 100
        }
    }

    private func aggregateSleep(_ sleepHistory: [SleepData], previous prevSleep: [SleepData]) {
        if !prevSleep.isEmpty {
            prevAverageSleepDuration = prevSleep.map(\.totalSleepDuration).reduce(0, +) / Double(prevSleep.count)
        }

        guard !sleepHistory.isEmpty else { return }

        let count = Double(sleepHistory.count)
        averageSleepDuration = sleepHistory.map(\.totalSleepDuration).reduce(0, +) / count
        averageSleepEfficiency = sleepHistory.map(\.sleepEfficiency).reduce(0, +) / count
        averageQualityScore = Int(sleepHistory.map { Double($0.qualityScore) }.reduce(0, +) / count)

        if averageSleepDuration > 0 && prevAverageSleepDuration > 0 {
            sleepDurationChange = averageSleepDuration - prevAverageSleepDuration
        }

        let withStages = sleepHistory.filter { $0.deepSleepDuration != nil && $0.totalSleepDuration > 0 }
        if !withStages.isEmpty {
            let stageCount = Double(withStages.count)
            averageDeepPercent = withStages.map { ($0.deepSleepDuration! / $0.totalSleepDuration) * 100 }.reduce(0, +) / stageCount
            let coreValues = withStages.compactMap { s in
                s.coreSleepDuration.map { ($0 / s.totalSleepDuration) * 100 }
            }
            if !coreValues.isEmpty {
                averageCorePercent = coreValues.reduce(0, +) / Double(coreValues.count)
            }
            let remValues = withStages.compactMap { s in
                s.remSleepDuration.map { ($0 / s.totalSleepDuration) * 100 }
            }
            if !remValues.isEmpty {
                averageRemPercent = remValues.reduce(0, +) / Double(remValues.count)
            }
        }
    }

    private func loadRecoveryData(from start: Date, to end: Date, prevStart: Date, prevEnd: Date) async {
        var scores: [Int] = []
        var currentMetrics: [RecoveryMetrics] = []

        var currentDate = start
        while currentDate < end {
            guard !Task.isCancelled else { return }
            if let metrics = try? await loadRecovery(currentDate) {
                if metrics.hasRecoveryMeasurements() {
                    scores.append(metrics.recoveryScore)
                }
                currentMetrics.append(metrics)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        dailyHRV = currentMetrics.compactMap(\.hrvAverage)
        dailyRestingHR = currentMetrics.compactMap(\.restingHeartRate)
        dailySpO2 = currentMetrics.compactMap(\.oxygenSaturation)
        dailyRespRate = currentMetrics.compactMap(\.respiratoryRate)

        if !scores.isEmpty {
            averageRecoveryScore = scores.reduce(0, +) / scores.count
        }
        averageHRV = dailyHRV.isEmpty ? nil : dailyHRV.reduce(0, +) / Double(dailyHRV.count)
        averageRestingHR = dailyRestingHR.isEmpty ? nil : dailyRestingHR.reduce(0, +) / Double(dailyRestingHR.count)
        averageSpO2 = dailySpO2.isEmpty ? nil : dailySpO2.reduce(0, +) / Double(dailySpO2.count)
        averageRespRate = dailyRespRate.isEmpty ? nil : dailyRespRate.reduce(0, +) / Double(dailyRespRate.count)

        // Previous week recovery for comparison
        var previousMetrics: [RecoveryMetrics] = []
        var prevScores: [Int] = []
        var prevHRV: [Double] = []
        var prevRHR: [Double] = []
        var prevSpO2: [Double] = []
        var prevResp: [Double] = []

        var prevDate = prevStart
        while prevDate < prevEnd {
            guard !Task.isCancelled else { return }
            if let metrics = try? await loadRecovery(prevDate) {
                previousMetrics.append(metrics)
                if metrics.hasRecoveryMeasurements() {
                    prevScores.append(metrics.recoveryScore)
                }
                if let hrv = metrics.hrvAverage { prevHRV.append(hrv) }
                if let rhr = metrics.restingHeartRate { prevRHR.append(rhr) }
                if let spo2 = metrics.oxygenSaturation { prevSpO2.append(spo2) }
                if let resp = metrics.respiratoryRate { prevResp.append(resp) }
            }
            prevDate = calendar.date(byAdding: .day, value: 1, to: prevDate)!
        }

        aggregateSleep(currentMetrics.compactMap(\.sleepData), previous: previousMetrics.compactMap(\.sleepData))

        if let averageRecoveryScore, !prevScores.isEmpty {
            let prevAvg = prevScores.reduce(0, +) / prevScores.count
            prevAverageRecoveryScore = prevAvg
            recoveryScoreChange = averageRecoveryScore - prevAvg
        }

        if let avg = averageHRV, !prevHRV.isEmpty {
            let p = prevHRV.reduce(0, +) / Double(prevHRV.count)
            prevAverageHRV = p
            hrvDelta = avg - p
        }
        if let avg = averageRestingHR, !prevRHR.isEmpty {
            restingHRDelta = avg - prevRHR.reduce(0, +) / Double(prevRHR.count)
        }
        if let avg = averageSpO2, !prevSpO2.isEmpty {
            spo2Delta = avg - prevSpO2.reduce(0, +) / Double(prevSpO2.count)
        }
        if let avg = averageRespRate, !prevResp.isEmpty {
            respRateDelta = avg - prevResp.reduce(0, +) / Double(prevResp.count)
        }
    }

    /// Generates a coaching insight based on the week-over-week deltas.
    /// Returns nil when no signal worth reporting.
    var coachingInsight: String? {
        // Big drop in recovery → focus on sleep & load
        if let rec = recoveryScoreChange, rec <= -5 {
            if let sleepDelta = sleepDurationChange, sleepDelta < -15 * 60 {
                let minutesShort = Int(abs(sleepDelta) / 60)
                return String(
                    format: String(localized: "Recovery is down this week. Sleep is short by %d min on average — aim for a long night before your next run.", comment: "Weekly coaching insight: low recovery + short sleep"),
                    minutesShort
                )
            }
            return String(localized: "Recovery is down this week. Take it easy and prioritise sleep and hydration.", comment: "Weekly coaching insight: low recovery")
        }
        // Strong improvement
        if let rec = recoveryScoreChange, rec >= 5 {
            return String(localized: "Nice progression this week. Keep this rhythm and stay consistent on sleep.", comment: "Weekly coaching insight: high recovery")
        }
        // Stable but volume changed sharply
        if let dist = distanceChange, dist <= -50, totalDistance < 1 {
            return String(localized: "No run logged this week. Schedule a short easy session to keep momentum.", comment: "Weekly coaching insight: no runs")
        }
        if let dist = distanceChange, dist >= 30 {
            return String(localized: "Volume is up significantly. Watch fatigue indicators and plan an easy day.", comment: "Weekly coaching insight: high volume jump")
        }
        // Default: only show insight when there's enough data
        if averageRecoveryScore == nil {
            return nil
        }
        return String(localized: "Recovery is stable this week. Maintain your rhythm.", comment: "Weekly coaching insight: stable recovery")
    }
}
