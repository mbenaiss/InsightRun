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
    var source: String  // "healthKit", "strava", "merged"
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

    // Original source name for display (e.g., "Apple Watch", "Suunto Run")
    var originalSourceName: String?

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

        // Store original source name for display (e.g., "Apple Watch", "Suunto Run")
        self.originalSourceName = unified.sourceName
    }

    // Convert back to UnifiedWorkout from cached fields
    // Note: This creates a fallback UnifiedWorkout from cached data only
    // The original WorkoutModel/StravaActivity objects are NOT preserved
    func toUnifiedWorkout() -> UnifiedWorkout {
        // Reconstruct based on original source type
        switch source {
        case "strava":
            // Create minimal StravaActivity for Strava-only workouts
            let stravaId = stravaActivityId ?? Int64(id.hashValue)
            let stravaActivity = StravaActivity(
                id: stravaId,
                name: name,
                distance: distance ?? 0,
                movingTime: Int(duration),
                elapsedTime: Int(duration),
                totalElevationGain: totalElevationGain ?? 0,
                type: "Run",
                startDate: ISO8601DateFormatter().string(from: startDate),
                startDateLocal: ISO8601DateFormatter().string(from: startDate),
                averageSpeed: averageSpeed,
                maxSpeed: nil,
                averageHeartrate: averageHeartRate,
                maxHeartrate: maxHeartRate,
                calories: totalEnergyBurned,
                trainer: nil
            )
            return UnifiedWorkout(from: stravaActivity)

        case "healthKit", "merged":
            // Create minimal WorkoutModel for HealthKit or merged workouts
            // Use originalSourceName to preserve the device name (e.g., "Apple Watch")
            let workoutId = UUID(uuidString: healthKitWorkoutId ?? id) ?? UUID()
            let displaySourceName = originalSourceName ?? "Apple Watch"
            var metadata: [String: Any]? = nil

            if !name.isEmpty {
                metadata = [
                    "display_name": name,
                    "name": name
                ]
                if source == "merged" || stravaActivityId != nil {
                    metadata?["strava_name"] = name
                    if let stravaActivityId {
                        metadata?["strava_id"] = String(stravaActivityId)
                    }
                }
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

        default:
            // Unknown source, use originalSourceName if available
            let workoutId = UUID(uuidString: healthKitWorkoutId ?? id) ?? UUID()
            let displaySourceName = originalSourceName ?? "Apple Watch"
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
}
