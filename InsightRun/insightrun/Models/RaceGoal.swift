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
        guard let plan = trainingPlan, let weekIndex = plan.currentWeekIndex else { return nil }
        guard weekIndex < plan.weeks.count else { return nil }
        let todayDOW = Calendar.current.component(.weekday, from: Date()) // 1=Sunday...7=Saturday
        guard let dow = DayOfWeek(rawValue: todayDOW) else { return nil }
        let week = plan.weeks[weekIndex]
        guard let dayIndex = week.days.firstIndex(where: { $0.dayOfWeek == dow }) else { return nil }
        let day = week.days[dayIndex]
        guard day.workout != nil, !day.isCompleted else { return nil }
        return (weekIndex, dayIndex, day)
    }

    var formattedFinishTime: String? {
        guard let time = finishTime else { return nil }
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
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
}
