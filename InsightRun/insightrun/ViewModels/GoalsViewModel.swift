//
//  GoalsViewModel.swift
//  InsightRun
//
//  ViewModel for race goals management and training plan generation
//

import Combine
import SwiftUI

@MainActor
class GoalsViewModel: ObservableObject {
    @Published var goals: [RaceGoal] = []
    @Published var isGeneratingPlan = false
    @Published var generationError: String?
    @Published private(set) var generationErrorGoalID: UUID?
    @Published var isAdaptingPlan = false
    @Published var adaptationError: String?
    @Published private(set) var adaptationErrorGoalID: UUID?
    @Published var showAddGoal = false
    @Published var needsConsent = false
    @Published var needsSubscription = false

    private var pendingGenerationGoal: RaceGoal?
    private var pendingGenerationStart: Date?

    private let storage = GoalStorage.shared
    private let generatePlan: (TrainingPlanGenerationRequest) async throws -> TrainingPlanGenerationResponse
    private let adaptPlan: (AdaptTrainingPlanRequest) async throws -> AdaptTrainingPlanResponse
    private let hasConsent: @MainActor () -> Bool
    private let hasAIAccess: @MainActor () -> Bool
    private let recordGeneration: @MainActor () -> Void
    private let loadRunningHistory: @MainActor () async -> RunningHistorySummary?
    @Published private(set) var generatingGoalID: UUID?
    @Published private(set) var adaptingGoalID: UUID?
    private var planRevisions: [UUID: UUID] = [:]

    init(
        generatePlan:
            @escaping (TrainingPlanGenerationRequest) async throws -> TrainingPlanGenerationResponse = {
                try await BackendAPIClient.shared.generateTrainingPlan(request: $0)
            },
        adaptPlan: @escaping (AdaptTrainingPlanRequest) async throws -> AdaptTrainingPlanResponse = {
            try await BackendAPIClient.shared.adaptTrainingPlan(request: $0)
        },
        hasConsent: @escaping @MainActor () -> Bool = { ConsentService.shared.hasConsentedToAIDataSharing },
        hasAIAccess: @escaping @MainActor () -> Bool = { RevenueCatManager.shared.hasAIAccess },
        recordGeneration: @escaping @MainActor () -> Void = {
            if !DemoMode.isEnabled { RevenueCatManager.shared.incrementFreeRequestCount() }
        },
        loadRunningHistory: @escaping @MainActor () async -> RunningHistorySummary? = {
            await RunningHistorySummary.recent()
        }
    ) {
        self.generatePlan = generatePlan
        self.adaptPlan = adaptPlan
        self.hasConsent = hasConsent
        self.hasAIAccess = hasAIAccess
        self.recordGeneration = recordGeneration
        self.loadRunningHistory = loadRunningHistory
        if DemoMode.isEnabled {
            goals = [MockData.sampleRaceGoal]
            return
        }
        goals = storage.load()
    }

    // MARK: - Computed

    var activeGoals: [RaceGoal] {
        goals.filter { $0.isActive && !$0.isPast && !$0.isPastRace }
    }

    var pastGoals: [RaceGoal] {
        goals.filter { !$0.isPastRace && ($0.isPast || !$0.isActive) }
    }

    // MARK: - CRUD

    func reload() {
        guard !DemoMode.isEnabled else { return }
        goals = storage.load()
    }

    func addGoal(_ goal: RaceGoal) {
        goals.append(goal)
        storage.addGoal(goal)
    }

    func renameGoal(id: UUID, newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let index = goals.firstIndex(where: { $0.id == id }) {
            goals[index].raceName = name
            storage.updateGoal(goals[index])
        }
    }

    func deleteGoal(_ goal: RaceGoal) {
        planRevisions[goal.id] = nil
        if pendingGenerationGoal?.id == goal.id { clearPendingGeneration() }
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

    func generateTrainingPlan(for goal: RaceGoal, startingOn requestedStart: Date? = nil) async {
        guard !isGeneratingPlan, !isAdaptingPlan,
            let goal = goals.first(where: { $0.id == goal.id })
        else { return }
        guard hasAIAccess() else {
            needsSubscription = true
            return
        }
        guard hasConsent() else {
            pendingGenerationGoal = goal
            pendingGenerationStart = requestedStart
            needsConsent = true
            return
        }

        clearPendingGeneration()
        isGeneratingPlan = true
        generationError = nil
        generationErrorGoalID = goal.id

        generatingGoalID = goal.id
        defer {
            isGeneratingPlan = false
            generatingGoalID = nil
        }
        let revision = UUID()
        planRevisions[goal.id] = revision
        do {
            guard !goal.preferredDays.isEmpty else { throw BackendError.invalidResponse }
            let schedule = try goal.generationSchedule(startingOn: requestedStart)
            let history = await loadRunningHistory()
            let request = TrainingPlanGenerationRequest(
                raceType: goal.raceType.rawValue,
                targetDate: schedule.dateString(schedule.target),
                startDate: schedule.dateString(schedule.start),
                fitnessLevel: goal.fitnessLevel.rawValue,
                currentWeeklyVolumeKm: history?.weeklyVolumeKm,
                avgPace: history?.averagePaceMinPerKm,
                language: AppLanguage.current,
                trainingDaysPerWeek: goal.trainingDaysPerWeek,
                preferredDays: goal.preferredDays.map { $0.rawValue },
                injury: goal.injury,
                targetTimeSeconds: goal.targetTime.map { Int($0) },
                weeksCount: schedule.weeksCount
            )

            let response = try await generatePlan(request)
            try Task.checkCancellation()
            guard planRevisions[goal.id] == revision else { return }
            let plan = try convertResponseToPlan(response, for: goal, schedule: schedule)
            recordGeneration()

            if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[index].planStartDate = schedule.start
                goals[index].trainingPlan = plan
                storage.updateGoal(goals[index])
            }
        } catch is CancellationError {
            return
        } catch {
            if goals.contains(where: { $0.id == goal.id }) {
                generationError = error.localizedDescription
            }
        }

    }

