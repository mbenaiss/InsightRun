//
//  SleepData.swift
//  InsightRun
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

    init(date: Date, sleepStart: Date, sleepEnd: Date, totalSleepDuration: TimeInterval,
         timeInBed: TimeInterval, deepSleepDuration: TimeInterval?, coreSleepDuration: TimeInterval?,
         remSleepDuration: TimeInterval?, awakeDuration: TimeInterval?, napDuration: TimeInterval?) {
        self.date = date
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.totalSleepDuration = totalSleepDuration
        self.timeInBed = timeInBed
        let stages = [deepSleepDuration, coreSleepDuration, remSleepDuration].compactMap { $0 }
        // Conflicting HealthKit sources can classify the same interval differently.
        let validStages = stages.allSatisfy { $0.isFinite && $0 >= 0 }
            && stages.reduce(0, +) <= totalSleepDuration + 0.001
        self.deepSleepDuration = validStages ? deepSleepDuration : nil
        self.coreSleepDuration = validStages ? coreSleepDuration : nil
        self.remSleepDuration = validStages ? remSleepDuration : nil
        self.awakeDuration = awakeDuration
        self.napDuration = napDuration
    }

    // Sleep efficiency (percentage of time in bed actually sleeping)
    var sleepEfficiency: Double {
        guard timeInBed.isFinite, timeInBed > 0, totalSleepDuration.isFinite else { return 0 }
        return min(100, max(0, (totalSleepDuration / timeInBed) * 100))
    }

    /// Sleep quality score (0-100)
    /// Duration thresholds: Hirshkowitz M et al. (2015). "National Sleep Foundation's sleep time
    /// duration recommendations." Sleep Health 1(1):40-43. (7-9h optimal for adults)
    /// Efficiency thresholds: Ohayon M et al. (2017). "National Sleep Foundation's sleep quality
    /// recommendations." Sleep Health 3(1):6-19. (≥85% = good efficiency)
    var qualityScore: Int {
        guard totalSleepDuration.isFinite, totalSleepDuration > 0 else { return 0 }
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
            return String(localized: "Excellent", comment: "Sleep quality: excellent (80-100)")
        case 60..<80:
            return String(localized: "Good", comment: "Sleep quality: good (60-79)")
        case 40..<60:
            return String(localized: "Average", comment: "Sleep quality: average (40-59)")
        default:
            return String(localized: "Insufficient", comment: "Sleep quality: insufficient (<40)")
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

    // Format sleep session time range (locale-aware 12/24h)
    var formattedSleepTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none

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

    var localizedDescription: String {
        switch self {
        case .awake: return String(localized: "Awake", comment: "Sleep stage: awake")
        case .rem: return String(localized: "REM Sleep", comment: "Sleep stage: REM/paradoxical sleep")
        case .core: return String(localized: "Light Sleep", comment: "Sleep stage: core/light sleep")
        case .deep: return String(localized: "Deep Sleep", comment: "Sleep stage: deep sleep")
        case .inBed: return String(localized: "In Bed", comment: "Sleep stage: in bed")
        }
    }
}
