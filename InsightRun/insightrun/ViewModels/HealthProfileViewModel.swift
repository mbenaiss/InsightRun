//
//  HealthProfileViewModel.swift
//  InsightRun
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
            errorMessage = String(localized: "Unable to load health profile: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func refresh() async {
        await loadHealthProfile()
    }
}
