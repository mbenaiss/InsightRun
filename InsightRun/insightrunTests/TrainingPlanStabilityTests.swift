import HealthKit
import SwiftData
import XCTest

@testable import insightrun

@MainActor
final class TrainingPlanStabilityTests: XCTestCase {
    private var container: ModelContainer!
    private let calendar = Calendar.current

    override func setUp() async throws {
        container = try ModelContainer(
            for: CachedRaceGoal.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        GoalStorage.shared.setModelContext(container.mainContext)
    }

    private func run() -> PlannedWorkout {
        PlannedWorkout(
            type: .easyRun, name: "QA", description: "QA", targetDuration: 1800,
            targetDistance: 5000)
    }

    private func date(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))!
    }

    private func plan(days: [TrainingDay], start: Date) -> TrainingPlan {
        TrainingPlan(
            name: "QA", goal: "QA", level: .intermediate,
            weeks: [TrainingWeek(weekNumber: 1, phase: .base, days: days)], startDate: start)
    }

    private func goal(plan: TrainingPlan) -> RaceGoal {
        RaceGoal(raceType: .tenK, raceName: "QA", targetDate: date(40), trainingPlan: plan)
    }

    private func workout(at start: Date) -> HKWorkout {
        HKWorkout(
            activityType: .running, start: start, end: start.addingTimeInterval(1800),
            duration: 1800, totalEnergyBurned: nil,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000), metadata: nil)
    }

    func testBatchMatchingKeepsAllCompletedSessions() async throws {
        let first = date(-2)
        let second = date(-1)
        let days = [first, second].map {
            TrainingDay(
                dayOfWeek: DayOfWeek(rawValue: calendar.component(.weekday, from: $0))!,
                workout: run())
        }
        let item = goal(plan: plan(days: days, start: first))
        GoalStorage.shared.addGoal(item)
        WorkoutMatchingService.shared.matchWorkouts([workout(at: first), workout(at: second)])
        let saved = try XCTUnwrap(GoalStorage.shared.load().first)
        XCTAssertEqual(saved.completedWorkouts, 2, "Both imported sessions must remain completed")
    }

    func testSkippedSessionStaysSkippedAfterAutomaticMatching() async throws {
        let today = date(0)
        let day = TrainingDay(
            dayOfWeek: DayOfWeek(rawValue: calendar.component(.weekday, from: today))!,
            workout: run(), isSkipped: true)
        GoalStorage.shared.addGoal(goal(plan: plan(days: [day], start: today)))
        WorkoutMatchingService.shared.matchWorkouts([workout(at: today)])
        let dayAfter = try XCTUnwrap(
            GoalStorage.shared.load().first?.trainingPlan?.weeks.first?.days.first)
        XCTAssertFalse(dayAfter.isCompleted)
        XCTAssertTrue(dayAfter.isSkipped)
    }

    func testDurationOnlyRunRejectsAnUnrelatedShortActivity() {
        let planned = PlannedWorkout(
            type: .easyRun, name: "QA", description: "QA", targetDuration: 3600)
        XCTAssertFalse(
            WorkoutMatchingService.isMatch(planned: planned, hkDistance: 200, hkDuration: 60))
    }

    func testUpcomingSundayIsNotPastInAWeekStartingMidweek() throws {
        let start = date(0)
        guard calendar.component(.weekday, from: start) > 1 else {
            throw XCTSkip("Requires a midweek start")
        }
        let day = TrainingDay(dayOfWeek: .sunday, workout: run())
        let schedule = plan(days: [day], start: start)
        XCTAssertGreaterThan(try XCTUnwrap(schedule.effectiveDate(weekIndex: 0, day: day)), start)
        XCTAssertFalse(TrainingCalendarView.isDayPast(plan: schedule, weekIndex: 0, day: day))
    }

    func testRescheduledSessionUsesItsEffectiveDateForPastStatus() {
        let today = date(0)
        let day = TrainingDay(
            dayOfWeek: DayOfWeek(rawValue: calendar.component(.weekday, from: today))!,
            workout: run(), dateOverride: date(-1))
        XCTAssertTrue(
            TrainingCalendarView.isDayPast(
                plan: plan(days: [day], start: today), weekIndex: 0, day: day))
    }

    func testFinishedPlanSessionsArePast() {
        let day = TrainingDay(dayOfWeek: .monday, workout: run())
        let schedule = plan(days: [day], start: date(-30))
        XCTAssertNil(schedule.currentWeekIndex)
        XCTAssertTrue(TrainingCalendarView.isDayPast(plan: schedule, weekIndex: 0, day: day))
    }

    func testGoalPlanPersistenceRoundTrip() throws {
        let item = goal(
            plan: plan(days: [TrainingDay(dayOfWeek: .monday, workout: run())], start: date(0)))
        XCTAssertTrue(GoalStorage.shared.addGoal(item))
        var restored = try XCTUnwrap(GoalStorage.shared.load().first)
        XCTAssertEqual(restored.trainingPlan?.id, item.trainingPlan?.id)
        restored.raceName = "QA renamed"
        restored.trainingPlan?.weeks[0].days[0].isCompleted = true
        XCTAssertTrue(GoalStorage.shared.updateGoal(restored))
        XCTAssertEqual(GoalStorage.shared.load().first?.completedWorkouts, 1)
        XCTAssertEqual(GoalStorage.shared.load().first?.raceName, "QA renamed")
        XCTAssertTrue(GoalStorage.shared.deleteGoal(id: item.id))
        XCTAssertTrue(GoalStorage.shared.load().isEmpty)
    }
}

