//
//  OnboardingPaywallTrigger.swift
//  InsightRun
//

import Combine
import Foundation

@MainActor
final class OnboardingPaywallTrigger: ObservableObject {
    static let shared = OnboardingPaywallTrigger()

    @Published var isPresented = false

    // Persisted so a user who quits the app on the activation workout still gets the paywall on the next launch.
    private static let armedKey = "onboardingPaywallArmed"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func arm() {
        defaults.set(true, forKey: Self.armedKey)
    }

    func fireIfArmed(revenueCatManager: RevenueCatManager) {
        guard defaults.bool(forKey: Self.armedKey), revenueCatManager.isSubscriptionStatusResolved else { return }
        defaults.set(false, forKey: Self.armedKey)
        guard !revenueCatManager.isSubscriptionActive, !revenueCatManager.hasSeenInitialPaywall else { return }
        Task {
            // Let the pop or tab transition finish before presenting the full-screen cover.
            try? await Task.sleep(for: .milliseconds(450))
            isPresented = true
        }
    }
}
