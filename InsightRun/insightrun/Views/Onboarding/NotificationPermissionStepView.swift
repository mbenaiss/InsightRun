//
//  NotificationPermissionStepView.swift
//  InsightRun
//
//  Onboarding Step 3: Notification permissions request
//

import SwiftUI

struct NotificationPermissionStepView: View {
    let onContinue: () -> Void

    @State private var isRequesting = false
    @State private var titleOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated illustration
            AnimatedOnboardingIllustration(type: .notifications)

            // Icon & Title
            VStack(spacing: 16) {
                Text(String(localized: "Stay on track", comment: "Onboarding notification title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "Notifications help you stay consistent with daily readiness scores, coaching alerts, and weekly summaries", comment: "Onboarding notification description"))
                    .font(.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .opacity(titleOpacity)

            // Feature List
            VStack(spacing: 16) {
                DataAccessRow(
                    icon: "sunrise.fill",
                    title: String(localized: "Daily readiness score", comment: "Onboarding notification: daily readiness"),
                    description: String(localized: "Get your readiness score each morning", comment: "Onboarding notification: daily readiness description")
                )

                DataAccessRow(
                    icon: "chart.bar.fill",
                    title: String(localized: "Weekly summary", comment: "Onboarding notification: weekly summary"),
                    description: String(localized: "Review your training week every Sunday", comment: "Onboarding notification: weekly summary description")
                )

                DataAccessRow(
                    icon: "exclamationmark.triangle.fill",
                    title: String(localized: "Smart alerts", comment: "Onboarding notification: smart alerts"),
                    description: String(localized: "Warnings for overtraining and inactivity", comment: "Onboarding notification: smart alerts description")
                )
            }
            .padding(.horizontal, 24)
            .opacity(contentOpacity)

            // Privacy Note
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Color.irTextSecondary)

                Text(String(localized: "You can enable notifications later in Settings", comment: "Onboarding notification optional note"))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)

                Spacer()
            }
            .padding()
            .background(Color.irSurface)
            .cornerRadius(12)
            .padding(.horizontal, 24)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: requestNotificationPermission) {
                    if isRequesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(String(localized: "Allow notifications", comment: "Onboarding notification allow button"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(Color.irPrimaryAccent.gradient)
                .cornerRadius(16)
                .disabled(isRequesting)

                Button(action: {
                    AnalyticsService.shared.trackNotificationPermissionSkipped()
                    onContinue()
                }) {
                    Text(String(localized: "Skip for now", comment: "Onboarding notification skip button"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 3, stepName: "notification_permission")
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                titleOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                contentOpacity = 1
            }
        }
    }

    private func requestNotificationPermission() {
        isRequesting = true

        Task {
            let granted = await NotificationManager.shared.requestPermissions()

            if granted {
                NotificationManager.shared.enableDailyReadiness()
                NotificationManager.shared.scheduleWeeklySummary()
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
