//
//  GoalStorage.swift
//  InsightRun
//
//  Service for persisting race goals using SwiftData
//  Same pattern as UnifiedWorkoutCache (separate ModelContext)
//

import Foundation
import SwiftData

@MainActor
class GoalStorage {
    static let shared = GoalStorage()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Load

    func load() -> [RaceGoal] {
        guard let context = modelContext else {
            print("GoalStorage: No ModelContext set")
            return loadFromUserDefaults()
        }

        do {
            let descriptor = FetchDescriptor<CachedRaceGoal>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let cached = try context.fetch(descriptor)
            return cached.compactMap { $0.toRaceGoal() }
        } catch {
            print("GoalStorage: Failed to fetch from SwiftData: \(error)")
            return []
        }
    }

    // MARK: - Add

    func addGoal(_ goal: RaceGoal) {
        guard let context = modelContext else { return }

        context.insert(CachedRaceGoal(from: goal))
        try? context.save()
    }

    // MARK: - Delete

    func deleteGoal(id: UUID) {
        guard let context = modelContext else { return }

        let idString = id.uuidString
        do {
            let descriptor = FetchDescriptor<CachedRaceGoal>(
                predicate: #Predicate { $0.id == idString }
            )
            if let cached = try context.fetch(descriptor).first {
                context.delete(cached)
                try context.save()
            }
        } catch {
            print("GoalStorage: Failed to delete: \(error)")
        }
    }

    // MARK: - Update

    func updateGoal(_ goal: RaceGoal) {
        guard let context = modelContext else { return }

        let idString = goal.id.uuidString
        do {
            let descriptor = FetchDescriptor<CachedRaceGoal>(
                predicate: #Predicate { $0.id == idString }
            )
            if let cached = try context.fetch(descriptor).first {
                cached.update(from: goal)
                try context.save()
            }
        } catch {
            print("GoalStorage: Failed to update: \(error)")
        }
    }

    // MARK: - Migration from UserDefaults

    private let legacyKey = "com.insightrun.raceGoals"

    private func loadFromUserDefaults() -> [RaceGoal] {
        guard let data = UserDefaults.standard.data(forKey: legacyKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RaceGoal].self, from: data)) ?? []
    }

    func migrateFromUserDefaultsIfNeeded() {
        guard let context = modelContext else { return }

        // Check if SwiftData is empty and UserDefaults has data
        do {
            let descriptor = FetchDescriptor<CachedRaceGoal>()
            let count = try context.fetchCount(descriptor)
            guard count == 0 else { return } // Already migrated

            let legacyGoals = loadFromUserDefaults()
            guard !legacyGoals.isEmpty else { return }

            for goal in legacyGoals {
                context.insert(CachedRaceGoal(from: goal))
            }
            try context.save()

            // Clean up UserDefaults
            UserDefaults.standard.removeObject(forKey: legacyKey)
            print("GoalStorage: Migrated \(legacyGoals.count) goals from UserDefaults to SwiftData")
        } catch {
            print("GoalStorage: Migration failed: \(error)")
        }
    }

    // MARK: - Clear

    func clear() {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<CachedRaceGoal>()
            let all = try context.fetch(descriptor)
            for item in all {
                context.delete(item)
            }
            try context.save()
        } catch {
            print("GoalStorage: Failed to clear: \(error)")
        }
    }
}
