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
    @Published var needsConsent = false

    private var pendingGenerationGoal: RaceGoal?

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
        guard ConsentService.shared.hasConsentedToAIDataSharing else {
            pendingGenerationGoal = goal
            needsConsent = true
            return
        }

        pendingGenerationGoal = nil
        isGeneratingPlan = true
        generationError = nil

        let weeksCount = Self.computeWeeksCount(for: goal)
        let dateFormatter = ISO8601DateFormatter()
        let request = TrainingPlanGenerationRequest(
            raceType: goal.raceType.rawValue,
            targetDate: dateFormatter.string(from: goal.targetDate),
            startDate: goal.planStartDate.map { dateFormatter.string(from: $0) },
            fitnessLevel: goal.fitnessLevel.rawValue,
            currentWeeklyVolumeKm: nil,
            avgPace: nil,
            language: AppLanguage.current,
            trainingDaysPerWeek: goal.trainingDaysPerWeek,
            preferredDays: goal.preferredDays.map { $0.rawValue },
            injury: goal.injury,
            targetTimeSeconds: goal.targetTime.map { Int($0) },
            weeksCount: weeksCount
        )

        do {
            let response = try await backendClient.generateTrainingPlan(request: request)
            let plan = convertResponseToPlan(response, for: goal, weeksCount: weeksCount)

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

    // MARK: - Pending Generation (resume after consent)

    func resumePendingGeneration() async {
        guard let goal = pendingGenerationGoal else { return }
        pendingGenerationGoal = nil
        await generateTrainingPlan(for: goal)
    }

    func clearPendingGeneration() {
        pendingGenerationGoal = nil
    }

    // MARK: - Day Completion

    func toggleDayCompletion(goalId: UUID, weekIndex: Int, dayIndex: Int) {
        guard let goalIdx = goals.firstIndex(where: { $0.id == goalId }),
              goals[goalIdx].trainingPlan != nil else { return }

        goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isCompleted.toggle()
        if goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isCompleted {
            goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isSkipped = false
        }
        storage.updateGoal(goals[goalIdx])
    }

    func toggleDaySkipped(goalId: UUID, weekIndex: Int, dayIndex: Int) {
        guard let goalIdx = goals.firstIndex(where: { $0.id == goalId }),
              goals[goalIdx].trainingPlan != nil else { return }

        goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isSkipped.toggle()
        if goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isSkipped {
            goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isCompleted = false
            goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].completedWorkoutId = nil
        }
        storage.updateGoal(goals[goalIdx])
    }

    /// Move a planned session to a new date without changing anything else in the plan.
    /// Pass `nil` to clear an existing override.
    func setDayDateOverride(goalId: UUID, weekIndex: Int, dayIndex: Int, newDate: Date?) {
        guard let goalIdx = goals.firstIndex(where: { $0.id == goalId }),
              goals[goalIdx].trainingPlan != nil else { return }

        let normalized = newDate.map { Calendar.current.startOfDay(for: $0) }
        goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].dateOverride = normalized
        storage.updateGoal(goals[goalIdx])
    }

    /// Shift the plan start to a new date (keeps the plan structure, just re-anchors it).
    /// Triggers a retro-match so any recent HealthKit workout falling into the new window gets linked.
    func setPlanStartDate(goalId: UUID, newStart: Date) async {
        guard let goalIdx = goals.firstIndex(where: { $0.id == goalId }),
              goals[goalIdx].trainingPlan != nil else { return }

        let start = Calendar.current.startOfDay(for: newStart)
        goals[goalIdx].planStartDate = start
        goals[goalIdx].trainingPlan!.startDate = start
        storage.updateGoal(goals[goalIdx])

        await WorkoutMatchingService.shared.catchUpMatch()
        reload()
    }

    // MARK: - Training Plan Adaptation

    func adaptPlanIfNeeded(for goal: RaceGoal) async {
        guard RevenueCatManager.shared.hasAIAccess,
              ConsentService.shared.hasConsentedToAIDataSharing else { return }
        guard !isAdaptingPlan, !isGeneratingPlan else { return }

        guard let plan = goal.trainingPlan,
              let weekIndex = plan.currentWeekIndex,
              weekIndex >= 1,
              let startDate = plan.startDate else { return }

        // Adaptation runs only at the very start of a training week (day 0–1).
        // Mid-week or end-of-week shifts would invalidate sessions the user is about to do.
        let daysIntoCurrentWeek = (Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: startDate),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0) % 7
        guard daysIntoCurrentWeek <= 1 else { return }

        if plan.lastAdaptationWeekIndex == weekIndex { return }
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
            let originalRemaining = buildOriginalRemainingWeeks(plan: plan, fromWeek: weekIndex + 1)

            let dateFormatter = ISO8601DateFormatter()
            let request = AdaptTrainingPlanRequest(
                raceType: goal.raceType.rawValue,
                targetDate: dateFormatter.string(from: goal.targetDate),
                fitnessLevel: goal.fitnessLevel.rawValue,
                language: AppLanguage.current,
                trainingDaysPerWeek: goal.trainingDaysPerWeek,
                preferredDays: goal.preferredDays.map { $0.rawValue },
                targetTimeSeconds: goal.targetTime.map { Int($0) },
                injury: goal.injury,
                currentWeekNumber: weekIndex + 1,
                remainingWeeksCount: remainingWeeks,
                originalPlanName: plan.name,
                originalPlanGoal: plan.goal,
                completedWeeks: completedWeeks,
                originalRemainingWeeks: originalRemaining
            )

            let response = try await backendClient.adaptTrainingPlan(request: request)

            let adaptedWeeks = convertAdaptedWeeks(
                response.plan.weeks,
                for: goal,
                startTargetIndex: weekIndex + 1,
                raceWeekIndex: plan.weeks.count - 1
            )

            if let goalIdx = goals.firstIndex(where: { $0.id == goal.id }) {
                for i in 0..<adaptedWeeks.count {
                    let targetIdx = weekIndex + 1 + i
                    guard targetIdx < goals[goalIdx].trainingPlan!.weeks.count else { break }
                    goals[goalIdx].trainingPlan!.weeks[targetIdx] = adaptedWeeks[i]
                }
                goals[goalIdx].trainingPlan!.lastAdaptationDate = Date()
                goals[goalIdx].trainingPlan!.lastAdaptationWeekIndex = weekIndex
                goals[goalIdx].trainingPlan!.adaptationAssessment = response.plan.adaptation.assessment

                storage.updateGoal(goals[goalIdx])
            }
        } catch {
            adaptationError = error.localizedDescription
        }
    }

    private func buildOriginalRemainingWeeks(plan: TrainingPlan, fromWeek: Int) -> [OriginalRemainingWeekPayload] {
        guard fromWeek < plan.weeks.count else { return [] }
        return plan.weeks[fromWeek..<plan.weeks.count].map { week in
            let workouts = week.days.compactMap { day -> OriginalRemainingWorkoutPayload? in
                guard let w = day.workout else { return nil }
                return OriginalRemainingWorkoutPayload(
                    type: w.type.rawValue,
                    name: w.name,
                    intensity: w.intensity.rawValue,
                    targetDistance: w.targetDistance,
                    targetDuration: w.targetDuration,
                    targetPace: w.targetPace
                )
            }
            return OriginalRemainingWeekPayload(
                weekNumber: week.weekNumber,
                phase: week.phase.rawValue,
                weeklyVolumeKm: week.weeklyVolume,
                workouts: workouts
            )
        }
    }

    private func buildCompletedWeeksData(plan: TrainingPlan, upToWeek: Int) async -> [CompletedWeekPayload] {
        var completedUUIDs: [UUID] = []
        for i in 0..<upToWeek {
            for day in plan.weeks[i].days where day.workout != nil {
                if let uuidString = day.completedWorkoutId, let uuid = UUID(uuidString: uuidString) {
                    completedUUIDs.append(uuid)
                }
            }
        }

        let metricsMap = await fetchMetricsInParallel(uuids: completedUUIDs)

        var result: [CompletedWeekPayload] = []
        for i in 0..<upToWeek {
            let week = plan.weeks[i]
            let workoutDays = week.days.filter { $0.workout != nil }
            let completedCount = workoutDays.filter { $0.isCompleted }.count
            let completionRate: Double = workoutDays.isEmpty
                ? 1.0
                : Double(completedCount) / Double(workoutDays.count)

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
                   let metrics = metricsMap[uuid] {
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
                    actual: actual,
                    skipped: day.isSkipped ? true : nil
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

    private func fetchMetricsInParallel(
        uuids: [UUID]
    ) async -> [UUID: (distance: Double, duration: Double, pace: Double?, heartRate: Double?)] {
        await withTaskGroup(
            of: (UUID, (distance: Double, duration: Double, pace: Double?, heartRate: Double?)?).self
        ) { group in
            for uuid in uuids {
                group.addTask {
                    let metrics = await HealthKitManager.shared.fetchWorkoutBasicMetrics(uuid: uuid)
                    return (uuid, metrics)
                }
            }
            var map: [UUID: (distance: Double, duration: Double, pace: Double?, heartRate: Double?)] = [:]
            for await (uuid, metrics) in group {
                if let metrics { map[uuid] = metrics }
            }
            return map
        }
    }

    private func convertAdaptedWeeks(
        _ weekDatas: [TrainingPlanGenerationResponse.GeneratedWeekData],
        for goal: RaceGoal,
        startTargetIndex: Int,
        raceWeekIndex: Int
    ) -> [TrainingWeek] {
        let preferredDays = goal.preferredDays.sorted(by: { $0.rawValue < $1.rawValue })
        let raceDayOfWeek = Calendar.current.component(.weekday, from: goal.targetDate)
        let raceDistanceMeters = goal.raceType.distanceKm * 1000

        return weekDatas.enumerated().map { offset, data in
            let absoluteIdx = startTargetIndex + offset
            let isRaceWeek = absoluteIdx == raceWeekIndex
            return convertWeekData(
                data,
                preferredDays: preferredDays,
                raceDayOfWeek: isRaceWeek ? raceDayOfWeek : nil,
                raceDistanceMeters: isRaceWeek ? raceDistanceMeters : nil
            )
        }
    }

    // MARK: - Conversion

    private static func computeWeeksCount(for goal: RaceGoal) -> Int {
        let planStart = goal.planStartDate ?? Date()
        let seconds = goal.targetDate.timeIntervalSince(planStart)
        let weeks = Int(ceil(seconds / (7 * 86400)))
        return max(4, min(24, weeks))
    }

    private func buildSkeletonPlan(for goal: RaceGoal, weeksCount: Int) -> [TrainingWeek] {
        let raceDOW = DayOfWeek(rawValue: Calendar.current.component(.weekday, from: goal.targetDate)) ?? .sunday
        let raceDistanceMeters = goal.raceType.distanceKm * 1000
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

        return (0..<weeksCount).map { index in
            let isRaceWeek = index == weeksCount - 1
            let days = allDays.map { day -> TrainingDay in
                if isRaceWeek, day == raceDOW {
                    let raceWorkout = PlannedWorkout(
                        type: .longRun,
                        name: String(localized: "goals.plan.raceDayName", defaultValue: "Race day", comment: "Placeholder name for the race workout"),
                        description: goal.raceType.displayName,
                        targetDuration: goal.targetTime,
                        targetDistance: raceDistanceMeters,
                        intensity: .veryHard
                    )
                    return TrainingDay(dayOfWeek: day, workout: raceWorkout)
                }
                return TrainingDay(dayOfWeek: day, workout: nil)
            }
            return TrainingWeek(weekNumber: index + 1, phase: .base, days: days)
        }
    }

    private func convertResponseToPlan(
        _ response: TrainingPlanGenerationResponse,
        for goal: RaceGoal,
        weeksCount: Int
    ) -> TrainingPlan {
        let raceDayOfWeek = Calendar.current.component(.weekday, from: goal.targetDate)
        let preferredDays = goal.preferredDays.sorted(by: { $0.rawValue < $1.rawValue })
        let raceDistanceMeters = goal.raceType.distanceKm * 1000
        let lastIndex = weeksCount - 1

        var weeks = buildSkeletonPlan(for: goal, weeksCount: weeksCount)

        for received in response.plan.weeks {
            let idx = received.weekNumber - 1
            guard idx >= 0, idx < weeksCount else { continue }
            let isRaceWeek = idx == lastIndex
            weeks[idx] = convertWeekData(
                received,
                preferredDays: preferredDays,
                raceDayOfWeek: isRaceWeek ? raceDayOfWeek : nil,
                raceDistanceMeters: isRaceWeek ? raceDistanceMeters : nil
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
        raceDayOfWeek: Int?,
        raceDistanceMeters: Double? = nil
    ) -> TrainingWeek {
        let workouts = weekData.workouts.map { w -> PlannedWorkout in
            let steps = (w.steps ?? []).map { s in
                PlannedWorkoutStep(
                    type: PlannedStepType(rawValue: s.type) ?? .work,
                    duration: s.duration,
                    distance: s.distance,
                    targetPace: s.targetPace,
                    repetitions: s.repetitions,
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
            raceDayOfWeek: raceDayOfWeek,
            raceDistanceMeters: raceDistanceMeters
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

    private func mapWorkoutsToDays(
        workouts: [PlannedWorkout],
        preferredDays: [DayOfWeek],
        raceDayOfWeek: Int?,
        raceDistanceMeters: Double? = nil
    ) -> [TrainingDay] {
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

        var assignedDays: Set<DayOfWeek> = []
        var assignments: [DayOfWeek: PlannedWorkout] = [:]
        var remainingWorkouts = workouts

        if let raceDay = raceDayOfWeek,
           let raceDOW = DayOfWeek(rawValue: raceDay),
           !remainingWorkouts.isEmpty {
            let raceIndex = Self.identifyRaceWorkoutIndex(
                in: remainingWorkouts,
                raceDistanceMeters: raceDistanceMeters
            )
            let raceWorkout = remainingWorkouts.remove(at: raceIndex)
            assignments[raceDOW] = raceWorkout
            assignedDays.insert(raceDOW)
        }

        let availableDays = preferredDays.filter { !assignedDays.contains($0) }

        if remainingWorkouts.count > availableDays.count {
            let dropped = remainingWorkouts.count - availableDays.count
            print("⚠️ GoalsViewModel.mapWorkoutsToDays: dropping \(dropped) workout(s) — \(remainingWorkouts.count) sessions for \(availableDays.count) preferred day(s)")
        }

        for (index, workout) in remainingWorkouts.enumerated() {
            guard index < availableDays.count else { break }
            let day = availableDays[index]
            assignments[day] = workout
        }

        return allDays.map { day in
            TrainingDay(
                dayOfWeek: day,
                workout: assignments[day]
            )
        }
    }

    private static func identifyRaceWorkoutIndex(
        in workouts: [PlannedWorkout],
        raceDistanceMeters: Double?
    ) -> Int {
        guard let target = raceDistanceMeters else { return 0 }
        let best = workouts.enumerated().min { lhs, rhs in
            let lhsDiff = lhs.element.targetDistance.map { abs($0 - target) } ?? .greatestFiniteMagnitude
            let rhsDiff = rhs.element.targetDistance.map { abs($0 - target) } ?? .greatestFiniteMagnitude
            return lhsDiff < rhsDiff
        }
        return best?.offset ?? 0
    }
}
