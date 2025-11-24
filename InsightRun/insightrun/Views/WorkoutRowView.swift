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
    @ObservedObject private var stravaAuth = StravaAuthService.shared

    private var sourceInfo: (icon: String, color: Color) {
        let sourceLower = workout.sourceName.lowercased()
        if sourceLower.contains("strava") {
            return ("s.circle.fill", .orange)
        } else if sourceLower.contains("apple") || sourceLower.contains("watch") || sourceLower.contains("health") {
            return ("applewatch", .pink)
        } else {
            return ("app.badge.checkmark.fill", .blue)
        }
    }

    private var workoutIcon: String {
        workout.isIndoor ? "figure.indoor.run" : "figure.run"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon with gradient and source indicator
            ZStack {
                Circle()
                    .fill(Color.irPrimaryAccent.opacity(0.2))
                    .frame(width: 56, height: 56)

                Image(systemName: workoutIcon)
                    .font(.title2)
                    .foregroundStyle(Color.irPrimaryAccent)
            }
            .overlay(alignment: .bottomTrailing) {
                // Small source icon overlay - only show if Strava is connected
                if stravaAuth.isAuthenticated {
                    Image(systemName: sourceInfo.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .padding(4)
                        .background(sourceInfo.color)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.irCardBackground, lineWidth: 2)
                        )
                        .offset(x: 4, y: 4)
                }
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
