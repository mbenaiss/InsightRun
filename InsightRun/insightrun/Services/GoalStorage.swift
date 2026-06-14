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

    /// Returns false if the goal could not be persisted (no context yet, or save
    /// failed) so the caller can surface the data loss instead of dropping it silently.
    @discardableResult
    func addGoal(_ goal: RaceGoal) -> Bool {
        guard let context = modelContext else {
            // The shared context is injected asynchronously on first launch; if a
            // goal is created in that window, fall back to UserDefaults so it isn't
            // lost. migrateFromUserDefaultsIfNeeded() picks it up once context exists.
            persistToUserDefaults(appending: goal)
            print("GoalStorage: addGoal before context ready — buffered to UserDefaults")
            return false
        }

        context.insert(CachedRaceGoal(from: goal))
        do {
            try context.save()
            return true
        } catch {
            print("GoalStorage: Failed to save new goal: \(error)")
            return false
        }
    }

    // MARK: - Delete

    @discardableResult
    func deleteGoal(id: UUID) -> Bool {
        guard let context = modelContext else { return false }

        let idString = id.uuidString
        do {
            let descriptor = FetchDescriptor<CachedRaceGoal>(
                predicate: #Predicate { $0.id == idString }
            )
            if let cached = try context.fetch(descriptor).first {
                context.delete(cached)
                try context.save()
            }
            return true
        } catch {
            print("GoalStorage: Failed to delete: \(error)")
            return false
        }
    }

    // MARK: - Update

    @discardableResult
    func updateGoal(_ goal: RaceGoal) -> Bool {
        guard let context = modelContext else { return false }

        let idString = goal.id.uuidString
        do {
            let descriptor = FetchDescriptor<CachedRaceGoal>(
                predicate: #Predicate { $0.id == idString }
            )
            if let cached = try context.fetch(descriptor).first {
                cached.update(from: goal)
                try context.save()
            }
            return true
        } catch {
            print("GoalStorage: Failed to update: \(error)")
            return false
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

    /// Buffer a goal into the legacy UserDefaults store. Used only as a safety net
    /// when a goal is created before the SwiftData context is injected; the regular
    /// migration path drains it into SwiftData once the context is available.
    private func persistToUserDefaults(appending goal: RaceGoal) {
        var goals = loadFromUserDefaults()
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx] = goal
        } else {
            goals.append(goal)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(goals) {
            UserDefaults.standard.set(data, forKey: legacyKey)
        }
    }

    func migrateFromUserDefaultsIfNeeded() {
        guard let context = modelContext else { return }

        // Drain any legacy/buffered goals into SwiftData. We can't bail early on a
        // non-empty store: a goal created before the context was injected is buffered
        // to UserDefaults even when SwiftData already holds other goals, so we merge
        // by id and only insert the ones missing from SwiftData.
        do {
            let legacyGoals = loadFromUserDefaults()
            guard !legacyGoals.isEmpty else { return }

            let existing = try context.fetch(FetchDescriptor<CachedRaceGoal>())
            let existingIds = Set(existing.map { $0.id })

            var inserted = 0
            for goal in legacyGoals where !existingIds.contains(goal.id.uuidString) {
                context.insert(CachedRaceGoal(from: goal))
                inserted += 1
            }
            try context.save()

            // Clean up UserDefaults
            UserDefaults.standard.removeObject(forKey: legacyKey)
            print("GoalStorage: Migrated \(inserted) goals from UserDefaults to SwiftData")
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
