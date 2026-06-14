//
//  WorkoutModel.swift
//  InsightRun
//
//  Model representing a running workout from HealthKit
//

import Foundation
import HealthKit

struct WorkoutModel: Identifiable, Codable, Hashable {
    let id: UUID
    let workoutType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distance: Double? // meters
    let totalEnergyBurned: Double? // kcal
    let sourceName: String
    let sourceVersion: String?
    let metadata: [String: Any]?

    // Additional metrics
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let elevationGain: Double?
    let hasRoute: Bool
    let isIndoor: Bool

    /// Apple Workout Effort score on the 1–10 RPE scale.
    /// Source: `HKQuantityTypeIdentifier.workoutEffortScore` (user-rated) or
    /// `estimatedWorkoutEffortScore` (Apple-estimated) — populated lazily after
    /// the workout is fetched (HK relationship query). `nil` means unrated.
    var effortScore: Double? = nil
    var effortIsEstimated: Bool = false

    static func == (lhs: WorkoutModel, rhs: WorkoutModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Custom coding to handle HKWorkoutActivityType and metadata
    enum CodingKeys: String, CodingKey {
        case id, workoutType, startDate, endDate, duration
        case distance, totalEnergyBurned, sourceName, sourceVersion
        case averageHeartRate, maxHeartRate, elevationGain, hasRoute, isIndoor
        case metadataJSON, metadataData, effortScore, effortIsEstimated
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workoutType.rawValue, forKey: .workoutType)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(duration, forKey: .duration)
        try container.encode(distance, forKey: .distance)
        try container.encode(totalEnergyBurned, forKey: .totalEnergyBurned)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(sourceVersion, forKey: .sourceVersion)
        try container.encode(averageHeartRate, forKey: .averageHeartRate)
        try container.encode(maxHeartRate, forKey: .maxHeartRate)
        try container.encode(elevationGain, forKey: .elevationGain)
        try container.encode(hasRoute, forKey: .hasRoute)
        try container.encode(isIndoor, forKey: .isIndoor)
        try container.encodeIfPresent(effortScore, forKey: .effortScore)
        try container.encode(effortIsEstimated, forKey: .effortIsEstimated)

        // Encode metadata as JSON data so non-String values (Double, Int, arrays
        // such as suunto_splits) survive the round-trip. HKQuantity and other
        // non-JSON values are dropped by isValidJSONObject filtering.
        if let metadata = metadata {
            let jsonSafe = metadata.filter { JSONSerialization.isValidJSONObject([$0.value]) }
            if !jsonSafe.isEmpty,
               let data = try? JSONSerialization.data(withJSONObject: jsonSafe) {
                try container.encode(data, forKey: .metadataData)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let rawValue = try container.decode(UInt.self, forKey: .workoutType)
        workoutType = HKWorkoutActivityType(rawValue: rawValue) ?? .running
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        distance = try container.decodeIfPresent(Double.self, forKey: .distance)
        totalEnergyBurned = try container.decodeIfPresent(Double.self, forKey: .totalEnergyBurned)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        sourceVersion = try container.decodeIfPresent(String.self, forKey: .sourceVersion)
        averageHeartRate = try container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        maxHeartRate = try container.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        elevationGain = try container.decodeIfPresent(Double.self, forKey: .elevationGain)
        hasRoute = try container.decode(Bool.self, forKey: .hasRoute)
        isIndoor = try container.decodeIfPresent(Bool.self, forKey: .isIndoor) ?? false
        effortScore = try container.decodeIfPresent(Double.self, forKey: .effortScore)
        effortIsEstimated = try container.decodeIfPresent(Bool.self, forKey: .effortIsEstimated) ?? false

        // Decode metadata, preferring the JSON-data representation that preserves
        // non-String values. Fall back to the legacy string-only payload.
        if let data = try container.decodeIfPresent(Data.self, forKey: .metadataData),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadata = object
        } else if let metadataStrings = try container.decodeIfPresent([String: String].self, forKey: .metadataJSON) {
            metadata = metadataStrings
        } else {
            metadata = nil
        }
    }

    // Memberwise initializer (explicit since Codable overrides it)
    init(
        id: UUID,
        workoutType: HKWorkoutActivityType,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        distance: Double?,
        totalEnergyBurned: Double?,
        sourceName: String,
        sourceVersion: String?,
        metadata: [String: Any]?,
        averageHeartRate: Double?,
        maxHeartRate: Double?,
        elevationGain: Double?,
        hasRoute: Bool,
        isIndoor: Bool = false
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.distance = distance
        self.totalEnergyBurned = totalEnergyBurned
        self.sourceName = sourceName
        self.sourceVersion = sourceVersion
        self.metadata = metadata
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.elevationGain = elevationGain
        self.hasRoute = hasRoute
        self.isIndoor = isIndoor
    }

    // Computed properties for display
    var durationFormatted: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else {
            return String(format: "%dm %02ds", minutes, seconds)
        }
    }

