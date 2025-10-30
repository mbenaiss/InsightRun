//
//  RecoveryDashboardView.swift
//  InsightRun
//
//  Dashboard for recovery and readiness metrics
//

import SwiftUI
import Combine

struct RecoveryDashboardView: View {
    @StateObject private var viewModel = RecoveryViewModel()
    @ObservedObject private var revenueCatManager = RevenueCatManager.shared
    @State private var showingAIAssistant = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
                ScrollView {
                    if viewModel.isLoading {
                        loadingView
                    } else if let errorMessage = viewModel.errorMessage {
                        errorView(errorMessage)
                    } else if let recovery = viewModel.recoveryMetrics {
                        recoveryContent(recovery)
                    } else {
                        emptyView
                    }
                }
                .navigationTitle(String(localized: "Recovery", comment: "Navigation title for recovery dashboard"))
                .navigationBarTitleDisplayMode(.large)
                .refreshable {
                    await viewModel.refresh()
                }
                .task {
                    await viewModel.loadRecoveryMetrics()
                }
                .onAppear {
                    // Track recovery dashboard viewed
                    if let recovery = viewModel.recoveryMetrics {
                        let recoveryScore = recovery.recoveryScore
                        let hasRecentWorkouts = viewModel.recentWorkoutsCount > 0
                        AnalyticsService.shared.trackRecoveryDashboardViewed(
                            recoveryScore: recoveryScore,
                            hasRecentWorkouts: hasRecentWorkouts
                        )
                    }
                }
            }

            // Floating AI Button (only for subscribed users)
            if viewModel.recoveryMetrics != nil && revenueCatManager.isSubscriptionActive {
                Button(action: { showingAIAssistant = true }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)

                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showingAIAssistant) {
            if let recovery = viewModel.recoveryMetrics {
                WorkoutAIAssistantView(
                    mode: .recoveryCoaching(recovery),
                    isPresented: $showingAIAssistant
                )
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "Loading...", comment: "Loading indicator text"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange.gradient)

            VStack(spacing: 12) {
                Text(String(localized: "Error", comment: "Error state title"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(String(localized: "Retry", comment: "Button to retry loading data")) {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .padding(.top, 100)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red.gradient)

            VStack(spacing: 12) {
                Text(String(localized: "No Data", comment: "Empty state title when no recovery data available"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(localized: "Recovery data is not available.", comment: "Empty state message for recovery data"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text(String(localized: "Tip: Enable permissions in Settings → Privacy → Health → Insight Run", comment: "Tip about enabling HealthKit permissions"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }
        }
        .padding()
        .padding(.top, 100)
    }

    // MARK: - Recovery Content

    @ViewBuilder
    private func recoveryContent(_ recovery: RecoveryMetrics) -> some View {
        VStack(spacing: 20) {
            // Date Navigation
            dateNavigationBar
                .padding(.horizontal)
                .padding(.top)

            // Recovery Score Card
            recoveryScoreCard(recovery)
                .padding(.horizontal)

            // Recommendation Card
            recommendationCard(recovery)
                .padding(.horizontal)

            // Heart Rate Metrics
            heartRateSection(recovery)
                .padding(.horizontal)

            // Sleep Metrics
            if let sleep = recovery.sleepData {
                sleepSection(sleep)
                    .padding(.horizontal)
            }

            // Respiratory Rate
            if let respiratoryRate = recovery.respiratoryRate {
                respiratorySection(respiratoryRate)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Recovery Score Card

    private func recoveryScoreCard(_ recovery: RecoveryMetrics) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(recovery.recoveryStatus.emoji)
                    .font(.system(size: 40))

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Recovery Score", comment: "Label for recovery score metric"))
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("\(recovery.recoveryScore)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(scoreColor(recovery.recoveryScore))
                }

                Spacer()
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(scoreGradient(recovery.recoveryScore))
                        .frame(width: geometry.size.width * CGFloat(recovery.recoveryScore) / 100)
                }
            }
            .frame(height: 8)

            Text(recovery.recoveryStatus.description)
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Recommendation Card

    private func recommendationCard(_ recovery: RecoveryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Recommendation", comment: "Section header for recovery recommendation"), systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.orange.gradient)

            Text(recovery.recoveryStatus.recommendation)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Heart Rate Section

    private func heartRateSection(_ recovery: RecoveryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Heart Rate", comment: "Section header for heart rate metrics"))
                .font(.headline)

            VStack(spacing: 12) {
                if let rhr = recovery.restingHeartRate {
                    HealthMetricRow(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: String(localized: "Resting HR", comment: "Label for resting heart rate"),
                        value: String(format: "%.0f bpm", rhr)
                    )
                }

                if let hrv = recovery.hrv {
                    HealthMetricRow(
                        icon: "waveform.path.ecg",
                        iconColor: .blue,
                        title: String(localized: "Variability (HRV)", comment: "Label for heart rate variability"),
                        value: String(format: "%.0f ms", hrv)
                    )
                }

                if let whr = recovery.walkingHeartRate {
                    HealthMetricRow(
                        icon: "figure.walk",
                        iconColor: .green,
                        title: String(localized: "Walking HR", comment: "Label for walking heart rate"),
                        value: String(format: "%.0f bpm", whr)
                    )
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Sleep Section

    private func sleepSection(_ sleep: SleepData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Sleep", comment: "Section header for sleep metrics"))
                .font(.headline)

            VStack(spacing: 12) {
                HealthMetricRow(
                    icon: "moon.fill",
                    iconColor: .indigo,
                    title: String(localized: "Sleep session", comment: "Label for time of sleep session"),
                    value: sleep.formattedSleepTime
                )

                HealthMetricRow(
                    icon: "bed.double.fill",
                    iconColor: .blue,
                    title: String(localized: "Sleep duration", comment: "Label for total sleep duration"),
                    value: sleep.formattedTotalSleep
                )

                if let napDuration = sleep.formattedNapDuration {
                    HealthMetricRow(
                        icon: "powersleep",
                        iconColor: .orange,
                        title: String(localized: "Naps", comment: "Label for nap duration"),
                        value: napDuration
                    )
                }

                HealthMetricRow(
                    icon: "clock.fill",
                    iconColor: .cyan,
                    title: String(localized: "Time in bed", comment: "Label for total time in bed"),
                    value: sleep.formattedTimeInBed
                )

                HealthMetricRow(
                    icon: "chart.bar.fill",
                    iconColor: .teal,
                    title: String(localized: "Efficiency", comment: "Label for sleep efficiency percentage"),
                    value: String(format: "%.0f%%", sleep.sleepEfficiency)
                )

                HealthMetricRow(
                    icon: "star.fill",
                    iconColor: .yellow,
                    title: String(localized: "Quality", comment: "Label for sleep quality description"),
                    value: sleep.qualityDescription
                )
            }

            // Sleep stages if available
            if let deep = sleep.deepSleepDuration,
               let core = sleep.coreSleepDuration,
               let rem = sleep.remSleepDuration {
                Divider()
                    .padding(.vertical, 4)

                Text(String(localized: "Sleep stages", comment: "Section header for sleep stages breakdown"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    SleepStageRow(stage: String(localized: "Deep", comment: "Deep sleep stage label"), duration: deep, color: .blue)
                    SleepStageRow(stage: String(localized: "Light", comment: "Light sleep stage label"), duration: core, color: .cyan)
                    SleepStageRow(stage: String(localized: "REM", comment: "REM sleep stage label"), duration: rem, color: .indigo)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Respiratory Section

    private func respiratorySection(_ rate: Double) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Breathing", comment: "Section header for respiratory metrics"))
                .font(.headline)

            HealthMetricRow(
                icon: "wind",
                iconColor: .teal,
                title: String(localized: "Respiratory rate", comment: "Label for respiratory rate"),
                value: String(format: "%.0f /min", rate)
            )
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Date Navigation Bar

    private var dateNavigationBar: some View {
        HStack(spacing: 16) {
            // Previous Day Button
            Button(action: {
                Task {
                    await viewModel.goToPreviousDay()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            // Date Display
            Text(viewModel.formattedSelectedDate)
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)

            // Next Day Button
            Button(action: {
                Task {
                    await viewModel.goToNextDay()
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(viewModel.isToday ? .gray : .blue)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(viewModel.isToday)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Helper Functions

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100:
            return .green
        case 60..<80:
            return .yellow
        case 40..<60:
            return .orange
        default:
            return .red
        }
    }

    private func scoreGradient(_ score: Int) -> LinearGradient {
        let color = scoreColor(score)
        return LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Health Metric Row Component

struct HealthMetricRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor.gradient)
                .frame(width: 32)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sleep Stage Row Component

struct SleepStageRow: View {
    let stage: String
    let duration: TimeInterval
    let color: Color

    private var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        return String(format: "%dh%02d", hours, minutes)
    }

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(stage)
                .font(.subheadline)

            Spacer()

            Text(formattedDuration)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    RecoveryDashboardView()
}
