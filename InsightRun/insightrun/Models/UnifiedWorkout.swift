//
//  UnifiedWorkout.swift
//  InsightRun
//
//  Unified workout model that merges data from HealthKit and Strava
//  Strategy: Combine both sources, detect duplicates, merge data for best quality
//

import Foundation
import HealthKit

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        default: return "Workout"
        }
    }
}

/// Source of the workout data
enum WorkoutSource: String, Codable {
    case healthKit = "HealthKit"
    case strava = "Strava"
    case merged = "Merged" // When data comes from both sources
}

/// Unified workout that can contain data from HealthKit, Strava, or both
struct UnifiedWorkout: Identifiable {
    let id: String // Unique ID (either HealthKit UUID or Strava ID)

    // Source information
    var source: WorkoutSource
    var healthKitWorkout: WorkoutModel?
    var stravaActivity: StravaActivity?

    // Merged data (best from both sources)
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distance: Double? // meters
    let totalEnergyBurned: Double? // kcal

    // Performance metrics (prefer Strava if available, fallback to HealthKit)
    let averageSpeed: Double? // m/s
    let averagePace: Double? // min/km
    let averageHeartRate: Double? // bpm
    let maxHeartRate: Double? // bpm

    // Elevation (Strava usually more accurate)
    let totalElevationGain: Double? // meters

    // Route data (prefer Strava polyline if available)
    let hasRoute: Bool
    let routePolyline: String? // Strava polyline

    // Metadata
    let name: String
    let notes: String?

    // MARK: - Computed Properties

    var distanceKm: Double {
        (distance ?? 0) / 1000.0
    }

