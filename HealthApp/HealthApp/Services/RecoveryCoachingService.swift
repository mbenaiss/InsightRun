//
//  RecoveryCoachingService.swift
//  HealthApp
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
        var score = 50 // Base score
        var recommendations: [String] = []
        var shouldRest = false

        // Analyze Resting Heart Rate
        if let restingHR = metrics.restingHeartRate {
            let hrScore = analyzeRestingHR(restingHR)
            score += hrScore

            if restingHR > 70 {
                recommendations.append("FC au repos élevée (\(Int(restingHR)) bpm) - privilégiez la récupération")
                shouldRest = true
            } else if restingHR < 50 {
                recommendations.append("Excellente FC au repos (\(Int(restingHR)) bpm) - bonne forme aérobie")
            }
        }

        // Analyze HRV
        if let hrv = metrics.hrv {
            let hrvScore = analyzeHRV(hrv)
            score += hrvScore

            if hrv < 30 {
                recommendations.append("HRV faible (\(Int(hrv)) ms) - signe de fatigue, repos recommandé")
                shouldRest = true
            } else if hrv > 60 {
                recommendations.append("HRV excellente (\(Int(hrv)) ms) - système nerveux bien récupéré")
            }
        }

        // Analyze Sleep
        if let sleepData = metrics.sleepData {
            let sleepScore = analyzeSleep(sleepData)
            score += sleepScore

            let hours = sleepData.totalSleepDuration / 3600
            if hours < 7 {
                recommendations.append("Sommeil insuffisant (\(String(format: "%.1fh", hours))) - visez 7-9h par nuit")
                shouldRest = true
            } else if hours >= 8 {
                recommendations.append("Excellent sommeil (\(String(format: "%.1fh", hours))) - récupération optimale")
            }

            if sleepData.sleepEfficiency < 85 {
                recommendations.append("Efficacité de sommeil à améliorer (\(Int(sleepData.sleepEfficiency))%)")
            }
        }

        // Analyze Walking Heart Rate
        if let walkingHR = metrics.walkingHeartRate {
            if walkingHR > 100 {
                recommendations.append("FC de marche élevée - possible fatigue cardiaque")
                score -= 5
                shouldRest = true
            }
        }

        // Analyze Respiratory Rate
        if let respRate = metrics.respiratoryRate {
            if respRate > 20 {
                recommendations.append("Fréquence respiratoire élevée - stress possible")
                score -= 5
            } else if respRate >= 12 && respRate <= 16 {
                recommendations.append("Fréquence respiratoire optimale")
                score += 5
            }
        }

        // Cap score between 0-100
        score = max(0, min(100, score))

        // Determine status
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
            message = "Votre corps a besoin de récupération. Privilégiez un entraînement léger ou du repos complet aujourd'hui."
        } else {
            switch status {
            case .excellent:
                message = "Forme excellente ! C'est le moment idéal pour un entraînement intensif ou un workout de qualité."
            case .good:
                message = "Bonne forme générale. Vous pouvez vous entraîner normalement avec une intensité modérée à élevée."
            case .fair:
                message = "Forme correcte mais attention. Optez pour un entraînement léger à modéré aujourd'hui."
            case .poor:
                message = "Récupération insuffisante. Repos actif ou journée de repos recommandée."
            }
        }

        // Add general recommendations if none were specific
        if recommendations.isEmpty {
            recommendations = [
                "Continuez à surveiller vos métriques de récupération",
                "Hydratez-vous bien tout au long de la journée",
                "Maintenez une routine de sommeil régulière"
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

    // MARK: - Private Analysis Methods

    private func analyzeRestingHR(_ hr: Double) -> Int {
        switch hr {
        case ..<50:
            return 20 // Excellent athlete
        case 50..<60:
            return 15 // Very good
        case 60..<70:
            return 10 // Good
        case 70..<80:
            return 0  // Average
        case 80..<90:
            return -10 // Below average
        default:
            return -20 // Poor
        }
    }

    private func analyzeHRV(_ hrv: Double) -> Int {
        switch hrv {
        case ..<20:
            return -15 // Very low
        case 20..<30:
            return -5  // Low
        case 30..<50:
            return 5   // Average
        case 50..<70:
            return 15  // Good
        default:
            return 20  // Excellent
        }
    }

    private func analyzeSleep(_ sleep: SleepData) -> Int {
        let hours = sleep.totalSleepDuration / 3600
        let efficiency = sleep.sleepEfficiency

        var score = 0

        // Duration score
        if hours >= 8 && hours <= 9 {
            score += 15
        } else if hours >= 7 && hours < 8 {
            score += 10
        } else if hours >= 6 && hours < 7 {
            score += 5
        } else {
            score -= 10
        }

        // Efficiency score
        if efficiency >= 90 {
            score += 10
        } else if efficiency >= 85 {
            score += 5
        } else if efficiency < 75 {
            score -= 5
        }

        return score
    }

    // Generate a contextual string for AI assistant
    func generateRecoveryContext(metrics: RecoveryMetrics) -> String {
        let insight = analyzeRecovery(metrics: metrics)

        var context = """
        📊 État de Récupération:
        - Score de Préparation: \(insight.readinessScore)/100 \(insight.status.emoji)
        - Statut: \(insight.status)

        """

        if let restingHR = metrics.restingHeartRate {
            context += "- FC au repos: \(Int(restingHR)) bpm\n"
        }

        if let hrv = metrics.hrv {
            context += "- HRV (SDNN): \(Int(hrv)) ms\n"
        }

        if let walkingHR = metrics.walkingHeartRate {
            context += "- FC de marche: \(Int(walkingHR)) bpm\n"
        }

        if let respRate = metrics.respiratoryRate {
            context += "- Fréquence respiratoire: \(Int(respRate)) respirations/min\n"
        }

        if let sleep = metrics.sleepData {
            let hours = sleep.totalSleepDuration / 3600
            context += "- Sommeil: \(String(format: "%.1fh", hours)) (efficacité: \(Int(sleep.sleepEfficiency))%)\n"
        }

        context += "\n💡 Recommandations:\n"
        for rec in insight.recommendations {
            context += "- \(rec)\n"
        }

        return context
    }
}
