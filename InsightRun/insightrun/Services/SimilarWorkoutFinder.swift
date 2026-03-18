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
        guard let referenceDistance = workout.distance, referenceDistance > 0 else {
            // If the reference workout has no distance, match only by type
            return allWorkouts
                .filter { $0.id != workout.id && $0.workoutType == workout.workoutType }
                .sorted { $0.startDate > $1.startDate }
                .prefix(limit)
                .map { $0 }
        }

        let lowerBound = referenceDistance * 0.7 // -30%
        let upperBound = referenceDistance * 1.3 // +30%

        return allWorkouts
            .filter { candidate in
                // Exclude the workout itself
                guard candidate.id != workout.id else { return false }
                // Same workout type
                guard candidate.workoutType == workout.workoutType else { return false }
                // Distance within +/- 30%
                guard let candidateDistance = candidate.distance else { return false }
                return candidateDistance >= lowerBound && candidateDistance <= upperBound
            }
            .sorted { $0.startDate > $1.startDate }
            .prefix(limit)
            .map { $0 }
    }
}
