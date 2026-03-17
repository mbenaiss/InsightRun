//
//  TrainingLoadService.swift
//  InsightRun
//
//  Service for tracking training load, detecting overtraining risk,
//  and monitoring inactivity periods for proactive coaching
//

import Foundation
import Combine
import SwiftUI
import HealthKit

@MainActor
final class TrainingLoadService: ObservableObject {
    static let shared = TrainingLoadService()

    @Published var weeklyVolumeChange: Double?
    @Published var daysSinceLastWorkout: Int?
    @Published var isOvertrainingRisk: Bool = false
    @Published var isInactive: Bool = false

    @Published var dailyEffortScore: Int = 0

    @Published var cardiacLoadScore: Int?
    @Published var cardiacLoadStatus: CardiacLoadStatus = .detraining
    @Published var cardiacLoadTrendData: [TrendDataPoint] = []
    @Published var acwr: Double?

    private let healthKitManager = HealthKitManager.shared
    private let volumeIncreaseThreshold = 10.0 // 10% increase triggers warning
    private let inactivityThreshold = 4 // 4+ days without workout

    /// Daily effort scoring fallback targets (used when Apple Ring goals are unavailable)
    /// Sources:
    /// - Steps: Tudor-Locke C, Bassett DR (2004). "How many steps/day are enough?" Sports Med 34(1):1-8.
    ///   10,000 steps/day as public health target for "active" classification.
    /// - Active calories: Ainsworth BE et al. (2011). Compendium of Physical Activities. Med Sci Sports Exerc.
    ///   ~400 kcal/day active energy for moderately active adult.
    /// - Exercise minutes: WHO (2020). 150 min/week moderate activity ≈ 30 min/day as daily target.
    ///   Apple Exercise Ring uses elevated HR to count exercise minutes.
    private let stepsTarget: Double = 10_000
    private let defaultActiveCaloriesTarget: Double = 400
    private let defaultExerciseMinutesTarget: Double = 30

    /// Lookback: 49 days = 42 (CTL seed) + 7 (ATL seed)
    private let lookbackDays: Int = 49

    /// Trend: 14 days of ATL history for the chart
    private let trendDays: Int = 14

    /// TRIMP gender weighting — Banister (1991), Morton et al. (1990)
    /// Male:   weight = 0.64 × e^(1.92 × ΔHR)
    /// Female: weight = 0.86 × e^(1.67 × ΔHR)
    private let trimpMaleA: Double = 0.64
    private let trimpMaleB: Double = 1.92
    private let trimpFemaleA: Double = 0.86
    private let trimpFemaleB: Double = 1.67

    /// Default max HR (Fox formula fallback for ~30 years old)
    private let defaultMaxHR: Double = 190
    /// Default resting HR (AHA normal range, fit adult estimate)
    private let defaultRestingHR: Double = 65

    /// ACWR thresholds — Gabbett (2016), Hulin et al. (2016)
    private let acwrDetrainingThreshold: Double = 0.5
    private let acwrDecreasingThreshold: Double = 0.8
    private let acwrMaintainingUpperThreshold: Double = 1.3

    /// Max score for display
    private let maxScore: Double = 20

    /// Minimum CTL threshold for personalized normalization
    /// Below this, CTL is unreliable (new user < 6 weeks) -> fixed fallback
    /// Source: Impellizzeri et al. (2019) — individualized load monitoring requires stable CTL
    /// Source: Windt & Gabbett (2017) — CTL as personal denominator for load evaluation
    private let minCTLForNormalization: Double = 10

    /// Fixed fallback normalization for new users (CTL < 10)
    /// Used only during first ~6 weeks until CTL stabilizes
    private let fallbackATLNormalization: Double = 80

    private init() {}

    // MARK: - Training Load Analysis

    /// Analyze training load and detect potential issues
    func analyzeTrainingLoad() async {
        async let volumeTask: () = calculateWeeklyVolumeChange()
        async let inactivityTask: () = checkInactivity()

        await volumeTask
        await inactivityTask

        // Update risk flags
        isOvertrainingRisk = (weeklyVolumeChange ?? 0) > volumeIncreaseThreshold
        isInactive = (daysSinceLastWorkout ?? 0) >= inactivityThreshold
    }

