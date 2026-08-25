//
//  OnboardingView.swift
//  InsightRun
//
//  Main onboarding flow container
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared

    @State private var currentStep = 0

    private let totalSteps = 2

    var body: some View {
        VStack(spacing: 0) {
            // Progress Indicator
            OnboardingProgressView(currentStep: currentStep, totalSteps: totalSteps)
                .padding(.top, Spacing.base)
                .padding(.bottom, Spacing.sm)

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

                // Step 2: HealthKit Permission (optional — user can skip)
                HealthKitPermissionStepView(
                    onContinue: {
                        AnalyticsService.shared.trackOnboardingStepCompleted(step: 2, stepName: "healthkit_permission")
                        completeOnboarding()
                    },
                    onSkip: {
                        AnalyticsService.shared.trackOnboardingStepCompleted(step: 2, stepName: "healthkit_permission")
                        completeOnboarding()
                    }
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.irBackgroundApp)
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
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.xxs) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.irPrimaryAccent : Color.irBorder)
                        .frame(height: 3)
                        .animation(.easeInOut, value: currentStep)
                }
            }
            .padding(.horizontal, Spacing.cardPadding)

            Text(String(localized: "Step \(currentStep + 1) of \(totalSteps)", comment: "Onboarding progress text"))
                .font(IRFont.microLabel)
                .fontWeight(.semibold)
                .tracking(0.6)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(RevenueCatManager.shared)
}
