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
    case suunto = "Suunto"
    case merged = "Merged" // When data comes from both sources
}

/// Unified workout that can contain data from HealthKit, Strava, or both
struct UnifiedWorkout: Identifiable {
    let id: String // Unique ID (either HealthKit UUID or Strava ID)

    // Source information
    var source: WorkoutSource
    var healthKitWorkout: WorkoutModel?
    var stravaActivity: StravaActivity?
    var suuntoActivity: SuuntoActivity?

    // Merged data (best from both sources)
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distance: Double? // meters
    let totalEnergyBurned: Double? // kcal

    // Performance metrics (prefer Strava if available, fallback to HealthKit)
    let averageSpeed: Double? // m/s
    let maxSpeed: Double? // m/s (from Strava)
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
        self.suuntoActivity = nil

        // Copy HealthKit data
        self.startDate = healthKitWorkout.startDate
        self.endDate = healthKitWorkout.endDate
        self.duration = healthKitWorkout.duration
        self.distance = healthKitWorkout.distance
        self.totalEnergyBurned = healthKitWorkout.totalEnergyBurned
        self.averageSpeed = healthKitWorkout.averageSpeed
        self.maxSpeed = nil // HealthKit doesn't provide max speed directly
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
        self.suuntoActivity = nil

        // Copy Strava data
        self.startDate = stravaActivity.startDateParsed ?? Date()
        self.endDate = self.startDate.addingTimeInterval(TimeInterval(stravaActivity.movingTime))
        self.duration = TimeInterval(stravaActivity.movingTime)
        self.distance = stravaActivity.distance
        self.totalEnergyBurned = stravaActivity.calories
        self.averageSpeed = stravaActivity.averageSpeed
        self.maxSpeed = stravaActivity.maxSpeed
        self.averagePace = stravaActivity.averagePace
        self.averageHeartRate = stravaActivity.averageHeartrate
        self.maxHeartRate = stravaActivity.maxHeartrate
        self.totalElevationGain = stravaActivity.totalElevationGain
        self.hasRoute = true // Strava always has route data
        self.routePolyline = nil // Would need detailed activity fetch
        self.name = stravaActivity.name
        self.notes = nil
    }

    /// Create from Suunto only
    init(from suuntoActivity: SuuntoActivity) {
        self.id = suuntoActivity.id
        self.source = .suunto
        self.healthKitWorkout = nil
        self.stravaActivity = nil
        self.suuntoActivity = suuntoActivity

        // Copy Suunto data
        self.startDate = suuntoActivity.startDate
        self.endDate = suuntoActivity.endDate
        self.duration = suuntoActivity.duration
        self.distance = suuntoActivity.distance
        self.totalEnergyBurned = suuntoActivity.calories
        self.averageSpeed = suuntoActivity.averageSpeed
        self.maxSpeed = suuntoActivity.maxSpeed
        self.averagePace = suuntoActivity.averagePace
        self.averageHeartRate = suuntoActivity.averageHeartRate
        self.maxHeartRate = suuntoActivity.maxHeartRate
        self.totalElevationGain = suuntoActivity.elevationGain
        self.hasRoute = suuntoActivity.hasRoute
        self.routePolyline = nil
        self.name = suuntoActivity.activityType
        self.notes = nil
    }

    /// Create merged workout from HealthKit and Suunto
    /// Suunto provides enhanced metrics that HealthKit may not have
    init(merging healthKitWorkout: WorkoutModel, with suuntoActivity: SuuntoActivity) {
        self.id = healthKitWorkout.id.uuidString
        self.source = .merged
        self.healthKitWorkout = healthKitWorkout
        self.stravaActivity = nil
        self.suuntoActivity = suuntoActivity

        // Dates: Use HealthKit (more accurate on iOS)
        self.startDate = healthKitWorkout.startDate
        self.endDate = healthKitWorkout.endDate
        self.duration = healthKitWorkout.duration

        // Distance: Prefer Suunto (GPS-based from watch)
        self.distance = suuntoActivity.distance > 0 ? suuntoActivity.distance : healthKitWorkout.distance

        // Calories: Prefer Suunto (includes device sensors)
        self.totalEnergyBurned = suuntoActivity.calories > 0 ? suuntoActivity.calories : healthKitWorkout.totalEnergyBurned

        // Speed: Prefer Suunto
        self.averageSpeed = suuntoActivity.averageSpeed ?? healthKitWorkout.averageSpeed
        self.maxSpeed = suuntoActivity.maxSpeed

        // Pace
        if let speed = self.averageSpeed, speed > 0 {
            self.averagePace = (1000.0 / speed) / 60.0
        } else {
            self.averagePace = healthKitWorkout.averagePace
        }

        // Heart Rate: Prefer Suunto (from Suunto watch)
        self.averageHeartRate = suuntoActivity.averageHeartRate ?? healthKitWorkout.averageHeartRate
        self.maxHeartRate = suuntoActivity.maxHeartRate ?? healthKitWorkout.maxHeartRate

        // Elevation: Prefer Suunto
        self.totalElevationGain = suuntoActivity.elevationGain > 0 ? suuntoActivity.elevationGain : healthKitWorkout.elevationGain

        // Route
        self.hasRoute = healthKitWorkout.hasRoute || suuntoActivity.hasRoute
        self.routePolyline = nil

        // Name
        self.name = healthKitWorkout.workoutType.name
        self.notes = healthKitWorkout.metadata?["notes"] as? String
    }

    /// Create merged workout from both sources
    /// Takes the best data from each source
    init(merging healthKitWorkout: WorkoutModel, with stravaActivity: StravaActivity) {
        // Use HealthKit ID as primary (it's the source of truth on iOS)
        self.id = healthKitWorkout.id.uuidString
        self.source = .merged
        self.healthKitWorkout = healthKitWorkout
        self.stravaActivity = stravaActivity
        self.suuntoActivity = nil

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
        self.maxSpeed = stravaActivity.maxSpeed // Only available from Strava

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

// MARK: - WorkoutModel Compatibility

extension UnifiedWorkout {
    /// Convert to WorkoutModel for compatibility with existing views
    func toWorkoutModel() -> WorkoutModel {
        // Use HealthKit workout if available, otherwise create from Strava data
        if let hkWorkout = healthKitWorkout {
            // If we have Suunto data, enrich the WorkoutModel with it
            if let suunto = suuntoActivity {
                var metadata = hkWorkout.metadata ?? [:]
                metadata["suunto_device"] = suunto.deviceName
                metadata["suunto_avg_hr"] = suunto.averageHeartRate
                metadata["suunto_max_hr"] = suunto.maxHeartRate
                metadata["suunto_cadence"] = suunto.averageCadence
                metadata["suunto_power"] = suunto.averagePower
                metadata["suunto_ground_contact_time"] = suunto.averageGroundContactTime
                metadata["suunto_vertical_oscillation"] = suunto.averageVerticalOscillation
                metadata["suunto_stride_length"] = suunto.averageStrideLength
                metadata["suunto_vo2max"] = suunto.vo2Max
                metadata["suunto_training_effect"] = suunto.trainingEffect

                // Store Suunto splits as JSON in metadata
                if !suunto.splits.isEmpty {
                    let splitsData = suunto.splits.map { split -> [String: Any] in
                        var dict: [String: Any] = [
                            "km": split.kilometer,
                            "time": split.time,
                            "pace": split.pace
                        ]
                        if let hr = split.averageHeartRate { dict["hr"] = hr }
                        if let power = split.averagePower { dict["power"] = power }
                        if let cadence = split.averageCadence { dict["cadence"] = cadence }
                        if let elev = split.elevationGain { dict["elev"] = elev }
                        return dict
                    }
                    metadata["suunto_splits"] = splitsData
                    print("📊 DEBUG: Storing \(suunto.splits.count) Suunto splits in metadata")
                }

                return WorkoutModel(
                    id: hkWorkout.id,
                    workoutType: hkWorkout.workoutType,
                    startDate: hkWorkout.startDate,
                    endDate: hkWorkout.endDate,
                    duration: hkWorkout.duration,
                    distance: suunto.distance > 0 ? suunto.distance : hkWorkout.distance,
                    totalEnergyBurned: suunto.calories > 0 ? suunto.calories : hkWorkout.totalEnergyBurned,
                    sourceName: hkWorkout.sourceName,
                    sourceVersion: hkWorkout.sourceVersion,
                    metadata: metadata,
                    averageHeartRate: suunto.averageHeartRate ?? hkWorkout.averageHeartRate,
                    maxHeartRate: suunto.maxHeartRate ?? hkWorkout.maxHeartRate,
                    elevationGain: suunto.elevationGain > 0 ? suunto.elevationGain : hkWorkout.elevationGain,
                    hasRoute: hkWorkout.hasRoute || suunto.hasRoute,
                    isIndoor: hkWorkout.isIndoor
                )
            }
            return hkWorkout
        } else if let stravaActivity = stravaActivity {
            // Create a stable UUID from Strava ID using namespace UUID
            let stableUUID = UUID(uuidString: id) ?? Self.stableUUID(from: stravaActivity.id)

            // Create a WorkoutModel from Strava activity with all available metrics
            var metadata: [String: Any] = [
                "strava_id": String(stravaActivity.id),
                "strava_name": stravaActivity.name
            ]
            if let maxSpeed = maxSpeed {
                metadata["max_speed"] = maxSpeed
            }
            if let avgSpeed = averageSpeed {
                metadata["average_speed"] = avgSpeed
            }

            return WorkoutModel(
                id: stableUUID,
                workoutType: .running,
                startDate: startDate,
                endDate: endDate,
                duration: duration,
                distance: distance,
                totalEnergyBurned: totalEnergyBurned,
                sourceName: "Strava",
                sourceVersion: "API",
                metadata: metadata,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                elevationGain: totalElevationGain,
                hasRoute: hasRoute,
                isIndoor: stravaActivity.trainer ?? false
            )
        } else {
            // Fallback: generic workout
            return WorkoutModel(
                id: UUID(uuidString: id) ?? UUID(),
                workoutType: .running,
                startDate: startDate,
                endDate: endDate,
                duration: duration,
                distance: distance,
                totalEnergyBurned: totalEnergyBurned,
                sourceName: source.rawValue,
                sourceVersion: "Unknown",
                metadata: nil,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                elevationGain: totalElevationGain,
                hasRoute: hasRoute
            )
        }
    }

    /// Source name for display (compatible with WorkoutRowView badge logic)
    var sourceName: String {
        switch source {
        case .healthKit:
            return healthKitWorkout?.sourceName ?? "Apple Watch"
        case .strava:
            return "Strava"
        case .suunto:
            return "Import"
        case .merged:
            // For merged workouts, indicate sources
            if stravaActivity != nil {
                return "Strava + \(healthKitWorkout?.sourceName ?? "HealthKit")"
            } else if suuntoActivity != nil {
                return "Suunto + \(healthKitWorkout?.sourceName ?? "HealthKit")"
            }
            return healthKitWorkout?.sourceName ?? "Merged"
        }
    }

    /// Generate a stable UUID from Strava activity ID
    /// Uses namespace UUID (v5) to ensure same Strava ID always produces same UUID
    private static func stableUUID(from stravaId: Int64) -> UUID {
        // Namespace UUID for Strava activities (random but fixed)
        let namespace = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!

        // Create deterministic UUID from Strava ID
        let idString = "strava-\(stravaId)"
        let data = idString.data(using: .utf8)!

        // Simple hash-based UUID generation
        let hasher = data.withUnsafeBytes { buffer -> Int in
            var hash = 0
            for byte in buffer {
                hash = (hash &* 31) &+ Int(byte)
            }
            return hash
        }

        // Create UUID from hash (deterministic)
        let uuidString = String(format: "%08X-%04X-%04X-%04X-%012X",
                               hasher & 0xFFFFFFFF,
                               (hasher >> 32) & 0xFFFF,
                               0x5000 | ((hasher >> 48) & 0x0FFF), // Version 5 (name-based SHA-1)
                               0x8000 | ((hasher >> 60) & 0x3FFF), // Variant (RFC 4122)
                               Int64(stravaId))

        return UUID(uuidString: uuidString) ?? namespace
    }
}
