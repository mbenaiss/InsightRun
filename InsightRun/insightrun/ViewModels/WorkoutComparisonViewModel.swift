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
        guard let pace = referenceWorkout.averagePace else {
            return String(localized: "common.value.notAvailable", defaultValue: "N/A", comment: "Placeholder shown when a metric has no value")
        }
        return Self.formatPace(pace)
    }

    // MARK: - Private

    /// Build all metric deltas between the reference and a compared workout.
    private static func buildComparison(
        reference: WorkoutModel,
        compared: WorkoutModel
    ) -> WorkoutComparison {
        var deltas: [MetricDelta] = []

        // Delta direction is from the reference (current) workout's perspective:
        // "improved" = my current run is better than this old run

        // Pace (lower is better → negative diff = I'm faster now)
        if let refPace = reference.averagePace, let cmpPace = compared.averagePace {
            let diff = refPace - cmpPace
            let direction: DeltaDirection = diff < -0.01 ? .improved : (diff > 0.01 ? .regressed : .neutral)
            deltas.append(MetricDelta(
                label: String(localized: "Pace", comment: "Comparison metric label for pace"),
                icon: "speedometer",
                referenceValue: formatPace(cmpPace),
                comparedValue: formatPace(refPace),
                deltaText: formatPaceDelta(diff),
                direction: direction
            ))
        }

        // Distance (higher is better → positive diff = I ran further)
        if let refDist = reference.distance, let cmpDist = compared.distance {
            let diff = refDist - cmpDist
            let direction: DeltaDirection = diff > 10 ? .improved : (diff < -10 ? .regressed : .neutral)
            deltas.append(MetricDelta(
                label: String(localized: "Distance", comment: "Comparison metric label for distance"),
                icon: "ruler",
                referenceValue: formatDistance(cmpDist),
                comparedValue: formatDistance(refDist),
                deltaText: formatDistanceDelta(diff),
                direction: direction
            ))
        }

        // Duration (lower is better → negative diff = I was faster)
        let refDur = reference.duration
        let cmpDur = compared.duration
        if refDur > 0 && cmpDur > 0 {
            let diff = refDur - cmpDur
            let direction: DeltaDirection = diff < -1 ? .improved : (diff > 1 ? .regressed : .neutral)
            deltas.append(MetricDelta(
                label: String(localized: "Duration", comment: "Comparison metric label for duration"),
                icon: "clock",
                referenceValue: formatDuration(cmpDur),
                comparedValue: formatDuration(refDur),
                deltaText: formatDurationDelta(diff),
                direction: direction
            ))
        }

        // Average Heart Rate (neutral, just show delta)
        if let refHR = reference.averageHeartRate, let cmpHR = compared.averageHeartRate {
            let diff = refHR - cmpHR
            deltas.append(MetricDelta(
                label: String(localized: "Avg HR", comment: "Comparison metric label for average heart rate"),
                icon: "heart.fill",
                referenceValue: Formatters.heartRate(cmpHR),
                comparedValue: Formatters.heartRate(refHR),
                deltaText: signed(diff) { Formatters.heartRate($0) },
                direction: .neutral
            ))
        }

        // Calories (higher is better)
        if let refCal = reference.totalEnergyBurned, let cmpCal = compared.totalEnergyBurned {
            let diff = refCal - cmpCal
            let direction: DeltaDirection = diff > 1 ? .improved : (diff < -1 ? .regressed : .neutral)
            deltas.append(MetricDelta(
                label: String(localized: "Calories", comment: "Comparison metric label for calories"),
                icon: "flame.fill",
                referenceValue: Formatters.calories(cmpCal),
                comparedValue: Formatters.calories(refCal),
                deltaText: signed(diff) { Formatters.calories($0) },
                direction: direction
            ))
        }

        // Elevation gain (neutral)
        if let refElev = reference.elevationGain, let cmpElev = compared.elevationGain {
            let diff = refElev - cmpElev
            deltas.append(MetricDelta(
                label: String(localized: "Elevation", comment: "Comparison metric label for elevation gain"),
                icon: "mountain.2.fill",
                referenceValue: Formatters.elevation(meters: cmpElev),
                comparedValue: Formatters.elevation(meters: refElev),
                deltaText: signed(diff) { Formatters.elevation(meters: $0) },
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

    /// Signs a delta and formats its magnitude through a unit-suffixed formatter
    /// (e.g. `+5 bpm`, `-12 kcal`). Keeps the unit/separator locale-aware.
    private static func signed(_ value: Double, formatter: (Double) -> String) -> String {
        let prefix = value >= 0 ? "+" : "-"
        return "\(prefix)\(formatter(abs(value)))"
    }

    static func formatPace(_ pace: Double) -> String {
        Formatters.paceFromMinutesPerKm(pace)
    }

    private static func formatPaceDelta(_ diff: Double) -> String {
        let sign = diff >= 0 ? "+" : "-"
        return "\(sign)\(Formatters.paceClock(abs(diff) * 60))"
    }

    private static func formatDistance(_ meters: Double) -> String {
        Formatters.distance(km: meters / 1000.0, fractionDigits: 2)
    }

    private static func formatDistanceDelta(_ meters: Double) -> String {
        signed(meters / 1000.0) { Formatters.distance(km: $0, fractionDigits: 2) }
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
