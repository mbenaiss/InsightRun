//
//  RecoveryViewModel.swift
//  HealthApp
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

    private let healthKitManager = HealthKitManager.shared

    func loadRecoveryMetrics() async {
        isLoading = true
        errorMessage = nil

        do {
            recoveryMetrics = try await healthKitManager.fetchRecoveryMetrics(for: selectedDate)
        } catch {
            errorMessage = "Impossible de charger les métriques de récupération: \(error.localizedDescription)"
        }

        isLoading = false
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
        formatter.locale = Locale(identifier: "fr_FR")

        if Calendar.current.isDateInToday(selectedDate) {
            return "Aujourd'hui"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Hier"
        } else {
            formatter.dateFormat = "EEEE d MMMM yyyy"
            return formatter.string(from: selectedDate).capitalized
        }
    }
}
