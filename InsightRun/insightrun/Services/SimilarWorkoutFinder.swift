//
//  SimilarWorkoutFinder.swift
//  InsightRun
//
//  Service that finds similar workouts based on type and distance criteria
//

import Foundation
import HealthKit

struct SimilarWorkoutFinder {

    /// Find workouts similar to the reference workout.
    /// - Parameters:
    ///   - workout: The reference workout to compare against.
    ///   - allWorkouts: The full list of available workouts.
    ///   - limit: Maximum number of similar workouts to return (default: 5).
    /// - Returns: An array of similar workouts sorted by date (most recent first).
    static func findSimilar(
        to workout: WorkoutModel,
        from allWorkouts: [WorkoutModel],
        limit: Int = 5
    ) -> [WorkoutModel] {
        guard limit > 0,
              let referenceDistance = workout.distance,
              referenceDistance.isFinite, referenceDistance > 0 else { return [] }

        return allWorkouts
            .filter { candidate in
                guard candidate.id != workout.id,
                      candidate.workoutType == workout.workoutType,
                      candidate.isIndoor == workout.isIndoor,
                      candidate.endDate <= workout.startDate,
                      candidate.duration.isFinite, candidate.duration > 0,
                      let distance = candidate.distance, distance.isFinite else { return false }
                return distance >= referenceDistance * 0.7 && distance <= referenceDistance * 1.3
            }
            .sorted { $0.startDate > $1.startDate }
            .prefix(limit)
            .map { $0 }
    }
}
