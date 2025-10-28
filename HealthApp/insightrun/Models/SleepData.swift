//
//  SleepData.swift
//  HealthApp
//
//  Model for sleep analysis data
//

import Foundation
import HealthKit

struct SleepData: Identifiable {
    let id = UUID()
    let date: Date

    // Sleep session times
    let sleepStart: Date
    let sleepEnd: Date

    // Total sleep duration in seconds
    let totalSleepDuration: TimeInterval

    // Time in bed (including awake time)
    let timeInBed: TimeInterval

    // Sleep stages (iOS 16+)
    let deepSleepDuration: TimeInterval?
    let coreSleepDuration: TimeInterval?
    let remSleepDuration: TimeInterval?
    let awakeDuration: TimeInterval?

    // Naps (during the day, excluding main sleep session)
    let napDuration: TimeInterval?

    // Sleep efficiency (percentage of time in bed actually sleeping)
    var sleepEfficiency: Double {
        guard timeInBed > 0 else { return 0 }
        return (totalSleepDuration / timeInBed) * 100
    }

    // Sleep quality score (0-100)
    var qualityScore: Int {
        var score = 50

        // Sleep duration score
        let hours = totalSleepDuration / 3600.0
        if hours >= 7 && hours <= 9 {
            score += 25
        } else if hours >= 6 && hours < 7 {
            score += 15
        } else if hours >= 5 && hours < 6 {
            score += 5
        } else if hours < 5 {
            score -= 20
        }

        // Sleep efficiency score
        if sleepEfficiency >= 85 {
            score += 25
        } else if sleepEfficiency >= 75 {
            score += 15
        } else if sleepEfficiency >= 65 {
            score += 5
        }

        return max(0, min(100, score))
    }

    var qualityDescription: String {
        switch qualityScore {
        case 80...100:
            return "Excellent"
        case 60..<80:
            return "Bon"
        case 40..<60:
            return "Moyen"
        default:
            return "Insuffisant"
        }
    }

    // Format sleep duration
    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        return String(format: "%dh%02d", hours, minutes)
    }

    var formattedTotalSleep: String {
        formatDuration(totalSleepDuration)
    }

    var formattedTimeInBed: String {
        formatDuration(timeInBed)
    }

    // Format sleep session time range
    var formattedSleepTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"

        let startTime = formatter.string(from: sleepStart)
        let endTime = formatter.string(from: sleepEnd)

        return "\(startTime) - \(endTime)"
    }

    var formattedNapDuration: String? {
        guard let napDuration = napDuration, napDuration > 0 else { return nil }
        return formatDuration(napDuration)
    }
}

// Sleep stage information
struct SleepStage {
    let type: SleepStageType
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date
}

enum SleepStageType: String {
    case awake = "Awake"
    case rem = "REM"
    case core = "Core"
    case deep = "Deep"
    case inBed = "In Bed"

    var emoji: String {
        switch self {
        case .awake: return "👁️"
        case .rem: return "💭"
        case .core: return "😴"
        case .deep: return "🌙"
        case .inBed: return "🛏️"
        }
    }

    var description: String {
        switch self {
        case .awake: return "Éveillé"
        case .rem: return "Sommeil paradoxal"
        case .core: return "Sommeil léger"
        case .deep: return "Sommeil profond"
        case .inBed: return "Au lit"
        }
    }
}
