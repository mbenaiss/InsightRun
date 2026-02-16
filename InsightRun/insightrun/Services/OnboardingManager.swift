//
//  OnboardingManager.swift
//  InsightRun
//
//  Manages onboarding flow state
//

import Foundation
import Combine

@MainActor
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published private(set) var hasCompletedOnboarding: Bool

    private let hasCompletedKey = "hasCompletedOnboarding"

    private init() {
        self.hasCompletedOnboarding = DemoMode.isEnabled || UserDefaults.standard.bool(forKey: hasCompletedKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: hasCompletedKey)

        // Track onboarding completion
        AnalyticsService.shared.trackOnboardingCompleted()
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: hasCompletedKey)
    }
}
