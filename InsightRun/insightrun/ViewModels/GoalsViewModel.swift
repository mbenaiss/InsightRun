//
//  GoalsViewModel.swift
//  InsightRun
//
//  ViewModel for race goals management and training plan generation
//

import SwiftUI
import Combine

@MainActor
class GoalsViewModel: ObservableObject {
    @Published var goals: [RaceGoal] = []
    @Published var isGeneratingPlan = false
    @Published var generationError: String?
    @Published var isAdaptingPlan = false
    @Published var adaptationError: String?
    @Published var showAddGoal = false

    private let storage = GoalStorage.shared
    private let backendClient = BackendAPIClient.shared

    init() {
        goals = storage.load()
    }

    // MARK: - Computed

    var activeGoals: [RaceGoal] {
        goals.filter { $0.isActive && !$0.isPast && !$0.isPastRace }
    }

    var pastGoals: [RaceGoal] {
        goals.filter { !$0.isPastRace && ($0.isPast || !$0.isActive) }
    }

    var raceHistory: [RaceGoal] {
        goals.filter { $0.isPastRace }.sorted { $0.targetDate > $1.targetDate }
    }

    // MARK: - CRUD

    func reload() {
        goals = storage.load()
    }

    func addGoal(_ goal: RaceGoal) {
        goals.append(goal)
        storage.addGoal(goal)
    }

    func renameGoal(id: UUID, newName: String) {
        if let index = goals.firstIndex(where: { $0.id == id }) {
            goals[index].raceName = newName
            storage.updateGoal(goals[index])
        }
    }

    func deleteGoal(_ goal: RaceGoal) {
        goals.removeAll { $0.id == goal.id }
        storage.deleteGoal(id: goal.id)
    }

    func deleteGoals(at offsets: IndexSet) {
        let activeList = activeGoals
        for index in offsets {
            let goal = activeList[index]
            goals.removeAll { $0.id == goal.id }
            storage.deleteGoal(id: goal.id)
        }
    }

    // MARK: - Training Plan Generation

    func generateTrainingPlan(for goal: RaceGoal) async {
        isGeneratingPlan = true
        generationError = nil

        let dateFormatter = ISO8601DateFormatter()
        let request = TrainingPlanGenerationRequest(
            raceType: goal.raceType.rawValue,
            targetDate: dateFormatter.string(from: goal.targetDate),
            startDate: goal.planStartDate.map { dateFormatter.string(from: $0) },
            fitnessLevel: goal.fitnessLevel.rawValue,
            currentWeeklyVolumeKm: nil,
            avgPace: nil,
            language: Locale.current.language.languageCode?.identifier ?? "en",
            trainingDaysPerWeek: goal.trainingDaysPerWeek,
            preferredDays: goal.preferredDays.map { $0.rawValue },
            injury: goal.injury,
            targetTimeSeconds: goal.targetTime.map { Int($0) }
        )

        do {
            let response = try await backendClient.generateTrainingPlan(request: request)
            let plan = convertResponseToPlan(response, for: goal)

            if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[index].trainingPlan = plan
                storage.updateGoal(goals[index])
            }
        } catch let error as BackendError {
            generationError = error.localizedDescription
        } catch {
            generationError = error.localizedDescription
        }

