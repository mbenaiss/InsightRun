//
//  WelcomeStepView.swift
//  InsightRun
//
//  Onboarding Step 1: Welcome and value proposition
//

import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated illustration
            AnimatedOnboardingIllustration(type: .welcome)

            // App Icon & Title
            VStack(spacing: 16) {
                Text(String(localized: "Welcome to Insight Run", comment: "Onboarding welcome title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.irTextPrimary)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal)

                Text(String(localized: "Your intelligent running coach", comment: "Onboarding welcome subtitle"))
                    .font(.title3)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .opacity(titleOpacity)

            // Features List
            VStack(spacing: 24) {
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    color: .blue,
                    title: String(localized: "Advanced tracking", comment: "Onboarding feature: tracking"),
                    description: String(localized: "Detailed metrics for all your runs", comment: "Onboarding feature: tracking description")
                )

                FeatureRow(
                    icon: "brain.head.profile",
                    color: .purple,
                    title: String(localized: "AI Coach", comment: "Onboarding feature: AI"),
                    description: String(localized: "Personalized advice and analysis", comment: "Onboarding feature: AI description")
                )

                FeatureRow(
                    icon: "heart.fill",
                    color: .red,
                    title: String(localized: "Recovery analysis", comment: "Onboarding feature: recovery"),
                    description: String(localized: "Track your fitness and readiness", comment: "Onboarding feature: recovery description")
                )

                FeatureRow(
                    icon: "chart.bar.fill",
                    color: .green,
                    title: String(localized: "Progress tracking", comment: "Onboarding feature: progress"),
                    description: String(localized: "Visualize your evolution over time", comment: "Onboarding feature: progress description")
                )
            }
            .padding(.horizontal, 24)
            .opacity(contentOpacity)

            Spacer()

            // Continue Button
            Button(action: onContinue) {
                Text(String(localized: "Get started", comment: "Onboarding continue button"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.irPrimaryAccent.gradient)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 1, stepName: "welcome")
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                titleOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                contentOpacity = 1
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color.gradient)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.1))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
            }

            Spacer()
        }
    }
}

#Preview {
    WelcomeStepView(onContinue: {})
}
