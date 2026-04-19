//
//  TodaySessionCard.swift
//  InsightRun
//
//  Dashboard card showing today's planned training session
//

import SwiftUI

struct TodaySessionCard: View {
    let goal: RaceGoal
    let workout: PlannedWorkout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                // Intensity color bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(workout.intensity.themeColor.gradient)
                    .frame(width: 4)

                // Workout icon
                Image(systemName: workout.type.icon)
                    .font(.title2)
                    .foregroundStyle(workout.intensity.themeColor)
                    .frame(width: 36)

                // Workout details
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.sm) {
                        if let distance = workout.targetDistance {
                            Label(
                                String(format: "%.1f km", distance / 1000),
                                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                            )
                        }
                        if workout.targetDuration != nil {
                            Label(
                                workout.formattedDuration,
                                systemImage: "clock"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)

                    Text(goal.raceName)
                        .font(.caption2)
                        .foregroundStyle(workout.intensity.themeColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextSecondary)
            }
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle(padding: 0)
    }
}