    var distanceFormatted: String {
        guard let distance = distance else { return String(localized: "common.value.notAvailable") }
        return Formatters.distance(km: distance / 1000.0)
    }

    var caloriesFormatted: String {
        guard let calories = totalEnergyBurned else { return String(localized: "common.value.notAvailable") }
        return Formatters.calories(calories)
    }

    nonisolated var averagePace: Double? {
        guard let distance = distance, distance > 0, duration > 0 else { return nil }
        // Pace in minutes per kilometer
        let minutes = duration / 60.0
        let kilometers = distance / 1000.0
        return minutes / kilometers
    }

    nonisolated var averageSpeed: Double? {
        guard let distance = distance, duration > 0 else { return nil }
        // Speed in km/h
        let kilometers = distance / 1000.0
        let hours = duration / 3600.0
        return kilometers / hours
    }
}

extension WorkoutModel {
    // Create from HKWorkout
    init(from workout: HKWorkout) {
        self.id = workout.uuid
        self.workoutType = workout.workoutActivityType
        self.startDate = workout.startDate
        self.endDate = workout.endDate
        self.duration = workout.duration
        self.distance = workout.totalDistance?.doubleValue(for: .meter())
        self.totalEnergyBurned = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        self.sourceName = workout.sourceRevision.source.name
        self.sourceVersion = workout.sourceRevision.version
        self.metadata = workout.metadata

        // Heart rate metrics
        self.averageHeartRate = workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        self.maxHeartRate = workout.statistics(for: HKQuantityType(.heartRate))?.maximumQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))

        // Elevation gain — read from workout metadata. The HK statistic for
        // `distanceWalkingRunning` returns total distance in meters, which is
        // not what we want.
        if let quantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
            self.elevationGain = quantity.doubleValue(for: .meter())
        } else if let meters = workout.metadata?["HKElevationAscended"] as? Double {
            self.elevationGain = meters
        } else {
            self.elevationGain = nil
        }

        // Route availability - Note: Routes must be queried separately from HealthStore
        // For now, assume no route data available directly from HKWorkout
        self.hasRoute = false

        // Check if workout is indoor (treadmill)
        self.isIndoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
    }
}

extension Array where Element == WorkoutModel {
    /// Canonical average pace (min/km): sum(durations) / sum(distances).
    /// Never an arithmetic mean of per-workout paces.
    nonisolated var averagePace: Double? {
        var totalDurationSeconds = 0.0
        var totalDistanceMeters = 0.0
        for workout in self {
            guard let distance = workout.distance, distance > 0, workout.duration > 0 else { continue }
            totalDurationSeconds += workout.duration
            totalDistanceMeters += distance
        }
        guard totalDistanceMeters > 0, totalDurationSeconds > 0 else { return nil }
        let minutes = totalDurationSeconds / 60.0
        let kilometers = totalDistanceMeters / 1000.0
        return minutes / kilometers
    }
}
