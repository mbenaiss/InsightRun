//
//  WorkoutComparisonViewModel.swift
//  InsightRun
//
//  ViewModel that computes comparison metrics between a reference workout
//  and a list of similar workouts.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class WorkoutComparisonViewModel: ObservableObject {

    // MARK: - Types

    /// Direction of change for a metric comparison.
    enum DeltaDirection {
        case improved
        case regressed
        case neutral
    }

    /// A single metric comparison between the reference and a compared workout.
    struct MetricDelta: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let referenceValue: String
        let comparedValue: String
        let deltaText: String
        let direction: DeltaDirection
    }

    /// Complete comparison result for one workout.
    struct WorkoutComparison: Identifiable {
        let id: UUID
        let workout: WorkoutModel
        let deltas: [MetricDelta]
    }

    // MARK: - Published

    @Published var comparisons: [WorkoutComparison] = []

    // MARK: - Data

    let referenceWorkout: WorkoutModel
    let similarWorkouts: [WorkoutModel]

    // MARK: - Init

    init(referenceWorkout: WorkoutModel, similarWorkouts: [WorkoutModel]) {
        self.referenceWorkout = referenceWorkout
        self.similarWorkouts = similarWorkouts
        self.comparisons = similarWorkouts.map { Self.buildComparison(reference: referenceWorkout, compared: $0) }
    }

    // MARK: - Formatted Reference Info

    var referenceDate: String {
        referenceWorkout.startDate.formatted(date: .abbreviated, time: .omitted)
    }

    var referenceDistance: String {
        referenceWorkout.distanceFormatted
    }

    var referencePace: String {
        guard let pace = referenceWorkout.averagePace else { return "N/A" }
        return Self.formatPace(pace)
    }

    // MARK: - Private

    /// Build all metric deltas between the reference and a compared workout.
    private static func buildComparison(
        reference: WorkoutModel,
        compared: WorkoutModel
    ) -> WorkoutComparison {
        var deltas: [MetricDelta] = []

        // Pace (lower is better)
        if let refPace = reference.averagePace, let cmpPace = compared.averagePace {
            let diff = cmpPace - refPace // positive means slower
            let direction: DeltaDirection = diff < -0.01 ? .improved : (diff > 0.01 ? .regressed : .neutral)
            deltas.append(MetricDelta(
                label: String(localized: "Pace", comment: "Comparison metric label for pace"),
                icon: "speedometer",
                referenceValue: formatPace(refPace),
                comparedValue: formatPace(cmpPace),
                deltaText: formatPaceDelta(diff),
                direction: direction
            ))
        }

        // Distance (higher is better)
        if let refDist = reference.distance, let cmpDist = compared.distance {
            let diff = cmpDist - refDist
            let direction: DeltaDirection = diff > 10 ? .improved : (diff < -10 ? .regressed : .neutral)
            deltas.append(MetricDelta(
                label: String(localized: "Distance", comment: "Comparison metric label for distance"),
                icon: "ruler",
                referenceValue: formatDistance(refDist),
                comparedValue: formatDistance(cmpDist),
                deltaText: formatDistanceDelta(diff),
                direction: direction
            ))
        }

        // Duration (lower is better for same distance type workout)
        let refDur = reference.duration
        let cmpDur = compared.duration
        if refDur > 0 && cmpDur > 0 {
            let diff = cmpDur - refDur
            let direction: DeltaDirection = diff < -1 ? .improved : (diff > 1 ? .regressed : .neutral)
            deltas.append(MetricDelta(
                label: String(localized: "Duration", comment: "Comparison metric label for duration"),
                icon: "clock",
                referenceValue: formatDuration(refDur),
                comparedValue: formatDuration(cmpDur),
                deltaText: formatDurationDelta(diff),
                direction: direction
            ))
        }

        // Average Heart Rate (neutral, just show delta)
        if let refHR = reference.averageHeartRate, let cmpHR = compared.averageHeartRate {
            let diff = cmpHR - refHR
            deltas.append(MetricDelta(
                label: String(localized: "Avg HR", comment: "Comparison metric label for average heart rate"),
                icon: "heart.fill",
                referenceValue: String(format: "%.0f bpm", refHR),
                comparedValue: String(format: "%.0f bpm", cmpHR),
                deltaText: String(format: "%+.0f bpm", diff),
                direction: .neutral
            ))
        }

        // Calories
        if let refCal = reference.totalEnergyBurned, let cmpCal = compared.totalEnergyBurned {
            let diff = cmpCal - refCal
            let direction: DeltaDirection = diff > 1 ? .improved : (diff < -1 ? .regressed : .neutral)
            deltas.append(MetricDelta(
                label: String(localized: "Calories", comment: "Comparison metric label for calories"),
                icon: "flame.fill",
                referenceValue: String(format: "%.0f kcal", refCal),
                comparedValue: String(format: "%.0f kcal", cmpCal),
                deltaText: String(format: "%+.0f kcal", diff),
                direction: direction
            ))
        }

        // Elevation gain
        if let refElev = reference.elevationGain, let cmpElev = compared.elevationGain {
            let diff = cmpElev - refElev
            deltas.append(MetricDelta(
                label: String(localized: "Elevation", comment: "Comparison metric label for elevation gain"),
                icon: "mountain.2.fill",
                referenceValue: String(format: "%.0f m", refElev),
                comparedValue: String(format: "%.0f m", cmpElev),
                deltaText: String(format: "%+.0f m", diff),
                direction: .neutral
            ))
        }

        return WorkoutComparison(
            id: compared.id,
            workout: compared,
            deltas: deltas
        )
    }

    // MARK: - Formatting Helpers

    static func formatPace(_ pace: Double) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"/km", minutes, seconds)
    }

    private static func formatPaceDelta(_ diff: Double) -> String {
        let absDiff = abs(diff)
        let minutes = Int(absDiff)
        let seconds = Int((absDiff - Double(minutes)) * 60)
        let sign = diff >= 0 ? "+" : "-"
        return String(format: "%@%d'%02d\"", sign, minutes, seconds)
    }

    private static func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.2f km", km)
    }

    private static func formatDistanceDelta(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%+.2f km", km)
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = Int(seconds) / 60 % 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%dh %02dm %02ds", h, m, s)
        }
        return String(format: "%dm %02ds", m, s)
    }

    private static func formatDurationDelta(_ seconds: TimeInterval) -> String {
        let totalSec = Int(abs(seconds))
        let m = totalSec / 60
        let s = totalSec % 60
        let sign = seconds >= 0 ? "+" : "-"
        if m > 0 {
            return String(format: "%@%dm %02ds", sign, m, s)
        }
        return String(format: "%@%ds", sign, s)
    }
}
