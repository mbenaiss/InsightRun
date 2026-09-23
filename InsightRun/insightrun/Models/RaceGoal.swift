//
//  RaceGoal.swift
//  InsightRun
//
//  Model for race goals with target date and training plan tracking
//

import Foundation

// MARK: - Race Goal

struct RaceGoal: Identifiable, Codable {
    let id: UUID
    var raceType: RaceType
    var raceName: String
    var targetDate: Date
    let createdAt: Date
    var fitnessLevel: FitnessLevel
    var trainingPlan: TrainingPlan?
    var isActive: Bool
    var isPastRace: Bool
    var finishTime: TimeInterval? // Finish time in seconds (for past races)
    var notes: String?
    var trainingDaysPerWeek: Int
    var preferredDays: [DayOfWeek]
    var injury: String?
    var targetTime: TimeInterval? // Target finish time in seconds
    var planStartDate: Date? // User-chosen date to start the training plan

    init(
        id: UUID = UUID(),
        raceType: RaceType,
        raceName: String? = nil,
        targetDate: Date,
        fitnessLevel: FitnessLevel = .intermediate,
        trainingPlan: TrainingPlan? = nil,
        createdAt: Date = Date(),
        isActive: Bool = true,
        isPastRace: Bool = false,
        finishTime: TimeInterval? = nil,
        notes: String? = nil,
        trainingDaysPerWeek: Int = 4,
        preferredDays: [DayOfWeek] = [.monday, .wednesday, .friday, .saturday],
        injury: String? = nil,
        targetTime: TimeInterval? = nil,
        planStartDate: Date? = nil
    ) {
        self.id = id
        self.raceType = raceType
        self.raceName = raceName ?? raceType.displayName
        self.targetDate = targetDate
        self.fitnessLevel = fitnessLevel
        self.trainingPlan = trainingPlan
        self.createdAt = createdAt
        self.isActive = isPastRace ? false : isActive
        self.isPastRace = isPastRace
        self.finishTime = finishTime
        self.notes = notes
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.preferredDays = preferredDays
        self.injury = injury
        self.targetTime = targetTime
        self.planStartDate = planStartDate
    }

    // MARK: - Computed Properties

    var daysRemaining: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
        return max(0, days)
    }

    var weeksRemaining: Int {
        let weeks = Calendar.current.dateComponents([.weekOfYear], from: Date(), to: targetDate).weekOfYear ?? 0
        return max(0, weeks)
    }

    var isPast: Bool {
        isPastRace || targetDate < Date()
    }

    func canStartPlan(on date: Date, calendar: Calendar = .current) -> Bool {
        guard completedWorkouts == 0,
            let schedule = try? TrainingPlanSchedule(start: date, target: targetDate, calendar: calendar)
        else { return false }
        return schedule.start == calendar.startOfDay(for: date)
    }

    // A plan never starts in the past: elapsed weeks would reach adaptation as missed sessions.
    func generationSchedule(
        startingOn requestedStart: Date? = nil, now: Date = Date(), calendar: Calendar = .current
    ) throws -> TrainingPlanSchedule {
        let today = calendar.startOfDay(for: now)
        let start = max(today, calendar.startOfDay(for: requestedStart ?? planStartDate ?? today))
        return try TrainingPlanSchedule(start: start, target: targetDate, calendar: calendar)
    }

    var canGeneratePlan: Bool {
        (try? generationSchedule()) != nil
    }

    var hasTrainingPlan: Bool {
        trainingPlan != nil
    }

    var progressPercentage: Double {
        guard let plan = trainingPlan, let startDate = plan.startDate else { return 0 }
        let totalDays = Calendar.current.dateComponents([.day], from: startDate, to: targetDate).day ?? 1
        let elapsedDays = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        guard totalDays > 0 else { return 0 }
        return min(1.0, max(0, Double(elapsedDays) / Double(totalDays)))
    }

    var completedWorkouts: Int {
        guard let plan = trainingPlan else { return 0 }
        return plan.weeks.flatMap { $0.days }.filter { $0.isCompleted }.count
    }

    var totalPlannedWorkouts: Int {
        guard let plan = trainingPlan else { return 0 }
        return plan.weeks.flatMap { $0.days }.filter { $0.workout != nil }.count
    }

    var workoutCompletionRate: Double {
        guard totalPlannedWorkouts > 0 else { return 0 }
        return Double(completedWorkouts) / Double(totalPlannedWorkouts)
    }

    var currentPhase: TrainingPhase? {
        guard let plan = trainingPlan, let weekIndex = plan.currentWeekIndex else { return nil }
        return plan.weeks[weekIndex].phase
    }

    /// Returns today's pending training session with its indices, if any
    var todaySession: (weekIndex: Int, dayIndex: Int, day: TrainingDay)? {
        guard let plan = trainingPlan else { return nil }
        for (weekIndex, week) in plan.weeks.enumerated() {
            for (dayIndex, day) in week.days.enumerated() {
                guard day.workout != nil, !day.isCompleted, !day.isSkipped,
                    let date = plan.effectiveDate(weekIndex: weekIndex, day: day),
                    plan.calendar.isDate(date, inSameDayAs: Date())
                else { continue }
                return (weekIndex, dayIndex, day)
            }
        }
        return nil
    }

    var formattedFinishTime: String? {
        finishTime.map(Self.formatClockTime)
    }

    var formattedTargetTime: String? {
        targetTime.map(Self.formatClockTime)
    }

    nonisolated private static func formatClockTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Race Type

