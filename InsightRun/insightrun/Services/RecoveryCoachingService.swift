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
                recommendations.append("FC au repos élevée (\(Int(restingHR)) bpm) - privilégiez la récupération")
                shouldRest = true
            } else if restingHR < 55 {
                recommendations.append("Excellente FC au repos (\(Int(restingHR)) bpm) - bonne forme aérobie")
            } else if restingHR >= 55 && restingHR <= 65 {
                recommendations.append("FC au repos normale (\(Int(restingHR)) bpm) - bonne récupération")
            }
        }

        // Analyze HRV
        if let hrv = metrics.hrvAverage {
            if hrv < 30 {
                recommendations.append("HRV faible (\(Int(hrv)) ms) - signe de fatigue, repos recommandé")
                shouldRest = true
            } else if hrv > 60 {
                recommendations.append("HRV excellente (\(Int(hrv)) ms) - système nerveux bien récupéré")
            } else if hrv >= 40 && hrv <= 60 {
                recommendations.append("HRV correcte (\(Int(hrv)) ms) - récupération en cours")
            }
        }

        // Analyze Sleep
        if let sleepData = metrics.sleepData {
            let hours = sleepData.totalSleepDuration / 3600
            if hours < 7 {
                recommendations.append("Sommeil insuffisant (\(String(format: "%.1fh", hours))) - visez 7-9h par nuit")
                shouldRest = true
            } else if hours >= 8 && hours <= 9 {
                recommendations.append("Excellent sommeil (\(String(format: "%.1fh", hours))) - récupération optimale")
            } else if hours > 10 {
                recommendations.append("Sommeil prolongé (\(String(format: "%.1fh", hours))) - possible signe de fatigue")
            }

            if sleepData.sleepEfficiency < 80 {
                recommendations.append("Efficacité de sommeil à améliorer (\(Int(sleepData.sleepEfficiency))%) - optimisez votre environnement de sommeil")
            } else if sleepData.sleepEfficiency >= 90 {
                recommendations.append("Excellente efficacité de sommeil (\(Int(sleepData.sleepEfficiency))%)")
            }
        }

        // Analyze Walking Heart Rate
        if let walkingHR = metrics.walkingHeartRate {
            if walkingHR > 105 {
                recommendations.append("FC de marche élevée (\(Int(walkingHR)) bpm) - possible fatigue cardiaque")
                shouldRest = true
            } else if walkingHR < 80 {
                recommendations.append("FC de marche excellente (\(Int(walkingHR)) bpm) - bonne condition cardiovasculaire")
            }
        }

        // Analyze Respiratory Rate
        if let respRate = metrics.respiratoryRate {
            if respRate > 18 {
                recommendations.append("Fréquence respiratoire élevée (\(Int(respRate)) /min) - stress possible")
                if respRate > 20 {
                    shouldRest = true
                }
            } else if respRate >= 12 && respRate <= 16 {
                recommendations.append("Fréquence respiratoire optimale (\(Int(respRate)) /min)")
            } else if respRate < 10 {
                recommendations.append("Fréquence respiratoire basse (\(Int(respRate)) /min) - surveillez votre respiration")
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

    // MARK: - Private Helper Methods
    // Note: Score calculation is now centralized in RecoveryMetrics
    // This service focuses on generating contextual recommendations

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

        if let hrv = metrics.hrvAverage {
            context += "- HRV (SDNN) moyenne: \(Int(hrv)) ms"
            if let hrvMin = metrics.hrvMin, let hrvMax = metrics.hrvMax {
                context += " (plage: \(Int(hrvMin))-\(Int(hrvMax)) ms)"
            }
            context += "\n"
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
