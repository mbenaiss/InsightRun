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
        VStack(spacing: 16) {
            ProgressView(value: viewModel.progressionLoadingProgress)
                .tint(Color.irPrimaryAccent)

            Text(String(
                format: String(localized: "progression.loading", defaultValue: "Loading metrics… %d%%", comment: "Loading progression metrics"),
                Int(viewModel.progressionLoadingProgress * 100)
            ))
            .font(.subheadline)
            .foregroundStyle(Color.irTextSecondary)
        }
        .padding()
        .padding(.top, 30)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundStyle(Color.irTextSecondary)

            Text(String(localized: "progression.empty.title", defaultValue: "Not enough data", comment: "Progression empty state title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "progression.empty.message", defaultValue: "At least 2 workouts are needed in this period to show progression.", comment: "Progression empty state message"))
                .font(.body)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 50)
    }

    // MARK: - Metrics Content

    private var metricsContent: some View {
        VStack(spacing: 20) {
            if viewModel.isLoadingProgression {
                ProgressView(value: viewModel.progressionLoadingProgress)
                    .tint(Color.irPrimaryAccent)
                    .padding(.horizontal)
            }

            if !viewModel.performanceMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "progression.section.performance", defaultValue: "Performance", comment: "Performance section title"))
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(viewModel.performanceMetrics) { metric in
                        MetricProgressionCard(series: metric)
                    }
                }
            }

            if !viewModel.advancedMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "progression.section.advanced", defaultValue: "Advanced metrics", comment: "Advanced metrics section title"))
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(viewModel.advancedMetrics) { metric in
                        MetricProgressionCard(series: metric)
                    }
                }
            }
        }
    }
}
