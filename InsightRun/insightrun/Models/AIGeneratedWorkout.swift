//
//  AIGeneratedWorkout.swift
//  InsightRun
//
//  Models for AI-generated workouts with WorkoutKit integration
//

import Foundation
import HealthKit

// MARK: - WorkoutGoal

struct WorkoutGoal: Codable, Equatable {
    let type: GoalType
    var value: Double

    enum GoalType: String, Codable {
        case distance // meters
        case duration // seconds
        case open // no specific goal
    }

    // Validation
    var isValid: Bool {
        switch type {
        case .distance:
            return value > 0 && value <= 100_000 // Max 100km
        case .duration:
            return value > 0 && value <= 14_400 // Max 4 hours
        case .open:
            return true
        }
    }

    // Display helpers
    var distanceFormatted: String? {
        guard type == .distance else { return nil }
        let km = value / 1000.0
        return String(format: "%.2f km", km)
    }

    var durationFormatted: String? {
        guard type == .duration else { return nil }
        let minutes = Int(value / 60)
        let seconds = Int(value.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - WorkoutStep

struct WorkoutStep: Codable, Identifiable, Equatable {
    let id: UUID
    let type: StepType
    var goal: WorkoutGoal
    var targetPace: String? // Format: "4:30" per km
    var targetHeartRateZone: Int? // 1-5
    var instructions: String?

    enum StepType: String, Codable {
        case warmup
        case work
        case recovery
        case cooldown
        case interval
    }

    init(id: UUID = UUID(), type: StepType, goal: WorkoutGoal, targetPace: String? = nil, targetHeartRateZone: Int? = nil, instructions: String? = nil) {
        self.id = id
        self.type = type
        self.goal = goal
        self.targetPace = targetPace
        self.targetHeartRateZone = targetHeartRateZone
        self.instructions = instructions
    }

    // Validation
    var isValid: Bool {
        guard goal.isValid else { return false }

        if let hrZone = targetHeartRateZone {
            guard (1...5).contains(hrZone) else { return false }
        }

        return true
    }

    // Display color for UI
    var displayColor: String {
        switch type {
        case .warmup:
            return "blue"
        case .work:
            return "red"
        case .recovery:
            return "green"
        case .cooldown:
            return "purple"
        case .interval:
            return "orange"
        }
    }

    // Display name
    var displayName: String {
        switch type {
        case .warmup:
            return String(localized: "Warm-up", comment: "Workout step type: warm-up")
        case .work:
            return String(localized: "Work", comment: "Workout step type: work interval")
        case .recovery:
            return String(localized: "Recovery", comment: "Workout step type: recovery")
        case .cooldown:
            return String(localized: "Cool-down", comment: "Workout step type: cool-down")
        case .interval:
            return String(localized: "Interval", comment: "Workout step type: interval")
        }
    }

    // Calculate distance for this step
    var calculatedDistance: Double {
        // If goal is already distance, return it
        if goal.type == .distance {
            return goal.value
        }

        // If goal is duration, calculate distance based on pace
        if goal.type == .duration, let paceStr = targetPace {
            // Parse pace string (e.g., "5:30" → 5.5 minutes per km)
            let paceComponents = paceStr.split(separator: ":")
            guard paceComponents.count == 2,
                  let minutes = Double(paceComponents[0]),
                  let seconds = Double(paceComponents[1]) else {
                return 0
            }

            let paceMinutesPerKm = minutes + (seconds / 60.0)
            let durationMinutes = goal.value / 60.0

            // Distance in km = duration / pace
            let distanceKm = durationMinutes / paceMinutesPerKm

            // Return in meters
            return distanceKm * 1000.0
        }

        return 0
    }

    // Formatted distance for display
    var distanceFormatted: String? {
        let distance = calculatedDistance
        guard distance > 0 else { return nil }

        let km = distance / 1000.0
        if km >= 1.0 {
            return String(format: "%.2f km", km)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
}

// MARK: - AIGeneratedWorkout

struct AIGeneratedWorkout: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String
    let sport: WorkoutSportType
    var steps: [WorkoutStep]
    var totalDistance: Double? // meters
    var estimatedDuration: TimeInterval?
    let createdDate: Date

    enum WorkoutSportType: String, Codable {
        case running
        case cycling
        case swimming

        var activityType: HKWorkoutActivityType {
            switch self {
            case .running:
                return .running
            case .cycling:
                return .cycling
            case .swimming:
                return .swimming
            }
        }

        var displayName: String {
            switch self {
            case .running:
                return String(localized: "Running", comment: "Sport type: running")
            case .cycling:
                return String(localized: "Cycling", comment: "Sport type: cycling")
            case .swimming:
                return String(localized: "Swimming", comment: "Sport type: swimming")
            }
        }
    }

    init(id: UUID = UUID(), name: String, description: String, sport: WorkoutSportType, steps: [WorkoutStep], totalDistance: Double? = nil, estimatedDuration: TimeInterval? = nil, createdDate: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.sport = sport
        self.steps = steps
        self.totalDistance = totalDistance
        self.estimatedDuration = estimatedDuration
        self.createdDate = createdDate
    }

    // Validation
    var isValid: Bool {
        guard !name.isEmpty else { return false }
        guard !steps.isEmpty else { return false }
        guard steps.count <= 50 else { return false } // Max 50 steps
        guard steps.allSatisfy({ $0.isValid }) else { return false }

        if let distance = totalDistance {
            // Allow 0.0 for duration-based workouts, just check max limit
            guard distance >= 0 && distance <= 100_000 else { return false } // Max 100km
        }

        if let duration = estimatedDuration {
            guard duration > 0 && duration <= 14_400 else { return false } // Max 4 hours
        }

        return true
    }

    // Display helpers
    var totalDistanceFormatted: String? {
        let distance = calculatedTotalDistance
        guard distance > 0 else { return nil }
        let km = distance / 1000.0
        return String(format: "%.2f km", km)
    }

    var estimatedDurationFormatted: String? {
        guard let duration = estimatedDuration else { return nil }
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    // Calculate total distance from steps (including estimated from duration+pace)
    var calculatedTotalDistance: Double {
        // If total distance is explicitly provided, use it
        if let total = totalDistance, total > 0 {
            return total
        }

        // Otherwise, sum up distances from all steps (including calculated ones)
        return steps.reduce(0) { sum, step in
            return sum + step.calculatedDistance
        }
    }

    // Calculate estimated duration from steps if not provided
    var calculatedEstimatedDuration: TimeInterval {
        if let duration = estimatedDuration {
            return duration
        }

        return steps.reduce(0) { sum, step in
            if step.goal.type == .duration {
                return sum + step.goal.value
            }
            // Estimate duration for distance-based steps (assume 5:00/km pace)
            if step.goal.type == .distance {
                let km = step.goal.value / 1000.0
                let estimatedMinutes = km * 5.0
                return sum + (estimatedMinutes * 60.0)
            }
            return sum
        }
    }
}

// MARK: - Sample Data for Testing

extension AIGeneratedWorkout {
    static var sampleIntervalWorkout: AIGeneratedWorkout {
        AIGeneratedWorkout(
            name: "10x400m Speed Intervals",
            description: "Classic speed workout with 10 repetitions of 400m at 5K pace with 1-minute recovery jogs",
            sport: .running,
            steps: [
                WorkoutStep(
                    type: .warmup,
                    goal: WorkoutGoal(type: .distance, value: 1600),
                    targetPace: "5:30",
                    targetHeartRateZone: 2,
                    instructions: "Start slow and gradually increase pace"
                ),
                WorkoutStep(
                    type: .work,
                    goal: WorkoutGoal(type: .distance, value: 400),
                    targetPace: "4:00",
                    targetHeartRateZone: 4,
                    instructions: "Fast but controlled, maintain form"
                ),
                WorkoutStep(
                    type: .recovery,
                    goal: WorkoutGoal(type: .duration, value: 60),
                    targetPace: "6:00",
                    targetHeartRateZone: 2,
                    instructions: "Slow jog to recover"
                ),
                WorkoutStep(
                    type: .cooldown,
                    goal: WorkoutGoal(type: .distance, value: 800),
                    targetPace: "5:45",
                    targetHeartRateZone: 2,
                    instructions: "Easy pace to finish"
                )
            ],
            totalDistance: 7600,
            estimatedDuration: 2700
        )
    }

    static var sampleTempoRun: AIGeneratedWorkout {
        AIGeneratedWorkout(
            name: "5K Tempo Run",
            description: "Sustained effort at threshold pace to improve lactate tolerance",
            sport: .running,
            steps: [
                WorkoutStep(
                    type: .warmup,
                    goal: WorkoutGoal(type: .distance, value: 1600),
                    targetPace: "5:30",
                    targetHeartRateZone: 2,
                    instructions: "Easy warm-up"
                ),
                WorkoutStep(
                    type: .work,
                    goal: WorkoutGoal(type: .distance, value: 5000),
                    targetPace: "4:30",
                    targetHeartRateZone: 4,
                    instructions: "Comfortably hard pace, stay controlled"
                ),
                WorkoutStep(
                    type: .cooldown,
                    goal: WorkoutGoal(type: .distance, value: 1600),
                    targetPace: "5:45",
                    targetHeartRateZone: 2,
                    instructions: "Easy cool-down"
                )
            ],
            totalDistance: 8200,
            estimatedDuration: 2400
        )
    }
}
