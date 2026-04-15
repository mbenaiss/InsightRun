//
//  CachedRaceGoal.swift
//  InsightRun
//
//  SwiftData persistence for race goals and their training plans
//

import Foundation
import SwiftData

@Model
class CachedRaceGoal {
    @Attribute(.unique) var id: String
    var raceType: String
    var raceName: String
    var targetDate: Date
    var createdAt: Date
    var fitnessLevel: String
    var isActive: Bool
    var isPastRace: Bool
    var finishTime: Double? // seconds
    var notes: String?
    var trainingDaysPerWeek: Int
    var preferredDaysRaw: String // JSON-encoded [Int]
    var injury: String?
    var targetTime: Double?
    var trainingPlanData: Data? // JSON-encoded TrainingPlan

    init(from goal: RaceGoal) {
        self.id = goal.id.uuidString
        self.raceType = goal.raceType.rawValue
        self.raceName = goal.raceName
        self.targetDate = goal.targetDate
        self.createdAt = goal.createdAt
        self.fitnessLevel = goal.fitnessLevel.rawValue
        self.isActive = goal.isActive
        self.isPastRace = goal.isPastRace
        self.finishTime = goal.finishTime
        self.notes = goal.notes
        self.trainingDaysPerWeek = goal.trainingDaysPerWeek
        self.injury = goal.injury
        self.targetTime = goal.targetTime
        self.preferredDaysRaw = Self.encodePreferredDays(goal.preferredDays)
        self.trainingPlanData = Self.encodeTrainingPlan(goal.trainingPlan)
    }

    func toRaceGoal() -> RaceGoal? {
        guard let uuid = UUID(uuidString: id),
              let type = RaceType(rawValue: raceType),
              let level = FitnessLevel(rawValue: fitnessLevel) else { return nil }

        let decoder = JSONDecoder()
        let days: [DayOfWeek] = {
            guard let data = preferredDaysRaw.data(using: .utf8),
                  let rawValues = try? decoder.decode([Int].self, from: data) else { return [] }
            return rawValues.compactMap { DayOfWeek(rawValue: $0) }
        }()

        let plan: TrainingPlan? = {
            guard let data = trainingPlanData else { return nil }
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(TrainingPlan.self, from: data)
        }()

        return RaceGoal(
            id: uuid,
            raceType: type,
            raceName: raceName,
            targetDate: targetDate,
            fitnessLevel: level,
            trainingPlan: plan,
            createdAt: createdAt,
            isActive: isActive,
            isPastRace: isPastRace,
            finishTime: finishTime,
            notes: notes,
            trainingDaysPerWeek: trainingDaysPerWeek,
            preferredDays: days,
            injury: injury,
            targetTime: targetTime
        )
    }

    func update(from goal: RaceGoal) {
        self.raceType = goal.raceType.rawValue
        self.raceName = goal.raceName
        self.targetDate = goal.targetDate
        self.fitnessLevel = goal.fitnessLevel.rawValue
        self.isActive = goal.isActive
        self.isPastRace = goal.isPastRace
        self.finishTime = goal.finishTime
        self.notes = goal.notes
        self.trainingDaysPerWeek = goal.trainingDaysPerWeek
        self.injury = goal.injury
        self.targetTime = goal.targetTime
        self.preferredDaysRaw = Self.encodePreferredDays(goal.preferredDays)
        self.trainingPlanData = Self.encodeTrainingPlan(goal.trainingPlan)
    }

    // MARK: - Encoding Helpers

    private static func encodePreferredDays(_ days: [DayOfWeek]) -> String {
        (try? String(data: JSONEncoder().encode(days.map { $0.rawValue }), encoding: .utf8)) ?? "[]"
    }

    private static func encodeTrainingPlan(_ plan: TrainingPlan?) -> Data? {
        guard let plan else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(plan)
    }
}
