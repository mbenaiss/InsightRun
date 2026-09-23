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

    @State private var paywallAppearedAt: ContinuousClock.Instant?
    @State private var showConsentSheet = false
    @State private var hasConsented = !ConsentService.shared.isConsentRequired()
    @State private var consentShownInPaywall = false
    @State private var purchaseAttempt: PurchaseAttempt?
    private let outcomeTracker = SubscriptionOutcomeTracker()

    private let purchaseSource = "locked_content"

    var body: some View {
        if hasConsented {
            actualPaywallView
        } else {
            Color.clear
                .onAppear {
                    consentShownInPaywall = true
                    showConsentSheet = true
                }
                .sheet(isPresented: $showConsentSheet, onDismiss: {
                    // Show the paywall only once the sheet has finished dismissing, so no purchase starts mid-transition.
                    if !ConsentService.shared.isConsentRequired() {
                        hasConsented = true
                    }
                }) {
                    AIConsentSheet(
                        onConsent: {
                            showConsentSheet = false
                        },
                        onDecline: closePaywall
                    )
                }
        }
    }

    private var actualPaywallView: some View {
        PaywallView()
            .onPurchaseStarted { package in
                let product = package.storeProduct
                purchaseAttempt = outcomeTracker.purchaseStarted(
                    productId: product.productIdentifier,
                    price: product.price,
                    currency: product.currencyCode,
                    priceDisplay: product.localizedPriceString,
                    billingPeriod: String(describing: package.packageType),
                    source: purchaseSource,
                    paywallAppearedAt: paywallAppearedAt,
                    consentShownInPaywall: consentShownInPaywall
                )
            }
            .onPurchaseCompleted { transaction, customerInfo in
                let entitlement = customerInfo.entitlements.active.values.first
                outcomeTracker.purchaseCompleted(
                    purchaseAttempt,
                    productId: transaction?.productIdentifier ?? entitlement?.productIdentifier,
                    isTrial: entitlement?.periodType == .trial,
                    hasActiveSubscription: entitlement != nil,
                    source: purchaseSource
                )
                purchaseAttempt = nil

                revenueCatManager.applyCustomerInfo(customerInfo, trackLifecycleChanges: false)
                Task {
                    await revenueCatManager.fetchCustomerInfo()
                }
                revenueCatManager.markPaywallAsSeen()

                closePaywall()
            }
            .onPurchaseFailure { error in
                outcomeTracker.purchaseFailed(purchaseAttempt, error: error, source: purchaseSource)
                purchaseAttempt = nil
            }
            .onPurchaseCancelled {
                outcomeTracker.purchaseCancelled(purchaseAttempt, source: purchaseSource)
                purchaseAttempt = nil
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

                closePaywall()
            }
            .onRequestedDismissal {
                // User tapped "Skip now" or close button from RevenueCat paywall
                if let paywallAppearedAt {
                    let timeSpent = paywallAppearedAt.duration(to: .now) / .seconds(1)
                    AnalyticsService.shared.trackPaywallDismissed(timeSpentSeconds: timeSpent)
                }

                revenueCatManager.markPaywallAsSeen()

                closePaywall()
            }
            .onAppear {
                paywallAppearedAt = .now
                AnalyticsService.shared.trackPaywallViewed(
                    triggerSource: purchaseSource,
                    availableProducts: ["premium_subscription"]
                )
            }
    }

    private func closePaywall() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}

#Preview {
    SubscriptionPaywallView()
        .environmentObject(RevenueCatManager.shared)
}
