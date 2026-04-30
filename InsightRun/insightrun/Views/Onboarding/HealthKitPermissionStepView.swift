//
//  HealthKitPermissionStepView.swift
//  InsightRun
//
//  Onboarding Step 2: HealthKit permissions request (Pulse-Ring layout).
//

import SwiftUI

struct HealthKitPermissionStepView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var contentOpacity: Double = 0

    var body: some View {
        OnboardingScaffold(
            primaryTitle: String(localized: "Continue", comment: "Onboarding HealthKit authorize button"),
            primaryAction: requestHealthKitAuthorization,
            isPrimaryLoading: isRequesting,
            secondaryTitle: String(localized: "Skip for now", comment: "Onboarding HealthKit skip button"),
            secondaryAction: skipHealthKit
        ) {
            VStack(spacing: 24) {
                AnimatedOnboardingIllustration(type: .healthKit)

                OnboardingEditorialHeader(
                    eyebrow: String(localized: "onboarding.healthkit.eyebrow", defaultValue: "Health data", comment: "Onboarding HealthKit eyebrow"),
                    title: String(localized: "See what your body is telling you", comment: "Onboarding HealthKit title"),
                    body: String(localized: "Get AI coaching, recovery insights, and performance tracking — all from data your watch already collects", comment: "Onboarding HealthKit description")
                )

                HealthKitPreviewCard()

                VStack(spacing: 8) {
                    OnboardingFeatureCard(
                        icon: "figure.run",
                        title: String(localized: "Workouts and activities", comment: "Onboarding HealthKit: workouts"),
                        description: String(localized: "Running sessions and metrics", comment: "Onboarding HealthKit: workouts description"),
                        trailing: .checkmark
                    )
                    OnboardingFeatureCard(
                        icon: "heart.fill",
                        iconTint: .irError,
                        title: String(localized: "Heart rate (onboarding)", comment: "Onboarding HealthKit: heart rate"),
                        description: String(localized: "Training intensity and recovery", comment: "Onboarding HealthKit: heart rate description"),
                        trailing: .checkmark
                    )
                    OnboardingFeatureCard(
                        icon: "moon.fill",
                        iconTint: .irAIAccentSecondary,
                        title: String(localized: "Sleep data", comment: "Onboarding HealthKit: sleep"),
                        description: String(localized: "Recovery and readiness analysis", comment: "Onboarding HealthKit: sleep description"),
                        trailing: .checkmark
                    )
                    OnboardingFeatureCard(
                        icon: "waveform.path.ecg",
                        iconTint: .irAIAccent,
                        title: String(localized: "Advanced metrics (onboarding)", comment: "Onboarding HealthKit: advanced"),
                        description: String(localized: "VO2 Max, HRV, and more", comment: "Onboarding HealthKit: advanced description"),
                        trailing: .checkmark
                    )
                }

                privacyNote
            }
            .opacity(contentOpacity)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 2, stepName: "healthkit_permission")
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                contentOpacity = 1
            }
        }
        .alert(
            String(localized: "HealthKit access needed", comment: "Onboarding HealthKit error alert title"),
            isPresented: $showError
        ) {
            Button(String(localized: "Open Settings", comment: "Onboarding HealthKit open settings button")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(String(localized: "Skip for now", comment: "Onboarding HealthKit skip button")) {
                skipHealthKit()
            }
            Button(String(localized: "Cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.irSuccess)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Your data is private", comment: "Onboarding privacy note title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.irTextPrimary)
                Text(String(localized: "All data stays on your device", comment: "Onboarding privacy note description"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.irTextSecondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irSuccess.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.irSuccess.opacity(0.30), lineWidth: 0.5)
        )
    }

    private func skipHealthKit() {
        AnalyticsService.shared.track(.healthKitPermissionSkipped)
        onSkip()
    }

    private func requestHealthKitAuthorization() {
        isRequesting = true
        showError = false

        Task {
            do {
                let hasAccess = try await HealthKitManager.shared.requestAuthorization()

                await MainActor.run {
                    isRequesting = false
                    if hasAccess {
                        onContinue()
                    } else {
                        errorMessage = String(localized: "You can grant access later in Settings. Some features won't be available without HealthKit.", comment: "Onboarding HealthKit denied message")
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                    errorMessage = String(localized: "An error occurred while requesting access. You can skip and try again later.", comment: "Onboarding HealthKit error message")
                    showError = true
                }
            }
        }
    }
}

// MARK: - Mini Dashboard Preview

struct HealthKitPreviewCard: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                PreviewMetricBadge(icon: "figure.run", value: "5:32", unit: "/km", color: .irPrimaryAccent)
                PreviewMetricBadge(icon: "heart.fill", value: "142", unit: "bpm", color: .irError)
                PreviewMetricBadge(icon: "bed.double.fill", value: "85%", unit: "recovery", color: .irSuccess)
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.irAIAccent)
                Text(String(localized: "AI Coach: Great pace consistency! Try adding intervals next week.", comment: "Onboarding HealthKit preview AI hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

struct PreviewMetricBadge: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.irTextPrimary)
            Text(unit)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    HealthKitPermissionStepView(onContinue: {}, onSkip: {})
}
