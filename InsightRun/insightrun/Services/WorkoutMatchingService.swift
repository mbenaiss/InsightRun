//
//  WorkoutMatchingService.swift
//  InsightRun
//
//  Automatically matches completed HealthKit workouts to planned training sessions
//

import Foundation
import HealthKit

extension Notification.Name {
    static let trainingDayCompleted = Notification.Name("trainingDayCompleted")
}

@MainActor
final class WorkoutMatchingService {
    static let shared = WorkoutMatchingService()

    private let storage = GoalStorage.shared
    private let distanceTolerance = 0.30 // 30%
    private let durationTolerance = 0.30 // 30%

    private init() {}

    // MARK: - Public

    func matchWorkouts(_ hkWorkouts: [HKWorkout]) {
        let goals = storage.load()
        let activeGoals = goals.filter { $0.isActive && !$0.isPast && $0.hasTrainingPlan }
        guard !activeGoals.isEmpty else { return }

        for hkWorkout in hkWorkouts {
            matchWorkout(hkWorkout, activeGoals: activeGoals)
        }
    }

    private func matchWorkout(_ hkWorkout: HKWorkout, activeGoals: [RaceGoal]) {

        let workoutDate = Calendar.current.startOfDay(for: hkWorkout.startDate)
        let workoutDistance = hkWorkout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let workoutDuration = hkWorkout.duration

        for goal in activeGoals {
            guard let plan = goal.trainingPlan, let startDate = plan.startDate else { continue }

            let planStart = Calendar.current.startOfDay(for: startDate)
            let daysSinceStart = Calendar.current.dateComponents([.day], from: planStart, to: workoutDate).day ?? -1
            guard daysSinceStart >= 0 else { continue }

            let weekIndex = daysSinceStart / 7
            guard weekIndex < plan.weeks.count else { continue }

            let workoutDOW = Calendar.current.component(.weekday, from: hkWorkout.startDate)
            let week = plan.weeks[weekIndex]
            guard let dayIndex = week.days.firstIndex(where: { $0.dayOfWeek.rawValue == workoutDOW }) else { continue }
            let day = week.days[dayIndex]

            guard let planned = day.workout, !day.isCompleted else { continue }
            guard planned.type != .crossTraining else { continue }

            let distanceOK = planned.targetDistance.map {
                abs(workoutDistance - $0) / max($0, 1) < distanceTolerance
            } ?? true

            let durationOK = planned.targetDuration.map {
                abs(workoutDuration - $0) / max($0, 1) < durationTolerance
            } ?? true

            guard distanceOK || durationOK else { continue }

            // Match found — update the goal
            var updatedGoal = goal
            updatedGoal.trainingPlan!.weeks[weekIndex].days[dayIndex].isCompleted = true
            updatedGoal.trainingPlan!.weeks[weekIndex].days[dayIndex].completedWorkoutId = hkWorkout.uuid.uuidString
            storage.updateGoal(updatedGoal)

            NotificationCenter.default.post(
                name: .trainingDayCompleted,
                object: nil,
                userInfo: [
                    "goalId": goal.id.uuidString,
                    "weekIndex": weekIndex,
                    "dayIndex": dayIndex,
                ]
            )

            print("WorkoutMatchingService: Matched workout to \(planned.name) in \(goal.raceName)")
            return // One workout matches at most one planned session
        }
    }
}
