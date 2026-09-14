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
    @State private var pendingPurchasePrice = "unknown"
    @State private var pendingPurchaseProductId: String?
    private let outcomeTracker = SubscriptionOutcomeTracker()

    private var purchaseSource: String { isInitialFlow ? "onboarding" : "locked_content" }

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
            .onPurchaseStarted { package in
                pendingPurchasePrice = package.storeProduct.localizedPriceString
                pendingPurchaseProductId = package.storeProduct.productIdentifier
                AnalyticsService.shared.trackSubscriptionPurchaseStarted(
                    productId: package.storeProduct.productIdentifier,
                    price: package.storeProduct.localizedPriceString,
                    billingPeriod: String(describing: package.packageType),
                    source: purchaseSource
                )
            }
            .onPurchaseCompleted { transaction, customerInfo in
                let entitlement = customerInfo.entitlements.active.values.first
                outcomeTracker.purchaseCompleted(
                    productId: transaction?.productIdentifier ?? entitlement?.productIdentifier ?? pendingPurchaseProductId,
                    revenue: pendingPurchasePrice,
                    isTrial: entitlement?.periodType == .trial,
                    hasActiveSubscription: entitlement != nil,
                    source: purchaseSource
                )
                pendingPurchaseProductId = nil

                revenueCatManager.applyCustomerInfo(customerInfo, trackLifecycleChanges: false)
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
            .onPurchaseFailure { error in
                outcomeTracker.purchaseFailed(error: error, productId: pendingPurchaseProductId, source: purchaseSource)
                pendingPurchaseProductId = nil
            }
            .onPurchaseCancelled {
                outcomeTracker.purchaseCancelled(productId: pendingPurchaseProductId, source: purchaseSource)
                pendingPurchaseProductId = nil
            }
            .onRestoreFailure { error in
                outcomeTracker.restoreFailed(error: error, source: purchaseSource)
            }
            .onRestoreCompleted { customerInfo in
                let productId = customerInfo.entitlements.active.values.first?.productIdentifier
                outcomeTracker.restored(
                    productId: productId,
                    source: purchaseSource
                )
                revenueCatManager.applyCustomerInfo(customerInfo, trackLifecycleChanges: false)
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