    /// Calculate weekly volume change vs previous week
    private func calculateWeeklyVolumeChange() async {
        do {
            let calendar = Calendar.current
            let today = Date()

            // This week's range (Monday to today)
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return }
            let thisWeekWorkouts = try await healthKitManager.fetchRunningWorkouts(from: weekStart, to: today)
            let thisWeekVolume = thisWeekWorkouts.compactMap { $0.distance }.reduce(0, +)

            // Previous week's range (same days of the week for fair comparison)
            guard let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else { return }
            let daysIntoWeek = calendar.component(.weekday, from: today) - calendar.component(.weekday, from: weekStart)
            guard let prevWeekEnd = calendar.date(byAdding: .day, value: daysIntoWeek, to: prevWeekStart) else { return }
            let prevWeekWorkouts = try await healthKitManager.fetchRunningWorkouts(from: prevWeekStart, to: prevWeekEnd)
            let prevWeekVolume = prevWeekWorkouts.compactMap { $0.distance }.reduce(0, +)

            // Calculate percentage change
            if prevWeekVolume > 0 {
                weeklyVolumeChange = ((thisWeekVolume - prevWeekVolume) / prevWeekVolume) * 100
            } else if thisWeekVolume > 0 {
                weeklyVolumeChange = 100 // First week with activity
            } else {
                weeklyVolumeChange = 0
            }

            print("📊 TrainingLoadService: This week: \(thisWeekVolume / 1000)km, Last week: \(prevWeekVolume / 1000)km, Change: \(weeklyVolumeChange ?? 0)%")
        } catch {
            print("⚠️ TrainingLoadService: Failed to calculate volume change: \(error)")
            weeklyVolumeChange = nil
        }
    }

    /// Check days since last workout
    private func checkInactivity() async {
        do {
            let calendar = Calendar.current
            guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) else { return }
            let workouts = try await healthKitManager.fetchRunningWorkouts(from: thirtyDaysAgo, to: Date())

            if let lastWorkout = workouts.first {
                let days = calendar.dateComponents([.day], from: lastWorkout.startDate, to: Date()).day ?? 0
                daysSinceLastWorkout = days
            } else {
                daysSinceLastWorkout = 30 // No workouts in last 30 days
            }

            print("📊 TrainingLoadService: Days since last workout: \(daysSinceLastWorkout ?? 0)")
        } catch {
            print("⚠️ TrainingLoadService: Failed to check inactivity: \(error)")
            daysSinceLastWorkout = nil
        }
    }

    // MARK: - Daily Effort

    /// Calculate daily effort score from all-day activity: steps, active calories, exercise minutes (HR zones)
    /// Weighted composite: steps 30%, active calories 35%, exercise minutes 35%
    /// Uses personal Apple Ring goals when available, fixed fallbacks otherwise
    func analyzeDailyEffort(for date: Date) async {
        let activity = await healthKitManager.fetchDailyActivityData(for: date)

        let caloriesTarget = activity.activeCaloriesGoal ?? defaultActiveCaloriesTarget
        let exerciseTarget = activity.exerciseMinutesGoal ?? defaultExerciseMinutesTarget

        let stepsScore = min(activity.steps / stepsTarget, 1.0)
        let caloriesScore = min(activity.activeCalories / caloriesTarget, 1.0)
        let exerciseScore = min(activity.exerciseMinutes / exerciseTarget, 1.0)

        let composite = stepsScore * 0.30 + caloriesScore * 0.35 + exerciseScore * 0.35
        dailyEffortScore = min(100, Int((composite * 100).rounded()))
    }

    // MARK: - Cardiac Load Analysis (TRIMP + EWMA ATL/CTL + ACWR)

    /// Banister TRIMP-based cardiac load with EWMA ATL (τ=7) / CTL (τ=42) and ACWR
    /// Sources:
    /// - Banister EW (1991). "Modeling elite athletic performance." TRIMP = duration × ΔHR × weight(ΔHR)
    /// - Williams S et al. (2017). EWMA-based ACWR superior to rolling averages. ATL α=2/8, CTL α=2/43.
    /// - Gabbett TJ (2016). ACWR sweet spot 0.8-1.3 for injury prevention.
    /// - Hulin BT et al. (2016). Validated ACWR thresholds in elite athletes.
    func analyzeCardiacLoad() async {
        do {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            guard let startDate = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return }

            let workouts = try await healthKitManager.fetchRunningWorkouts(from: startDate, to: Date())

            // Fetch resting HR from personal baseline (fallback: 65 bpm)
            let baseline = PersonalBaselineStorage.shared.load()
            let restingHR = baseline?.restingHeartRateAverage ?? defaultRestingHR

            // Fetch age/sex for max HR and TRIMP gender weighting
            let biologicalSex: HKBiologicalSex?
            let maxHR: Double
            do {
                let profile = try await healthKitManager.fetchHealthProfile()
                biologicalSex = profile.biologicalSex
                if let age = profile.age, age > 0 {
                    maxHR = 220.0 - Double(age) // Fox formula
                } else {
                    maxHR = defaultMaxHR
                }
            } catch {
                biologicalSex = nil
                maxHR = defaultMaxHR
            }

            // Build daily load map for lookback period
            var dailyLoad: [Date: Double] = [:]
            for dayOffset in (-lookbackDays + 1)...0 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
                dailyLoad[calendar.startOfDay(for: day)] = 0
            }

            for workout in workouts {
                let day = calendar.startOfDay(for: workout.startDate)
                dailyLoad[day, default: 0] += workoutLoad(
                    workout: workout,
                    restingHR: restingHR,
                    maxHR: maxHR,
                    biologicalSex: biologicalSex
                )
            }

            // EWMA iteration (chronological order)
            let atlAlpha = 2.0 / (7.0 + 1.0)
            let ctlAlpha = 2.0 / (42.0 + 1.0)
            var atlEWMA: Double = 0
            var ctlEWMA: Double = 0
            var trendPoints: [TrendDataPoint] = []

            let sortedDays = dailyLoad.keys.sorted()
            for day in sortedDays {
                let load = dailyLoad[day] ?? 0
                atlEWMA = atlAlpha * load + (1 - atlAlpha) * atlEWMA
                ctlEWMA = ctlAlpha * load + (1 - ctlAlpha) * ctlEWMA
            }

            // Score: personalized via CTL, or fixed fallback for new users
            // CTL ≥ threshold: score = ATL/CTL × 10 (maintaining = 10/20)
            // CTL < threshold: score = ATL/fallback × 20 (absolute scale)
            let score: Int
            if ctlEWMA >= minCTLForNormalization {
                score = min(Int(maxScore), Int((atlEWMA / ctlEWMA) * 10))
            } else {
                score = min(Int(maxScore), Int((atlEWMA / fallbackATLNormalization) * maxScore))
            }

            // Build trend data (last 14 days, recompute EWMA for each day)
            var trendATL: Double = 0
            var trendCTL: Double = 0
            for day in sortedDays {
                let load = dailyLoad[day] ?? 0
                trendATL = atlAlpha * load + (1 - atlAlpha) * trendATL
                trendCTL = ctlAlpha * load + (1 - ctlAlpha) * trendCTL

                if let daysAgo = calendar.dateComponents([.day], from: day, to: today).day, daysAgo < trendDays {
                    let normalizedValue: Double
                    if trendCTL >= minCTLForNormalization {
                        normalizedValue = min(maxScore, (trendATL / trendCTL) * 10)
                    } else {
                        normalizedValue = min(maxScore, (trendATL / fallbackATLNormalization) * maxScore)
                    }
                    trendPoints.append(TrendDataPoint(date: day, value: normalizedValue))
                }
            }

            // ACWR = ATL / CTL
            let computedACWR: Double?
            if ctlEWMA > 0 {
                computedACWR = atlEWMA / ctlEWMA
            } else {
                computedACWR = nil
            }

            // Status from ACWR thresholds (Gabbett 2016)
            let status: CardiacLoadStatus
            if let ratio = computedACWR {
                if ratio < acwrDetrainingThreshold {
                    status = .detraining
                } else if ratio < acwrDecreasingThreshold {
                    status = .decreasing
                } else if ratio <= acwrMaintainingUpperThreshold {
                    status = .maintaining
                } else {
                    status = .increasing
                }
            } else {
                // CTL = 0 (new user): derive from ATL alone
                status = atlEWMA > 0 ? .increasing : .detraining
            }

            cardiacLoadScore = score
            cardiacLoadStatus = status
            cardiacLoadTrendData = trendPoints
            acwr = computedACWR

            print("📊 TrainingLoadService: ATL=\(String(format: "%.1f", atlEWMA)) CTL=\(String(format: "%.1f", ctlEWMA)) ACWR=\(computedACWR.map { String(format: "%.2f", $0) } ?? "n/a") score=\(score) status=\(status.rawValue)")
        } catch {
            print("⚠️ TrainingLoadService: Failed to analyze cardiac load: \(error)")
            cardiacLoadScore = nil
        }
    }

    // MARK: - TRIMP Calculation

    /// TRIMP when HR available, otherwise fallback to pace-based intensity
    /// Source: Banister (1991) — TRIMP = duration × ΔHR × weight(ΔHR)
    private func workoutLoad(
        workout: WorkoutModel,
        restingHR: Double,
        maxHR: Double,
        biologicalSex: HKBiologicalSex?
    ) -> Double {
        let durationMin = workout.duration / 60.0

        // HR-based TRIMP (primary)
        if let avgHR = workout.averageHeartRate, avgHR > 0, maxHR > restingHR {
            let deltaHR = max(0, min(1.0, (avgHR - restingHR) / (maxHR - restingHR)))
            let (a, b): (Double, Double) = (biologicalSex == .female)
                ? (trimpFemaleA, trimpFemaleB)
                : (trimpMaleA, trimpMaleB)
            return durationMin * deltaHR * a * exp(b * deltaHR)
        }

        // Fallback: pace-based
        return durationMin * intensityFactor(for: workout)
    }

    /// Pace-based intensity factor mapping
    /// Zone model: Seiler S, Kjerland GØ (2006). "Quantifying training intensity distribution
    /// in elite endurance athletes." Scand J Med Sci Sports 16(1):49-56.
    /// Calorie fallback: Ainsworth BE et al. (2011). "Compendium of Physical Activities." Med Sci Sports Exerc.
    private func intensityFactor(for workout: WorkoutModel) -> Double {
        if let distance = workout.distance, distance > 0 {
            let paceMinPerKm = (workout.duration / 60.0) / (distance / 1000.0)
            switch paceMinPerKm {
            case ..<4.0: return 1.8
            case 4.0..<4.5: return 1.6
            case 4.5..<5.0: return 1.4
            case 5.0..<5.5: return 1.2
            case 5.5..<6.0: return 1.0
            case 6.0..<7.0: return 0.8
            default: return 0.6
            }
        }

        if let kcal = workout.totalEnergyBurned, workout.duration > 0 {
            let calPerMin = kcal / (workout.duration / 60.0)
            switch calPerMin {
            case 15...: return 1.6
            case 12..<15: return 1.3
            case 9..<12: return 1.0
            case 6..<9: return 0.8
            default: return 0.6
            }
        }

        return 1.0
    }

    // MARK: - Training Status

    /// Get current training status for display
    var trainingStatus: TrainingStatus {
        if isOvertrainingRisk {
            return .overtraining
        } else if isInactive {
            return .inactive
        } else {
            return .normal
        }
    }

    /// Get recommended action based on current status
    var recommendedAction: String {
        switch trainingStatus {
        case .overtraining:
            return String(
                localized: "Your training volume increased by \(Int(weeklyVolumeChange ?? 0))% this week. Consider reducing intensity to prevent injury.",
                comment: "Overtraining warning recommendation"
            )
        case .inactive:
            return String(
                localized: "You haven't run in \(daysSinceLastWorkout ?? 4) days. A light jog could help maintain your fitness.",
                comment: "Inactivity reminder recommendation"
            )
        case .normal:
            return String(
                localized: "Your training load is well balanced. Keep up the good work!",
                comment: "Normal training status message"
            )
        }
    }
}

