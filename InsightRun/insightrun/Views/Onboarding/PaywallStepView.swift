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
    var stepNumber: Int = 4

    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    var body: some View {
        Group {
            if revenueCatManager.isSubscriptionActive {
                // User is already subscribed - show confirmation screen
                AlreadySubscribedView(onContinue: onContinue, stepNumber: stepNumber)
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
            AnalyticsService.shared.trackOnboardingStepViewed(step: stepNumber, stepName: "paywall")
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
    var stepNumber: Int = 4

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Premium Icon
            ZStack {
                Circle()
                    .fill(Color.irWarning.gradient)
                    .frame(width: 120, height: 120)

                Image(systemName: "crown.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 12) {
                Text(String(localized: "paywall.alreadySubscribed.title", comment: "Title shown when user is already premium"))
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "paywall.alreadySubscribed.message", comment: "Message shown when user is already premium"))
                    .font(.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Continue Button
            Button(action: onContinue) {
                Text(String(localized: "paywall.alreadySubscribed.continue", comment: "Continue button when already subscribed"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.irPrimaryAccent)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: stepNumber, stepName: "paywall_already_subscribed")
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
                .foregroundStyle(Color.irWarning.gradient)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }

            Spacer()

            Image(systemName: "star.fill")
                .font(.title3)
                .foregroundStyle(Color.irWarning)
        }
    }
}

#Preview {
    PaywallStepView(onContinue: {})
        .environmentObject(RevenueCatManager.shared)
}
