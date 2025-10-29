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

    @State private var paywallAppearTime: Date?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Show explanatory text for initial flow
                if isInitialFlow {
                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.yellow.gradient)

                        Text(String(localized: "Subscribe to access your workouts", comment: "Paywall initial flow title"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text(String(localized: "Unlock unlimited access to your running data, AI coaching, and advanced analytics", comment: "Paywall initial flow description"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }

                PaywallView()
                    .onPurchaseCompleted { customerInfo in
                        // Track purchase completed
                        let activeEntitlements = customerInfo.entitlements.active.values
                        if let entitlement = activeEntitlements.first,
                           let productId = entitlement.productIdentifier as String? {
                            let isTrial = entitlement.periodType == .trial

                            AnalyticsService.shared.trackSubscriptionPurchaseCompleted(
                                productId: productId,
                                revenue: "unknown", // RevenueCat doesn't provide price in customerInfo
                                isTrial: isTrial
                            )
                        }

                        // Purchase completed successfully
                        Task {
                            await revenueCatManager.fetchCustomerInfo()
                        }
                        // Mark as seen
                        revenueCatManager.markPaywallAsSeen()
                        dismiss()
                    }
                    .onRestoreCompleted { customerInfo in
                        // Restore completed successfully
                        Task {
                            await revenueCatManager.fetchCustomerInfo()
                        }
                        // Mark as seen
                        revenueCatManager.markPaywallAsSeen()
                        dismiss()
                    }
                    .onAppear {
                        // Track paywall viewed
                        paywallAppearTime = Date()
                        let triggerSource = isInitialFlow ? "onboarding" : "locked_content"
                        AnalyticsService.shared.trackPaywallViewed(
                            triggerSource: triggerSource,
                            availableProducts: ["premium_subscription"] // TODO: Get actual products from RevenueCat
                        )
                    }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isInitialFlow ? String(localized: "Later", comment: "Dismiss paywall button") : String(localized: "Close", comment: "Close button")) {
                        // Track paywall dismissed
                        if let startTime = paywallAppearTime {
                            let timeSpent = Date().timeIntervalSince(startTime)
                            AnalyticsService.shared.trackPaywallDismissed(timeSpentSeconds: timeSpent)
                        }

                        // Mark as seen even if dismissed
                        if isInitialFlow {
                            revenueCatManager.markPaywallAsSeen()
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SubscriptionPaywallView()
        .environmentObject(RevenueCatManager.shared)
}