extension TrainingPlanStabilityTests {
    private func response(weeks: Int, days: Int = 4, distance: Double = 10000) throws -> TrainingPlanGenerationResponse
    {
        let plan: [String: Any] = [
            "name": "QA generated", "goal": "QA goal",
            "weeks": (1...weeks).map { number -> [String: Any] in
                [
                    "weekNumber": number, "phase": number == weeks ? "taper" : "base",
                    "workouts": (0..<days).map { index -> [String: Any] in
                        [
                            "name": number == weeks && index == 0 ? "QA race" : "QA run",
                            "type": "long_run", "description": "QA", "intensity": "easy",
                            "targetDistance": number == weeks && index == 0 ? distance : 3000,
                        ]
                    },
                ]
            },
        ]
        return try JSONDecoder().decode(
            TrainingPlanGenerationResponse.self,
            from: JSONSerialization.data(withJSONObject: [
                "plan": plan,
                "metadata": ["generationTimeMs": 1, "modelUsed": "test", "attempts": 1, "weeksGenerated": weeks],
            ]))
    }

    func testCalendarLengthIncludesRaceOnExactWeekBoundaryAndCapsDistantRaces() throws {
        var calendar = Calendar(identifier: .gregorian)
        for zone in ["Europe/Paris", "America/New_York", "Pacific/Auckland"] {
            calendar.timeZone = TimeZone(identifier: zone)!
            for month in [3, 10] {
                let start = calendar.date(from: DateComponents(year: 2027, month: month, day: 1))!
                for days in [27, 28, 29, 120, 167, 168, 365] {
                    let target = calendar.date(byAdding: .day, value: days, to: start)!
                    let schedule = try TrainingPlanSchedule(start: start, target: target, calendar: calendar)
                    XCTAssertEqual(schedule.weeksCount, min(24, days / 7 + 1))
                    let raceDay = TrainingDay(
                        dayOfWeek: DayOfWeek(rawValue: calendar.component(.weekday, from: target))!)
                    let schedulePlan = TrainingPlan(
                        name: "QA", goal: "QA", level: .beginner,
                        weeks: (1...schedule.weeksCount).map {
                            TrainingWeek(weekNumber: $0, phase: .base, days: [raceDay])
                        },
                        startDate: schedule.start, calendarTimeZoneIdentifier: zone)
                    XCTAssertEqual(schedulePlan.naturalDate(weekIndex: schedule.weeksCount - 1, day: raceDay), target)
                    let restored = try JSONDecoder().decode(TrainingPlan.self, from: JSONEncoder().encode(schedulePlan))
                    XCTAssertEqual(restored.calendar.timeZone.identifier, zone)
                    XCTAssertEqual(restored.naturalDate(weekIndex: schedule.weeksCount - 1, day: raceDay), target)
                }
            }
        }
        XCTAssertThrowsError(try TrainingPlanSchedule(start: date(0), target: date(26)))
    }

