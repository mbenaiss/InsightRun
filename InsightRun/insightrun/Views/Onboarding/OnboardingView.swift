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
        remoteConfig.isFeatureEnabled(.strava) ? 5 : 4
    }

    // Strava step tag (only used when Strava is enabled)
    private var stravaStepTag: Int { 3 }

    // Paywall step tag depends on whether Strava is enabled
    private var paywallStepTag: Int {
        remoteConfig.isFeatureEnabled(.strava) ? 4 : 3
    }

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
                        withAnimation {
                            currentStep = 2
                        }
                    },
                    onSkip: {
                        AnalyticsService.shared.trackOnboardingStepCompleted(step: 2, stepName: "healthkit_permission")
                        withAnimation {
                            currentStep = 2
                        }
                    }
                )
                .tag(1)

                // Step 3: Notification Permission
                NotificationPermissionStepView(onContinue: {
                    AnalyticsService.shared.trackOnboardingStepCompleted(step: 3, stepName: "notification_permission")
                    withAnimation {
                        currentStep = remoteConfig.isFeatureEnabled(.strava) ? stravaStepTag : paywallStepTag
                    }
                })
                .tag(2)

                // Step 4: Strava Connection (only if enabled)
                if remoteConfig.isFeatureEnabled(.strava) {
                    StravaConnectionStepView(onContinue: {
                        AnalyticsService.shared.trackOnboardingStepCompleted(step: 4, stepName: "strava_connection")
                        withAnimation {
                            currentStep = paywallStepTag
                        }
                    })
                    .tag(stravaStepTag)
                }

                // Paywall (always present for stability)
                PaywallStepView(onContinue: {
                    let stepNumber = remoteConfig.isFeatureEnabled(.strava) ? 5 : 4
                    AnalyticsService.shared.trackOnboardingStepCompleted(step: stepNumber, stepName: "paywall")
                    completeOnboarding()
                }, stepNumber: remoteConfig.isFeatureEnabled(.strava) ? 5 : 4)
                .tag(paywallStepTag)
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
