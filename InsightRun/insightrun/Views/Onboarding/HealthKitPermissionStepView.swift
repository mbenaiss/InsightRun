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
            primaryTitle: isRequesting
                ? String(localized: "Syncing your latest run…", comment: "Onboarding HealthKit synchronization status")
                : String(localized: "Continue", comment: "Onboarding HealthKit authorize button"),
            primaryAction: requestHealthKitAuthorization,
            isPrimaryLoading: isRequesting,
            secondaryTitle: String(localized: "Skip for now", comment: "Onboarding HealthKit skip button"),
            secondaryAction: skipHealthKit
        ) {
            VStack(spacing: Spacing.xl) {
                AnimatedOnboardingIllustration(type: .healthKit)

                OnboardingEditorialHeader(
                    eyebrow: String(localized: "onboarding.healthkit.eyebrow", defaultValue: "Health data", comment: "Onboarding HealthKit eyebrow"),
                    title: String(localized: "See what your body is telling you", comment: "Onboarding HealthKit title"),
                    body: String(localized: "Get AI coaching, recovery insights, and performance tracking — all from data your watch already collects", comment: "Onboarding HealthKit description")
                )

                HealthKitPreviewCard()

                VStack(spacing: Spacing.sm) {
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
                        iconTint: .irPrimaryAccent,
                        title: String(localized: "Sleep data", comment: "Onboarding HealthKit: sleep"),
                        description: String(localized: "Recovery and readiness analysis", comment: "Onboarding HealthKit: sleep description"),
                        trailing: .checkmark
                    )
                    OnboardingFeatureCard(
                        icon: "waveform.path.ecg",
                        iconTint: .irPrimaryAccent,
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
        HStack(spacing: Spacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(IRFont.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irSuccess)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Your data is private", comment: "Onboarding privacy note title"))
                    .font(IRFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)
                Text(String(localized: "All data stays on your device", comment: "Onboarding privacy note description"))
                    .font(IRFont.eyebrow)
                    .foregroundStyle(Color.irTextSecondary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irSuccess.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .strokeBorder(Color.irSuccess.opacity(0.30), lineWidth: 0.5)
        )
    }

    private func skipHealthKit() {
        AnalyticsService.shared.track(.healthKitPermissionSkipped)
        AnalyticsService.shared.trackActivationStarted(source: "sample_workout")
        let sample = MockData.activationWorkout
        NotificationRouter.shared.routeToActivationWorkout(sample)
        AnalyticsService.shared.trackActivationWorkoutReady(isSample: true)
        onSkip()
    }

    private func requestHealthKitAuthorization() {
        isRequesting = true
        showError = false

        Task {
            do {
                let hasAccess = try await HealthKitManager.shared.requestAuthorization()

                if hasAccess {
                    AnalyticsService.shared.trackActivationStarted(source: "healthkit")
                    let latestResult = try? await HealthKitManager.shared.fetchRunningWorkouts(limit: 1)
                    let latestWorkout = latestResult?.workouts.first
                    let workout = latestWorkout ?? MockData.activationWorkout

                    await MainActor.run {
                        isRequesting = false
                        NotificationRouter.shared.routeToActivationWorkout(workout)
                        AnalyticsService.shared.trackActivationWorkoutReady(isSample: latestWorkout == nil)
                        WorkoutSyncService.shared.startObserving()
                        onContinue()
                    }
                } else {
                    await MainActor.run {
                        isRequesting = false
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
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                PreviewMetricBadge(icon: "figure.run", value: "5:32", unit: "/km", color: .irPrimaryAccent)
                PreviewMetricBadge(icon: "heart.fill", value: "142", unit: "bpm", color: .irError)
                PreviewMetricBadge(icon: "bed.double.fill", value: "85%", unit: "recovery", color: .irSuccess)
            }

            HStack(spacing: Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(IRFont.eyebrow)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irPrimaryAccent)
                Text(String(localized: "AI Coach: Great pace consistency! Try adding intervals next week.", comment: "Onboarding HealthKit preview AI hint"))
                    .font(IRFont.eyebrow)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(2)
            }
        }
        .padding(Spacing.dash)
        .frame(maxWidth: .infinity)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
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
                .font(IRFont.eyebrow)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(value)
                .font(IRFont.numSM)
                .fontWeight(.heavy)
                .foregroundStyle(Color.irTextPrimary)
            Text(unit)
                .font(IRFont.eyebrow)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
    }
}

#Preview {
    HealthKitPermissionStepView(onContinue: {}, onSkip: {})
}