// MARK: - Training Status Enum

enum TrainingStatus {
    case normal
    case overtraining
    case inactive

    var emoji: String {
        switch self {
        case .normal: return "✅"
        case .overtraining: return "⚠️"
        case .inactive: return "💤"
        }
    }

    var title: String {
        switch self {
        case .normal:
            return String(localized: "On Track", comment: "Training status - normal")
        case .overtraining:
            return String(localized: "High Load", comment: "Training status - overtraining risk")
        case .inactive:
            return String(localized: "Time to Run", comment: "Training status - inactive")
        }
    }

    var color: String {
        switch self {
        case .normal: return "green"
        case .overtraining: return "orange"
        case .inactive: return "blue"
        }
    }
}

// MARK: - Cardiac Load Status Enum

enum CardiacLoadStatus: String {
    case increasing
    case maintaining
    case decreasing
    case detraining

    var title: String {
        switch self {
        case .increasing:
            return String(localized: "Increasing", comment: "Cardiac load status - increasing")
        case .maintaining:
            return String(localized: "Maintaining", comment: "Cardiac load status - maintaining")
        case .decreasing:
            return String(localized: "Decreasing", comment: "Cardiac load status - decreasing")
        case .detraining:
            return String(localized: "Detraining", comment: "Cardiac load status - detraining")
        }
    }

    var color: Color {
        switch self {
        case .increasing: return .orange
        case .maintaining: return .purple
        case .decreasing: return .blue
        case .detraining: return .red
        }
    }

    var icon: String {
        switch self {
        case .increasing: return "arrow.up.right"
        case .maintaining: return "arrow.right"
        case .decreasing: return "arrow.down.right"
        case .detraining: return "arrow.down"
        }
    }
}
