//
//  RecoveryMetrics.swift
//  InsightRun
//
//  Model for recovery and readiness metrics
//  Uses personal baseline comparison for Whoop/Oura-style scoring
//

import Foundation

/// Weight configuration for recovery score calculation (total = 100%)
/// Sources:
/// - HRV as recovery marker: Plews DJ et al. (2013). "Training adaptation and heart rate variability
///   in elite endurance athletes." Int J Sports Physiol Perform 8(6):688-94.
/// - RHR for cardiovascular stress: Buchheit M (2014). "Monitoring training status with HR measures."
///   Int J Sports Physiol Perform 9(5):883-93.
/// - SpO2 clinical thresholds: Jubran A (1999). "Pulse oximetry." Crit Care 3(2):R11-R17.
/// - Sleep for recovery: Halson SL (2014). "Sleep in elite athletes and nutritional interventions
///   to enhance sleep." Sports Med 44(S1):13-23.
/// - Weight distribution: Adapted from Whoop recovery model and Stanley et al. (2013).
///   "Cardiac parasympathetic reactivation following exercise." Sports Med 43(12):1259-77.
private enum RecoveryWeights {
    static let hrv = 0.25              // 25% - Primary recovery indicator (higher is better)
    static let restingHeartRate = 0.15 // 15% - Cardiovascular stress indicator (lower is better)
    static let oxygenSaturation = 0.10 // 10% - Oxygen saturation (higher is better)
    static let respiratoryRate = 0.10  // 10% - Stress indicator (lower is better)
    static let sleep = 0.40            // 40% - Sleep quality (duration + efficiency + stages)
}

private enum RecoveryCaps {
    static let criticalSleepHours = 5.0
    static let severeSleepHours = 6.0
    static let criticalLowHRV = 30.0
    static let maxScoreCriticalSleep = 35
    static let maxScoreComboAlert = 40
}

struct RecoveryMetrics: Identifiable {
    let id = UUID()
    let date: Date

    // Heart Rate Metrics
    let restingHeartRate: Double?
    let hrvAverage: Double?
    let hrvMin: Double?
    let hrvMax: Double?
    let walkingHeartRate: Double?

    // Sleep Metrics
    let sleepData: SleepData?

    // Respiratory
    let respiratoryRate: Double?

    // Oxygen Saturation (SpO2)
    let oxygenSaturation: Double?

    // Personal baseline for comparison
    let baseline: PersonalBaseline?

    // Cached recovery score (0-100), computed once at init
    let recoveryScore: Int

    init(
        date: Date,
        restingHeartRate: Double? = nil,
        hrvAverage: Double? = nil,
        hrvMin: Double? = nil,
        hrvMax: Double? = nil,
        walkingHeartRate: Double? = nil,
        sleepData: SleepData? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturation: Double? = nil,
        baseline: PersonalBaseline? = nil
    ) {
        self.date = date
        self.restingHeartRate = restingHeartRate
        self.hrvAverage = hrvAverage
        self.hrvMin = hrvMin
        self.hrvMax = hrvMax
        self.walkingHeartRate = walkingHeartRate
        self.sleepData = sleepData
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.baseline = baseline
        self.recoveryScore = Self.calculateRecoveryScore(
            baseline: baseline,
            sleepData: sleepData,
            hrvAverage: hrvAverage,
            restingHeartRate: restingHeartRate,
            oxygenSaturation: oxygenSaturation,
            respiratoryRate: respiratoryRate
        )
    }

