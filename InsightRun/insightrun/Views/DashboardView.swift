//
//  DashboardView.swift
//  InsightRun
//
//  Dashboard combining recovery, coaching, and recent activity
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var recoveryVM = RecoveryViewModel()
    @StateObject private var readinessVM = DailyReadinessViewModel()
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared
    @State private var showSettings = false
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject private var revenueCatManager: RevenueCatManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if recoveryVM.isLoading && recoveryVM.recoveryMetrics == nil {
                        loadingView
                    } else if let recovery = recoveryVM.recoveryMetrics {
                        recoveryScoreSection(recovery)
                        coachingSection(recovery)
                        keyMetricsSection(recovery)
                        weekQuickStats
                        recentWorkoutsSection
                    } else {
                        emptyRecoveryView
                    }
                }
                .padding()
                .padding(.bottom, 80)
            }
            .navigationTitle(String(localized: "tab.dashboard", defaultValue: "Dashboard", comment: "Dashboard tab title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(themeManager)
                    .environmentObject(revenueCatManager)
            }
            .refreshable {
                await recoveryVM.refresh()
                await readinessVM.fetchDailyReadiness()
                await contextProvider.loadRecentWorkouts()
            }
        }
        .task {
            await recoveryVM.loadRecoveryMetrics()
            await readinessVM.fetchDailyReadiness()
            if contextProvider.recentWorkouts.isEmpty {
                await contextProvider.loadRecentWorkouts()
            }
            if let recovery = recoveryVM.recoveryMetrics {
                contextProvider.recoveryMetrics = recovery
            }
        }
    }

    // MARK: - Recovery Score Ring

    private func recoveryScoreSection(_ recovery: RecoveryMetrics) -> some View {
        VStack(spacing: 16) {
            CircularProgressView(score: recovery.recoveryScore, size: 180, lineWidth: 14)

            Text(recovery.recoveryStatus.description)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - AI Coaching Card

    private func coachingSection(_ recovery: RecoveryMetrics) -> some View {
        CoachingSection(fallbackRecommendation: recovery.recoveryStatus.recommendation)
    }

    // MARK: - Key Metrics

    private func keyMetricsSection(_ recovery: RecoveryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "dashboard.today", defaultValue: "Today", comment: "Today's metrics section title"))
                .font(.headline)

            VStack(spacing: 8) {
                if let hrv = recovery.hrvAverage {
                    HealthMetricRow(
                        icon: "waveform.path.ecg",
                        iconColor: .blue,
                        title: String(localized: "HRV", comment: "HRV metric label"),
                        value: String(format: "%.0f ms", hrv)
                    )
                }

                if let rhr = recovery.restingHeartRate {
                    HealthMetricRow(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: String(localized: "Resting HR", comment: "Resting heart rate label"),
                        value: String(format: "%.0f bpm", rhr)
                    )
                }

                if let sleep = recovery.sleepData {
                    HealthMetricRow(
                        icon: "bed.double.fill",
                        iconColor: .indigo,
                        title: String(localized: "Sleep", comment: "Sleep metric label"),
                        value: sleep.formattedTotalSleep
                    )
                }

                if let spo2 = recovery.oxygenSaturation {
                    HealthMetricRow(
                        icon: "drop.fill",
                        iconColor: .cyan,
                        title: String(localized: "SpO2", comment: "Oxygen saturation label"),
                        value: String(format: "%.1f%%", spo2)
                    )
                }
            }
            .padding()
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Week Quick Stats

    private var weekQuickStats: some View {
        let workouts = contextProvider.recentWorkouts
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let thisWeekWorkouts = workouts.filter { $0.startDate >= startOfWeek }

        let totalDistance = thisWeekWorkouts.compactMap(\.distance).reduce(0, +)
        let totalDuration = thisWeekWorkouts.map(\.duration).reduce(0, +)
        let count = thisWeekWorkouts.count

        return NavigationLink(destination: WeeklySummaryView()) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "dashboard.thisWeek", defaultValue: "This Week", comment: "This week section title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text(formatDistance(totalDistance))
                            .font(.headline)
                            .foregroundStyle(Color.irPrimaryAccent)
                        Text(String(localized: "Distance", comment: "Distance label"))
                            .font(.caption2)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 30)

                    VStack(spacing: 4) {
                        Text(formatDuration(totalDuration))
                            .font(.headline)
                            .foregroundStyle(Color.irSuccess)
                        Text(String(localized: "Time", comment: "Time label"))
                            .font(.caption2)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 30)

                    VStack(spacing: 4) {
                        Text("\(count)")
                            .font(.headline)
                            .foregroundStyle(Color.irWarning)
                        Text(String(localized: "Runs", comment: "Runs count label"))
                            .font(.caption2)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Workouts

    private var recentWorkoutsSection: some View {
        let workouts = Array(contextProvider.recentWorkouts.prefix(3))

        return Group {
            if !workouts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "dashboard.recentWorkouts", defaultValue: "Recent Workouts", comment: "Recent workouts section title"))
                            .font(.headline)

                        Spacer()
                    }

                    ForEach(workouts) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            WorkoutRowView(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Empty / Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "Loading...", comment: "Loading indicator"))
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var emptyRecoveryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.irPrimaryAccent.gradient)

            VStack(spacing: 8) {
                Text(String(localized: "No Recovery Data", comment: "Empty recovery state title"))
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(String(localized: "Recovery data will appear once HealthKit provides your metrics.", comment: "Empty recovery description"))
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        if hours > 0 {
            return String(format: "%dh%02d", hours, minutes)
        }
        return String(format: "%d min", minutes)
    }
}

#Preview {
    DashboardView()
        .environment(ThemeManager())
        .environmentObject(RevenueCatManager.shared)
}
