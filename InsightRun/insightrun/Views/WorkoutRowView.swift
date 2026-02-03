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

// MARK: - Suunto Icon (Triangle from Suunto logo)
struct SuuntoIconView: View {
    var size: CGFloat = 14
    var color: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24.0
            let centerX = canvasSize.width / 2
            let padding = 3.0 * scale

            // Triangle pointing up (simplified Suunto logo)
            var trianglePath = Path()
            trianglePath.move(to: CGPoint(x: centerX, y: padding)) // Top
            trianglePath.addLine(to: CGPoint(x: canvasSize.width - padding, y: canvasSize.height - padding)) // Bottom right
            trianglePath.addLine(to: CGPoint(x: padding, y: canvasSize.height - padding)) // Bottom left
            trianglePath.closeSubpath()
            context.fill(trianglePath, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

struct WorkoutRowView: View {
    let workout: WorkoutModel

    private enum WorkoutSource {
        case strava
        case apple
        case suunto
        case garmin
        case polar
        case coros
        case imported  // FIT file imports
        case other

        var color: Color {
            switch self {
            case .strava: return Color(hex: "FC5200") // Strava orange
            case .apple: return .pink
            case .suunto: return Color(hex: "E84545") // Suunto red
            case .garmin: return Color(hex: "007CC3") // Garmin blue
            case .polar: return Color(hex: "D32F2F") // Polar red
            case .coros: return Color(hex: "FF6B00") // Coros orange
            case .imported: return Color(hex: "FF9500") // Import orange
            case .other: return .blue
            }
        }
    }

    private var workoutSource: WorkoutSource {
        let sourceLower = workout.sourceName.lowercased()
        if sourceLower.contains("strava") {
            return .strava
        } else if sourceLower.contains("suunto") {
            return .suunto
        } else if sourceLower.contains("garmin") {
            return .garmin
        } else if sourceLower.contains("polar") {
            return .polar
        } else if sourceLower.contains("coros") {
            return .coros
        } else if sourceLower.contains("apple") || sourceLower.contains("watch") || sourceLower.contains("health") {
            return .apple
        } else if sourceLower.contains("import") {
            return .imported
        } else {
            return .other
        }
    }

    private var workoutIcon: String {
        workout.isIndoor ? "figure.run.treadmill" : "figure.run"
    }

    @ViewBuilder
    private var sourceIconView: some View {
        switch workoutSource {
        case .strava:
            StravaIconView(size: 12)
                .padding(5)
        case .suunto:
            SuuntoIconView(size: 12)
                .padding(5)
        case .apple:
            Image(systemName: "applewatch")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundStyle(.white)
                .padding(5)
        case .imported:
            Text("I")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
        default:
            Text(String(workout.sourceName.prefix(1)).uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
        }
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
                // Source icon overlay - always show to identify workout origin
                sourceIconView
                    .background(workoutSource.color)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.irCardBackground, lineWidth: 2)
                    )
                    .offset(x: 4, y: 4)
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