    func testEveryRaceLevelAndWeekdaySelectionProducesACompleteCorrectlyDatedPlan() async throws {
        let viewModel = GoalsViewModel()
        let schedule = try TrainingPlanSchedule(start: date(0), target: date(32))
        for race in RaceType.allCases {
            for level in FitnessLevel.allCases {
                for count in 1...7 {
                    let days = Array(DayOfWeek.allCases.prefix(count))
                    let item = RaceGoal(
                        raceType: race, targetDate: date(32), fitnessLevel: level,
                        trainingDaysPerWeek: count, preferredDays: days)
                    let generated = try viewModel.convertResponseToPlan(
                        response(weeks: schedule.weeksCount, days: count, distance: race.distanceKm * 1000),
                        for: item, schedule: schedule)
                    XCTAssertEqual(generated.totalWeeks, schedule.weeksCount)
                    XCTAssertEqual(generated.level, level)
                    for (index, week) in generated.weeks.enumerated() {
                        for day in week.days where day.workout != nil {
                            let effective = try XCTUnwrap(generated.effectiveDate(weekIndex: index, day: day))
                            XCTAssertGreaterThanOrEqual(effective, schedule.start)
                            XCTAssertLessThanOrEqual(effective, schedule.target)
                            if day.workout?.name == "QA race" {
                                XCTAssertEqual(effective, schedule.target)
                                XCTAssertEqual(day.workout?.targetDistance, race.distanceKm * 1000)
                            } else {
                                XCTAssertTrue(days.contains(day.dayOfWeek))
                            }
                        }
                    }
                    XCTAssertEqual(generated.weeks.last?.days.filter { $0.workout?.name == "QA race" }.count, 1)
                }
            }
        }
    }

    func testPartialPlanIsRejectedAndExistingPlanSurvivesNetworkFailure() async throws {
        let original = plan(days: [TrainingDay(dayOfWeek: .monday, workout: run())], start: date(0))
        let item = goal(plan: original)
        let viewModel = GoalsViewModel(generatePlan: { _ in throw URLError(.timedOut) })
        viewModel.goals = [item]
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertNotNil(viewModel.generationError)
        XCTAssertFalse(viewModel.isGeneratingPlan)
        XCTAssertNil(viewModel.generatingGoalID)
        XCTAssertEqual(viewModel.goals.first?.trainingPlan?.id, original.id)
        XCTAssertThrowsError(
            try viewModel.convertResponseToPlan(
                response(weeks: 4), for: item,
                schedule: TrainingPlanSchedule(start: date(0), target: date(40))))
    }

    func testConsentDeclineResumeAndSubscriptionGateDoNotLoseTheGoal() async throws {
        var consent = false
        var access = true
        var requests = 0
        let output = try response(weeks: 6)
        let viewModel = GoalsViewModel(
            generatePlan: { _ in
                requests += 1
                return output
            },
            hasConsent: { consent }, hasAIAccess: { access })
        let item = RaceGoal(raceType: .tenK, targetDate: date(40), planStartDate: date(0))
        viewModel.addGoal(item)
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertTrue(viewModel.needsConsent)
        XCTAssertEqual(requests, 0)
        viewModel.clearPendingGeneration()
        consent = true
        await viewModel.resumePendingGeneration()
        XCTAssertEqual(requests, 0)
        access = false
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertEqual(requests, 0)
        access = true
        consent = false
        await viewModel.generateTrainingPlan(for: item)
        consent = true
        await viewModel.resumePendingGeneration()
        XCTAssertEqual(requests, 1)
        XCTAssertNotNil(viewModel.goals.first(where: { $0.id == item.id })?.trainingPlan)
    }

