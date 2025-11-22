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

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
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

                if stravaAuth.isAuthenticated {
                    Image(systemName: "checkmark")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "figure.run")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 32)

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
                                .foregroundStyle(.secondary)
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

            Spacer()

            // Features
            if !stravaAuth.isAuthenticated {
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "clock.arrow.circlepath",
                        title: "Import Full History",
                        description: "Get all your activities from the past years"
                    )

                    FeatureRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Auto Sync",
                        description: "New activities automatically appear in the app"
                    )

                    FeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Advanced Analytics",
                        description: "AI insights based on your complete training history"
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
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
                    // Connect with Strava button
                    Button(action: {
                        connectStrava()
                    }) {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "link")
                                Text(String(localized: "Connect with Strava", comment: "Connect Strava button"))
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .orange.opacity(0.3), radius: 10, y: 5)
                    }
                    .disabled(isConnecting)

                    // Skip button
                    Button(action: {
                        AnalyticsService.shared.trackEvent(name: "strava_connection_skipped", properties: [:])
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
        .alert("Connection Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
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
                AnalyticsService.shared.trackEvent(
                    name: "strava_connected",
                    properties: ["athlete_id": stravaAuth.athleteId ?? 0]
                )

                print("✅ Strava connected successfully")
            } catch {
                errorMessage = error.localizedDescription
                showError = true

                // Track connection failure
                AnalyticsService.shared.trackEvent(
                    name: "strava_connection_failed",
                    properties: ["error": error.localizedDescription]
                )

                print("❌ Strava connection failed: \(error)")
            }

            isConnecting = false
        }
    }
}

struct FeatureRow: View {
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
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    StravaConnectionStepView(onContinue: {})
}