    // MARK: - Pending Generation (resume after consent)

    func resumePendingGeneration() async {
        guard let goal = pendingGenerationGoal else { return }
        let start = pendingGenerationStart
        clearPendingGeneration()
        await generateTrainingPlan(for: goal, startingOn: start)
    }

    func clearPendingGeneration() {
        pendingGenerationGoal = nil
        pendingGenerationStart = nil
    }

    // MARK: - Day Completion

    /// Validate that (weekIndex, dayIndex) still point inside the plan. Indices can
    /// go stale after a plan adaptation shortens the schedule; indexing blindly would crash.
    private func hasValidDayIndex(_ goalIdx: Int, weekIndex: Int, dayIndex: Int) -> Bool {
        guard let plan = goals[goalIdx].trainingPlan,
            plan.weeks.indices.contains(weekIndex)
        else { return false }
        return plan.weeks[weekIndex].days.indices.contains(dayIndex)
    }

    func toggleDayCompletion(goalId: UUID, weekIndex: Int, dayIndex: Int) {
        guard let goalIdx = goals.firstIndex(where: { $0.id == goalId }),
            hasValidDayIndex(goalIdx, weekIndex: weekIndex, dayIndex: dayIndex)
        else { return }
        planRevisions[goalId] = UUID()

        goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isCompleted.toggle()
        if goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isCompleted {
            goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].isSkipped = false
        }
        storage.updateGoal(goals[goalIdx])
    }

    func toggleDaySkipped(goalId: UUID, weekIndex: Int, dayIndex: Int) {
        guard let goalIdx = goals.firstIndex(where: { $0.id == goalId }),
            hasValidDayIndex(goalIdx, weekIndex: weekIndex, dayIndex: dayIndex)
        else { return }
        planRevisions[goalId] = UUID()

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
            hasValidDayIndex(goalIdx, weekIndex: weekIndex, dayIndex: dayIndex)
        else { return }
        planRevisions[goalId] = UUID()

        let normalized = newDate.map { Calendar.current.startOfDay(for: $0) }
        goals[goalIdx].trainingPlan!.weeks[weekIndex].days[dayIndex].dateOverride = normalized
        storage.updateGoal(goals[goalIdx])
    }

    func setPlanStartDate(goalId: UUID, newStart: Date) async {
        guard let goal = goals.first(where: { $0.id == goalId }), goal.trainingPlan != nil,
            goal.canStartPlan(on: newStart)
        else { return }
        await generateTrainingPlan(for: goal, startingOn: newStart)
    }

    // MARK: - Training Plan Adaptation

    func adaptPlanIfNeeded(for goal: RaceGoal) async {
        guard hasAIAccess(), hasConsent() else { return }
        guard !isAdaptingPlan, !isGeneratingPlan else { return }

        guard let plan = goal.trainingPlan,
            let weekIndex = plan.currentWeekIndex,
            weekIndex >= 1,
            let startDate = plan.startDate
        else { return }

        // Adaptation runs only at the very start of a training week (day 0–1).
        // Mid-week or end-of-week shifts would invalidate sessions the user is about to do.
        let daysIntoCurrentWeek =
            (plan.calendar.dateComponents(
                [.day],
                from: plan.calendar.startOfDay(for: startDate),
                to: plan.calendar.startOfDay(for: Date())
            ).day ?? 0) % 7
        guard daysIntoCurrentWeek <= 1 else { return }

        if plan.lastAdaptationWeekIndex == weekIndex { return }
        if let lastAdapt = plan.lastAdaptationDate,
            plan.calendar.dateComponents([.day], from: lastAdapt, to: Date()).day ?? 0 < 7
        {
            return
        }

        let remainingWeeks = plan.weeks.count - weekIndex - 1
        guard remainingWeeks > 0 else { return }

        isAdaptingPlan = true
        adaptingGoalID = goal.id
        let revision = UUID()
        planRevisions[goal.id] = revision
        adaptationError = nil
        adaptationErrorGoalID = goal.id
        defer {
            isAdaptingPlan = false
            adaptingGoalID = nil
        }

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

            let response = try await adaptPlan(request)

            let adaptedWeeks = convertAdaptedWeeks(
                response.plan.weeks,
                for: goal,
                startTargetIndex: weekIndex + 1,
                raceWeekIndex: plan.weeks.count - 1
            )

            try Task.checkCancellation()
            guard planRevisions[goal.id] == revision,
                let goalIdx = goals.firstIndex(where: { $0.id == goal.id }),
                goals[goalIdx].trainingPlan?.id == plan.id
            else { return }
            guard adaptedWeeks.count == remainingWeeks,
                response.plan.weeks.map(\.weekNumber).sorted() == Array((weekIndex + 2)...plan.weeks.count)
            else {
                throw BackendError.invalidResponse
            }
            do {
                for i in 0..<adaptedWeeks.count {
                    let targetIdx = weekIndex + 1 + i
                    guard targetIdx < goals[goalIdx].trainingPlan!.weeks.count else { break }
                    goals[goalIdx].trainingPlan!.weeks[targetIdx] = adaptedWeeks[i]
                }
                removeSessionsAfterRace(from: &goals[goalIdx].trainingPlan!, target: goal.targetDate)
                goals[goalIdx].trainingPlan!.lastAdaptationDate = Date()
                goals[goalIdx].trainingPlan!.lastAdaptationWeekIndex = weekIndex
                goals[goalIdx].trainingPlan!.adaptationAssessment = response.plan.adaptation.assessment

                storage.updateGoal(goals[goalIdx])
            }
        } catch is CancellationError {
            return
        } catch {
            adaptationError = error.localizedDescription
        }
    }

    private func buildOriginalRemainingWeeks(plan: TrainingPlan, fromWeek: Int)
        -> [OriginalRemainingWeekPayload]
    {
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

    private func buildCompletedWeeksData(plan: TrainingPlan, upToWeek: Int) async
        -> [CompletedWeekPayload]
    {
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
            let completionRate: Double =
                workoutDays.isEmpty
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
                    let metrics = metricsMap[uuid]
                {
                    actual = ActualWorkoutPayload(
                        distance: metrics.distance,
                        duration: metrics.duration,
                        pace: metrics.pace,
                        heartRate: metrics.heartRate
                    )
                }

                workouts.append(
                    CompletedWorkoutPayload(
                        type: day.workout?.type.rawValue ?? "easy_run",
                        planned: planned,
                        actual: actual,
                        skipped: day.isSkipped ? true : nil
                    ))
            }

            result.append(
                CompletedWeekPayload(
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

        return weekDatas.sorted { $0.weekNumber < $1.weekNumber }.enumerated().map { offset, data in
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

    func convertResponseToPlan(
        _ response: TrainingPlanGenerationResponse,
        for goal: RaceGoal,
        schedule: TrainingPlanSchedule
    ) throws -> TrainingPlan {
        let receivedWeeks = response.plan.weeks.sorted { $0.weekNumber < $1.weekNumber }
        guard receivedWeeks.map(\.weekNumber) == Array(1...schedule.weeksCount) else {
            throw BackendError.invalidResponse
        }
        let raceDay = schedule.calendar.component(.weekday, from: schedule.target)
        var plan = TrainingPlan(
            name: response.plan.name, goal: response.plan.goal, level: goal.fitnessLevel,
            weeks: receivedWeeks.map { week in
                convertWeekData(
                    week, preferredDays: goal.preferredDays.sorted { $0.rawValue < $1.rawValue },
                    raceDayOfWeek: week.weekNumber == schedule.weeksCount ? raceDay : nil,
                    raceDistanceMeters: week.weekNumber == schedule.weeksCount
                        ? goal.raceType.distanceKm * 1000 : nil)
            },
            startDate: schedule.start, isActive: true,
            calendarTimeZoneIdentifier: schedule.calendar.timeZone.identifier
        )
        removeSessionsAfterRace(from: &plan, target: schedule.target)
        return plan
    }

    private func removeSessionsAfterRace(from plan: inout TrainingPlan, target: Date) {
        guard !plan.weeks.isEmpty else { return }
        let last = plan.weeks.count - 1
        let raceDay = plan.calendar.startOfDay(for: target)
        plan.weeks[last].days = plan.weeks[last].days.map { day in
            if let date = plan.naturalDate(weekIndex: last, day: day), date > raceDay {
                return TrainingDay(dayOfWeek: day.dayOfWeek)
            }
            return day
        }
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
        let allDays: [DayOfWeek] = [
            .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
        ]

        var assignedDays: Set<DayOfWeek> = []
        var assignments: [DayOfWeek: PlannedWorkout] = [:]
        var remainingWorkouts = workouts

        if let raceDay = raceDayOfWeek,
            let raceDOW = DayOfWeek(rawValue: raceDay),
            !remainingWorkouts.isEmpty
        {
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
            print(
                "⚠️ GoalsViewModel.mapWorkoutsToDays: dropping \(dropped) workout(s) — \(remainingWorkouts.count) sessions for \(availableDays.count) preferred day(s)"
            )
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