    var durationFormatted: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else {
            return String(format: "%dm %02ds", minutes, seconds)
        }
    }

    var paceFormatted: String {
        guard let pace = averagePace else { return "N/A" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    var speedKmh: Double? {
        guard let speed = averageSpeed else { return nil }
        return speed * 3.6 // m/s to km/h
    }

    var caloriesFormatted: String {
        guard let calories = totalEnergyBurned else { return "N/A" }
        return String(format: "%.0f kcal", calories)
    }

    var elevationFormatted: String {
        guard let elevation = totalElevationGain else { return "N/A" }
        return String(format: "%.0f m", elevation)
    }

    // MARK: - Merge Quality Indicators

    /// Returns true if this workout has data from both sources
    var isMerged: Bool {
        return source == .merged
    }

    /// Returns true if this workout has route data
    var hasEnhancedRouteData: Bool {
        return routePolyline != nil || hasRoute
    }

    /// Quality score (0-100) based on data completeness
    var dataQualityScore: Int {
        var score = 0

        // Basic data (20 points)
        if distance != nil { score += 10 }
        if duration > 0 { score += 10 }

        // Performance metrics (40 points)
        if averageSpeed != nil { score += 10 }
        if averageHeartRate != nil { score += 10 }
        if maxHeartRate != nil { score += 10 }
        if totalElevationGain != nil { score += 10 }

        // Enhanced data (40 points)
        if hasRoute { score += 20 }
        if isMerged { score += 10 }
        if routePolyline != nil { score += 10 }

        return score
    }

    // MARK: - Initializers

    /// Create from HealthKit only
    init(from healthKitWorkout: WorkoutModel) {
        self.id = healthKitWorkout.id.uuidString
        self.source = .healthKit
        self.healthKitWorkout = healthKitWorkout
        self.stravaActivity = nil

        // Copy HealthKit data
        self.startDate = healthKitWorkout.startDate
        self.endDate = healthKitWorkout.endDate
        self.duration = healthKitWorkout.duration
        self.distance = healthKitWorkout.distance
        self.totalEnergyBurned = healthKitWorkout.totalEnergyBurned
        self.averageSpeed = healthKitWorkout.averageSpeed
        self.averagePace = healthKitWorkout.averagePace
        self.averageHeartRate = healthKitWorkout.averageHeartRate
        self.maxHeartRate = healthKitWorkout.maxHeartRate
        self.totalElevationGain = healthKitWorkout.elevationGain
        self.hasRoute = healthKitWorkout.hasRoute
        self.routePolyline = nil // HealthKit doesn't provide polylines
        self.name = healthKitWorkout.workoutType.name
        self.notes = healthKitWorkout.metadata?["notes"] as? String
    }

    /// Create from Strava only
    init(from stravaActivity: StravaActivity) {
        self.id = "strava-\(stravaActivity.id)"
        self.source = .strava
        self.healthKitWorkout = nil
        self.stravaActivity = stravaActivity

        // Copy Strava data
        self.startDate = stravaActivity.startDateParsed ?? Date()
        self.endDate = self.startDate.addingTimeInterval(TimeInterval(stravaActivity.movingTime))
        self.duration = TimeInterval(stravaActivity.movingTime)
        self.distance = stravaActivity.distance
        self.totalEnergyBurned = stravaActivity.calories
        self.averageSpeed = stravaActivity.averageSpeed
        self.averagePace = stravaActivity.averagePace
        self.averageHeartRate = stravaActivity.averageHeartrate
        self.maxHeartRate = stravaActivity.maxHeartrate
        self.totalElevationGain = stravaActivity.totalElevationGain
        self.hasRoute = true // Strava always has route data
        self.routePolyline = nil // Would need detailed activity fetch
        self.name = stravaActivity.name
        self.notes = nil
    }

    /// Create merged workout from both sources
    /// Takes the best data from each source
    init(merging healthKitWorkout: WorkoutModel, with stravaActivity: StravaActivity) {
        // Use HealthKit ID as primary (it's the source of truth on iOS)
        self.id = healthKitWorkout.id.uuidString
        self.source = .merged
        self.healthKitWorkout = healthKitWorkout
        self.stravaActivity = stravaActivity

        // Dates: Use HealthKit (more accurate on iOS)
        self.startDate = healthKitWorkout.startDate
        self.endDate = healthKitWorkout.endDate

        // Duration: Use HealthKit (includes pauses)
        self.duration = healthKitWorkout.duration

        // Distance: Prefer Strava (GPS-based, usually more accurate)
        self.distance = stravaActivity.distance > 0 ? stravaActivity.distance : healthKitWorkout.distance

        // Calories: Prefer HealthKit (includes device sensors)
        self.totalEnergyBurned = healthKitWorkout.totalEnergyBurned ?? stravaActivity.calories

        // Speed: Prefer Strava (GPS-based)
        self.averageSpeed = stravaActivity.averageSpeed ?? healthKitWorkout.averageSpeed

        // Pace: Recalculate from best speed
        if let speed = self.averageSpeed, speed > 0 {
            self.averagePace = (1000.0 / speed) / 60.0 // min/km
        } else {
            self.averagePace = healthKitWorkout.averagePace
        }

        // Heart Rate: Prefer HealthKit (direct from Apple Watch)
        self.averageHeartRate = healthKitWorkout.averageHeartRate ?? stravaActivity.averageHeartrate
        self.maxHeartRate = healthKitWorkout.maxHeartRate ?? stravaActivity.maxHeartrate

        // Elevation: Prefer Strava (GPS altitude)
        self.totalElevationGain = stravaActivity.totalElevationGain > 0
            ? stravaActivity.totalElevationGain
            : healthKitWorkout.elevationGain

        // Route: Combine info
        self.hasRoute = healthKitWorkout.hasRoute || true // Strava always has route
        self.routePolyline = nil // Would need Strava detailed activity

        // Name: Prefer Strava (user-defined)
        self.name = stravaActivity.name.isEmpty ? healthKitWorkout.workoutType.name : stravaActivity.name

        // Notes: Combine
        self.notes = healthKitWorkout.metadata?["notes"] as? String
    }
}

// MARK: - Duplicate Detection

extension UnifiedWorkout {
    /// Check if this workout is likely a duplicate of another
    /// Uses time, distance, and duration as matching criteria
    func isDuplicateOf(_ other: UnifiedWorkout, tolerance: DuplicateTolerance = .default) -> Bool {
        // 1. Time check: Start dates within tolerance
        let timeDiff = abs(startDate.timeIntervalSince(other.startDate))
        guard timeDiff < tolerance.timeWindow else { return false }

        // 2. Duration check: Within percentage tolerance
        let durationDiff = abs(duration - other.duration) / max(duration, other.duration)
        guard durationDiff < tolerance.durationPercentage else { return false }

        // 3. Distance check: Within percentage tolerance (if both have distance)
        if let dist1 = distance, let dist2 = other.distance {
            guard dist1 > 0 && dist2 > 0 else { return false }
            let distanceDiff = abs(dist1 - dist2) / max(dist1, dist2)
            guard distanceDiff < tolerance.distancePercentage else { return false }
        }

        // All checks passed - likely duplicate
        return true
    }
}

/// Tolerance for duplicate detection
struct DuplicateTolerance {
    let timeWindow: TimeInterval // seconds
    let durationPercentage: Double // 0.0 - 1.0
    let distancePercentage: Double // 0.0 - 1.0

    static let `default` = DuplicateTolerance(
        timeWindow: 5 * 60, // 5 minutes
        durationPercentage: 0.05, // 5%
        distancePercentage: 0.05 // 5%
    )

    static let strict = DuplicateTolerance(
        timeWindow: 2 * 60, // 2 minutes
        durationPercentage: 0.02, // 2%
        distancePercentage: 0.02 // 2%
    )

    static let loose = DuplicateTolerance(
        timeWindow: 10 * 60, // 10 minutes
        durationPercentage: 0.10, // 10%
        distancePercentage: 0.10 // 10%
    )
}