    func testDuplicateGenerationAndDeletedGoalCannotApplyLateResponse() async throws {
        var continuation: CheckedContinuation<TrainingPlanGenerationResponse, Error>?
        var requests = 0
        let viewModel = GoalsViewModel(generatePlan: { _ in
            requests += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        let item = RaceGoal(raceType: .tenK, targetDate: date(40), planStartDate: date(0))
        viewModel.goals = [item]
        let task = Task { await viewModel.generateTrainingPlan(for: item) }
        while continuation == nil { await Task.yield() }
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(viewModel.generatingGoalID, item.id)
        viewModel.deleteGoal(item)
        continuation?.resume(returning: try response(weeks: 6))
        await task.value
        XCTAssertTrue(viewModel.goals.isEmpty)
        XCTAssertNil(viewModel.generationError)
        XCTAssertFalse(viewModel.isGeneratingPlan)
    }

    func testRequestCarriesManualProfileTimeAndConstraintAndCanRetry() async throws {
        var calls = 0
        let output = try response(weeks: 6)
        let viewModel = GoalsViewModel(generatePlan: { request in
            calls += 1
            XCTAssertEqual(request.fitnessLevel, "advanced")
            XCTAssertEqual(request.targetTimeSeconds, 5400)
            XCTAssertEqual(request.injury, "QA knee constraint")
            XCTAssertEqual(request.preferredDays, [2, 4, 6, 7])
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return output
        })
        let item = RaceGoal(
            raceType: .halfMarathon, targetDate: date(40), fitnessLevel: .advanced,
            injury: "QA knee constraint", targetTime: 5400, planStartDate: date(0))
        viewModel.addGoal(item)
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertNotNil(viewModel.generationError)
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertNil(viewModel.generationError)
        XCTAssertEqual(calls, 2)
        XCTAssertNotNil(viewModel.goals.last?.trainingPlan)
    }

    func testTodaySessionIgnoresSkippedAndUsesRescheduledDateAcrossWeeks() {
        let moved = TrainingDay(dayOfWeek: .monday, workout: run(), dateOverride: date(0))
        var item = goal(plan: plan(days: [moved], start: date(-40)))
        XCTAssertNotNil(item.todaySession)
        item.trainingPlan?.weeks[0].days[0].isSkipped = true
        XCTAssertNil(item.todaySession)
        item.trainingPlan?.weeks[0].days[0].isSkipped = false
        item.trainingPlan?.weeks[0].days[0].dateOverride = date(1)
        XCTAssertNil(item.todaySession)
    }

    func testMultipleGoalsRenameAndDeleteAreIsolated() async {
        let viewModel = GoalsViewModel()
        viewModel.goals = []
        XCTAssertTrue(viewModel.activeGoals.isEmpty)
        let first = RaceGoal(raceType: .fiveK, raceName: "QA first", targetDate: date(40))
        let second = RaceGoal(raceType: .marathon, raceName: "QA second", targetDate: date(180))
        viewModel.addGoal(first)
        viewModel.addGoal(second)
        viewModel.renameGoal(id: first.id, newName: "  Renamed  ")
        viewModel.renameGoal(id: second.id, newName: "   ")
        XCTAssertEqual(viewModel.goals[0].raceName, "Renamed")
        XCTAssertEqual(viewModel.goals[1].raceName, "QA second")
        viewModel.deleteGoal(first)
        XCTAssertEqual(viewModel.goals.map(\.id), [second.id])
        viewModel.deleteGoal(second)
        XCTAssertTrue(viewModel.activeGoals.isEmpty)
        XCTAssertTrue(viewModel.pastGoals.isEmpty)
    }
}

extension TrainingPlanStabilityTests {
    func testPlannedWorkoutWithoutDetailedStepsExportsDistanceDurationAndOpenGoals() throws {
        for workout in [
            PlannedWorkout(type: .easyRun, name: "Distance", description: "QA", targetDistance: 5000),
            PlannedWorkout(type: .easyRun, name: "Duration", description: "QA", targetDuration: 1800),
            PlannedWorkout(type: .easyRun, name: "Open", description: "QA"),
        ] {
            let export = workout.exportWorkout
            XCTAssertEqual(export.steps.count, 1)
            XCTAssertTrue(export.isValid)
            XCTAssertNoThrow(try WorkoutKitManager.shared.createCustomWorkout(from: export))
        }
        let intervals = PlannedWorkout(
            type: .intervals, name: "Intervals", description: "QA",
            steps: [
                PlannedWorkoutStep(type: .warmup, duration: 600, description: "Warmup"),
                PlannedWorkoutStep(
                    type: .interval, distance: 400, targetPace: "4:30", repetitions: 6, description: "Effort"),
                PlannedWorkoutStep(type: .recovery, duration: 60, description: "Recovery"),
                PlannedWorkoutStep(type: .cooldown, duration: 300, description: "Cooldown"),
            ])
        XCTAssertEqual(intervals.exportWorkout.steps[1].repetitions, 6)
        XCTAssertEqual(intervals.exportWorkout.steps[1].goal.value, 400)
        XCTAssertNoThrow(
            try WorkoutKitManager.shared.createCustomWorkout(from: intervals.exportWorkout, destination: .treadmill))
    }

    func testPlanExportUsesScheduledDayAndPastSessionsRemainAvailableToday() {
        let now = date(0)
        XCTAssertEqual(
            WorkoutKitManager.exportDate(scheduledDate: date(4), now: now).day, calendar.component(.day, from: date(4)))
        XCTAssertEqual(
            WorkoutKitManager.exportDate(scheduledDate: date(-4), now: now).day, calendar.component(.day, from: now))
        XCTAssertEqual(
            WorkoutKitManager.exportDate(scheduledDate: nil, now: now).day, calendar.component(.day, from: now))
    }

    func testRegenerationAndStartTodayKeepRaceDateAndDoNotShiftCompletedHistory() async throws {
        var calls = 0
        let viewModel = GoalsViewModel(generatePlan: { request in
            calls += 1
            return try self.response(weeks: request.weeksCount!)
        })
        var item = RaceGoal(raceType: .tenK, targetDate: date(40), planStartDate: date(3))
        viewModel.addGoal(item)
        await viewModel.generateTrainingPlan(for: item)
        let firstID = try XCTUnwrap(viewModel.goals.last?.trainingPlan?.id)
        await viewModel.setPlanStartDate(goalId: item.id, newStart: date(0))
        var generated = try XCTUnwrap(viewModel.goals.last?.trainingPlan)
        XCTAssertEqual(generated.startDate, date(0))
        XCTAssertNotEqual(generated.id, firstID)
        let race = try XCTUnwrap(generated.weeks.last?.days.first(where: { $0.workout?.name == "QA race" }))
        XCTAssertEqual(generated.effectiveDate(weekIndex: generated.weeks.count - 1, day: race), date(40))
        item = try XCTUnwrap(viewModel.goals.last)
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertEqual(calls, 3)
        XCTAssertNotEqual(viewModel.goals.last?.trainingPlan?.id, generated.id)
        viewModel.toggleDayCompletion(goalId: item.id, weekIndex: 0, dayIndex: 1)
        generated = try XCTUnwrap(viewModel.goals.last?.trainingPlan)
        await viewModel.setPlanStartDate(goalId: item.id, newStart: date(2))
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(viewModel.goals.last?.trainingPlan?.id, generated.id)
        XCTAssertEqual(viewModel.goals.last?.completedWorkouts, 1)
    }

    func testAdaptationPreservesCompletedWeeksAndRejectsAStaleResponse() async throws {
        let schedule = try TrainingPlanSchedule(start: date(-7), target: date(40))
        let converter = GoalsViewModel()
        var item = RaceGoal(raceType: .tenK, targetDate: date(40), planStartDate: date(-7))
        item.trainingPlan = try converter.convertResponseToPlan(response(weeks: 7), for: item, schedule: schedule)
        item.trainingPlan?.weeks[0].days[1].isCompleted = true
        var continuation: CheckedContinuation<AdaptTrainingPlanResponse, Error>?
        var requests = 0
        let viewModel = GoalsViewModel(adaptPlan: { request in
            requests += 1
            XCTAssertEqual(request.currentWeekNumber, 2)
            XCTAssertEqual(request.remainingWeeksCount, 5)
            XCTAssertEqual(request.completedWeeks.count, 1)
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        viewModel.addGoal(item)
        let task = Task { await viewModel.adaptPlanIfNeeded(for: item) }
        while continuation == nil { await Task.yield() }
        await viewModel.adaptPlanIfNeeded(for: item)
        XCTAssertEqual(requests, 1)
        viewModel.setDayDateOverride(goalId: item.id, weekIndex: 3, dayIndex: 1, newDate: date(12))
        let data: [String: Any] = [
            "plan": ["weeks": [], "adaptation": ["assessment": "QA"]],
            "metadata": ["generationTimeMs": 1, "modelUsed": "test", "attempts": 1, "weeksGenerated": 5],
        ]
        let adapted = try JSONDecoder().decode(
            AdaptTrainingPlanResponse.self, from: JSONSerialization.data(withJSONObject: data))
        continuation?.resume(returning: adapted)
        await task.value
        XCTAssertNil(viewModel.adaptationError)
        XCTAssertFalse(viewModel.isAdaptingPlan)
        XCTAssertEqual(viewModel.goals.last?.trainingPlan?.weeks[3].days[1].dateOverride, date(12))
        XCTAssertEqual(viewModel.goals.last?.trainingPlan?.weeks[0].days[1].isCompleted, true)
    }
}

extension TrainingPlanStabilityTests {
    func testSuccessfulAdaptationKeepsHistoryAndDoesNotScheduleAfterRace() async throws {
        let schedule = try TrainingPlanSchedule(start: date(-7), target: date(40))
        let converter = GoalsViewModel()
        var item = RaceGoal(raceType: .tenK, targetDate: date(40), planStartDate: date(-7))
        item.trainingPlan = try converter.convertResponseToPlan(response(weeks: 7), for: item, schedule: schedule)
        item.trainingPlan?.weeks[0].days[1].isCompleted = true
        let originalDayID = item.trainingPlan?.weeks[0].days[1].id
        let generated = try response(weeks: 7)
        let output = AdaptTrainingPlanResponse(
            plan: .init(
                weeks: Array(generated.plan.weeks.suffix(5).reversed()),
                adaptation: try JSONDecoder().decode(
                    AdaptTrainingPlanResponse.AdaptationAnalysis.self,
                    from: Data("{\"assessment\":\"QA adjusted\"}".utf8))),
            metadata: generated.metadata)
        var requests = 0
        let viewModel = GoalsViewModel(adaptPlan: { _ in
            requests += 1
            return output
        })
        viewModel.addGoal(item)
        await viewModel.adaptPlanIfNeeded(for: item)
        XCTAssertNil(viewModel.adaptationError)
        let updated = try XCTUnwrap(viewModel.goals.last?.trainingPlan)
        XCTAssertEqual(updated.weeks.map(\.weekNumber), Array(1...7))
        XCTAssertEqual(updated.weeks[0].days[1].id, originalDayID)
        XCTAssertTrue(updated.weeks[0].days[1].isCompleted)
        XCTAssertEqual(updated.adaptationAssessment, "QA adjusted")
        for day in updated.weeks[6].days where day.workout != nil {
            XCTAssertLessThanOrEqual(try XCTUnwrap(updated.effectiveDate(weekIndex: 6, day: day)), date(40))
        }
        await viewModel.adaptPlanIfNeeded(for: try XCTUnwrap(viewModel.goals.last))
        XCTAssertEqual(requests, 1)
    }

    func testCancelledGenerationPreservesPlanWithoutDisplayingAnError() async throws {
        let item = goal(plan: plan(days: [TrainingDay(dayOfWeek: .monday, workout: run())], start: date(0)))
        let viewModel = GoalsViewModel(generatePlan: { _ in throw CancellationError() })
        viewModel.goals = [item]
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertNil(viewModel.generationError)
        XCTAssertFalse(viewModel.isGeneratingPlan)
        XCTAssertEqual(viewModel.goals[0].trainingPlan?.id, item.trainingPlan?.id)
    }
}

extension TrainingPlanStabilityTests {
    func testFreeAllowanceIsConsumedOnlyBySuccessfulGeneration() async throws {
        var calls = 0
        var consumed = 0
        let output = try response(weeks: 6)
        let viewModel = GoalsViewModel(
            generatePlan: { _ in
                calls += 1
                if calls == 1 { throw URLError(.timedOut) }
                return output
            }, recordGeneration: { consumed += 1 })
        let item = RaceGoal(raceType: .tenK, targetDate: date(40), planStartDate: date(0))
        viewModel.addGoal(item)
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertEqual(consumed, 0)
        await viewModel.generateTrainingPlan(for: item)
        XCTAssertEqual(consumed, 1)
    }
}

extension TrainingPlanStabilityTests {
    func testStartingTodayIsUnavailableWhenItCannotReachRaceWithinSupportedWindow() {
        let distant = RaceGoal(raceType: .marathon, targetDate: date(365))
        XCTAssertFalse(distant.canStartPlan(on: date(0)))
        XCTAssertTrue(distant.canStartPlan(on: date(198)))
        let nearby = RaceGoal(raceType: .fiveK, targetDate: date(10))
        XCTAssertFalse(nearby.canStartPlan(on: date(0)))
    }
}
