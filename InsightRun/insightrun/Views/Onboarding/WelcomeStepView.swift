//
//  WelcomeStepView.swift
//  InsightRun
//
//  Onboarding Step 1: Welcome and value proposition (Pulse-Ring layout).
//

import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void

    @State private var contentOpacity: Double = 0

    var body: some View {
        OnboardingScaffold(
            primaryTitle: String(localized: "Get started", comment: "Onboarding continue button"),
            primaryAction: onContinue
        ) {
            VStack(spacing: Spacing.xl) {
                AnimatedOnboardingIllustration(type: .welcome)

                OnboardingEditorialHeader(
                    eyebrow: String(localized: "onboarding.welcome.eyebrow", defaultValue: "Welcome", comment: "Onboarding welcome eyebrow"),
                    title: String(localized: "Welcome to Insight Run", comment: "Onboarding welcome title"),
                    body: String(localized: "Your intelligent running coach. Detailed metrics, AI analysis, recovery and progression — in one place.", comment: "Onboarding welcome subtitle")
                )

                VStack(spacing: Spacing.sm) {
                    OnboardingFeatureCard(
                        icon: "chart.line.uptrend.xyaxis",
                        iconTint: .irPrimaryAccent,
                        title: String(localized: "Advanced tracking", comment: "Onboarding feature: tracking"),
                        description: String(localized: "Detailed metrics for all your runs", comment: "Onboarding feature: tracking description")
                    )
                    OnboardingFeatureCard(
                        icon: "sparkles",
                        iconTint: .irPrimaryAccent,
                        title: String(localized: "AI Coach", comment: "Onboarding feature: AI"),
                        description: String(localized: "Personalized advice and analysis", comment: "Onboarding feature: AI description")
                    )
                    OnboardingFeatureCard(
                        icon: "heart.fill",
                        iconTint: .irError,
                        title: String(localized: "Recovery analysis", comment: "Onboarding feature: recovery"),
                        description: String(localized: "Track your fitness and readiness", comment: "Onboarding feature: recovery description")
                    )
                    OnboardingFeatureCard(
                        icon: "chart.bar.fill",
                        iconTint: .irSuccess,
                        title: String(localized: "Progress tracking", comment: "Onboarding feature: progress"),
                        description: String(localized: "Visualize your evolution over time", comment: "Onboarding feature: progress description")
                    )
                }
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 1, stepName: "welcome")
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                contentOpacity = 1
            }
        }
    }
}

#Preview {
    WelcomeStepView(onContinue: {})
}
