//
//  RecoveryCoachingService.swift
//  InsightRun
//
//  Service for analyzing recovery data and providing coaching insights
//

import Foundation

struct RecoveryInsight {
    let readinessScore: Int // 0-100
    let status: RecoveryStatus
    let message: String
    let recommendations: [String]
    let shouldRest: Bool

    enum RecoveryStatus {
        case excellent  // 80-100
        case good       // 60-79
        case fair       // 40-59
        case poor       // 0-39

        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "orange"
            case .poor: return "red"
            }
        }

        var emoji: String {
            switch self {
            case .excellent: return "🚀"
            case .good: return "✅"
            case .fair: return "⚠️"
            case .poor: return "🛑"
            }
        }
    }
}

class RecoveryCoachingService {
    static let shared = RecoveryCoachingService()

    private init() {}

    // Analyze recovery data and generate insights
    func analyzeRecovery(metrics: RecoveryMetrics) -> RecoveryInsight {
        // Use the optimized recovery score from RecoveryMetrics
        let score = metrics.recoveryScore
        var recommendations: [String] = []
        var shouldRest = false

        // Analyze Resting Heart Rate
        if let restingHR = metrics.restingHeartRate {
            if restingHR > 75 {
                recommendations.append(String(localized: "High resting HR (\(Int(restingHR)) bpm) - prioritize recovery"))
                shouldRest = true
            } else if restingHR < 55 {
                recommendations.append(String(localized: "Excellent resting HR (\(Int(restingHR)) bpm) - good aerobic fitness"))
            } else if restingHR >= 55 && restingHR <= 65 {
                recommendations.append(String(localized: "Normal resting HR (\(Int(restingHR)) bpm) - good recovery"))
            }
        }

        // Analyze HRV
        if let hrv = metrics.hrvAverage {
            if hrv < 30 {
                recommendations.append(String(localized: "Low HRV (\(Int(hrv)) ms) - sign of fatigue, rest recommended"))
                shouldRest = true
            } else if hrv > 60 {
                recommendations.append(String(localized: "Excellent HRV (\(Int(hrv)) ms) - nervous system well recovered"))
            } else if hrv >= 40 && hrv <= 60 {
                recommendations.append(String(localized: "Adequate HRV (\(Int(hrv)) ms) - recovery in progress"))
            }
        }

        // Analyze Sleep
        if let sleepData = metrics.sleepData {
            let hours = sleepData.totalSleepDuration / 3600
            if hours < 7 {
                recommendations.append(String(localized: "Insufficient sleep (\(String(format: "%.1fh", hours))) - aim for 7-9h per night"))
                shouldRest = true
            } else if hours >= 8 && hours <= 9 {
                recommendations.append(String(localized: "Excellent sleep (\(String(format: "%.1fh", hours))) - optimal recovery"))
            } else if hours > 10 {
                recommendations.append(String(localized: "Prolonged sleep (\(String(format: "%.1fh", hours))) - possible sign of fatigue"))
            }

            if sleepData.sleepEfficiency < 80 {
                recommendations.append(String(localized: "Sleep efficiency needs improvement (\(Int(sleepData.sleepEfficiency))%) - optimize your sleep environment"))
            } else if sleepData.sleepEfficiency >= 90 {
                recommendations.append(String(localized: "Excellent sleep efficiency (\(Int(sleepData.sleepEfficiency))%)"))
            }
        }

        // Analyze Walking Heart Rate
        if let walkingHR = metrics.walkingHeartRate {
            if walkingHR > 105 {
                recommendations.append(String(localized: "High walking HR (\(Int(walkingHR)) bpm) - possible cardiac fatigue"))
                shouldRest = true
            } else if walkingHR < 80 {
                recommendations.append(String(localized: "Excellent walking HR (\(Int(walkingHR)) bpm) - good cardiovascular condition"))
            }
        }

        // Analyze Respiratory Rate
        if let respRate = metrics.respiratoryRate {
            if respRate > 18 {
                recommendations.append(String(localized: "High respiratory rate (\(Int(respRate)) /min) - possible stress"))
                if respRate > 20 {
                    shouldRest = true
                }
            } else if respRate >= 12 && respRate <= 16 {
                recommendations.append(String(localized: "Optimal respiratory rate (\(Int(respRate)) /min)"))
            } else if respRate < 10 {
                recommendations.append(String(localized: "Low respiratory rate (\(Int(respRate)) /min) - monitor your breathing"))
            }
        }

        // Determine status based on the optimized score
        let status: RecoveryInsight.RecoveryStatus
        if score >= 80 {
            status = .excellent
        } else if score >= 60 {
            status = .good
        } else if score >= 40 {
            status = .fair
        } else {
            status = .poor
        }

        // Generate message based on status
        let message: String
        if shouldRest {
            message = String(localized: "Your body needs recovery. Prioritize light training or complete rest today.")
        } else {
            switch status {
            case .excellent:
                message = String(localized: "Excellent shape! This is the ideal time for intensive training or a quality workout.")
            case .good:
                message = String(localized: "Good overall shape. You can train normally with moderate to high intensity.")
            case .fair:
                message = String(localized: "Fair shape but be careful. Opt for light to moderate training today.")
            case .poor:
                message = String(localized: "Insufficient recovery. Active rest or a rest day is recommended.")
            }
        }

        // Add general recommendations if none were specific
        if recommendations.isEmpty {
            recommendations = [
                String(localized: "Keep monitoring your recovery metrics"),
                String(localized: "Stay well hydrated throughout the day"),
                String(localized: "Maintain a regular sleep routine")
            ]
        }

        return RecoveryInsight(
            readinessScore: score,
            status: status,
            message: message,
            recommendations: recommendations,
            shouldRest: shouldRest
        )
    }

    // MARK: - Private Helper Methods
    // Note: Score calculation is now centralized in RecoveryMetrics
    // This service focuses on generating contextual recommendations

    // Generate a contextual string for AI assistant
    func generateRecoveryContext(metrics: RecoveryMetrics) -> String {
        let insight = analyzeRecovery(metrics: metrics)

        var context = """
        Recovery Status:
        - Readiness Score: \(insight.readinessScore)/100 \(insight.status.emoji)
        - Status: \(insight.status)

        """

        if let restingHR = metrics.restingHeartRate {
            context += "- Resting HR: \(Int(restingHR)) bpm\n"
        }

        if let hrv = metrics.hrvAverage {
            context += "- HRV (SDNN) average: \(Int(hrv)) ms"
            if let hrvMin = metrics.hrvMin, let hrvMax = metrics.hrvMax {
                context += " (range: \(Int(hrvMin))-\(Int(hrvMax)) ms)"
            }
            context += "\n"
        }

        if let walkingHR = metrics.walkingHeartRate {
            context += "- Walking HR: \(Int(walkingHR)) bpm\n"
        }

        if let respRate = metrics.respiratoryRate {
            context += "- Respiratory rate: \(Int(respRate)) breaths/min\n"
        }

        if let sleep = metrics.sleepData {
            let hours = sleep.totalSleepDuration / 3600
            context += "- Sleep: \(String(format: "%.1fh", hours)) (Efficiency: \(Int(sleep.sleepEfficiency))%)\n"
        }

        context += "\nRecommendations:\n"
        for rec in insight.recommendations {
            context += "- \(rec)\n"
        }

        return context
    }
}
