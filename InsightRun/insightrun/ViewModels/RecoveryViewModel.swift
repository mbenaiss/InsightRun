//
//  RecoveryViewModel.swift
//  InsightRun
//
//  ViewModel for recovery and readiness metrics
//

import SwiftUI
import Combine

@MainActor
class RecoveryViewModel: ObservableObject {
    @Published var recoveryMetrics: RecoveryMetrics?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedDate = Date()
    @Published var recentWorkoutsCount: Int = 0

    private let healthKitManager = HealthKitManager.shared

    func loadRecoveryMetrics() async {
        isLoading = true
        errorMessage = nil

        do {
            recoveryMetrics = try await healthKitManager.fetchRecoveryMetrics(for: selectedDate)
            await loadRecentWorkoutsCount()
        } catch {
            errorMessage = "Impossible de charger les métriques de récupération: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Load count of recent workouts (last 7 days)
    private func loadRecentWorkoutsCount() async {
        do {
            let allWorkouts = try await healthKitManager.fetchRunningWorkouts()

            // Count workouts from the last 7 days
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            recentWorkoutsCount = allWorkouts.filter { $0.startDate >= sevenDaysAgo }.count
        } catch {
            // If we can't fetch workouts, set count to 0
            recentWorkoutsCount = 0
        }
    }

    func refresh() async {
        await loadRecoveryMetrics()
    }

    func goToPreviousDay() async {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        await loadRecoveryMetrics()
    }

    func goToNextDay() async {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        await loadRecoveryMetrics()
    }

    func goToToday() async {
        selectedDate = Date()
        await loadRecoveryMetrics()
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        if Calendar.current.isDateInToday(selectedDate) {
            return String(localized: "Today", comment: "Label for today's date")
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return String(localized: "Yesterday", comment: "Label for yesterday's date")
        } else {
            formatter.dateFormat = "EEEE d MMMM yyyy"
            return formatter.string(from: selectedDate).capitalized
        }
    }
}
