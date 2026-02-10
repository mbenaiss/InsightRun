//
//  DashboardView.swift
//  InsightRun
//
//  Modern dashboard combining key training and recovery signals.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var unifiedViewModel = UnifiedWorkoutViewModel()
    @StateObject private var recoveryViewModel = RecoveryViewModel()
    @ObservedObject private var contextProvider = UnifiedAIContextProvider.shared

    private var recentWorkouts: [UnifiedWorkout] {
        Array(unifiedViewModel.unifiedWorkouts.prefix(3))
    }

    private var weeklyDistanceKm: Double {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()

        return unifiedViewModel.unifiedWorkouts
            .filter { $0.startDate >= weekStart }
            .reduce(0.0) { partialResult, workout in
                partialResult + (workout.distance ?? 0)
            } / 1000
    }

    private var weeklyDurationHours: Double {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()

        return unifiedViewModel.unifiedWorkouts
            .filter { $0.startDate >= weekStart }
            .reduce(0.0) { $0 + $1.duration } / 3600
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    topHero

                    if let recovery = recoveryViewModel.recoveryMetrics {
                        recoveryCard(recovery)
                    }

                    metricsGrid

                    recentWorkoutsCard
                }
                .padding(Spacing.base)
                .padding(.bottom, 90)
            }
            .background(Color.irBackgroundApp.ignoresSafeArea())
            .navigationTitle(String(localized: "Dashboard", comment: "Dashboard tab title"))
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refreshData()
            }
            .task {
                await refreshData()
            }
        }
    }

    private var topHero: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "Prêt pour une nouvelle séance ?", comment: "Dashboard welcome title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)

            Text(String(localized: "Votre synthèse quotidienne combine charge d'entraînement, récupération et dernières sorties.", comment: "Dashboard subtitle"))
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }

    private func recoveryCard(_ recovery: RecoveryMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Label(String(localized: "Recovery", comment: "Recovery card title"), systemImage: "waveform.path.ecg.rectangle")
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                Text("\(recovery.recoveryScore)%")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irPrimaryAccent)
            }

            ProgressView(value: Double(recovery.recoveryScore), total: 100)
                .tint(Color.irPrimaryAccent)

            Text(recovery.recoveryStatus.recommendation)
                .font(.footnote)
                .foregroundStyle(Color.irTextSecondary)
                .lineLimit(3)
        }
        .dashboardCard()
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.base) {
            MetricTile(
                title: String(localized: "Runs", comment: "Weekly runs metric"),
                value: "\(unifiedViewModel.unifiedWorkouts.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }.count)",
                icon: "figure.run",
                tint: Color.irPrimaryAccent
            )

            MetricTile(
                title: String(localized: "Distance", comment: "Weekly distance metric"),
                value: String(format: "%.1f km", weeklyDistanceKm),
                icon: "location.fill",
                tint: Color.irSuccess
            )

            MetricTile(
                title: String(localized: "Training", comment: "Weekly training duration"),
                value: String(format: "%.1f h", weeklyDurationHours),
                icon: "timer",
                tint: Color.irWarning
            )

            MetricTile(
                title: String(localized: "Total", comment: "Total workouts metric"),
                value: "\(unifiedViewModel.unifiedWorkouts.count)",
                icon: "chart.line.uptrend.xyaxis",
                tint: Color.irTextPrimary
            )
        }
    }

    private var recentWorkoutsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Text(String(localized: "Recent runs", comment: "Dashboard recent workouts title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                NavigationLink {
                    WorkoutListView()
                } label: {
                    Text(String(localized: "Voir tout", comment: "See all workouts"))
                        .font(.footnote)
                        .fontWeight(.semibold)
                }
            }

            if recentWorkouts.isEmpty {
                Text(String(localized: "Aucune séance pour le moment.", comment: "No workout placeholder"))
                    .font(.footnote)
                    .foregroundStyle(Color.irTextSecondary)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(recentWorkouts) { workout in
                        HStack(spacing: Spacing.md) {
                            Circle()
                                .fill(Color.irSurface)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Image(systemName: "figure.run")
                                        .font(.caption)
                                        .foregroundStyle(Color.irPrimaryAccent)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.startDate, format: .dateTime.weekday(.wide).day().month())
                                    .font(.subheadline)
                                    .foregroundStyle(Color.irTextPrimary)

                                Text(String(format: "%.1f km · %@", (workout.distance ?? 0) / 1000, workout.paceFormatted))
                                    .font(.caption)
                                    .foregroundStyle(Color.irTextSecondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .dashboardCard()
    }

    private func refreshData() async {
        await unifiedViewModel.loadUnifiedWorkouts()
        await recoveryViewModel.loadRecoveryMetrics()

        if let recovery = recoveryViewModel.recoveryMetrics {
            contextProvider.recoveryMetrics = recovery
        }
        contextProvider.recentWorkouts = unifiedViewModel.unifiedWorkouts.prefix(10).map { $0.toWorkoutModel() }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)

            Text(title)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(padding: Spacing.base)
    }
}

#Preview {
    DashboardView()
}
