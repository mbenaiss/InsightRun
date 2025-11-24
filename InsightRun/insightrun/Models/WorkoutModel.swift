//
//  WorkoutModel.swift
//  InsightRun
//
//  Model representing a running workout from HealthKit
//

import Foundation
import HealthKit

struct WorkoutModel: Identifiable, Codable {
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

    // Custom coding to handle HKWorkoutActivityType and metadata
    enum CodingKeys: String, CodingKey {
        case id, workoutType, startDate, endDate, duration
        case distance, totalEnergyBurned, sourceName, sourceVersion
        case averageHeartRate, maxHeartRate, elevationGain, hasRoute
        case metadataJSON
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

        // Encode metadata as JSON string (simplified, only stores string values)
        if let metadata = metadata {
            let metadataStrings = metadata.compactMapValues { $0 as? String }
            if !metadataStrings.isEmpty {
                try container.encode(metadataStrings, forKey: .metadataJSON)
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

        // Decode metadata from JSON string
        if let metadataStrings = try container.decodeIfPresent([String: String].self, forKey: .metadataJSON) {
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
        hasRoute: Bool
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
        guard let distance = distance else { return "N/A" }
        let km = distance / 1000.0
        return String(format: "%.2f km", km)
    }

    var caloriesFormatted: String {
        guard let calories = totalEnergyBurned else { return "N/A" }
        return String(format: "%.0f kcal", calories)
    }

    var averagePace: Double? {
        guard let distance = distance, distance > 0, duration > 0 else { return nil }
        // Pace in minutes per kilometer
        let minutes = duration / 60.0
        let kilometers = distance / 1000.0
        return minutes / kilometers
    }

    var averageSpeed: Double? {
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

        // Elevation
        self.elevationGain = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())

        // Route availability - Note: Routes must be queried separately from HealthStore
        // For now, assume no route data available directly from HKWorkout
        self.hasRoute = false
    }
}
