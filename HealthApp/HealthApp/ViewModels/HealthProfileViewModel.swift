//
//  HealthProfileViewModel.swift
//  HealthApp
//
//  ViewModel for health profile and body metrics
//

import SwiftUI
import Combine

@MainActor
class HealthProfileViewModel: ObservableObject {
    @Published var healthProfile: HealthProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let healthKitManager = HealthKitManager.shared

    func loadHealthProfile() async {
        isLoading = true
        errorMessage = nil

        do {
            healthProfile = try await healthKitManager.fetchHealthProfile()
        } catch {
            errorMessage = "Impossible de charger le profil de santé: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func refresh() async {
        await loadHealthProfile()
    }
}
