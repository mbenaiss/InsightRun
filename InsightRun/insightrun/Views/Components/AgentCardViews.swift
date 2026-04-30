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
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Image(systemName: workoutIcon)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.irPrimaryAccent, Color.irPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(IRFont.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutTypeName)
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(String(localized: "\(workout.duration) min", comment: "Workout duration"))
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                Image(systemName: "figure.run.circle.fill")
                    .font(IRFont.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.irPrimaryAccent, Color.irPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Divider()

            // Steps
            ForEach(workout.steps) { step in
                HStack(spacing: Spacing.md) {
                    Image(systemName: step.stepIcon)
                        .font(IRFont.caption)
                        .foregroundStyle(stepColor(step.type))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(stepTypeName(step.type))
                                .font(IRFont.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.irTextPrimary)

                            Text(String(localized: "\(step.duration) min", comment: "Step duration in minutes"))
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irTextSecondary)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.irBackgroundApp)
                                .clipShape(Capsule())
                        }

                        Text(step.description)
                            .font(IRFont.caption)
                            .foregroundStyle(Color.irTextSecondary)

                        if let pace = step.targetPace {
                            Text(String(localized: "Target: \(pace) /km", comment: "Target pace"))
                                .font(IRFont.microLabel)
                                .foregroundStyle(Color.irPrimaryAccent)
                        }
                    }
                }
            }

            // Message
            if let message = message, !message.isEmpty {
                Text(message)
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.top, Spacing.xxs)
            }
        }
        .padding(Spacing.base)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
        case "warmup": return Color.irWarning
        case "cooldown": return Color.irPrimaryAccent
        case "intervals": return Color.irError
        case "tempo": return Color.irPurple
        default: return Color.irSuccess
        }
    }
}

// MARK: - Trend Analysis Card View

struct TrendAnalysisCardView: View {
    let trend: AgentTrendResult
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.irPurple, Color.irPrimaryAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(IRFont.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(trend.metricDisplayName)
                        .font(IRFont.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    Text(trend.periodDisplayName)
                        .font(IRFont.body)
                        .foregroundStyle(Color.irTextSecondary)
                }

                Spacer()

                // Trend indicator
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: trend.trendIcon)
                        .font(IRFont.title3)

                    Text(String(format: "%+.1f%%", trend.percentageChange))
                        .font(IRFont.headline)
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
                    .font(IRFont.body)
                    .fontWeight(.medium)
                    .foregroundStyle(trendColor)
            }

            // Insights
            if !trend.insights.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(trend.insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "lightbulb.fill")
                                .font(IRFont.microLabel)
                                .foregroundStyle(Color.irWarning)
                                .padding(.top, 2)

                            Text(insight)
                                .font(IRFont.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }
                }
            }

            // Message
            if let message = message, !message.isEmpty {
                Text(message)
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .padding(.top, Spacing.xxs)
            }
        }
        .padding(Spacing.base)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: Color.irShadow, radius: 8, y: 4)
    }

    private var trendColor: Color {
        switch trend.trend {
        case "improving": return Color.irSuccess
        case "declining": return Color.irError
        default: return Color.irWarning
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
