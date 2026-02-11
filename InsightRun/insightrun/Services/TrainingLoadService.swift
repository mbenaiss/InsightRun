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

@MainActor
class TrainingLoadService: ObservableObject {
    static let shared = TrainingLoadService()

    @Published var weeklyVolumeChange: Double?
    @Published var daysSinceLastWorkout: Int?
    @Published var isOvertrainingRisk: Bool = false
    @Published var isInactive: Bool = false

    @Published var cardiacLoadScore: Int?
    @Published var cardiacLoadStatus: CardiacLoadStatus = .detraining
    @Published var cardiacLoadTrendData: [TrendDataPoint] = []

    private let healthKitManager = HealthKitManager.shared
    private let volumeIncreaseThreshold = 10.0 // 10% increase triggers warning
    private let inactivityThreshold = 4 // 4+ days without workout
    private let maxLoadNormalization: Double = 500

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

    // MARK: - Cardiac Load Analysis

    func analyzeCardiacLoad() async {
        do {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            guard let startDate = calendar.date(byAdding: .day, value: -21, to: today) else { return }

            let workouts = try await healthKitManager.fetchRunningWorkouts(from: startDate, to: Date())

            var dailyLoad: [Date: Double] = [:]
            for dayOffset in -20...0 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
                dailyLoad[calendar.startOfDay(for: day)] = 0
            }

            for workout in workouts {
                let day = calendar.startOfDay(for: workout.startDate)
                let durationMin = workout.duration / 60.0
                let intensity = intensityFactor(for: workout)
                dailyLoad[day, default: 0] += durationMin * intensity
            }

            var trendPoints: [TrendDataPoint] = []
            var currentWeekLoad: Double = 0
            var previousWeekLoad: Double = 0

            for dayOffset in -13...0 {
                guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
                let targetStart = calendar.startOfDay(for: targetDay)

                var rollingLoad: Double = 0
                for lookback in 0..<7 {
                    guard let lookbackDay = calendar.date(byAdding: .day, value: -lookback, to: targetStart) else { continue }
                    let dayLoad = dailyLoad[calendar.startOfDay(for: lookbackDay)] ?? 0
                    let decay = exp(-0.1 * Double(lookback))
                    rollingLoad += dayLoad * decay
                }

                trendPoints.append(TrendDataPoint(date: targetStart, value: rollingLoad))

                if dayOffset >= -6 {
                    currentWeekLoad += dailyLoad[targetStart] ?? 0
                } else {
                    previousWeekLoad += dailyLoad[targetStart] ?? 0
                }
            }

            let latestLoad = trendPoints.last?.value ?? 0
            let score = min(100, Int((latestLoad / maxLoadNormalization) * 100))

            let status: CardiacLoadStatus
            if currentWeekLoad == 0 && previousWeekLoad == 0 {
                status = .detraining
            } else if previousWeekLoad == 0 {
                status = .increasing
            } else {
                let changePercent = ((currentWeekLoad - previousWeekLoad) / previousWeekLoad) * 100
                if changePercent > 10 {
                    status = .increasing
                } else if changePercent < -30 {
                    status = .detraining
                } else if changePercent < -10 {
                    status = .decreasing
                } else {
                    status = .maintaining
                }
            }

            cardiacLoadScore = score
            cardiacLoadStatus = status
            cardiacLoadTrendData = trendPoints
        } catch {
            print("⚠️ TrainingLoadService: Failed to analyze cardiac load: \(error)")
            cardiacLoadScore = nil
        }
    }

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
