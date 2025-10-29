//
//  PaywallStepView.swift
//  InsightRun
//
//  Onboarding Step 3: Premium subscription offer
//

import SwiftUI
import RevenueCat

struct PaywallStepView: View {
    let onContinue: () -> Void

    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @State private var showFullPaywall = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon & Title
            VStack(spacing: 16) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.yellow.gradient)

                Text(String(localized: "Unlock all features", comment: "Onboarding paywall title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text(String(localized: "Get unlimited access to your running data and AI coaching", comment: "Onboarding paywall subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Premium Features
            VStack(spacing: 16) {
                PremiumFeatureRow(
                    icon: "infinity",
                    title: String(localized: "Unlimited workouts", comment: "Onboarding paywall feature: unlimited"),
                    description: String(localized: "Access all your running history", comment: "Onboarding paywall feature: unlimited description")
                )

                PremiumFeatureRow(
                    icon: "brain.head.profile",
                    title: String(localized: "AI Coach", comment: "Onboarding paywall feature: AI coach"),
                    description: String(localized: "Personalized analysis and advice", comment: "Onboarding paywall feature: AI coach description")
                )

                PremiumFeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: String(localized: "Advanced analytics", comment: "Onboarding paywall feature: analytics"),
                    description: String(localized: "Detailed metrics and progression", comment: "Onboarding paywall feature: analytics description")
                )

                PremiumFeatureRow(
                    icon: "heart.circle.fill",
                    title: String(localized: "Recovery tracking", comment: "Onboarding paywall feature: recovery"),
                    description: String(localized: "Optimize your training load", comment: "Onboarding paywall feature: recovery description")
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Subscription Buttons or RevenueCat Paywall
            VStack(spacing: 12) {
                // If user is already subscribed, just show continue button
                if revenueCatManager.isSubscriptionActive {
                    Button(action: {
                        onContinue()
                    }) {
                        Text(String(localized: "Continue", comment: "Continue button"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue.gradient)
                            .cornerRadius(16)
                    }
                } else {
                    // Show simple subscription options
                    Text(String(localized: "Choose your plan", comment: "Onboarding paywall plan title"))
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    // Note: In a real implementation, you would fetch prices from RevenueCat
                    // For now, we'll show a button that opens the full paywall
                    Button(action: openFullPaywall) {
                        VStack(spacing: 4) {
                            Text(String(localized: "Start Premium", comment: "Onboarding paywall subscribe button"))
                                .font(.headline)
                            Text(String(localized: "3 days free trial", comment: "Onboarding paywall trial"))
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .cornerRadius(16)
                    }

                    Button(action: {
                        // Track skip and continue
                        AnalyticsService.shared.trackPaywallDismissed(timeSpentSeconds: 0)
                        revenueCatManager.markPaywallAsSeen()
                        onContinue()
                    }) {
                        Text(String(localized: "Continue without Premium", comment: "Onboarding paywall skip button"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if showError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 3, stepName: "paywall")
            AnalyticsService.shared.trackPaywallViewed(
                triggerSource: "onboarding",
                availableProducts: ["premium_subscription"]
            )
        }
        .fullScreenCover(isPresented: $showFullPaywall) {
            SubscriptionPaywallView(isInitialFlow: true)
                .onDisappear {
                    // After paywall is dismissed, check if user subscribed
                    if revenueCatManager.isSubscriptionActive {
                        // User subscribed, continue onboarding
                        onContinue()
                    }
                    // If not subscribed, stay on this step
                }
        }
    }

    private func openFullPaywall() {
        showFullPaywall = true
    }
}

struct PremiumFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.yellow.gradient)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "star.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
        }
    }
}

#Preview {
    PaywallStepView(onContinue: {})
        .environmentObject(RevenueCatManager.shared)
}