enum RaceType: String, Codable, CaseIterable, Identifiable {
    case fiveK = "5k"
    case tenK = "10k"
    case halfMarathon = "half_marathon"
    case marathon = "marathon"
    case ultra = "ultra"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveK:
            return "5K"
        case .tenK:
            return "10K"
        case .halfMarathon:
            return String(localized: "goals.raceType.halfMarathon", defaultValue: "Half Marathon", comment: "Race type - half marathon")
        case .marathon:
            return String(localized: "goals.raceType.marathon", defaultValue: "Marathon", comment: "Race type - marathon")
        case .ultra:
            return String(localized: "goals.raceType.ultra", defaultValue: "Ultra Marathon", comment: "Race type - ultra")
        }
    }

    var distanceKm: Double {
        switch self {
        case .fiveK: return 5.0
        case .tenK: return 10.0
        case .halfMarathon: return 21.1
        case .marathon: return 42.195
        case .ultra: return 50.0
        }
    }

    var icon: String {
        switch self {
        case .fiveK: return "figure.run"
        case .tenK: return "figure.run.circle"
        case .halfMarathon: return "figure.run.circle.fill"
        case .marathon: return "trophy"
        case .ultra: return "mountain.2"
        }
    }

    /// Minimum weeks recommended for training
    var minimumWeeks: Int {
        switch self {
        case .fiveK: return 6
        case .tenK: return 8
        case .halfMarathon: return 10
        case .marathon: return 16
        case .ultra: return 20
        }
    }

    func shortPlanWarning(weeks: Int) -> String? {
        guard weeks < minimumWeeks else { return nil }
        return String(
            localized: "goals.plan.shortWarning",
            defaultValue:
                "\(displayName) plans usually last at least \(minimumWeeks) weeks. Yours will have \(weeks), so the progression will be compressed.",
            comment: "Goal - warning when a plan is shorter than recommended for the race distance")
    }
}

// MARK: - Running History

struct RunningHistorySummary: Equatable {
    let runCount: Int
    let weeklyVolumeKm: Double?
    let averagePaceMinPerKm: Double?

    init(runs: [(distance: Double?, duration: TimeInterval)], weeks: Int) {
        let valid = runs.compactMap { run -> (km: Double, minutes: Double)? in
            guard let distance = run.distance, distance > 0 else { return nil }
            return (distance / 1000, run.duration / 60)
        }
        runCount = valid.count
        guard !valid.isEmpty else {
            weeklyVolumeKm = nil
            averagePaceMinPerKm = nil
            return
        }
        averagePaceMinPerKm = valid.map { $0.minutes / $0.km }.reduce(0, +) / Double(valid.count)
        weeklyVolumeKm = valid.map(\.km).reduce(0, +) / Double(max(1, weeks))
    }

    static func recent(now: Date = Date(), calendar: Calendar = .current) async -> RunningHistorySummary? {
        let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        guard let workouts = try? await HealthKitManager.shared.fetchRunningWorkouts(from: start, to: now)
        else { return nil }
        let weeks = calendar.dateComponents([.weekOfYear], from: start, to: now).weekOfYear ?? 1
        return RunningHistorySummary(runs: workouts.map { ($0.distance, $0.duration) }, weeks: weeks)
    }
}
