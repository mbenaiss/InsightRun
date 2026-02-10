//
//  AgentCardViews.swift
//  InsightRun
//
//  Rich card views for agentic AI function results
//

import SwiftUI

// MARK: - Workout Card View

struct WorkoutCardView: View {
    let workout: AgentWorkoutResult
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: workoutIcon)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutTypeName)
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "\(workout.duration) min", comment: "Workout duration"))
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Divider()

            // Steps
            ForEach(workout.steps) { step in
                HStack(spacing: 10) {
                    Image(systemName: step.stepIcon)
                        .font(.caption)
                        .foregroundStyle(stepColor(step.type))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(stepTypeName(step.type))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.irTextPrimary)

                            Text(String(localized: "\(step.duration) min", comment: "Step duration in minutes"))
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.irBackgroundApp)
                                .clipShape(Capsule())
                        }

                        Text(step.description)
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)

                        if let pace = step.targetPace {
                            Text(String(localized: "Target: \(pace) /km", comment: "Target pace"))
                                .font(.caption2)
                                .foregroundStyle(Color.irPrimaryAccent)
                        }
                    }
                }
            }

            // Message
            if let message = message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    private var workoutIcon: String {
        switch workout.type {
        case "intervals": return "bolt.fill"
        case "tempo": return "gauge.with.dots.needle.67percent"
        case "long_run": return "road.lanes"
        case "recovery": return "leaf.fill"
        case "hill_repeats": return "mountain.2.fill"
        case "fartlek": return "shuffle"
        default: return "figure.run"
        }
    }

    private var workoutTypeName: String {
        switch workout.type {
        case "easy_run": return String(localized: "Easy Run", comment: "Workout type")
        case "tempo": return String(localized: "Tempo Run", comment: "Workout type")
        case "intervals": return String(localized: "Intervals", comment: "Workout type")
        case "long_run": return String(localized: "Long Run", comment: "Workout type")
        case "recovery": return String(localized: "Recovery Run", comment: "Workout type")
        case "hill_repeats": return String(localized: "Hill Repeats", comment: "Workout type")
        case "fartlek": return String(localized: "Fartlek", comment: "Workout type")
        default: return String(localized: "Workout", comment: "Default workout type name")
        }
    }

    private func stepTypeName(_ type: String) -> String {
        switch type {
        case "warmup": return String(localized: "Warm Up", comment: "Workout step type")
        case "cooldown": return String(localized: "Cool Down", comment: "Workout step type")
        case "intervals": return String(localized: "Intervals", comment: "Workout step type")
        case "tempo": return String(localized: "Tempo", comment: "Workout step type")
        case "steady": return String(localized: "Steady", comment: "Workout step type")
        case "main": return String(localized: "Main", comment: "Workout step type")
        default: return String(localized: "Exercise", comment: "Default workout step type")
        }
    }

    private func stepColor(_ type: String) -> Color {
        switch type {
        case "warmup": return .orange
        case "cooldown": return .blue
        case "intervals": return .red
        case "tempo": return .purple
        default: return .green
        }
    }
}

// MARK: - Trend Analysis Card View

struct TrendAnalysisCardView: View {
    let trend: AgentTrendResult
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(trend.metricDisplayName)
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(trend.periodDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                // Trend indicator
                HStack(spacing: 4) {
                    Image(systemName: trend.trendIcon)
                        .font(.title3)

                    Text(String(format: "%+.1f%%", trend.percentageChange))
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundStyle(trendColor)
            }

            Divider()

            // Trend label
            HStack {
                Circle()
                    .fill(trendColor)
                    .frame(width: 8, height: 8)

                Text(trendLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(trendColor)
            }

            // Insights
            if !trend.insights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(trend.insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.irWarning)
                                .padding(.top, 2)

                            Text(insight)
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }
                }
            }

            // Message
            if let message = message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    private var trendColor: Color {
        switch trend.trend {
        case "improving": return .green
        case "declining": return .red
        default: return .orange
        }
    }

    private var trendLabel: String {
        switch trend.trend {
        case "improving": return String(localized: "Improving", comment: "Trend direction")
        case "declining": return String(localized: "Declining", comment: "Trend direction")
        default: return String(localized: "Stable", comment: "Trend direction")
        }
    }
}
