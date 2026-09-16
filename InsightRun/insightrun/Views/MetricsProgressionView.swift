//
//  MetricsProgressionView.swift
//  InsightRun
//
//  Progression tab showing metric evolution over time
//

import SwiftUI

struct MetricsProgressionView: View {
    @ObservedObject var viewModel: StatisticsViewModel

    var body: some View {
        if viewModel.isLoadingProgression && viewModel.progressionData.isEmpty {
            loadingState
        } else if viewModel.performanceMetrics.isEmpty && viewModel.advancedMetrics.isEmpty {
            emptyState
        } else {
            metricsContent
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: Spacing.base) {
            ProgressView(value: viewModel.progressionLoadingProgress)
                .tint(Color.irPrimaryAccent)

            Text(
                String(
                    format: String(
                        localized: "progression.loading", defaultValue: "Loading metrics… %d%%",
                        comment: "Loading progression metrics"),
                    Int(viewModel.progressionLoadingProgress * 100)
                )
            )
            .font(IRFont.body)
            .foregroundStyle(Color.irTextSecondary)
        }
        .padding()
        .padding(.top, Spacing.xxl)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(IRFont.numLG)
                .foregroundStyle(Color.irTextSecondary)

            Text(
                String(
                    localized: "progression.empty.title", defaultValue: "Not enough data",
                    comment: "Progression empty state title")
            )
            .font(IRFont.title2)

            Text(
                String(
                    localized: "progression.empty.message",
                    defaultValue: "At least 2 workouts are needed in this period to show progression.",
                    comment: "Progression empty state message")
            )
            .font(IRFont.body)
            .foregroundStyle(Color.irTextSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .padding(.top, Spacing.xxl)
    }

    // MARK: - Metrics Content

    private var metricsContent: some View {
        VStack(spacing: Spacing.lg) {
            if viewModel.isLoadingProgression {
                ProgressView(value: viewModel.progressionLoadingProgress)
                    .tint(Color.irPrimaryAccent)
                    .padding(.horizontal)
            }

            Text(
                String(
                    localized: "progression.availability",
                    defaultValue: "Each chart needs this metric in at least 2 workouts within the selected period. The number of available metrics can vary by period.")
            )
            .font(IRFont.caption)
            .foregroundStyle(Color.irTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("statistics-progression-availability")

            Text(String(localized: "progression.vo2_context", defaultValue: "VO₂ max uses the latest estimate available at each workout, up to 7 days earlier."))
                .font(IRFont.caption)
                .foregroundStyle(Color.irTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.performanceMetrics.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(
                        String(
                            localized: "progression.section.performance", defaultValue: "Performance",
                            comment: "Performance section title")
                    )
                    .font(IRFont.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(viewModel.performanceMetrics) { metric in
                        MetricProgressionCard(series: metric)
                            .accessibilityIdentifier("statistics-metric-\(metric.id)")
                    }
                }
            }

            if !viewModel.advancedMetrics.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(
                        String(
                            localized: "progression.section.advanced", defaultValue: "Advanced metrics",
                            comment: "Advanced metrics section title")
                    )
                    .font(IRFont.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(viewModel.advancedMetrics) { metric in
                        MetricProgressionCard(series: metric)
                            .accessibilityIdentifier("statistics-metric-\(metric.id)")
                    }
                }
            }
        }
    }
}