        isGeneratingPlan = false
    }

    // MARK: - Day Completion

    func toggleDayCompletion(goalId: UUID, weekIndex: Int, dayIndex: Int) {
        guard let goalIdx = goals.firstIndex(where: { $0.id == goalId }),
              goals[goalIdx].trainingPlan != nil else { return }

        goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isCompleted.toggle()
        storage.updateGoal(goals[goalIdx])
    }

    // MARK: - Training Plan Adaptation

    func adaptPlanIfNeeded(for goal: RaceGoal) async {
        guard let plan = goal.trainingPlan,
              let weekIndex = plan.currentWeekIndex,
              weekIndex >= 1 else { return } // Only from week 2+

        // Throttle: don't adapt more than once per week
        if let lastAdapt = plan.lastAdaptationDate,
           Calendar.current.dateComponents([.day], from: lastAdapt, to: Date()).day ?? 0 < 7 {
            return
        }

        let remainingWeeks = plan.weeks.count - weekIndex - 1
        guard remainingWeeks > 0 else { return }

        isAdaptingPlan = true
        adaptationError = nil
        defer { isAdaptingPlan = false }

        do {
            let completedWeeks = await buildCompletedWeeksData(plan: plan, upToWeek: weekIndex)

            let dateFormatter = ISO8601DateFormatter()
            let request = AdaptTrainingPlanRequest(
                raceType: goal.raceType.rawValue,
                targetDate: dateFormatter.string(from: goal.targetDate),
                fitnessLevel: goal.fitnessLevel.rawValue,
                language: Locale.current.language.languageCode?.identifier ?? "en",
                trainingDaysPerWeek: goal.trainingDaysPerWeek,
                preferredDays: goal.preferredDays.map { $0.rawValue },
                targetTimeSeconds: goal.targetTime.map { Int($0) },
                injury: goal.injury,
                currentWeekNumber: weekIndex + 1,
                remainingWeeksCount: remainingWeeks,
                originalPlanName: plan.name,
                originalPlanGoal: plan.goal,
                completedWeeks: completedWeeks
            )

            let response = try await backendClient.adaptTrainingPlan(request: request)

            let adaptedWeeks = convertAdaptedWeeks(response.plan.weeks, for: goal)

            if let goalIdx = goals.firstIndex(where: { $0.id == goal.id }) {
                // Replace future weeks only (keep completed + current week)
                for i in 0..<adaptedWeeks.count {
                    let targetIdx = weekIndex + 1 + i
                    guard targetIdx < goals[goalIdx].trainingPlan!.weeks.count else { break }
                    goals[goalIdx].trainingPlan!.weeks[targetIdx] = adaptedWeeks[i]
                }
                goals[goalIdx].trainingPlan!.lastAdaptationDate = Date()
                goals[goalIdx].trainingPlan!.adaptationAssessment = response.plan.adaptation.assessment

                storage.updateGoal(goals[goalIdx])
            }
        } catch {
            adaptationError = error.localizedDescription
        }
    }

    private func buildCompletedWeeksData(plan: TrainingPlan, upToWeek: Int) async -> [CompletedWeekPayload] {
        var result: [CompletedWeekPayload] = []

        for i in 0..<upToWeek {
            let week = plan.weeks[i]
            let workoutDays = week.days.filter { $0.workout != nil }
            let completedCount = workoutDays.filter { $0.isCompleted }.count
            let completionRate = workoutDays.isEmpty ? 0.0 : Double(completedCount) / Double(workoutDays.count)

            var workouts: [CompletedWorkoutPayload] = []
            for day in workoutDays {
                let planned = PlannedWorkoutPayload(
                    distance: day.workout?.targetDistance,
                    duration: day.workout?.targetDuration,
                    pace: day.workout?.targetPace,
                    intensity: day.workout?.intensity.rawValue ?? "moderate"
                )

                var actual: ActualWorkoutPayload?
                if let uuidString = day.completedWorkoutId,
                   let uuid = UUID(uuidString: uuidString),
                   let metrics = await HealthKitManager.shared.fetchWorkoutBasicMetrics(uuid: uuid) {
                    actual = ActualWorkoutPayload(
                        distance: metrics.distance,
                        duration: metrics.duration,
                        pace: metrics.pace,
                        heartRate: metrics.heartRate
                    )
                }

                workouts.append(CompletedWorkoutPayload(
                    type: day.workout?.type.rawValue ?? "easy_run",
                    planned: planned,
                    actual: actual
                ))
            }

            result.append(CompletedWeekPayload(
                weekNumber: week.weekNumber,
                phase: week.phase.rawValue,
                completionRate: completionRate,
                workouts: workouts
            ))
        }

        return result
    }

    private func convertAdaptedWeeks(
        _ weekDatas: [TrainingPlanGenerationResponse.GeneratedWeekData],
        for goal: RaceGoal
    ) -> [TrainingWeek] {
        let preferredDays = goal.preferredDays.sorted(by: { $0.rawValue < $1.rawValue })
        return weekDatas.map { convertWeekData($0, preferredDays: preferredDays, raceDayOfWeek: nil) }
    }

    // MARK: - Conversion

    private func convertResponseToPlan(_ response: TrainingPlanGenerationResponse, for goal: RaceGoal) -> TrainingPlan {
        let raceDayOfWeek = Calendar.current.component(.weekday, from: goal.targetDate)
        let lastWeekIndex = response.plan.weeks.count - 1
        let preferredDays = goal.preferredDays.sorted(by: { $0.rawValue < $1.rawValue })

        let weeks = response.plan.weeks.enumerated().map { weekIndex, weekData in
            convertWeekData(
                weekData,
                preferredDays: preferredDays,
                raceDayOfWeek: weekIndex == lastWeekIndex ? raceDayOfWeek : nil
            )
        }

        let startDate: Date = goal.planStartDate ?? (Calendar.current.date(
            byAdding: .weekOfYear,
            value: -weeks.count,
            to: goal.targetDate
        ) ?? Date())

        return TrainingPlan(
            name: response.plan.name,
            goal: response.plan.goal,
            level: goal.fitnessLevel,
            weeks: weeks,
            startDate: startDate,
            isActive: true
        )
    }

    private func convertWeekData(
        _ weekData: TrainingPlanGenerationResponse.GeneratedWeekData,
        preferredDays: [DayOfWeek],
        raceDayOfWeek: Int?
    ) -> TrainingWeek {
        let workouts = weekData.workouts.map { w -> PlannedWorkout in
            let steps = (w.steps ?? []).map { s in
                PlannedWorkoutStep(
                    type: PlannedStepType(rawValue: s.type) ?? .work,
                    duration: s.duration,
                    distance: s.distance,
                    targetPace: s.targetPace,
                    description: s.description
                )
            }

            return PlannedWorkout(
                type: WorkoutType(rawValue: w.type) ?? .easyRun,
                name: w.name,
                description: w.description,
                targetDuration: w.targetDuration,
                targetDistance: w.targetDistance,
                targetPace: w.targetPace,
                steps: steps,
                intensity: WorkoutIntensity(rawValue: w.intensity) ?? .moderate
            )
        }

        let days = mapWorkoutsToDays(
            workouts: workouts,
            preferredDays: preferredDays,
            raceDayOfWeek: raceDayOfWeek
        )

        let volume: Double? = {
            guard let v = weekData.weeklyVolume else { return nil }
            return v > 500 ? v / 1000.0 : v
        }()

        return TrainingWeek(
            weekNumber: weekData.weekNumber,
            phase: TrainingPhase(rawValue: weekData.phase) ?? .base,
            days: days,
            weeklyVolume: volume,
            notes: weekData.notes
        )
    }

    /// Map a list of workouts to a 7-day week using preferred days.
    /// - workouts: ordered list from AI (key session first)
    /// - preferredDays: user's selected training days
    /// - raceDayOfWeek: if set, the first workout (race) goes on this day (last week only)
    private func mapWorkoutsToDays(
        workouts: [PlannedWorkout],
        preferredDays: [DayOfWeek],
        raceDayOfWeek: Int?
    ) -> [TrainingDay] {
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

        // Track which days have a workout assigned
        var assignedDays: Set<DayOfWeek> = []
        var assignments: [DayOfWeek: PlannedWorkout] = [:]
        var remainingWorkouts = workouts

        // If race week, place race on race day first
        if let raceDay = raceDayOfWeek,
           let raceDOW = DayOfWeek(rawValue: raceDay),
           !remainingWorkouts.isEmpty {
            assignments[raceDOW] = remainingWorkouts.removeFirst()
            assignedDays.insert(raceDOW)
        }

        // Assign remaining workouts to preferred days (skip already assigned)
        let availableDays = preferredDays.filter { !assignedDays.contains($0) }

        for (index, workout) in remainingWorkouts.enumerated() {
            guard index < availableDays.count else { break }
            let day = availableDays[index]
            assignments[day] = workout
        }

        // Build 7-day array
        return allDays.map { day in
            TrainingDay(
                dayOfWeek: day,
                workout: assignments[day]
            )
        }
    }
}
