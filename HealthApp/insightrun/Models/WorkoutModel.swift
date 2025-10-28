//
//  WorkoutModel.swift
//  HealthApp
//
//  Model representing a running workout from HealthKit
//

import Foundation
import HealthKit

struct WorkoutModel: Identifiable {
    let id: UUID
    let workoutType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distance: Double? // meters
    let totalEnergyBurned: Double? // kcal
    let sourceName: String
    let sourceVersion: String?

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
    }
}