    func withSleepData(_ sleepData: SleepData?) -> RecoveryMetrics {
        RecoveryMetrics(
            date: date,
            restingHeartRate: restingHeartRate,
            hrvAverage: hrvAverage,
            hrvMin: hrvMin,
            hrvMax: hrvMax,
            walkingHeartRate: walkingHeartRate,
            sleepData: sleepData,
            respiratoryRate: respiratoryRate,
            oxygenSaturation: oxygenSaturation,
            baseline: baseline
        )
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

    private static func calculateRecoveryScore(
        baseline: PersonalBaseline?,
        sleepData: SleepData?,
        hrvAverage: Double?,
        restingHeartRate: Double?,
        oxygenSaturation: Double?,
        respiratoryRate: Double?
    ) -> Int {
        var score: Int
        if let baseline = baseline, baseline.isReliable {
            score = calculateBaselineAwareScore(
                baseline,
                hrvAverage: hrvAverage,
                restingHeartRate: restingHeartRate,
                oxygenSaturation: oxygenSaturation,
                respiratoryRate: respiratoryRate,
                sleepData: sleepData
            )
        } else {
            score = calculateFixedRangeScore(
                hrvAverage: hrvAverage,
                restingHeartRate: restingHeartRate,
                oxygenSaturation: oxygenSaturation,
                respiratoryRate: respiratoryRate,
                sleepData: sleepData
            )
        }

        if let sleep = sleepData {
            let hours = sleep.totalSleepDuration / 3600.0
            if hours < RecoveryCaps.criticalSleepHours {
                score = min(score, RecoveryCaps.maxScoreCriticalSleep)
            }
            if let hrv = hrvAverage, hrv < RecoveryCaps.criticalLowHRV, hours < RecoveryCaps.severeSleepHours {
                score = min(score, RecoveryCaps.maxScoreComboAlert)
            }
        }

        return score
    }

    // MARK: - Baseline-Aware Scoring (Whoop/Oura style)

    /// Scoring based on deviation from personal baseline
    /// A normal day (at baseline) scores ~50%, better = higher, worse = lower
    /// Based on 4 metrics + sleep quality:
    /// - HRV (higher is better)
    /// - Resting HR (lower is better)
    /// - SpO2 (higher is better)
    /// - Respiratory Rate (lower is better)
    /// - Sleep (duration + efficiency + stages)
    private static func calculateBaselineAwareScore(
        _ baseline: PersonalBaseline,
        hrvAverage: Double?,
        restingHeartRate: Double?,
        oxygenSaturation: Double?,
        respiratoryRate: Double?,
        sleepData: SleepData?
    ) -> Int {
        var totalScore = 0.0
        var totalWeight = 0.0

        // HRV Score (higher is better)
        if let hrv = hrvAverage {
            let score = scoreFromDeviation(
                value: hrv,
                average: baseline.hrvAverage,
                stdDev: baseline.hrvStdDev,
                isHigherBetter: true,
                defaultCV: MetricCV.hrv
            )
            totalScore += score * RecoveryWeights.hrv
            totalWeight += RecoveryWeights.hrv
        }

        // RHR Score (lower is better)
        if let rhr = restingHeartRate {
            let score = scoreFromDeviation(
                value: rhr,
                average: baseline.restingHeartRateAverage,
                stdDev: baseline.restingHeartRateStdDev,
                isHigherBetter: false,
                defaultCV: MetricCV.restingHR
            )
            totalScore += score * RecoveryWeights.restingHeartRate
            totalWeight += RecoveryWeights.restingHeartRate
        }

        // SpO2 Score (higher is better, uses clinical thresholds)
        if let spo2 = oxygenSaturation {
            let score = scoreSpO2(spo2)
            totalScore += score * RecoveryWeights.oxygenSaturation
            totalWeight += RecoveryWeights.oxygenSaturation
        }

        // Respiratory Rate Score (lower is better)
        if let respRate = respiratoryRate {
            let score = scoreFromDeviation(
                value: respRate,
                average: baseline.respiratoryRateAverage,
                stdDev: baseline.respiratoryRateStdDev,
                isHigherBetter: false,
                defaultCV: MetricCV.respiratoryRate
            )
            totalScore += score * RecoveryWeights.respiratoryRate
            totalWeight += RecoveryWeights.respiratoryRate
        }

        // Sleep Score (duration + efficiency + stages combined)
        if let sleep = sleepData {
            let durationEfficiencyScore = scoreSleepVsBaseline(sleep, baseline: baseline)
            let stagesScore = scoreSleepStages(sleep, baseline: baseline)
            // Combine: 60% duration/efficiency, 40% stages
            let combinedSleepScore = (durationEfficiencyScore * 0.6) + (stagesScore * 0.4)
            totalScore += combinedSleepScore * RecoveryWeights.sleep
            totalWeight += RecoveryWeights.sleep
        }

        // Normalize by total weight
        let rawScore = totalWeight > 0 ? (totalScore / totalWeight) : 0.5

        // Map to 0-100 scale: raw 0.5 (at baseline) = 50%, perfect = 100%, worst = 0%
        let finalScore = rawScore * 100.0

        return max(0, min(100, Int(finalScore.rounded())))
    }

    /// Metric-specific coefficient of variation for fallback stdDev calculation
    /// Based on typical physiological variability
    private enum MetricCV {
        static let hrv = 0.30           // HRV: 20-40% CV, use 30%
        static let restingHR = 0.08     // RHR: 5-10% CV, use 8%
        static let respiratoryRate = 0.12  // Resp: 10-15% CV, use 12%
        static let oxygenSaturation = 0.02 // SpO2: 1-2% CV, use 2%
    }

    /// Convert deviation to a 0-1 score
    /// - isHigherBetter: true for HRV/SpO2, false for RHR/RespRate
    /// - defaultCV: metric-specific coefficient of variation for fallback
    private static func scoreFromDeviation(
        value: Double,
        average: Double?,
        stdDev: Double?,
        isHigherBetter: Bool?,
        defaultCV: Double = 0.15
    ) -> Double {
        guard let avg = average else {
            return 0.5
        }

        let std = stdDev ?? (avg * defaultCV)
        guard std > 0 else { return 0.5 }

        let zScore = (value - avg) / std

        let clampedZ = max(-3.0, min(3.0, zScore))

        switch isHigherBetter {
        case true:
            return min(max((clampedZ + 2) / 4.0, 0.0), 1.0)
        case false:
            return min(max((2 - clampedZ) / 4.0, 0.0), 1.0)
        case nil:
            return max(0, 1.0 - abs(clampedZ) / 2.0)
        }
    }

    /// SpO2 scoring with clinical thresholds
    private static func scoreSpO2(_ spo2: Double) -> Double {
        if spo2 >= 98 {
            return 1.0
        } else if spo2 >= 96 {
            return 0.9
        } else if spo2 >= 95 {
            return 0.75
        } else if spo2 >= 93 {
            return 0.5
        } else if spo2 >= 90 {
            return 0.25
        } else {
            return 0.0
        }
    }

    /// Sleep scoring compared to baseline
    private static func scoreSleepVsBaseline(_ sleep: SleepData, baseline: PersonalBaseline) -> Double {
        var score = 0.0
        var count = 0

        let hours = sleep.totalSleepDuration / 3600.0

        let optimalScore: Double
        if hours >= 7 && hours <= 9 {
            optimalScore = 0.9 + 0.1 * min(hours / 8.0, 1.0)
        } else if hours >= 6 && hours < 7 {
            optimalScore = 0.6
        } else if hours >= 5 && hours < 6 {
            optimalScore = 0.3
        } else if hours < 5 {
            optimalScore = max(0.0, hours / 10.0)
        } else {
            optimalScore = 0.7
        }
        score += optimalScore
        count += 1

        if let avgEfficiency = baseline.sleepEfficiencyAverage {
            let efficiencyScore = scoreFromDeviation(
                value: sleep.sleepEfficiency,
                average: avgEfficiency,
                stdDev: 5.0,
                isHigherBetter: true
            )
            score += efficiencyScore
            count += 1
        } else {
            let efficiencyScore = min(max((sleep.sleepEfficiency - 75) / 20, 0.0), 1.0)
            score += efficiencyScore
            count += 1
        }

        return count > 0 ? score / Double(count) : 0.5
    }

    /// Score sleep stages (deep and REM percentages)
    private static func scoreSleepStages(_ sleep: SleepData, baseline: PersonalBaseline) -> Double {
        guard let deep = sleep.deepSleepDuration,
              let rem = sleep.remSleepDuration,
              sleep.totalSleepDuration > 0 else {
            return 0.5
        }

        let totalSleep = sleep.totalSleepDuration
        let deepPercent = (deep / totalSleep) * 100
        let remPercent = (rem / totalSleep) * 100

        var score = 0.0
        var count = 0

        if let avgDeep = baseline.deepSleepPercentageAverage {
            let deepScore = scoreFromDeviation(
                value: deepPercent,
                average: avgDeep,
                stdDev: 5.0,
                isHigherBetter: true
            )
            score += deepScore
        } else {
            if deepPercent >= 15 && deepPercent <= 20 {
                score += 1.0
            } else if deepPercent >= 13 && deepPercent <= 25 {
                score += 0.7
            } else {
                score += 0.3
            }
        }
        count += 1

        if let avgRem = baseline.remSleepPercentageAverage {
            let remScore = scoreFromDeviation(
                value: remPercent,
                average: avgRem,
                stdDev: 5.0,
                isHigherBetter: true
            )
            score += remScore
        } else {
            if remPercent >= 20 && remPercent <= 25 {
                score += 1.0
            } else if remPercent >= 18 && remPercent <= 28 {
                score += 0.7
            } else {
                score += 0.3
            }
        }
        count += 1

        return score / Double(count)
    }

    // MARK: - Fixed Range Scoring (Fallback)

    /// Fallback scoring without personal baseline
    private static func calculateFixedRangeScore(
        hrvAverage: Double?,
        restingHeartRate: Double?,
        oxygenSaturation: Double?,
        respiratoryRate: Double?,
        sleepData: SleepData?
    ) -> Int {
        var totalScore = 0.0
        var totalWeight = 0.0

        if let hrv = hrvAverage {
            let hrvScore = calculateHRVScore(hrv)
            totalScore += hrvScore * RecoveryWeights.hrv
            totalWeight += RecoveryWeights.hrv
        }

        if let rhr = restingHeartRate {
            let rhrScore = calculateRHRScore(rhr)
            totalScore += rhrScore * RecoveryWeights.restingHeartRate
            totalWeight += RecoveryWeights.restingHeartRate
        }

        if let spo2 = oxygenSaturation {
            let spo2Score = scoreSpO2(spo2)
            totalScore += spo2Score * RecoveryWeights.oxygenSaturation
            totalWeight += RecoveryWeights.oxygenSaturation
        }

        if let respRate = respiratoryRate {
            let respScore = calculateRespiratoryScore(respRate)
            totalScore += respScore * RecoveryWeights.respiratoryRate
            totalWeight += RecoveryWeights.respiratoryRate
        }

        if let sleep = sleepData {
            let sleepScore = calculateSleepScore(sleep)
            totalScore += sleepScore * RecoveryWeights.sleep
            totalWeight += RecoveryWeights.sleep
        }

        let finalScore = totalWeight > 0 ? (totalScore / totalWeight) * 100 : 50

        return max(0, min(100, Int(finalScore.rounded())))
    }

    // MARK: - Fixed Range Helper Methods

    private static func calculateHRVScore(_ hrv: Double) -> Double {
        return min(max((hrv - 20) / 80, 0.0), 1.0)
    }

    private static func calculateRHRScore(_ rhr: Double) -> Double {
        return min(max((80 - rhr) / 40, 0.0), 1.0)
    }

    private static func calculateSleepScore(_ sleep: SleepData) -> Double {
        let hours = sleep.totalSleepDuration / 3600.0
        let efficiency = sleep.sleepEfficiency / 100.0

        var durationScore: Double
        if hours < 5 {
            durationScore = 0.0
        } else if hours <= 9 {
            durationScore = (hours - 5) / 4
        } else if hours <= 10 {
            durationScore = 1.0
        } else {
            durationScore = max(0.7, 1.0 - (hours - 10) * 0.1)
        }

        let efficiencyScore = min(max((efficiency - 0.75) / 0.20, 0.0), 1.0)

        return durationScore * 0.7 + efficiencyScore * 0.3
    }

    private static func calculateRespiratoryScore(_ rate: Double) -> Double {
        if rate >= 12 && rate <= 16 {
            return 1.0
        } else if rate < 12 {
            return min(max((rate - 8) / 4, 0.5), 1.0)
        } else {
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
