//
//  PaywallStepView.swift
//  InsightRun
//
//  Onboarding Step 3: Premium subscription offer
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallStepView: View {
    let onContinue: () -> Void

    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    var body: some View {
        Group {
            if revenueCatManager.isSubscriptionActive {
                // User is already subscribed - show confirmation screen
                AlreadySubscribedView(onContinue: onContinue)
            } else {
                // User is not subscribed - show paywall
                PaywallView()
                    .onPurchaseCompleted { customerInfo in
                        // Purchase completed successfully
                        Task {
                            await revenueCatManager.fetchCustomerInfo()
                        }
                        revenueCatManager.markPaywallAsSeen()
                        onContinue()
                    }
                    .onRestoreCompleted { customerInfo in
                        // Restore completed successfully
                        Task {
                            await revenueCatManager.fetchCustomerInfo()
                        }
                        revenueCatManager.markPaywallAsSeen()
                        onContinue()
                    }
                    .onRequestedDismissal {
                        // User tapped "Skip now" button from RevenueCat paywall
                        revenueCatManager.markPaywallAsSeen()
                        onContinue()
                    }
            }
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 3, stepName: "paywall")
            if !revenueCatManager.isSubscriptionActive {
                AnalyticsService.shared.trackPaywallViewed(
                    triggerSource: "onboarding",
                    availableProducts: ["premium_subscription"]
                )
            }
        }
    }
}

// MARK: - Already Subscribed View

struct AlreadySubscribedView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Premium Icon
            ZStack {
                Circle()
                    .fill(Color.yellow.gradient)
                    .frame(width: 120, height: 120)

                Image(systemName: "crown.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 12) {
                Text("You're Already Premium!")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Your subscription is active.\nEnjoy all premium features!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Continue Button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 3, stepName: "paywall_already_subscribed")
        }
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
