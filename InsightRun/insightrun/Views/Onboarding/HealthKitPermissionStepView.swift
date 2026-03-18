//
//  HealthKitPermissionStepView.swift
//  InsightRun
//
//  Onboarding Step 2: HealthKit permissions request
//

import SwiftUI

struct HealthKitPermissionStepView: View {
    let onContinue: () -> Void

    @State private var isRequesting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var titleOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated illustration
            AnimatedOnboardingIllustration(type: .healthKit)

            // Icon & Title
            VStack(spacing: 16) {
                Text(String(localized: "Access to your health data", comment: "Onboarding HealthKit title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "Insight Run needs access to HealthKit to analyze your runs and provide personalized coaching", comment: "Onboarding HealthKit description"))
                    .font(.body)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .opacity(titleOpacity)

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

            Spacer()

            // Authorize Button
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

                if showError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.irError)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 2, stepName: "healthkit_permission")
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                titleOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                contentOpacity = 1
            }
        }
        .alert(
            String(localized: "HealthKit access required", comment: "Onboarding HealthKit error alert title"),
            isPresented: $showError
        ) {
            Button(String(localized: "Try again", comment: "Onboarding HealthKit retry button")) {
                requestHealthKitAuthorization()
            }
            Button(String(localized: "Cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
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
                        // User denied permission
                        errorMessage = String(localized: "Insight Run cannot work without HealthKit access. Please grant access in Settings.", comment: "Onboarding HealthKit denied message")
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                    errorMessage = String(localized: "An error occurred while requesting access. Please try again.", comment: "Onboarding HealthKit error message")
                    showError = true
                }
            }
        }
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
    HealthKitPermissionStepView(onContinue: {})
}
