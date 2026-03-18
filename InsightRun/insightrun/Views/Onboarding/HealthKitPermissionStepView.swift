//
//  HealthKitPermissionStepView.swift
//  InsightRun
//
//  Onboarding Step 2: HealthKit permissions request
//

import SwiftUI

struct HealthKitPermissionStepView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var titleOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var previewOpacity: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 16)

                // Animated illustration
                AnimatedOnboardingIllustration(type: .healthKit)

                // Icon & Title — benefit-driven copy
                VStack(spacing: 16) {
                    Text(String(localized: "See what your body is telling you", comment: "Onboarding HealthKit title"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "Get AI coaching, recovery insights, and performance tracking — all from data your watch already collects", comment: "Onboarding HealthKit description"))
                        .font(.body)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .opacity(titleOpacity)

                // Mini dashboard preview
                HealthKitPreviewCard()
                    .padding(.horizontal, 24)
                    .opacity(previewOpacity)

                // Data Access List
                VStack(spacing: 16) {
                    DataAccessRow(
                        icon: "figure.run",
                        title: String(localized: "Workouts and activities", comment: "Onboarding HealthKit: workouts"),
                        description: String(localized: "Running sessions and metrics", comment: "Onboarding HealthKit: workouts description")
                    )

                    DataAccessRow(
                        icon: "heart.fill",
                        title: String(localized: "Heart rate (onboarding)", comment: "Onboarding HealthKit: heart rate"),
                        description: String(localized: "Training intensity and recovery", comment: "Onboarding HealthKit: heart rate description")
                    )

                    DataAccessRow(
                        icon: "moon.fill",
                        title: String(localized: "Sleep data", comment: "Onboarding HealthKit: sleep"),
                        description: String(localized: "Recovery and readiness analysis", comment: "Onboarding HealthKit: sleep description")
                    )

                    DataAccessRow(
                        icon: "waveform.path.ecg",
                        title: String(localized: "Advanced metrics (onboarding)", comment: "Onboarding HealthKit: advanced"),
                        description: String(localized: "VO2 Max, HRV, and more", comment: "Onboarding HealthKit: advanced description")
                    )
                }
                .padding(.horizontal, 24)
                .opacity(contentOpacity)

                // Privacy Note
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title3)
                        .foregroundStyle(Color.irSuccess)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Your data is private", comment: "Onboarding privacy note title"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.irTextPrimary)
                        Text(String(localized: "All data stays on your device", comment: "Onboarding privacy note description"))
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.irSuccess.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, 24)

                Spacer(minLength: 16)

                // Authorize Button + Skip
                VStack(spacing: 12) {
                    Button(action: requestHealthKitAuthorization) {
                        if isRequesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text(String(localized: "Continue", comment: "Onboarding HealthKit authorize button"))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(Color.irPrimaryAccent.gradient)
                    .cornerRadius(16)
                    .disabled(isRequesting)

                    // Skip for now
                    Button(action: skipHealthKit) {
                        Text(String(localized: "Skip for now", comment: "Onboarding HealthKit skip button"))
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .disabled(isRequesting)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 2, stepName: "healthkit_permission")
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                titleOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                previewOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
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

    private func skipHealthKit() {
        AnalyticsService.shared.track(.healthKitPermissionSkipped)
        onSkip()
    }

    private func requestHealthKitAuthorization() {
        isRequesting = true
        showError = false

        Task {
            do {
                try await HealthKitManager.shared.requestAuthorization()

                // Check if we actually got access
                let hasAccess = await HealthKitManager.shared.checkDataAccess()

                await MainActor.run {
                    isRequesting = false

                    if hasAccess {
                        // Track success
                        AnalyticsService.shared.trackOnboardingStepCompleted(step: 2, stepName: "healthkit_permission")
                        onContinue()
                    } else {
                        // User denied — offer to skip or open Settings
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PreviewMetricBadge(icon: "figure.run", value: "5:32", unit: "/km", color: .blue)
                PreviewMetricBadge(icon: "heart.fill", value: "142", unit: "bpm", color: .red)
                PreviewMetricBadge(icon: "bed.double.fill", value: "85%", unit: "recovery", color: .green)
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                Text(String(localized: "AI Coach: Great pace consistency! Try adding intervals next week.", comment: "Onboarding HealthKit preview AI hint"))
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.irCardBackground)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
    }
}

struct PreviewMetricBadge: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
}

struct DataAccessRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.irPrimaryAccent)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.irSuccess)
        }
    }
}

#Preview {
    HealthKitPermissionStepView(onContinue: {}, onSkip: {})
}
