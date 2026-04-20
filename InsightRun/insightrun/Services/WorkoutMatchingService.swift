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
    private let healthStore = HKHealthStore()

    // Easy/recovery: permissive — distance OR duration
    private static let easyDistanceTolerance = 0.30
    private static let easyDurationTolerance = 0.30
    // Long run: distance is the training stimulus, duration alone isn't enough
    private static let longRunDistanceTolerance = 0.25
    // Tempo/threshold: distance must be close AND pace must match the target
    private static let tempoDistanceTolerance = 0.25
    private static let paceTolerance = 0.10

    private static let paceRegex = try! NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#)

    private init() {}

    // MARK: - Public

    /// Re-run matching on recent HealthKit workouts without touching the sync anchor.
    /// Useful to catch up when the observer consumed a workout before the plan existed.
    func catchUpMatch(daysBack: Int = 30) async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let workoutType = HKObjectType.workoutType()

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let running = (samples as? [HKWorkout])?.filter { $0.workoutActivityType == .running } ?? []
                continuation.resume(returning: running)
            }
            healthStore.execute(query)
        }
        matchWorkouts(workouts)
    }

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
            guard Self.shouldAttemptAutoMatch(planned.type) else { continue }

            guard Self.isMatch(
                planned: planned,
                hkDistance: workoutDistance,
                hkDuration: workoutDuration
            ) else { continue }

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

    // MARK: - Matching rules

    /// Quality sessions whose training stimulus can't be inferred from duration/distance alone
    /// (intervals, fartlek, hill repeats) are left for manual confirmation — auto-matching them
    /// from a steady run would miscalibrate the adaptation engine.
    static func shouldAttemptAutoMatch(_ type: WorkoutType) -> Bool {
        switch type {
        case .crossTraining, .intervals, .fartlek, .hillRepeats:
            return false
        case .easyRun, .recovery, .longRun, .tempo:
            return true
        }
    }

    static func isMatch(
        planned: PlannedWorkout,
        hkDistance: Double,
        hkDuration: TimeInterval
    ) -> Bool {
        switch planned.type {
        case .easyRun, .recovery:
            let distanceOK = withinTolerance(hkDistance, target: planned.targetDistance, tol: easyDistanceTolerance) ?? true
            let durationOK = withinTolerance(hkDuration, target: planned.targetDuration, tol: easyDurationTolerance) ?? true
            return distanceOK || durationOK

        case .longRun:
            // Distance is the point of a long run — a short steady run that happens
            // to last the same duration shouldn't count.
            guard let distanceOK = withinTolerance(hkDistance, target: planned.targetDistance, tol: longRunDistanceTolerance) else {
                // No target distance — fall back to duration, same tolerance.
                return withinTolerance(hkDuration, target: planned.targetDuration, tol: longRunDistanceTolerance) ?? false
            }
            return distanceOK

        case .tempo:
            // Distance window + pace coherence. Without targetPace we can't
            // distinguish a tempo from an easy run at the same distance.
            let distanceOK = withinTolerance(hkDistance, target: planned.targetDistance, tol: tempoDistanceTolerance) ?? false
            guard distanceOK,
                  let targetPaceSec = parseTargetPaceSecPerKm(planned.targetPace),
                  hkDistance > 0
            else { return false }
            let actualPaceSec = hkDuration / (hkDistance / 1000.0)
            return abs(actualPaceSec - targetPaceSec) / targetPaceSec < paceTolerance

        case .intervals, .fartlek, .hillRepeats, .crossTraining:
            return false
        }
    }

    /// Returns `nil` when no target is set (caller decides the default),
    /// `true`/`false` when a target exists and we can compare.
    private static func withinTolerance(_ actual: Double, target: Double?, tol: Double) -> Bool? {
        guard let target, target > 0 else { return nil }
        return abs(actual - target) / target < tol
    }

    /// Parses pace strings like "5:30/km", "5:30 min/km", "5:30" into seconds per km.
    static func parseTargetPaceSecPerKm(_ raw: String?) -> TimeInterval? {
        guard let raw, !raw.isEmpty,
              let match = paceRegex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges == 3,
              let minRange = Range(match.range(at: 1), in: raw),
              let secRange = Range(match.range(at: 2), in: raw),
              let minutes = Int(raw[minRange]),
              let seconds = Int(raw[secRange]),
              seconds < 60
        else { return nil }
        return TimeInterval(minutes * 60 + seconds)
    }
}
