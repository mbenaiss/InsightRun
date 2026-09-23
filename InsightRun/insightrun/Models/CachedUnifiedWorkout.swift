//
//  CachedUnifiedWorkout.swift
//  InsightRun
//
//  SwiftData cache for unified workouts (HealthKit + Strava merged)
//  Strategy: Keep all workouts cached, clear only when user disconnects Strava
//

import Foundation
import SwiftData
import HealthKit

@Model
class CachedUnifiedWorkout {
    @Attribute(.unique) var id: String
    var source: String  // WorkoutSource.rawValue: "HealthKit", "Strava", "Suunto", "Merged"
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval
    var distance: Double?
    var totalEnergyBurned: Double?
    var averageSpeed: Double?
    var averagePace: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var totalElevationGain: Double?
    var hasRoute: Bool
    var routePolyline: String?
    var name: String
    var notes: String?
    var cachedAt: Date

    // Original IDs for tracking
    var healthKitWorkoutId: String?
    var stravaActivityId: Int64?
    var stravaActivityType: String?

    // Original source name for display (e.g., "Apple Watch", "Suunto Run")
    var originalSourceName: String?
    var originalWorkoutData: Data?
    var stravaTrainer: Bool?

    init(from unified: UnifiedWorkout) {
        self.id = unified.id
        self.source = unified.source.rawValue
        self.startDate = unified.startDate
        self.endDate = unified.endDate
        self.duration = unified.duration
        self.distance = unified.distance
        self.totalEnergyBurned = unified.totalEnergyBurned
        self.averageSpeed = unified.averageSpeed
        self.averagePace = unified.averagePace
        self.averageHeartRate = unified.averageHeartRate
        self.maxHeartRate = unified.maxHeartRate
        self.totalElevationGain = unified.totalElevationGain
        self.hasRoute = unified.hasRoute
        self.routePolyline = unified.routePolyline
        self.name = unified.name
        self.notes = unified.notes
        self.cachedAt = Date()

        // Store original IDs for tracking
        self.healthKitWorkoutId = unified.healthKitWorkout?.id.uuidString
        self.stravaActivityId = unified.stravaActivity?.id
        self.stravaActivityType = unified.stravaActivity?.type

        // Store original source name for display (e.g., "Apple Watch", "Suunto Run")
        self.originalSourceName = unified.healthKitWorkout?.sourceName ?? unified.sourceName
        self.originalWorkoutData = unified.healthKitWorkout.flatMap { _ in try? JSONEncoder().encode(unified.toWorkoutModel()) }
        self.stravaTrainer = unified.stravaActivity?.trainer
    }

    func toUnifiedWorkout() -> UnifiedWorkout {
        if let originalWorkoutData,
           let workout = try? JSONDecoder().decode(WorkoutModel.self, from: originalWorkoutData) {
            var restored = UnifiedWorkout(from: workout)
            restored.source = WorkoutSource(rawValue: source) ?? .healthKit
            if stravaActivityId != nil { restored.stravaActivity = cachedStravaActivity() }
            return restored
        }

        // Compare via the enum so the canonical rawValue casing
        // ("HealthKit"/"Strava"/"Merged") is honored.
        switch WorkoutSource(rawValue: source) {
        case .strava:
            // Create minimal StravaActivity for Strava-only workouts
            let stravaActivity = cachedStravaActivity()
            return UnifiedWorkout(from: stravaActivity)

        case .healthKit, .merged, .suunto:
            // Create minimal WorkoutModel for HealthKit, merged or Suunto workouts.
            // Use originalSourceName to preserve the device name (e.g., "Apple Watch")
            let workoutId = UnifiedWorkout.stableWorkoutID(source: source, sourceID: healthKitWorkoutId ?? id)
            let displaySourceName = (originalSourceName ?? "Apple Watch").replacingOccurrences(of: "Strava + ", with: "")
            var metadata: [String: Any]? = nil

            if !name.isEmpty {
                metadata = [
                    "display_name": name,
                    "name": name
                ]
                if source == WorkoutSource.merged.rawValue || stravaActivityId != nil {
                    metadata?["strava_name"] = name
                    if let stravaActivityId {
                        metadata?["strava_id"] = String(stravaActivityId)
                    }
                }
            }

            if source == WorkoutSource.suunto.rawValue {
                metadata = metadata ?? [:]
                metadata?["suunto_id"] = id
            }

            let fallbackWorkout = WorkoutModel(
                id: workoutId,
                workoutType: .running,
                startDate: startDate,
                endDate: endDate,
                duration: duration,
                distance: distance,
                totalEnergyBurned: totalEnergyBurned,
                sourceName: displaySourceName,
                sourceVersion: "Cached",
                metadata: metadata,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                elevationGain: totalElevationGain,
                hasRoute: hasRoute
            )
            return UnifiedWorkout(from: fallbackWorkout)

        case nil:
            // Unknown source, use originalSourceName if available
            let workoutId = UnifiedWorkout.stableWorkoutID(source: source, sourceID: healthKitWorkoutId ?? id)
            let displaySourceName = (originalSourceName ?? "Apple Watch").replacingOccurrences(of: "Strava + ", with: "")
            let fallbackWorkout = WorkoutModel(
                id: workoutId,
                workoutType: .running,
                startDate: startDate,
                endDate: endDate,
                duration: duration,
                distance: distance,
                totalEnergyBurned: totalEnergyBurned,
                sourceName: displaySourceName,
                sourceVersion: "Cached",
                metadata: nil,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                elevationGain: totalElevationGain,
                hasRoute: hasRoute
            )
            return UnifiedWorkout(from: fallbackWorkout)
        }
    }
    private func cachedStravaActivity() -> StravaActivity {
        let stravaId = stravaActivityId ?? Int64(id.hashValue)
        return StravaActivity(
            id: stravaId,
            name: name,
            distance: distance ?? 0,
            movingTime: Int(duration),
            elapsedTime: Int(duration),
            totalElevationGain: totalElevationGain ?? 0,
            type: stravaActivityType ?? "Workout",
            startDate: ISO8601DateFormatter().string(from: startDate),
            startDateLocal: ISO8601DateFormatter().string(from: startDate),
            averageSpeed: averageSpeed,
            maxSpeed: nil,
            averageHeartrate: averageHeartRate,
            maxHeartrate: maxHeartRate,
            calories: totalEnergyBurned,
            trainer: stravaTrainer
        )
    }

}
