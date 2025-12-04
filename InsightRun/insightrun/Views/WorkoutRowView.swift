//
//  WorkoutRowView.swift
//  InsightRun
//
//  Cell view for each workout in the list
//  Featuring iOS 26 Liquid Glass design
//

import SwiftUI
import HealthKit

// MARK: - Strava Icon (Official Strava brand logo)
struct StravaIconView: View {
    var size: CGFloat = 14
    var color: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 64.0

            // Back chevron (lighter)
            var backPath = Path()
            backPath.move(to: CGPoint(x: 41.03 * scale, y: 47.852 * scale))
            backPath.addLine(to: CGPoint(x: 35.458 * scale, y: 36.876 * scale))
            backPath.addLine(to: CGPoint(x: 27.286 * scale, y: 36.876 * scale))
            backPath.addLine(to: CGPoint(x: 41.03 * scale, y: 64 * scale))
            backPath.addLine(to: CGPoint(x: 54.766 * scale, y: 36.876 * scale))
            backPath.addLine(to: CGPoint(x: 46.586 * scale, y: 36.876 * scale))
            backPath.closeSubpath()
            context.fill(backPath, with: .color(color.opacity(0.6)))

            // Front chevron (main)
            var frontPath = Path()
            frontPath.move(to: CGPoint(x: 27.898 * scale, y: 21.944 * scale))
            frontPath.addLine(to: CGPoint(x: 35.462 * scale, y: 36.872 * scale))
            frontPath.addLine(to: CGPoint(x: 46.586 * scale, y: 36.872 * scale))
            frontPath.addLine(to: CGPoint(x: 27.898 * scale, y: 0 * scale))
            frontPath.addLine(to: CGPoint(x: 9.234 * scale, y: 36.876 * scale))
            frontPath.addLine(to: CGPoint(x: 20.35 * scale, y: 36.876 * scale))
            frontPath.closeSubpath()
            context.fill(frontPath, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

struct WorkoutRowView: View {
    let workout: WorkoutModel
    @ObservedObject private var stravaAuth = StravaAuthService.shared
    @ObservedObject private var remoteConfig = RemoteConfigService.shared

    // Strava orange color from brand guidelines
    private let stravaOrange = Color(hex: "FC5200")

    private enum WorkoutSource {
        case strava
        case apple
        case other
    }

    private var workoutSource: WorkoutSource {
        let sourceLower = workout.sourceName.lowercased()
        if sourceLower.contains("strava") {
            return .strava
        } else if sourceLower.contains("apple") || sourceLower.contains("watch") || sourceLower.contains("health") {
            return .apple
        } else {
            return .other
        }
    }

    private var sourceColor: Color {
        switch workoutSource {
        case .strava: return stravaOrange
        case .apple: return .pink
        case .other: return .blue
        }
    }

    private var workoutIcon: String {
        workout.isIndoor ? "figure.run.treadmill" : "figure.run"
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
                // Small source icon overlay - only show if Strava feature is enabled and connected
                if remoteConfig.isFeatureEnabled(.strava) && stravaAuth.isAuthenticated {
                    Group {
                        if workoutSource == .strava {
                            // Custom Strava icon
                            StravaIconView(size: 12)
                                .padding(5)
                        } else {
                            // SF Symbol for other sources
                            Image(systemName: workoutSource == .apple ? "applewatch" : "app.badge.checkmark.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                                .foregroundStyle(.white)
                                .padding(5)
                        }
                    }
                    .background(sourceColor)
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
