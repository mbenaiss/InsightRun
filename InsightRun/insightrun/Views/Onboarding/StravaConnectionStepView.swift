//
//  StravaConnectionStepView.swift
//  InsightRun
//
//  Onboarding step for Strava connection (OAuth 2.0)
//

import SwiftUI

struct StravaConnectionStepView: View {
    let onContinue: () -> Void

    @StateObject private var stravaAuth = StravaAuthService.shared
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var titleOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            if stravaAuth.isAuthenticated {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: .orange.opacity(0.3), radius: 20, y: 10)

                    Image(systemName: "checkmark")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 32)
            } else {
                AnimatedOnboardingIllustration(type: .strava)
                    .padding(.bottom, 32)
            }

            // Title & Description
            VStack(spacing: 16) {
                Text(String(localized: "Connect Strava", comment: "Strava onboarding title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                if stravaAuth.isAuthenticated {
                    VStack(spacing: 8) {
                        Text(String(localized: "Connected Successfully!", comment: "Strava connected success"))
                            .font(.headline)
                            .foregroundStyle(.green)

                        if let athleteId = stravaAuth.athleteId {
                            Text(String(localized: "Athlete ID: \(athleteId)", comment: "Strava athlete ID"))
                                .font(.subheadline)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }
                } else {
                    Text(String(localized: "Import your running history from Strava to get AI-powered insights based on years of training data.", comment: "Strava onboarding description"))
                        .font(.body)
                        .foregroundStyle(Color.irTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .opacity(titleOpacity)

            Spacer()

            // Features
            if !stravaAuth.isAuthenticated {
                VStack(alignment: .leading, spacing: 16) {
                    StravaFeatureRow(
                        icon: "clock.arrow.circlepath",
                        title: String(localized: "Import Full History", comment: "Strava feature title"),
                        description: String(localized: "Get all your activities from the past years", comment: "Strava feature description")
                    )

                    StravaFeatureRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: String(localized: "Auto Sync", comment: "Strava feature title"),
                        description: String(localized: "New activities automatically appear in the app", comment: "Strava feature description")
                    )

                    StravaFeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: String(localized: "Advanced Analytics", comment: "Strava feature title"),
                        description: String(localized: "AI insights based on your complete training history", comment: "Strava feature description")
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .opacity(contentOpacity)
            }

            Spacer()

            // Buttons
            VStack(spacing: 16) {
                if stravaAuth.isAuthenticated {
                    // Continue button
                    Button(action: {
                        onContinue()
                    }) {
                        HStack {
                            Text(String(localized: "Continue", comment: "Continue button"))
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.irPrimaryAccent.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 10, y: 5)
                    }
                } else {
                    // Connect with Strava button (official per Strava Brand Guidelines)
                    StravaConnectButton(
                        action: {
                            connectStrava()
                        },
                        isLoading: isConnecting,
                        variant: .orange
                    )

                    // Skip button
                    Button(action: {
                        AnalyticsService.shared.trackStravaConnectionSkipped()
                        onContinue()
                    }) {
                        Text(String(localized: "Skip for now", comment: "Skip Strava button"))
                            .font(.subheadline)
                            .foregroundStyle(Color.irPrimaryAccent)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .alert(String(localized: "Connection Error", comment: "Strava connection error alert title"), isPresented: $showError) {
            Button(String(localized: "OK", comment: "OK button"), role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 4, stepName: "strava_connection")
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                titleOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                contentOpacity = 1
            }
        }
    }

    private func connectStrava() {
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                try await stravaAuth.authenticate()

                // Track successful connection
                AnalyticsService.shared.trackStravaConnectionSuccess(athleteId: stravaAuth.athleteId ?? 0)

                print("✅ Strava connected successfully")

                // Trigger initial sync after successful authentication
                await triggerInitialSync()
            } catch StravaAuthError.userCancelled {
                AnalyticsService.shared.trackStravaConnectionSkipped()
                print("ℹ️ Strava authentication cancelled by user")
            } catch {
                errorMessage = error.localizedDescription
                showError = true

                AnalyticsService.shared.trackStravaConnectionFailed(
                    errorType: String(describing: type(of: error)),
                    errorMessage: error.localizedDescription
                )

                print("❌ Strava connection failed: \(error)")
            }

            isConnecting = false
        }
    }

    private func triggerInitialSync() async {
        let backendClient = StravaBackendClient.shared
        let userId = UserIdentityService.shared.userID

        AnalyticsService.shared.trackStravaInitialSyncTriggered()

        do {
            let syncResponse = try await backendClient.syncActivities(userId: userId, force: false)
            print("🎉 Initial sync complete: \(syncResponse.newActivities) new activities, \(syncResponse.totalActivities) total")
        } catch {
            print("⚠️ Initial sync failed (non-blocking): \(error)")
            // Don't block authentication success on sync failure
        }
    }
}

struct StravaFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.irPrimaryAccent.gradient)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
    }
}

#Preview {
    StravaConnectionStepView(onContinue: {})
}
