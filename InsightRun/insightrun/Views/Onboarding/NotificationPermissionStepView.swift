//
//  NotificationPermissionStepView.swift
//  InsightRun
//
//  Onboarding Step 3: Notification permissions request (Pulse-Ring layout).
//

import SwiftUI

struct NotificationPermissionStepView: View {
    let onContinue: () -> Void

    @State private var isRequesting = false
    @State private var contentOpacity: Double = 0

    var body: some View {
        OnboardingScaffold(
            primaryTitle: String(localized: "Allow notifications", comment: "Onboarding notification allow button"),
            primaryAction: requestNotificationPermission,
            isPrimaryLoading: isRequesting,
            secondaryTitle: String(localized: "Skip for now", comment: "Onboarding notification skip button"),
            secondaryAction: skip
        ) {
            VStack(spacing: 24) {
                AnimatedOnboardingIllustration(type: .notifications)

                OnboardingEditorialHeader(
                    eyebrow: String(localized: "onboarding.notifications.eyebrow", defaultValue: "Notifications", comment: "Onboarding notifications eyebrow"),
                    title: String(localized: "Stay on track", comment: "Onboarding notification title"),
                    body: String(localized: "Notifications help you stay consistent with daily readiness scores, coaching alerts, and weekly summaries", comment: "Onboarding notification description")
                )

                VStack(spacing: 8) {
                    OnboardingFeatureCard(
                        icon: "sunrise.fill",
                        iconTint: .irWarning,
                        title: String(localized: "Daily readiness score", comment: "Onboarding notification: daily readiness"),
                        description: String(localized: "Get your readiness score each morning", comment: "Onboarding notification: daily readiness description")
                    )
                    OnboardingFeatureCard(
                        icon: "chart.bar.fill",
                        iconTint: .irPrimaryAccent,
                        title: String(localized: "Weekly summary", comment: "Onboarding notification: weekly summary"),
                        description: String(localized: "Review your training week every Sunday", comment: "Onboarding notification: weekly summary description")
                    )
                    OnboardingFeatureCard(
                        icon: "exclamationmark.triangle.fill",
                        iconTint: .irError,
                        title: String(localized: "Smart alerts", comment: "Onboarding notification: smart alerts"),
                        description: String(localized: "Warnings for overtraining and inactivity", comment: "Onboarding notification: smart alerts description")
                    )
                }

                settingsHint
            }
            .opacity(contentOpacity)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 3, stepName: "notification_permission")
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                contentOpacity = 1
            }
        }
    }

    private var settingsHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.irTextSecondary)
            Text(String(localized: "You can enable notifications later in Settings", comment: "Onboarding notification optional note"))
                .font(.system(size: 11))
                .foregroundStyle(Color.irTextSecondary)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func skip() {
        AnalyticsService.shared.trackNotificationPermissionSkipped()
        onContinue()
    }

    private func requestNotificationPermission() {
        isRequesting = true
        Task {
            let granted = await NotificationManager.shared.requestPermissions()
            if granted {
                NotificationManager.shared.enableDailyReadiness()
                NotificationManager.shared.scheduleWeeklySummary()
                NotificationManager.shared.scheduleWeeklyAIInsight()
                AnalyticsService.shared.trackNotificationPermissionGranted()
            } else {
                AnalyticsService.shared.trackNotificationPermissionDenied()
            }
            await MainActor.run {
                isRequesting = false
                onContinue()
            }
        }
    }
}

#Preview {
    NotificationPermissionStepView(onContinue: {})
}
