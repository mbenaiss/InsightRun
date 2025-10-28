//
//  WorkoutRowView.swift
//  HealthApp
//
//  Cell view for each workout in the list
//  Featuring iOS 26 Liquid Glass design
//

import SwiftUI
import HealthKit

struct WorkoutRowView: View {
    let workout: WorkoutModel

    var body: some View {
        HStack(spacing: 16) {
            // Icon with gradient
            ZStack {
                Circle()
                    .fill(.blue.gradient.opacity(0.2))
                    .frame(width: 56, height: 56)

                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundStyle(.blue.gradient)
            }

            // Workout info
            VStack(alignment: .leading, spacing: 6) {
                Text(workout.startDate, style: .date)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(workout.startDate, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(workout.distanceFormatted, systemImage: "ruler")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(workout.durationFormatted, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let pace = workout.averagePace {
                        let minutes = Int(pace)
                        let seconds = Int((pace - Double(minutes)) * 60)
                        Label(String(format: "%d'%02d\"/km", minutes, seconds), systemImage: "speedometer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

// Preview
#Preview {
    WorkoutRowView(
        workout: WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            duration: 1800,
            distance: 5000,
            totalEnergyBurned: 350,
            sourceName: "Apple Watch",
            sourceVersion: "10.0"
        )
    )
    .padding()
}
