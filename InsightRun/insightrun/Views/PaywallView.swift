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

    var isInitialFlow: Bool = false

    var onDismiss: (() -> Void)? = nil

    @State private var paywallAppearTime: Date?
    @State private var showConsentSheet = false
    @State private var hasConsented = false

    var body: some View {
        Group {
            if !hasConsented && ConsentService.shared.isConsentRequired() {
                Color.clear
                    .sheet(isPresented: .constant(true)) {
                        AIConsentSheet(
                            onConsent: {
                                hasConsented = true
                            },
                            onDecline: {
                                if let onDismiss = onDismiss {
                                    onDismiss()
                                } else {
                                    dismiss()
                                }
                            }
                        )
                    }
            } else {
                actualPaywallView
            }
        }
        .onAppear {
            hasConsented = !ConsentService.shared.isConsentRequired()
        }
    }

    private var actualPaywallView: some View {
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
