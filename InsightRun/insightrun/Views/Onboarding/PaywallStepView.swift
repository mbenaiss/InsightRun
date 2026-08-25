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
    @State private var pendingPurchasePrice = "unknown"

    var body: some View {
        Group {
            if revenueCatManager.isSubscriptionActive {
                // User is already subscribed - show confirmation screen
                AlreadySubscribedView(onContinue: onContinue, stepNumber: stepNumber)
            } else {
                // User is not subscribed - show paywall
                PaywallView()
                    .onPurchaseStarted { package in
                        pendingPurchasePrice = package.storeProduct.localizedPriceString
                        AnalyticsService.shared.trackSubscriptionPurchaseStarted(
                            productId: package.storeProduct.productIdentifier,
                            price: package.storeProduct.localizedPriceString,
                            billingPeriod: String(describing: package.packageType)
                        )
                    }
                    .onPurchaseCompleted { transaction, customerInfo in
                        if let entitlement = customerInfo.entitlements.active.values.first {
                            AnalyticsService.shared.trackSubscriptionPurchaseCompleted(
                                productId: transaction?.productIdentifier ?? entitlement.productIdentifier,
                                revenue: pendingPurchasePrice,
                                isTrial: entitlement.periodType == .trial,
                                source: "onboarding"
                            )
                        }
                        revenueCatManager.applyCustomerInfo(customerInfo, trackLifecycleChanges: false)
                        Task {
                            await revenueCatManager.fetchCustomerInfo()
                        }
                        revenueCatManager.markPaywallAsSeen()
                        onContinue()
                    }
                    .onRestoreCompleted { customerInfo in
                        AnalyticsService.shared.trackSubscriptionRestored(
                            productId: customerInfo.entitlements.active.values.first?.productIdentifier,
                            source: "onboarding"
                        )
                        revenueCatManager.applyCustomerInfo(customerInfo, trackLifecycleChanges: false)
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

    @State private var contentOpacity: Double = 0

    var body: some View {
        OnboardingScaffold(
            primaryTitle: String(localized: "paywall.alreadySubscribed.continue", comment: "Continue button when already subscribed"),
            primaryAction: onContinue
        ) {
            VStack(spacing: Spacing.xl) {
                AnimatedOnboardingIllustration(type: .paywall)

                OnboardingEditorialHeader(
                    eyebrow: String(localized: "onboarding.paywall.eyebrow", defaultValue: "Premium", comment: "Onboarding paywall eyebrow"),
                    title: String(localized: "paywall.alreadySubscribed.title", comment: "Title shown when user is already premium"),
                    body: String(localized: "paywall.alreadySubscribed.message", comment: "Message shown when user is already premium")
                )
            }
            .opacity(contentOpacity)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: stepNumber, stepName: "paywall_already_subscribed")
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                contentOpacity = 1
            }
        }
    }
}

#Preview {
    PaywallStepView(onContinue: {})
        .environmentObject(RevenueCatManager.shared)
}
