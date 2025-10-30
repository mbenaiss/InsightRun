//
//  PaywallView.swift
//  InsightRun
//
//  Subscription paywall using RevenueCat UI
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct SubscriptionPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    // Indicates if this is the initial paywall shown after HealthKit authorization
    var isInitialFlow: Bool = false

    // Optional callback when paywall is dismissed (for onboarding flow)
    var onDismiss: (() -> Void)? = nil

    @State private var paywallAppearTime: Date?

    var body: some View {
        PaywallView()
            .onPurchaseCompleted { customerInfo in
                // Track purchase completed
                let activeEntitlements = customerInfo.entitlements.active.values
                if let entitlement = activeEntitlements.first,
                   let productId = entitlement.productIdentifier as String? {
                    let isTrial = entitlement.periodType == .trial

                    AnalyticsService.shared.trackSubscriptionPurchaseCompleted(
                        productId: productId,
                        revenue: "unknown",
                        isTrial: isTrial
                    )
                }

                // Purchase completed successfully
                Task {
                    await revenueCatManager.fetchCustomerInfo()
                }
                revenueCatManager.markPaywallAsSeen()

                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
            .onRestoreCompleted { customerInfo in
                // Restore completed successfully
                Task {
                    await revenueCatManager.fetchCustomerInfo()
                }
                revenueCatManager.markPaywallAsSeen()

                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
            .onRequestedDismissal {
                // User tapped "Skip now" or close button from RevenueCat paywall
                if let startTime = paywallAppearTime {
                    let timeSpent = Date().timeIntervalSince(startTime)
                    AnalyticsService.shared.trackPaywallDismissed(timeSpentSeconds: timeSpent)
                }

                revenueCatManager.markPaywallAsSeen()

                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
            .onAppear {
                paywallAppearTime = Date()
                let triggerSource = isInitialFlow ? "onboarding" : "locked_content"
                AnalyticsService.shared.trackPaywallViewed(
                    triggerSource: triggerSource,
                    availableProducts: ["premium_subscription"]
                )
            }
    }
}

#Preview {
    SubscriptionPaywallView()
        .environmentObject(RevenueCatManager.shared)
}
