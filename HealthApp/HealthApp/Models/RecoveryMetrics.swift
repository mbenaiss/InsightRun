//
//  RecoveryMetrics.swift
//  HealthApp
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
        var score = 50 // Base score
        var factors = 0

        // HRV contribution (higher is better)
        if let hrv = hrv {
            factors += 1
            if hrv > 60 {
                score += 15
            } else if hrv > 40 {
                score += 10
            } else if hrv > 20 {
                score += 5
            }
        }

        // Resting HR contribution (lower is better for athletes)
        if let rhr = restingHeartRate {
            factors += 1
            if rhr < 50 {
                score += 15
            } else if rhr < 60 {
                score += 10
            } else if rhr < 70 {
                score += 5
            }
        }

        // Sleep contribution
        if let sleep = sleepData {
            factors += 1
            let sleepHours = sleep.totalSleepDuration / 3600.0
            if sleepHours >= 7.5 {
                score += 20
            } else if sleepHours >= 6.5 {
                score += 15
            } else if sleepHours >= 5.5 {
                score += 10
            } else {
                score -= 10
            }
        }

        return max(0, min(100, score))
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
        case .excellent: return "Excellente"
        case .good: return "Bonne"
        case .fair: return "Moyenne"
        case .poor: return "Faible"
        }
    }

    var recommendation: String {
        switch self {
        case .excellent:
            return "Vous êtes au top ! C'est le bon moment pour un entraînement intensif."
        case .good:
            return "Bonne récupération. Vous pouvez faire un entraînement modéré à intense."
        case .fair:
            return "Récupération moyenne. Privilégiez un entraînement léger à modéré."
        case .poor:
            return "Récupération insuffisante. Repos ou récupération active recommandés."
        }
    }
}
