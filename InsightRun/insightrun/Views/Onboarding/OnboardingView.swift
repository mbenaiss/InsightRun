//
//  OnboardingView.swift
//  InsightRun
//
//  Main onboarding flow container
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @ObservedObject private var remoteConfig = RemoteConfigService.shared

    @State private var currentStep = 0

    // Number of onboarding steps depends on Strava feature flag
    private var totalSteps: Int {
        remoteConfig.isFeatureEnabled(.strava) ? 4 : 3 // 4 with Strava, 3 without
    }

    // Paywall step tag depends on whether Strava is enabled
    private var paywallStepTag: Int {
        remoteConfig.isFeatureEnabled(.strava) ? 3 : 2
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress Indicator
            OnboardingProgressView(currentStep: currentStep, totalSteps: totalSteps)
                .padding(.top, 16)

            // Steps
            TabView(selection: $currentStep) {
                // Step 1: Welcome
                WelcomeStepView(onContinue: {
                    AnalyticsService.shared.trackOnboardingStepCompleted(step: 1, stepName: "welcome")
                    withAnimation {
                        currentStep = 1
                    }
                })
                .tag(0)

                // Step 2: HealthKit Permission
                HealthKitPermissionStepView(onContinue: {
                    AnalyticsService.shared.trackOnboardingStepCompleted(step: 2, stepName: "healthkit_permission")
                    withAnimation {
                        // Skip to paywall if Strava is disabled
                        currentStep = remoteConfig.isFeatureEnabled(.strava) ? 2 : paywallStepTag
                    }
                })
                .tag(1)

                // Step 3: Strava Connection (only if enabled)
                if remoteConfig.isFeatureEnabled(.strava) {
                    StravaConnectionStepView(onContinue: {
                        AnalyticsService.shared.trackOnboardingStepCompleted(step: 3, stepName: "strava_connection")
                        withAnimation {
                            currentStep = paywallStepTag
                        }
                    })
                    .tag(2)
                }

                // Paywall (always present for stability)
                PaywallStepView(onContinue: {
                    let stepNumber = remoteConfig.isFeatureEnabled(.strava) ? 4 : 3
                    AnalyticsService.shared.trackOnboardingStepCompleted(step: stepNumber, stepName: "paywall")
                    completeOnboarding()
                })
                .tag(paywallStepTag)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)
        }
        .interactiveDismissDisabled() // Prevent swipe to dismiss
        .onAppear {
            AnalyticsService.shared.trackOnboardingStarted()
        }
    }

    private func completeOnboarding() {
        onboardingManager.completeOnboarding()
    }
}

struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(step <= currentStep ? Color.irPrimaryAccent : Color.irBorder.opacity(0.5))
                        .frame(height: 4)
                        .animation(.easeInOut, value: currentStep)
                }
            }
            .padding(.horizontal, 24)

            Text(String(localized: "Step \(currentStep + 1) of \(totalSteps)", comment: "Onboarding progress text"))
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(RevenueCatManager.shared)
}
