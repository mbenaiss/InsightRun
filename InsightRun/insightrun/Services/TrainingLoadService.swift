//
//  TrainingLoadService.swift
//  InsightRun
//
//  Service for tracking training load, detecting overtraining risk,
//  and monitoring inactivity periods for proactive coaching
//

import Foundation
import Combine

@MainActor
class TrainingLoadService: ObservableObject {
    static let shared = TrainingLoadService()

    @Published var weeklyVolumeChange: Double?
    @Published var daysSinceLastWorkout: Int?
    @Published var isOvertrainingRisk: Bool = false
    @Published var isInactive: Bool = false

    private let healthKitManager = HealthKitManager.shared
    private let volumeIncreaseThreshold = 10.0 // 10% increase triggers warning
    private let inactivityThreshold = 4 // 4+ days without workout

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
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
            let thisWeekWorkouts = try await healthKitManager.fetchRunningWorkouts(from: weekStart, to: today)
            let thisWeekVolume = thisWeekWorkouts.compactMap { $0.distance }.reduce(0, +)

            // Previous week's range (same days of the week for fair comparison)
            let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
            let daysIntoWeek = calendar.component(.weekday, from: today) - calendar.component(.weekday, from: weekStart)
            let prevWeekEnd = calendar.date(byAdding: .day, value: daysIntoWeek, to: prevWeekStart)!
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
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
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
