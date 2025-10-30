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
            .onAppear {
                AnalyticsService.shared.trackOnboardingStepViewed(step: 3, stepName: "paywall")
                AnalyticsService.shared.trackPaywallViewed(
                    triggerSource: "onboarding",
                    availableProducts: ["premium_subscription"]
                )
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
