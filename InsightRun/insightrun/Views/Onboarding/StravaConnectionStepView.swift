//
//  StravaConnectionStepView.swift
//  InsightRun
//
//  Onboarding step for Strava connection (Pulse-Ring layout, official Strava brand button preserved).
//

import SwiftUI

struct StravaConnectionStepView: View {
    let onContinue: () -> Void

    @StateObject private var stravaAuth = StravaAuthService.shared
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    illustration

                    OnboardingEditorialHeader(
                        eyebrow: String(localized: "onboarding.strava.eyebrow", defaultValue: "Strava", comment: "Onboarding Strava eyebrow"),
                        title: stravaAuth.isAuthenticated
                            ? String(localized: "Connected to Strava", comment: "Strava connected title")
                            : String(localized: "Connect Strava", comment: "Strava onboarding title"),
                        body: stravaAuth.isAuthenticated
                            ? stravaAuth.athleteId.map { String(localized: "Athlete ID: \($0)", comment: "Strava athlete ID") }
                            : String(localized: "Import your running history from Strava to get AI-powered insights based on years of training data.", comment: "Strava onboarding description")
                    )

                    if !stravaAuth.isAuthenticated {
                        VStack(spacing: Spacing.sm) {
                            OnboardingFeatureCard(
                                icon: "clock.arrow.circlepath",
                                iconTint: .irWarning,
                                title: String(localized: "Import Full History", comment: "Strava feature title"),
                                description: String(localized: "Get all your activities from the past years", comment: "Strava feature description")
                            )
                            OnboardingFeatureCard(
                                icon: "arrow.triangle.2.circlepath",
                                iconTint: .irPrimaryAccent,
                                title: String(localized: "Auto Sync", comment: "Strava feature title"),
                                description: String(localized: "New activities automatically appear in the app", comment: "Strava feature description")
                            )
                            OnboardingFeatureCard(
                                icon: "chart.line.uptrend.xyaxis",
                                iconTint: .irAIAccent,
                                title: String(localized: "Advanced Analytics", comment: "Strava feature title"),
                                description: String(localized: "AI insights based on your complete training history", comment: "Strava feature description")
                            )
                        }
                    }
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.xl)
                .opacity(contentOpacity)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: Spacing.xxs) {
                if stravaAuth.isAuthenticated {
                    OnboardingPrimaryButton(
                        title: String(localized: "Continue", comment: "Continue button"),
                        action: onContinue
                    )
                } else {
                    // Official Strava-branded button (must remain unmodified per brand guidelines).
                    StravaConnectButton(
                        action: connectStrava,
                        isLoading: isConnecting,
                        variant: .orange
                    )

                    OnboardingSecondaryButton(
                        title: String(localized: "Skip for now", comment: "Skip Strava button"),
                        action: {
                            AnalyticsService.shared.trackStravaConnectionSkipped()
                            onContinue()
                        }
                    )
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.irBackgroundApp)
        .alert(String(localized: "Connection Error", comment: "Strava connection error alert title"), isPresented: $showError) {
            Button(String(localized: "OK", comment: "OK button"), role: .cancel) {}
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStepViewed(step: 4, stepName: "strava_connection")
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                contentOpacity = 1
            }
        }
    }

    @ViewBuilder
    private var illustration: some View {
        if stravaAuth.isAuthenticated {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FC5200"), Color(hex: "E84545")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(IRFont.numMD)
                    .fontWeight(.heavy)
                    .foregroundStyle(Color.irTextPrimary)
            }
            .frame(maxWidth: .infinity)
        } else {
            AnimatedOnboardingIllustration(type: .strava)
        }
    }

    private func connectStrava() {
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                try await stravaAuth.authenticate()
                AnalyticsService.shared.trackStravaConnectionSuccess(athleteId: stravaAuth.athleteId ?? 0)
                await triggerInitialSync()
            } catch StravaAuthError.userCancelled {
                AnalyticsService.shared.trackStravaConnectionSkipped()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                AnalyticsService.shared.trackStravaConnectionFailed(
                    errorType: String(describing: type(of: error)),
                    errorMessage: error.localizedDescription
                )
            }
            isConnecting = false
        }
    }

    private func triggerInitialSync() async {
        let backendClient = StravaBackendClient.shared
        let userId = UserIdentityService.shared.userID
        AnalyticsService.shared.trackStravaInitialSyncTriggered()
        do {
            _ = try await backendClient.syncActivities(userId: userId, force: false)
        } catch {
            // Initial sync is best-effort; auth success is still the gating outcome.
        }
    }
}

#Preview {
    StravaConnectionStepView(onContinue: {})
}
