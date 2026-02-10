//
//  WeeklySummaryView.swift
//  InsightRun
//
//  Weekly summary screen showing running, sleep, recovery data and comparison.
//

import SwiftUI

struct WeeklySummaryView: View {
    @StateObject private var viewModel = WeeklySummaryViewModel()

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                summaryContent
            }
        }
        .background(Color.irBackgroundApp)
        .navigationTitle(String(localized: "Weekly Summary", comment: "Navigation title for weekly summary"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "Loading...", comment: "Loading indicator text"))
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.irWarning.gradient)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 100)
    }

    // MARK: - Content

    private var summaryContent: some View {
        VStack(spacing: 20) {
            // Header
            headerSection
                .padding(.horizontal)
                .padding(.top)

            // Running
            runningSection
                .padding(.horizontal)

            // Sleep
            sleepSection
                .padding(.horizontal)

            // Recovery
            recoverySection
                .padding(.horizontal)

            // Comparison
            comparisonSection
                .padding(.horizontal)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.formattedWeekRange)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)

                Text(String(localized: "\(viewModel.runCount) runs this week", comment: "Number of runs this week"))
                    .font(.subheadline)
                    .foregroundStyle(Color.irTextSecondary)
            }
            Spacer()
            Image(systemName: "calendar")
                .font(.title)
                .foregroundStyle(Color.irPrimaryAccent.gradient)
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irShadow, radius: 10, y: 5)
    }

    // MARK: - Running Section

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "Running", comment: "Section header for running metrics"), systemImage: "figure.run")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MetricCard(
                    icon: "map.fill",
                    iconColor: .blue,
                    title: String(localized: "Distance", comment: "Label for total distance"),
                    value: viewModel.formattedTotalDistance
                )

                MetricCard(
                    icon: "clock.fill",
                    iconColor: .green,
                    title: String(localized: "Duration", comment: "Label for total duration"),
                    value: viewModel.formattedTotalDuration
                )

                MetricCard(
                    icon: "speedometer",
                    iconColor: .orange,
                    title: String(localized: "Avg Pace", comment: "Label for average pace"),
                    value: viewModel.formattedAveragePace
                )

                MetricCard(
                    icon: "flame.fill",
                    iconColor: .red,
                    title: String(localized: "Calories", comment: "Label for total calories"),
                    value: String(format: "%.0f %@", viewModel.totalCalories, String(localized: "kcal", comment: "Unit abbreviation for kilocalories"))
                )

                MetricCard(
                    icon: "mountain.2.fill",
                    iconColor: .brown,
                    title: String(localized: "Elevation", comment: "Label for total elevation gain"),
                    value: String(format: "%.0f %@", viewModel.totalElevation, String(localized: "m", comment: "Unit abbreviation for meters"))
                )

                if let hr = viewModel.averageHeartRate {
                    MetricCard(
                        icon: "heart.fill",
                        iconColor: .pink,
                        title: String(localized: "Avg HR", comment: "Label for average heart rate"),
                        value: String(format: "%.0f %@", hr, String(localized: "bpm", comment: "Unit abbreviation for beats per minute"))
                    )
                }
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irShadow, radius: 10, y: 5)
    }

    // MARK: - Sleep Section

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "Sleep", comment: "Section header for sleep metrics"), systemImage: "moon.fill")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MetricCard(
                    icon: "bed.double.fill",
                    iconColor: .indigo,
                    title: String(localized: "Avg Duration", comment: "Label for average sleep duration"),
                    value: viewModel.formattedAverageSleep
                )

                MetricCard(
                    icon: "percent",
                    iconColor: .cyan,
                    title: String(localized: "Efficiency", comment: "Label for average sleep efficiency"),
                    value: String(format: "%.0f%%", viewModel.averageSleepEfficiency)
                )

                MetricCard(
                    icon: "star.fill",
                    iconColor: .yellow,
                    title: String(localized: "Quality", comment: "Label for average sleep quality score"),
                    value: "\(viewModel.averageQualityScore)/100"
                )
            }

            if viewModel.averageDeepPercent > 0 {
                sleepStagesBar
            }
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irShadow, radius: 10, y: 5)
    }

    private var sleepStagesBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Avg Sleep Stages", comment: "Label for average sleep stages breakdown"))
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    stageSegment(
                        width: geometry.size.width * viewModel.averageDeepPercent / 100,
                        color: .indigo,
                        label: String(localized: "Deep", comment: "Deep sleep stage label")
                    )
                    stageSegment(
                        width: geometry.size.width * viewModel.averageCorePercent / 100,
                        color: .blue,
                        label: String(localized: "Core", comment: "Core sleep stage label")
                    )
                    stageSegment(
                        width: geometry.size.width * viewModel.averageRemPercent / 100,
                        color: .cyan,
                        label: String(localized: "REM", comment: "REM sleep stage label")
                    )
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 16) {
                stageLegend(color: .indigo, label: "\(String(localized: "Deep", comment: "Deep sleep stage legend")) \(String(format: "%.0f%%", viewModel.averageDeepPercent))")
                stageLegend(color: .blue, label: "\(String(localized: "Core", comment: "Core sleep stage legend")) \(String(format: "%.0f%%", viewModel.averageCorePercent))")
                stageLegend(color: .cyan, label: "\(String(localized: "REM", comment: "REM sleep stage legend")) \(String(format: "%.0f%%", viewModel.averageRemPercent))")
            }
            .font(.caption2)
        }
    }

    private func stageSegment(width: CGFloat, color: Color, label: String) -> some View {
        Rectangle()
            .fill(color.gradient)
            .frame(width: max(width, 0))
            .accessibilityLabel(label)
    }

    private func stageLegend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(Color.irTextSecondary)
        }
    }

    // MARK: - Recovery Section

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "Recovery", comment: "Section header for recovery metrics"), systemImage: "heart.text.square.fill")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            HStack(spacing: 20) {
                CircularProgressView(score: viewModel.averageRecoveryScore, size: 100, lineWidth: 8)

                VStack(alignment: .leading, spacing: 12) {
                    if let hrv = viewModel.averageHRV {
                        recoveryMetricRow(
                            icon: "waveform.path.ecg",
                            color: .purple,
                            label: String(localized: "HRV", comment: "Label for heart rate variability"),
                            value: String(format: "%.0f %@", hrv, String(localized: "ms", comment: "Unit abbreviation for milliseconds"))
                        )
                    }

                    if let rhr = viewModel.averageRestingHR {
                        recoveryMetricRow(
                            icon: "heart.fill",
                            color: .red,
                            label: String(localized: "Resting HR", comment: "Label for resting heart rate"),
                            value: String(format: "%.0f %@", rhr, String(localized: "bpm", comment: "Unit abbreviation for beats per minute"))
                        )
                    }

                    if let spo2 = viewModel.averageSpO2 {
                        recoveryMetricRow(
                            icon: "drop.fill",
                            color: .blue,
                            label: String(localized: "SpO2", comment: "Label for blood oxygen saturation"),
                            value: String(format: "%.1f%%", spo2)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.irShadow, radius: 10, y: 5)
    }

    private func recoveryMetricRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color.gradient)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextPrimary)
        }
    }

    // MARK: - Comparison Section

    @ViewBuilder
    private var comparisonSection: some View {
        let hasComparison = viewModel.distanceChange != nil || viewModel.durationChange != nil || viewModel.recoveryScoreChange != nil

        if hasComparison {
            VStack(alignment: .leading, spacing: 16) {
                Label(String(localized: "vs Previous Week", comment: "Section header for comparison with previous week"), systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                VStack(spacing: 12) {
                    if let distChange = viewModel.distanceChange {
                        comparisonRow(
                            label: String(localized: "Distance", comment: "Label for distance comparison"),
                            change: distChange,
                            isPercent: true
                        )
                    }

                    if let durChange = viewModel.durationChange {
                        comparisonRow(
                            label: String(localized: "Duration", comment: "Label for duration comparison"),
                            change: durChange,
                            isPercent: true
                        )
                    }

                    if let recChange = viewModel.recoveryScoreChange {
                        comparisonRow(
                            label: String(localized: "Recovery Score", comment: "Label for recovery score comparison"),
                            change: Double(recChange),
                            isPercent: false
                        )
                    }
                }
            }
            .padding(20)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.irShadow, radius: 10, y: 5)
        }
    }

    private func comparisonRow(label: String, change: Double, isPercent: Bool) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)

                if isPercent {
                    Text(String(format: "%+.1f%%", change))
                        .font(.body)
                        .fontWeight(.semibold)
                } else {
                    Text(String(format: "%+.0f %@", change, String(localized: "pts", comment: "Unit abbreviation for points")))
                        .font(.body)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(change >= 0 ? Color.irSuccess : Color.irError)
        }
    }
}

#Preview {
    NavigationStack {
        WeeklySummaryView()
    }
}
