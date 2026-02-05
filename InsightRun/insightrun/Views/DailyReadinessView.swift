//
//  DailyReadinessView.swift
//  InsightRun
//
//  View displaying the daily readiness score with animated circle,
//  recommendation, and baseline comparison insights
//

import SwiftUI

struct DailyReadinessView: View {
    @StateObject private var viewModel = DailyReadinessViewModel()
    @State private var animatedScore: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Score Circle
                scoreCircleSection

                // Status & Recommendation
                if viewModel.readinessScore != nil {
                    statusSection
                    recommendationSection
                }

                // Insights
                if !viewModel.insights.isEmpty {
                    insightsSection
                }

                // Suggested Workout
                if viewModel.readinessScore != nil {
                    suggestedWorkoutSection
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle(String(localized: "Daily Readiness", comment: "Daily readiness view title"))
        .task {
            await viewModel.fetchDailyReadiness()
            withAnimation(.easeOut(duration: 1.0)) {
                animatedScore = Double(viewModel.readinessScore ?? 0)
            }
        }
        .refreshable {
            await viewModel.fetchDailyReadiness()
            withAnimation(.easeOut(duration: 0.5)) {
                animatedScore = Double(viewModel.readinessScore ?? 0)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(String(localized: "How ready are you today?", comment: "Daily readiness header question"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(formattedDate)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: Date())
    }

    // MARK: - Score Circle Section

    private var scoreCircleSection: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                .frame(width: 200, height: 200)

            // Progress circle
            Circle()
                .trim(from: 0, to: animatedScore / 100)
                .stroke(
                    viewModel.status.color,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: animatedScore)

            // Score text
            VStack(spacing: 4) {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let score = viewModel.readinessScore {
                    Text("\(score)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(viewModel.status.color)

                    Text(String(localized: "out of 100", comment: "Score denominator"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("--")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 12) {
            Text(viewModel.status.emoji)
                .font(.title)

            Text(viewModel.status.title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(viewModel.status.color)
        }
        .padding()
        .background(viewModel.status.color.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Recommendation Section

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text(String(localized: "Recommendation", comment: "Recommendation section title"))
                    .font(.headline)
            }

            Text(viewModel.recommendation)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Insights Section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text(String(localized: "Insights", comment: "Insights section title"))
                    .font(.headline)
            }

            ForEach(viewModel.insights) { insight in
                insightRow(insight)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func insightRow(_ insight: ReadinessInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(insight.metric)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: insight.comparison.icon)
                        .font(.caption)
                        .foregroundColor(insight.comparison.color)

                    if let deviation = insight.deviation {
                        Text("\(deviation > 0 ? "+" : "")\(Int(deviation))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(insight.comparison.color)
                    }
                }
            }

            Text(insight.message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Suggested Workout Section

    private var suggestedWorkoutSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: viewModel.suggestedWorkoutType.icon)
                    .font(.title2)
                    .foregroundColor(viewModel.status.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Suggested Workout", comment: "Suggested workout section title"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(viewModel.suggestedWorkoutType.title)
                        .font(.headline)
                }

                Spacer()
            }
            .padding()
            .background(viewModel.status.color.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DailyReadinessView()
    }
}
