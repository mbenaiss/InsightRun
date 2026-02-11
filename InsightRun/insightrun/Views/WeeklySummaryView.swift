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
        VStack(spacing: Spacing.lg) {
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
        VStack(spacing: Spacing.base) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.irWarning.gradient)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)
        }
        .padding(.top, 100)
    }

    // MARK: - Content

    private var summaryContent: some View {
        VStack(spacing: Spacing.base) {
            headerSection
                .padding(.horizontal)
                .padding(.top, Spacing.sm)

            runningHighlights
                .padding(.horizontal)

            runningDetails
                .padding(.horizontal)

            sleepSection
                .padding(.horizontal)

            recoverySection
                .padding(.horizontal)

            comparisonSection
                .padding(.horizontal)
        }
        .padding(.bottom, Spacing.lg)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
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
                .font(.title3)
                .foregroundStyle(Color.irPrimaryAccent.gradient)
        }
        .cardStyle()
    }

    // MARK: - Running Highlights

    private var runningHighlights: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(String(localized: "Running", comment: "Section header for running metrics"), systemImage: "figure.run")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            HStack(spacing: Spacing.lg) {
                highlightColumn(
                    value: viewModel.formattedTotalDistance,
                    label: String(localized: "Distance", comment: "Label for total distance")
                )

                highlightColumn(
                    value: viewModel.formattedTotalDuration,
                    label: String(localized: "Duration", comment: "Label for total duration")
                )

                highlightColumn(
                    value: viewModel.formattedAveragePace,
                    label: String(localized: "Avg Pace", comment: "Label for average pace")
                )
            }
        }
        .cardStyle()
    }

    private func highlightColumn(value: String, label: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Running Details

    private var runningDetails: some View {
        VStack(spacing: Spacing.sm) {
            metricRow(
                icon: "figure.run",
                iconColor: .blue,
                title: String(localized: "Runs", comment: "Label for number of runs"),
                value: "\(viewModel.runCount)"
            )

            metricRow(
                icon: "flame.fill",
                iconColor: .red,
                title: String(localized: "Calories", comment: "Label for total calories"),
                value: String(format: "%.0f %@", viewModel.totalCalories, String(localized: "kcal", comment: "Unit abbreviation for kilocalories"))
            )

            if viewModel.longestRunDistance > 0 {
                metricRow(
                    icon: "trophy.fill",
                    iconColor: .orange,
                    title: String(localized: "Longest Run", comment: "Label for longest run distance"),
                    value: viewModel.formattedLongestRun
                )
            }

            if viewModel.bestPace != nil {
                metricRow(
                    icon: "bolt.fill",
                    iconColor: .green,
                    title: String(localized: "Best Pace", comment: "Label for best pace"),
                    value: viewModel.formattedBestPace
                )
            }

            if let maxHR = viewModel.maxHeartRate {
                metricRow(
                    icon: "heart.fill",
                    iconColor: .pink,
                    title: String(localized: "Max HR", comment: "Label for max heart rate"),
                    value: String(format: "%.0f %@", maxHR, String(localized: "bpm", comment: "Unit abbreviation for beats per minute"))
                )
            }
        }
        .cardStyle(padding: Spacing.base)
    }

    private func metricRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(iconColor.opacity(0.8))
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextSecondary)
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - Sleep Section

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(String(localized: "Sleep", comment: "Section header for sleep metrics"), systemImage: "moon.fill")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            HStack(spacing: Spacing.lg) {
                highlightColumn(
                    value: viewModel.formattedAverageSleep,
                    label: String(localized: "Avg Duration", comment: "Label for average sleep duration")
                )

                highlightColumn(
                    value: String(format: "%.0f%%", viewModel.averageSleepEfficiency),
                    label: String(localized: "Efficiency", comment: "Label for average sleep efficiency")
                )

                highlightColumn(
                    value: "\(viewModel.averageQualityScore)/100",
                    label: String(localized: "Quality", comment: "Label for average sleep quality score")
                )
            }

            if viewModel.averageDeepPercent > 0 {
                Divider()
                    .padding(.vertical, Spacing.xxs)
                sleepStagesBar
            }
        }
        .cardStyle()
    }

    private var sleepStagesBar: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
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
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))

            HStack(spacing: Spacing.base) {
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
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(Color.irTextSecondary)
        }
    }

    // MARK: - Recovery Section

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(String(localized: "Recovery", comment: "Section header for recovery metrics"), systemImage: "heart.text.square.fill")
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            HStack(spacing: Spacing.lg) {
                CircularProgressView(score: viewModel.averageRecoveryScore, size: 90, lineWidth: 7)

                VStack(alignment: .leading, spacing: Spacing.md) {
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
        .cardStyle()
    }

    private func recoveryMetricRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color.gradient)
                .frame(width: 16)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextPrimary)
        }
    }

    // MARK: - Comparison Section

    @ViewBuilder
    private var comparisonSection: some View {
        let hasComparison = viewModel.distanceChange != nil || viewModel.durationChange != nil || viewModel.recoveryScoreChange != nil

        if hasComparison {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label(String(localized: "vs Previous Week", comment: "Section header for comparison with previous week"), systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)

                VStack(spacing: Spacing.sm) {
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
            .cardStyle()
        }
    }

    private func comparisonRow(label: String, change: Double, isPercent: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            HStack(spacing: Spacing.xxs) {
                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)

                if isPercent {
                    Text(String(format: "%+.1f%%", change))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else {
                    Text(String(format: "%+.0f %@", change, String(localized: "pts", comment: "Unit abbreviation for points")))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(change >= 0 ? Color.irSuccess : Color.irError)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

#Preview {
    NavigationStack {
        WeeklySummaryView()
    }
}
