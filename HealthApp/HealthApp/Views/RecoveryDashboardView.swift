//
//  RecoveryDashboardView.swift
//  HealthApp
//
//  Dashboard for recovery and readiness metrics
//

import SwiftUI

struct RecoveryDashboardView: View {
    @StateObject private var viewModel = RecoveryViewModel()
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
                .navigationTitle("Récupération")
                .navigationBarTitleDisplayMode(.large)
                .refreshable {
                    await viewModel.refresh()
                }
                .task {
                    await viewModel.loadRecoveryMetrics()
                }
            }

            // Floating AI Button
            if viewModel.recoveryMetrics != nil {
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
            Text("Chargement...")
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
                Text("Erreur")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Réessayer") {
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
                Text("Aucune Donnée")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Les données de récupération ne sont pas disponibles.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("Tip: Activez les permissions dans Réglages → Confidentialité → Santé → healthapp")
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
                    Text("Score de Récupération")
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
            Label("Recommandation", systemImage: "lightbulb.fill")
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
            Text("Fréquence Cardiaque")
                .font(.headline)

            VStack(spacing: 12) {
                if let rhr = recovery.restingHeartRate {
                    HealthMetricRow(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "FC au repos",
                        value: String(format: "%.0f bpm", rhr)
                    )
                }

                if let hrv = recovery.hrv {
                    HealthMetricRow(
                        icon: "waveform.path.ecg",
                        iconColor: .blue,
                        title: "Variabilité (HRV)",
                        value: String(format: "%.0f ms", hrv)
                    )
                }

                if let whr = recovery.walkingHeartRate {
                    HealthMetricRow(
                        icon: "figure.walk",
                        iconColor: .green,
                        title: "FC en marche",
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
            Text("Sommeil")
                .font(.headline)

            VStack(spacing: 12) {
                HealthMetricRow(
                    icon: "moon.fill",
                    iconColor: .indigo,
                    title: "Session de sommeil",
                    value: sleep.formattedSleepTime
                )

                HealthMetricRow(
                    icon: "bed.double.fill",
                    iconColor: .blue,
                    title: "Durée de sommeil",
                    value: sleep.formattedTotalSleep
                )

                if let napDuration = sleep.formattedNapDuration {
                    HealthMetricRow(
                        icon: "powersleep",
                        iconColor: .orange,
                        title: "Siestes",
                        value: napDuration
                    )
                }

                HealthMetricRow(
                    icon: "clock.fill",
                    iconColor: .cyan,
                    title: "Temps au lit",
                    value: sleep.formattedTimeInBed
                )

                HealthMetricRow(
                    icon: "chart.bar.fill",
                    iconColor: .teal,
                    title: "Efficacité",
                    value: String(format: "%.0f%%", sleep.sleepEfficiency)
                )

                HealthMetricRow(
                    icon: "star.fill",
                    iconColor: .yellow,
                    title: "Qualité",
                    value: sleep.qualityDescription
                )
            }

            // Sleep stages if available
            if let deep = sleep.deepSleepDuration,
               let core = sleep.coreSleepDuration,
               let rem = sleep.remSleepDuration {
                Divider()
                    .padding(.vertical, 4)

                Text("Phases de sommeil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    SleepStageRow(stage: "Profond", duration: deep, color: .blue)
                    SleepStageRow(stage: "Léger", duration: core, color: .cyan)
                    SleepStageRow(stage: "Paradoxal", duration: rem, color: .indigo)
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
            Text("Respiration")
                .font(.headline)

            HealthMetricRow(
                icon: "wind",
                iconColor: .teal,
                title: "Fréquence respiratoire",
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
            VStack(spacing: 4) {
                Text(viewModel.formattedSelectedDate)
                    .font(.headline)
                    .foregroundColor(.primary)

                if !viewModel.isToday {
                    Button(action: {
                        Task {
                            await viewModel.goToToday()
                        }
                    }) {
                        Text("Aujourd'hui")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
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
