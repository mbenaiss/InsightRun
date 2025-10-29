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

    @State private var currentStep = 0

    // Calculate total steps based on subscription status
    private var totalSteps: Int {
        revenueCatManager.isSubscriptionActive ? 2 : 3
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

                    // Check if user is already subscribed
                    if revenueCatManager.isSubscriptionActive {
                        // Skip paywall step and complete onboarding
                        completeOnboarding()
                    } else {
                        // Show paywall step
                        withAnimation {
                            currentStep = 2
                        }
                    }
                })
                .tag(1)

                // Step 3: Paywall (only if not subscribed)
                if !revenueCatManager.isSubscriptionActive {
                    PaywallStepView(onContinue: {
                        AnalyticsService.shared.trackOnboardingStepCompleted(step: 3, stepName: "paywall")
                        completeOnboarding()
                    })
                    .tag(2)
                }
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
                        .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .animation(.easeInOut, value: currentStep)
                }
            }
            .padding(.horizontal, 24)

            Text(String(localized: "Step \(currentStep + 1) of \(totalSteps)", comment: "Onboarding progress text"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(RevenueCatManager.shared)
}
