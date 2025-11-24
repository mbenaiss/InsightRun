//
//  WorkoutRowView.swift
//  InsightRun
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
                    .fill(Color.irPrimaryAccent.opacity(0.2))
                    .frame(width: 56, height: 56)

                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundStyle(Color.irPrimaryAccent)
            }

            // Workout info
            VStack(alignment: .leading, spacing: 6) {
                // Date and time on same line
                HStack {
                    Text(workout.startDate, style: .date)
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    Spacer()

                    Text(workout.startDate, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Metrics on same line with reduced spacing
                HStack(spacing: 8) {
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
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.irBorder, lineWidth: 0.5)
        )
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
            sourceVersion: "10.0",
            metadata: nil,
            averageHeartRate: 145,
            maxHeartRate: 165,
            elevationGain: 50,
            hasRoute: false
        )
    )
    .padding()
}
