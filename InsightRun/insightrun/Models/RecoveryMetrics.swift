//
//  RecoveryMetrics.swift
//  InsightRun
//
//  Model for recovery and readiness metrics
//

import Foundation

struct RecoveryMetrics: Identifiable {
    let id = UUID()
    let date: Date

    // Heart Rate Metrics
    let restingHeartRate: Double?
    let hrv: Double? // Heart Rate Variability (SDNN)
    let walkingHeartRate: Double?

    // Sleep Metrics
    let sleepData: SleepData?

    // Respiratory
    let respiratoryRate: Double?

    // Computed recovery score (0-100)
    var recoveryScore: Int {
        calculateRecoveryScore()
    }

    var recoveryStatus: RecoveryStatus {
        switch recoveryScore {
        case 80...100:
            return .excellent
        case 60..<80:
            return .good
        case 40..<60:
            return .fair
        default:
            return .poor
        }
    }

    private func calculateRecoveryScore() -> Int {
        var totalScore = 0.0
        var totalWeight = 0.0

        // Weight configuration (based on scientific literature on recovery metrics)
        let hrvWeight = 0.30      // 30% - Key recovery indicator
        let sleepWeight = 0.35    // 35% - Most important recovery factor
        let rhrWeight = 0.20      // 20% - Good cardiovascular indicator
        let walkingHRWeight = 0.08 // 8% - Additional cardiovascular metric
        let respRateWeight = 0.07  // 7% - Stress/recovery indicator

        // HRV Score (higher is better, typical range: 20-100ms)
        if let hrv = hrv {
            let hrvScore = calculateHRVScore(hrv)
            totalScore += hrvScore * hrvWeight
            totalWeight += hrvWeight
        }

        // Sleep Score (combination of duration and efficiency)
        if let sleep = sleepData {
            let sleepScore = calculateSleepScore(sleep)
            totalScore += sleepScore * sleepWeight
            totalWeight += sleepWeight
        }

        // Resting HR Score (lower is better, typical range: 40-80 bpm)
        if let rhr = restingHeartRate {
            let rhrScore = calculateRHRScore(rhr)
            totalScore += rhrScore * rhrWeight
            totalWeight += rhrWeight
        }

        // Walking HR Score (lower is better, typical range: 70-110 bpm)
        if let whr = walkingHeartRate {
            let whrScore = calculateWalkingHRScore(whr)
            totalScore += whrScore * walkingHRWeight
            totalWeight += walkingHRWeight
        }

        // Respiratory Rate Score (optimal: 12-16 breaths/min)
        if let respRate = respiratoryRate {
            let respScore = calculateRespiratoryScore(respRate)
            totalScore += respScore * respRateWeight
            totalWeight += respRateWeight
        }

        // Normalize by total weight to handle missing metrics gracefully
        // If no metrics available, default to 50 (neutral score)
        let finalScore = totalWeight > 0 ? (totalScore / totalWeight) * 100 : 50

        return max(0, min(100, Int(finalScore.rounded())))
    }

    // MARK: - Continuous Scoring Helper Methods

    /// Calculate HRV score using linear interpolation
    /// - Parameter hrv: Heart Rate Variability in milliseconds
    /// - Returns: Score from 0.0 to 1.0
    private func calculateHRVScore(_ hrv: Double) -> Double {
        // Linear interpolation: 20ms = 0.0, 100ms = 1.0
        // Values below 20 = 0.0, above 100 = 1.0
        return min(max((hrv - 20) / 80, 0.0), 1.0)
    }

    /// Calculate Resting Heart Rate score using linear interpolation
    /// - Parameter rhr: Resting Heart Rate in bpm
    /// - Returns: Score from 0.0 to 1.0
    private func calculateRHRScore(_ rhr: Double) -> Double {
        // Linear interpolation (inverted): 80bpm = 0.0, 40bpm = 1.0
        // Higher RHR = worse recovery, lower RHR = better recovery
        return min(max((80 - rhr) / 40, 0.0), 1.0)
    }

    /// Calculate sleep score based on duration and efficiency
    /// - Parameter sleep: Sleep data
    /// - Returns: Score from 0.0 to 1.0
    private func calculateSleepScore(_ sleep: SleepData) -> Double {
        let hours = sleep.totalSleepDuration / 3600.0
        let efficiency = sleep.sleepEfficiency / 100.0

        // Duration score: 5h = 0.0, 9h = 1.0, with penalty for oversleeping
        var durationScore: Double
        if hours < 5 {
            durationScore = 0.0
        } else if hours <= 9 {
            durationScore = (hours - 5) / 4
        } else if hours <= 10 {
            durationScore = 1.0
        } else {
            // Slight penalty for excessive sleep (possible fatigue indicator)
            durationScore = max(0.7, 1.0 - (hours - 10) * 0.1)
        }

        // Efficiency score: 75% = 0.5, 95% = 1.0
        let efficiencyScore = min(max((efficiency - 0.75) / 0.20, 0.0), 1.0)

        // Combine: 70% duration, 30% efficiency
        return durationScore * 0.7 + efficiencyScore * 0.3
    }

    /// Calculate Walking Heart Rate score using linear interpolation
    /// - Parameter whr: Walking Heart Rate in bpm
    /// - Returns: Score from 0.0 to 1.0
    private func calculateWalkingHRScore(_ whr: Double) -> Double {
        // Linear interpolation (inverted): 110bpm = 0.0, 70bpm = 1.0
        // Higher walking HR = worse recovery
        return min(max((110 - whr) / 40, 0.0), 1.0)
    }

    /// Calculate Respiratory Rate score with optimal range
    /// - Parameter rate: Respiratory rate in breaths per minute
    /// - Returns: Score from 0.0 to 1.0
    private func calculateRespiratoryScore(_ rate: Double) -> Double {
        // Optimal range: 12-16 breaths/min
        if rate >= 12 && rate <= 16 {
            return 1.0
        } else if rate < 12 {
            // Below optimal: 8 = 0.5, 12 = 1.0
            return min(max((rate - 8) / 4, 0.5), 1.0)
        } else {
            // Above optimal: 16 = 1.0, 22 = 0.0
            return min(max((22 - rate) / 6, 0.0), 1.0)
        }
    }
}

enum RecoveryStatus {
    case excellent
    case good
    case fair
    case poor

    var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .fair: return "🟠"
        case .poor: return "🔴"
        }
    }

    var description: String {
        switch self {
        case .excellent:
            return String(localized: "Excellent", comment: "Recovery status description - excellent")
        case .good:
            return String(localized: "Good", comment: "Recovery status description - good")
        case .fair:
            return String(localized: "Fair", comment: "Recovery status description - fair")
        case .poor:
            return String(localized: "Poor", comment: "Recovery status description - poor")
        }
    }

    var recommendation: String {
        switch self {
        case .excellent:
            return String(localized: "You're at your peak! This is the perfect time for an intensive workout.", comment: "Recovery recommendation - excellent status")
        case .good:
            return String(localized: "Good recovery. You can do a moderate to intense workout.", comment: "Recovery recommendation - good status")
        case .fair:
            return String(localized: "Average recovery. Prefer a light to moderate workout.", comment: "Recovery recommendation - fair status")
        case .poor:
            return String(localized: "Insufficient recovery. Rest or active recovery recommended.", comment: "Recovery recommendation - poor status")
        }
    }
}
